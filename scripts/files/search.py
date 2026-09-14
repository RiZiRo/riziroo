#!/usr/bin/env python3
"""Local filename search. One JSON request argument; newline-delimited JSON replies.

Only metadata is read. plocate supplies system coverage; bounded scandir walks
supplement its daily snapshot. No shell, content indexing, or persistent worker.
"""
from __future__ import annotations

import argparse
from collections import deque
from dataclasses import dataclass
import fnmatch
import json
import os
from pathlib import Path
import selectors
import shlex
import signal
import stat
import subprocess
import sys
import time

INDEX_SECONDS = 1.0
LIVE_SECONDS = 2.0
CANDIDATE_LIMIT = 12000
LIVE_LIMIT = 80000
SKIP_DIRS = {".git", ".cache", "node_modules", "__pycache__", ".venv", "venv"}
PSEUDO_ROOTS = ("/proc", "/sys", "/dev", "/run")


@dataclass
class Query:
    terms: list[str]
    extension: str = ""
    kind: str = ""
    directory: str = ""

    @property
    def empty(self):
        return not (self.terms or self.extension or self.kind or self.directory)


def within(path: str, directory: str) -> bool:
    return path == directory or path.startswith(directory.rstrip("/") + "/")


def parse_query(text: str) -> Query:
    query = Query([])
    try:
        tokens = shlex.split(text)
    except ValueError:
        raise ValueError('Close the quote around the filename or folder.')
    for token in tokens:
        if token.startswith("ext:"):
            query.extension = token[4:].lstrip(".").casefold()
            if not query.extension or "/" in query.extension:
                raise ValueError("Use an extension such as ext:pdf.")
        elif token.startswith("type:"):
            query.kind = token[5:].casefold()
            if query.kind not in ("file", "folder"):
                raise ValueError("Use type:file or type:folder.")
        elif token.startswith("in:"):
            value = os.path.expanduser(token[3:])
            if not os.path.isabs(value):
                raise ValueError('Use an absolute folder or in:"~/Some Folder".')
            query.directory = os.path.normpath(value)
            if any(within(query.directory, p) for p in PSEUDO_ROOTS):
                raise ValueError("Virtual device and process folders are not searched.")
            if not os.path.isdir(query.directory) or not os.access(query.directory, os.R_OK | os.X_OK):
                raise ValueError("That folder is unavailable or not readable.")
        else:
            query.terms.append(token.casefold())
    return query


def term_matches(term: str, name: str, path: str) -> bool:
    if any(c in term for c in "*?["):
        return fnmatch.fnmatchcase(name, term) or fnmatch.fnmatchcase(path, term) or fnmatch.fnmatchcase(path, "*/" + term)
    return term in path


def candidate(path: str, query: Query, home: str):
    path = os.path.normpath(path)
    if not os.path.isabs(path) or any(within(path, p) for p in PSEUDO_ROOTS):
        return None
    if query.directory and not within(path, query.directory):
        return None
    name = os.path.basename(path) or path
    folded, full = name.casefold(), path.casefold()
    if not all(term_matches(t, folded, full) for t in query.terms):
        return None
    if query.extension and not folded.endswith("." + query.extension):
        return None
    try:
        info = os.stat(path)
        kind = "folder" if stat.S_ISDIR(info.st_mode) else "file"
        if kind == "file" and not stat.S_ISREG(info.st_mode):
            return None
        if query.kind and kind != query.kind:
            return None
        if not os.access(path, os.R_OK | (os.X_OK if kind == "folder" else 0)):
            return None
    except (OSError, ValueError):
        return None
    phrase = " ".join(query.terms)
    if phrase and folded == phrase:
        rank = 0
    elif phrase and folded.startswith(phrase):
        rank = 1
    elif query.terms and all(term_matches(t, folded, folded) for t in query.terms):
        rank = 2
    else:
        rank = 3
    return {
        "path": path, "name": name, "parent": os.path.dirname(path),
        "kind": kind, "url": Path(path).as_uri(),
        "parentUrl": Path(os.path.dirname(path)).as_uri(),
        "rank": rank, "personal": within(path, home),
    }


def sort_key(item):
    return (item["rank"], not item["personal"], len(item["name"]), item["path"].casefold())


def personal_roots(home: str):
    roots = [os.path.join(home, n) for n in ("Desktop", "Documents", "Downloads", "Pictures", "Music", "Videos", ".config")]
    # Respect XDG user-dir customizations without executing their shell syntax.
    user_dirs = Path(os.environ.get("XDG_CONFIG_HOME", os.path.join(home, ".config"))) / "user-dirs.dirs"
    try:
        for line in user_dirs.read_text().splitlines():
            if line.startswith("XDG_") and "_DIR=" in line:
                value = shlex.split(line.split("=", 1)[1])
                if value:
                    path = value[0].replace("${HOME}", home).replace("$HOME", home)
                    if os.path.isabs(path) and path != home:
                        roots.append(path)
    except (OSError, ValueError):
        pass
    return list(dict.fromkeys(p for p in roots if os.path.isdir(p)))


