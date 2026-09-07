#!/usr/bin/env python3
"""Filesystem and search backend for the sidebar AI agent.

Reads a JSON request on stdin and writes a JSON result on stdout:
    in:  {"tool": "read_file", "args": {...}, "cwd": "/home/user"}
    out: {"ok": true, "content": "...", "meta": {...}}

Keeping this out of QML avoids shell quoting bugs and makes exact-string
edits reliable.
"""

import fnmatch
import io
import json
import os
import re
import shutil
import subprocess
import sys

MAX_READ_LINES = 2000
MAX_READ_BYTES = 256 * 1024
MAX_LIST_ENTRIES = 400
MAX_GLOB_RESULTS = 200
MAX_SEARCH_RESULTS = 200
MAX_OUTPUT_CHARS = 60_000

SKIP_DIRS = {
    ".git", "node_modules", "__pycache__", ".venv", "venv", ".cache",
    "dist", "build", ".next", "target", ".mypy_cache", ".pytest_cache",
}


class ToolError(Exception):
    pass


def resolve(cwd, path, must_exist=False):
    if not path:
        raise ToolError("A path is required.")
    expanded = os.path.expanduser(str(path))
    full = expanded if os.path.isabs(expanded) else os.path.join(cwd, expanded)
    full = os.path.normpath(full)
    if must_exist and not os.path.exists(full):
        raise ToolError(f"No such file or directory: {full}")
    return full


def read_text(path):
    if os.path.isdir(path):
        raise ToolError(f"{path} is a directory. Use list_directory instead.")
    size = os.path.getsize(path)
    with open(path, "rb") as handle:
        raw = handle.read(MAX_READ_BYTES)
    if b"\0" in raw[:4096]:
        raise ToolError(f"{path} looks like a binary file.")
    truncated_bytes = size > len(raw)
    return raw.decode("utf-8", errors="replace"), truncated_bytes


def tool_read_file(args, cwd):
    path = resolve(cwd, args.get("path"), must_exist=True)
    text, truncated_bytes = read_text(path)
    lines = text.splitlines()
    offset = max(int(args.get("offset") or 1), 1)
    limit = int(args.get("limit") or MAX_READ_LINES)
    limit = max(1, min(limit, MAX_READ_LINES))
    window = lines[offset - 1: offset - 1 + limit]
    numbered = "\n".join(
        f"{offset + i:6d}\t{line}" for i, line in enumerate(window)
    )
    truncated = truncated_bytes or (offset - 1 + len(window)) < len(lines)
    return {
        "content": numbered or "(empty file)",
        "meta": {
            "path": path,
            "total_lines": len(lines),
            "shown": f"{offset}-{offset + len(window) - 1}" if window else "none",
            "truncated": truncated,
        },
    }


def tool_write_file(args, cwd):
    path = resolve(cwd, args.get("path"))
    content = args.get("content")
    if content is None:
        raise ToolError("`content` is required.")
    parent = os.path.dirname(path)
    if parent:
        os.makedirs(parent, exist_ok=True)
    existed = os.path.exists(path)
    with open(path, "w", encoding="utf-8") as handle:
        handle.write(content)
    return {
        "content": f"{'Overwrote' if existed else 'Created'} {path} "
                   f"({len(content.splitlines())} lines).",
        "meta": {"path": path, "created": not existed},
    }


def tool_edit_file(args, cwd):
    path = resolve(cwd, args.get("path"), must_exist=True)
    old = args.get("old_string")
    new = args.get("new_string")
    if old is None or new is None:
        raise ToolError("`old_string` and `new_string` are both required.")
    if old == new:
        raise ToolError("`old_string` and `new_string` are identical.")
    text, truncated = read_text(path)
    if truncated:
        raise ToolError(f"{path} is too large to edit safely.")
    count = text.count(old)
    replace_all = bool(args.get("replace_all"))
    if count == 0:
        raise ToolError(
            "`old_string` was not found. Read the file again and copy the "
            "exact text, including indentation."
        )
    if count > 1 and not replace_all:
        raise ToolError(
            f"`old_string` appears {count} times. Add more surrounding context "
            "to make it unique, or pass replace_all=true."
        )
    updated = text.replace(old, new) if replace_all else text.replace(old, new, 1)
    with open(path, "w", encoding="utf-8") as handle:
        handle.write(updated)
    return {
        "content": f"Replaced {count if replace_all else 1} occurrence(s) in {path}.",
        "meta": {"path": path, "replacements": count if replace_all else 1},
    }


def tool_list_directory(args, cwd):
    path = resolve(cwd, args.get("path") or ".", must_exist=True)
    if not os.path.isdir(path):
        raise ToolError(f"{path} is not a directory.")
    entries = sorted(os.listdir(path), key=str.lower)
    lines = []
    for name in entries[:MAX_LIST_ENTRIES]:
        full = os.path.join(path, name)
        if os.path.isdir(full):
            lines.append(f"{name}/")
        else:
            try:
                lines.append(f"{name}\t{os.path.getsize(full)}B")
            except OSError:
                lines.append(name)
    return {
        "content": "\n".join(lines) or "(empty directory)",
        "meta": {
            "path": path,
            "total": len(entries),
            "truncated": len(entries) > MAX_LIST_ENTRIES,
        },
    }


def walk_files(root, follow_hidden=False):
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [
            d for d in dirnames
            if d not in SKIP_DIRS and (follow_hidden or not d.startswith("."))
        ]
        for name in filenames:
            yield os.path.join(dirpath, name)


def tool_glob(args, cwd):
    pattern = args.get("pattern")
    if not pattern:
        raise ToolError("`pattern` is required, e.g. **/*.qml")
    root = resolve(cwd, args.get("path") or ".", must_exist=True)
    normalized = pattern[3:] if pattern.startswith("**/") else pattern
    matches = []
    for full in walk_files(root, follow_hidden=True):
        rel = os.path.relpath(full, root)
        base = os.path.basename(full)
        if fnmatch.fnmatch(rel, pattern) or fnmatch.fnmatch(rel, normalized) \
                or fnmatch.fnmatch(base, normalized):
            matches.append(full)
            if len(matches) >= MAX_GLOB_RESULTS * 4:
                break
    matches.sort(key=lambda p: -os.path.getmtime(p) if os.path.exists(p) else 0)
    shown = matches[:MAX_GLOB_RESULTS]
    return {
        "content": "\n".join(shown) or f"No files matching {pattern} under {root}",
        "meta": {
            "pattern": pattern,
            "root": root,
            "count": len(shown),
            "truncated": len(matches) > len(shown),
        },
    }


def search_with_ripgrep(pattern, root, glob):
    binary = shutil.which("rg")
    if not binary:
        return None
    command = [binary, "--line-number", "--no-heading", "--color", "never",
               "--max-count", "50", "-e", pattern]
    if glob:
        command += ["--glob", glob]
    command.append(root)
    try:
        done = subprocess.run(command, capture_output=True, text=True, timeout=25)
    except (subprocess.TimeoutExpired, OSError):
        return None
    if done.returncode not in (0, 1):
        return None
    return done.stdout.splitlines()


def search_with_python(pattern, root, glob):
    try:
        regex = re.compile(pattern)
    except re.error as exc:
        raise ToolError(f"Invalid regex: {exc}") from exc
    hits = []
    for full in walk_files(root):
        if glob and not fnmatch.fnmatch(os.path.basename(full), glob):
            continue
        try:
            with open(full, "r", encoding="utf-8", errors="replace") as handle:
                for number, line in enumerate(handle, 1):
                    if regex.search(line):
                        hits.append(f"{full}:{number}:{line.rstrip()}")
                        if len(hits) >= MAX_SEARCH_RESULTS * 2:
                            return hits
        except (OSError, UnicodeDecodeError):
            continue
    return hits


def tool_search_files(args, cwd):
    pattern = args.get("pattern")
    if not pattern:
        raise ToolError("`pattern` is required.")
    root = resolve(cwd, args.get("path") or ".", must_exist=True)
    glob = args.get("glob")
    hits = search_with_ripgrep(pattern, root, glob)
    if hits is None:
        hits = search_with_python(pattern, root, glob)
    shown = hits[:MAX_SEARCH_RESULTS]
    return {
        "content": "\n".join(shown) or f"No matches for {pattern!r} under {root}",
        "meta": {
            "pattern": pattern,
            "root": root,
            "count": len(shown),
            "truncated": len(hits) > len(shown),
        },
    }


TOOLS = {
    "read_file": tool_read_file,
    "write_file": tool_write_file,
    "edit_file": tool_edit_file,
    "list_directory": tool_list_directory,
    "glob_files": tool_glob,
    "search_files": tool_search_files,
}


def main():
    try:
        request = json.load(sys.stdin)
    except (json.JSONDecodeError, UnicodeDecodeError) as exc:
        json.dump({"ok": False, "error": f"Malformed request: {exc}"}, sys.stdout)
        return 0

    name = request.get("tool")
    args = request.get("args") or {}
    cwd = request.get("cwd") or os.path.expanduser("~")
    if not os.path.isdir(cwd):
        cwd = os.path.expanduser("~")

    handler = TOOLS.get(name)
    if handler is None:
        json.dump({
            "ok": False,
            "error": f"Unknown tool {name!r}. Available: {', '.join(sorted(TOOLS))}",
        }, sys.stdout)
        return 0

    try:
        result = handler(args, cwd)
        content = result.get("content", "")
        if len(content) > MAX_OUTPUT_CHARS:
            content = content[:MAX_OUTPUT_CHARS] + "\n\n[[ output truncated ]]"
            result["content"] = content
        payload = {"ok": True, **result}
    except ToolError as exc:
        payload = {"ok": False, "error": str(exc)}
    except OSError as exc:
        payload = {"ok": False, "error": f"{type(exc).__name__}: {exc}"}
    except Exception as exc:  # surface bugs to the model instead of dying silently
        payload = {"ok": False, "error": f"Internal error: {type(exc).__name__}: {exc}"}

    json.dump(payload, sys.stdout)
    return 0


if __name__ == "__main__":
    sys.exit(main())