class Search:
    def __init__(self, request, *, home=None, roots=None, index_command="plocate"):
        self.request_id = request.get("requestId", 0)
        self.query = parse_query(str(request.get("query", ""))[:4096])
        self.limit = max(1, min(200, int(request.get("limit", 20))))
        self.home = home or str(Path.home())
        self.roots = roots if roots is not None else personal_roots(self.home)
        self.index_command = index_command
        self.items = {}
        self.notices = []
        self.partial = False
        self.child = None
        self.cancelled = False
        self.last_emit = 0.0
        self.dirty = False

    def stop(self, *_):
        self.cancelled = True
        if self.child and self.child.poll() is None:
            self.child.terminate()

    def add(self, path):
        if path in self.items:
            return
        item = candidate(path, self.query, self.home)
        if item:
            self.items[item["path"]] = item
            self.dirty = True
            # Bound memory as well as the number of rendered QML objects.
            if len(self.items) > self.limit * 4 + 100:
                self.items = {r["path"]: r for r in sorted(self.items.values(), key=sort_key)[:self.limit * 2]}

    def emit(self, busy, force=False):
        now = time.monotonic()
        if self.cancelled or (not force and (not self.dirty or now - self.last_emit < 0.2)):
            return
        rows = sorted(self.items.values(), key=sort_key)[:self.limit]
        print(json.dumps({
            "requestId": self.request_id, "results": rows, "busy": busy,
            "partial": self.partial, "message": " ".join(dict.fromkeys(self.notices)),
            "error": "",
        }, ensure_ascii=True), flush=True)
        self.last_emit, self.dirty = now, False

    def index(self):
        # plocate treats arguments as ANDed patterns. Widen glob patterns to
        # include path prefixes; candidate() applies the exact filename glob.
        patterns = [("*" + t if any(c in t for c in "*?[") else t) for t in self.query.terms]
        if self.query.extension:
            patterns.append("." + self.query.extension)
        if self.query.directory:
            # Escape metacharacters in a literal directory filter.
            directory = self.query.directory
            for char, replacement in (("[", "[[]"), ("*", "[*]"), ("?", "[?]")):
                directory = directory.replace(char, replacement)
            patterns.append("*" + directory.rstrip("/") + "/*")
        if not patterns:
            patterns = ["/"]
        command = [self.index_command, "-0", "-i", "-l", str(CANDIDATE_LIMIT + 1), "--", *patterns]
        try:
            self.child = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
        except OSError:
            self.partial = True
            self.notices.append("System index unavailable; searching live folders only.")
            return
        deadline, count, pending = time.monotonic() + INDEX_SECONDS, 0, b""
        try:
            with selectors.DefaultSelector() as selector:
                selector.register(self.child.stdout, selectors.EVENT_READ)
                while not self.cancelled:
                    remaining = deadline - time.monotonic()
                    if remaining <= 0 or count >= CANDIDATE_LIMIT:
                        self.partial = True
                        self.notices.append("Index search limited; narrow the name or folder.")
                        break
                    if not selector.select(min(remaining, 0.05)):
                        continue
                    chunk = os.read(self.child.stdout.fileno(), 65536)
                    if not chunk:
                        break
                    parts = (pending + chunk).split(b"\0")
                    pending = parts.pop()
                    for raw in parts:
                        if self.cancelled or count >= CANDIDATE_LIMIT or time.monotonic() >= deadline:
                            break
                        count += 1
                        self.add(os.fsdecode(raw))
                    self.emit(True)
            if self.child.poll() is None:
                self.child.terminate()
            code = self.child.wait(timeout=0.3)
            if code > 1:
                self.partial = True
                self.notices.append("System index unavailable; searching live folders only.")
        finally:
            if self.child.poll() is None:
                self.child.kill()
                self.child.wait()
            self.child.stdout.close()
            self.child = None

    def live(self):
        scoped = bool(self.query.directory)
        queue = deque([(self.query.directory, True)] if scoped else [(self.home, False)] + [(r, True) for r in self.roots])
        visited, count = set(), 0
        deadline = time.monotonic() + LIVE_SECONDS
        while queue and not self.cancelled:
            directory, recursive = queue.popleft()
            if directory in visited:
                continue
            visited.add(directory)
            try:
                with os.scandir(directory) as entries:
                    for entry in entries:
                        if self.cancelled:
                            return
                        if time.monotonic() >= deadline or count >= LIVE_LIMIT:
                            self.partial = True
                            self.notices.append("Live scan limited; use in: to narrow the folder.")
                            return
                        count += 1
                        self.add(entry.path)
                        if recursive and entry.is_dir(follow_symlinks=False):
                            if entry.name in SKIP_DIRS and not scoped:
                                continue
                            if any(within(entry.path, p) for p in PSEUDO_ROOTS):
                                continue
                            if not os.path.ismount(entry.path):
                                queue.append((entry.path, True))
                        self.emit(True)
            except OSError:
                self.partial = True
                self.notices.append("Some folders could not be read.")

    def run(self):
        if self.cancelled:
            return
        if not self.query.empty:
            self.index()
            self.emit(True, True)
            if not self.cancelled:
                self.live()
        self.emit(False, True)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--request", required=True)
    args = parser.parse_args()
    request = {}
    try:
        request = json.loads(args.request)
        if not isinstance(request, dict):
            raise ValueError("Search request must be an object.")
        search = Search(request)
        signal.signal(signal.SIGTERM, search.stop)
        signal.signal(signal.SIGINT, search.stop)
        search.run()
    except BrokenPipeError:
        pass
    except (ValueError, TypeError, OSError, subprocess.TimeoutExpired) as error:
        print(json.dumps({
            "requestId": request.get("requestId", 0) if isinstance(request, dict) else 0,
            "results": [], "busy": False, "partial": True,
            "message": "", "error": str(error),
        }), flush=True)


if __name__ == "__main__":
    main()
