#!/usr/bin/env python3
"""Lyrics lookup for the shell's media widgets.

Prints JSON objects on stdout, one per line, each with a `status` of "ok", "not_found" or "no_info".
Usually there is exactly one. When line-timed lyrics are already in hand and word timings are still
being fetched, the line-timed answer is printed first and the better one replaces it a few seconds
later, so nothing waits on the slower source.

Successful lookups are cached on disk so switching back to a track is instant and lrclib.net is
only asked once per song; failures are cached briefly so a track with no lyrics anywhere doesn't
re-query on every replay.

Timings come back per line, and per word for the sources that publish them: enhanced LRC word tags
and Musixmatch's richsync. Word timings are never invented -- a line with none reports none, and the
view wipes across it at reading pace instead of pretending to know when each word is sung.

Every request goes out directly first and is retried through a local proxy when one is listening, so
a source that this network blocks still resolves without the whole system having to be tunnelled.

usage: lyrics.py TITLE ARTIST DURATION [ALBUM] [URL] [--refresh] [--no-richsync]

--refresh ignores a cached answer and looks the track up again, which is what the reload button in
the lyrics view sends: without it a wrong match would keep being served from disk for months.
--no-richsync skips the Musixmatch word timing lookup.
"""

import functools
import hashlib
import http.client
import json
import os
import re
import socket
import ssl
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from difflib import SequenceMatcher
from pathlib import Path

API = "https://lrclib.net/api"
UA = "quickshell-illogical-impulse-lyrics/1.0 (https://github.com/end-4/dots-hyprland)"
TIMEOUT = 8.0
POSITIVE_TTL = 120 * 24 * 3600
NEGATIVE_TTL = 6 * 3600
# A gap this long between sung lines is an instrumental break worth showing as one
INTERLUDE_GAP = 4.5

CACHE_DIR = Path(os.environ.get("XDG_CACHE_HOME") or (Path.home() / ".cache")) / "quickshell" / "media" / "lyrics"
USER_LYRICS_DIR = Path(os.environ.get("XDG_CONFIG_HOME") or (Path.home() / ".config")) / "illogical-impulse" / "lyrics"


_emitted = False


def out(payload: dict) -> None:
    global _emitted
    print(json.dumps(payload, ensure_ascii=False, separators=(",", ":")), flush=True)
    _emitted = True


def fail(status: str = "not_found") -> None:
    # Only when nothing has been printed yet: a crash while looking for a better answer must not
    # replace a good one that already went out
    if not _emitted:
        out({"status": status, "lines": []})
    sys.exit(0)


# ---------------------------------------------------------------- cleaning

# Bracketed noise that stops a YouTube title from matching a release title. Anything that names a
# different *recording* (live, acoustic, remix, sped up) is dropped too: a remix almost never has
# its own synced lyrics, and the original's are close enough to be useful.
_BRACKET_NOISE = re.compile(
    r"""[\(\[\{]\s*(?:
        (?:the\s+)?official(?:\s+\w+){0,3}|
        (?:\w+\s+){0,2}(?:music|lyric|lyrics)\s*(?:video|visuali[sz]er)|
        lyrics?|audio|visuali[sz]er|video|hd|hq|uhd|4k|8k|full\s*album|
        remaster(?:ed)?(?:\s*\d{4})?|\d{4}\s*remaster(?:ed)?|
        explicit|clean|radio\s*edit|album\s*version|single\s*version|
        stereo|mono|anniversary\s*edition|deluxe|bonus\s*track|
        live(?:\s*[@at]{1,2}\s*[^\)\]\}]*)?|acoustic|unplugged|
        instrumental|karaoke|cover|remix|rmx|extended(?:\s*mix)?|vip\s*mix|
        slowed(?:\s*\+?\s*reverb)?|sped\s*up|nightcore|8d\s*audio|
        free\s*(?:download|dl)|out\s*now|lyric\s*by[^\)\]\}]*|
        prod\.?\s*(?:by)?[^\)\]\}]*|dir\.?\s*by[^\)\]\}]*|
        (?:feat|ft|featuring|with)\.?\s[^\)\]\}]*
    )\s*[\)\]\}]""",
    re.IGNORECASE | re.VERBOSE,
)

_TRAILING_NOISE = re.compile(
    r"\s*(?:[-–—|/]+\s*)?(?:"
    r"official\s*(?:music\s*)?(?:video|audio|visuali[sz]er)|"
    r"(?:official\s*)?lyrics?(?:\s*video)?|lyric\s*video|"
    r"music\s*video|m/?v|audio\s*only|visuali[sz]er|"
    r"hd|hq|4k|8k|full\s*hd|free\s*download"
    r")\s*$",
    re.IGNORECASE,
)

_FEAT = re.compile(r"\s*(?:[\(\[]\s*)?\b(?:feat|ft|featuring)\b\.?\s+[^\)\]\[\(]*(?:[\)\]])?", re.IGNORECASE)
_TRACK_NUMBER = re.compile(r"^\s*\d{1,2}\s*[\.\-–)]\s+")
_CHANNEL_SUFFIX = re.compile(r"\s*[-–—]\s*(?:topic|official|vevo|music|records?)\s*$", re.IGNORECASE)
_MULTISPACE = re.compile(r"\s{2,}")


def clean_title(title: str, keep_feat: bool = False) -> str:
    text = title or ""
    text = _TRACK_NUMBER.sub("", text)
    for _ in range(3):
        stripped = _BRACKET_NOISE.sub(" ", text)
        stripped = _TRAILING_NOISE.sub("", stripped)
        if stripped == text:
            break
        text = stripped
    if not keep_feat:
        text = _FEAT.sub("", text)
    # Leftover empty brackets from partial matches
    text = re.sub(r"[\(\[\{]\s*[\)\]\}]", " ", text)
    text = _MULTISPACE.sub(" ", text)
    return text.strip(" -–—|·,")


def clean_artist(artist: str) -> str:
    text = _CHANNEL_SUFFIX.sub("", artist or "")
    text = _FEAT.sub("", text)
    # "A, B & C" and "A x B" collapse to the first credited artist, which is how releases are filed
    text = re.split(r"\s*(?:,|&|/|\bx\b|\bvs\.?\b|\bwith\b|\band\b)\s+", text, maxsplit=1)[0]
    return _MULTISPACE.sub(" ", text).strip()


def split_embedded_artist(title: str, artist: str) -> tuple:
    """YouTube titles are usually "Artist - Song" with the channel as the artist."""
    parts = re.split(r"\s+[-–—]\s+", title, maxsplit=1)
    if len(parts) != 2:
        return title, artist
    lead, rest = (p.strip() for p in parts)
    if not lead or not rest:
        return title, artist
    known = norm(artist)
    # Only trust the split when the artist is missing, or when the leading half is the artist
    if not known or similar(norm(lead), known) > 0.7 or norm(lead) in known or known in norm(lead):
        return rest, (artist or lead)
    return title, artist


def norm(text: str) -> str:
    text = (text or "").lower()
    text = re.sub(r"[’'`´]", "", text)
    text = re.sub(r"[^\w\s]+", " ", text, flags=re.UNICODE)
    return _MULTISPACE.sub(" ", text).strip()


def similar(a: str, b: str) -> float:
    if not a or not b:
        return 0.0
    return SequenceMatcher(None, a, b).ratio()


# ---------------------------------------------------------------- LRC parsing

_TIME_TAG = re.compile(r"\[(\d{1,3}):(\d{1,2}(?:[.:]\d{1,3})?)\]")
_WORD_TAG = re.compile(r"<(\d{1,3}):(\d{1,2}(?:[.:]\d{1,3})?)>")
_META_TAG = re.compile(r"^\[(ar|ti|al|au|by|re|ve|length|offset|tool|encoding)\s*:(.*)\]\s*$", re.IGNORECASE)


def _seconds(minutes: str, rest: str) -> float:
    rest = rest.replace(":", ".")
    try:
        return int(minutes) * 60 + float(rest)
    except ValueError:
        return 0.0


def parse_lrc(text: str) -> tuple:
    """Returns (lines, synced). Each line is {t, x, w} with w as [start, end, word] triples."""
    offset = 0.0
    entries = []
    plain_only = []

    for raw in (text or "").splitlines():
        raw = raw.strip()
        if not raw:
            continue
        meta = _META_TAG.match(raw)
        if meta:
            if meta.group(1).lower() == "offset":
                try:
                    # Positive offset means the lyrics are shown early, so it subtracts
                    offset = -float(meta.group(2).strip().replace("+", "")) / 1000.0
                except ValueError:
                    pass
            continue

        stamps = list(_TIME_TAG.finditer(raw))
        if not stamps:
            plain_only.append(raw)
            continue
        body = raw[stamps[-1].end():]
        words = parse_word_tags(body)
        text_only = _WORD_TAG.sub("", body).strip()
        for stamp in stamps:
            start = _seconds(stamp.group(1), stamp.group(2))
            shift = start - (words[0][0] if words else start)
            entries.append({
                "t": start,
                "x": text_only,
                "w": [[w[0] + shift, w[1] + shift, w[2]] for w in words],
            })

    if not entries:
        return [line for line in plain_only], False
    if offset:
        for entry in entries:
            entry["t"] = max(0.0, entry["t"] + offset)
            entry["w"] = [[max(0.0, w[0] + offset), max(0.0, w[1] + offset), w[2]] for w in entry["w"]]
    entries.sort(key=lambda e: e["t"])
    return entries, True


def parse_word_tags(body: str) -> list:
    """Enhanced LRC: `<00:12.34>word <00:12.90>word`. Ends are filled in from the next tag."""
    tags = list(_WORD_TAG.finditer(body))
    if not tags:
        return []
    words = []
    for index, tag in enumerate(tags):
        start = _seconds(tag.group(1), tag.group(2))
        end_of_text = tags[index + 1].start() if index + 1 < len(tags) else len(body)
        word = body[tag.end():end_of_text].strip()
        if not word:
            continue
        words.append([start, None, word])
    for index, word in enumerate(words):
        following = words[index + 1][0] if index + 1 < len(words) else None
        word[1] = following if following is not None else word[0] + 0.6
    return words


def reading_span(text: str) -> float:
    """How long a wipe across this line should take when the source gives no word timings.

    Only a cap: the view wipes from the line's start to whichever comes first, this or the next
    line. It exists so a two word line followed by ten seconds of silence doesn't creep across the
    screen -- for ordinary lines the gap to the next one is shorter and wins.
    """
    return max(1.0, 0.34 * len(text) + 0.9)


def build_lines(entries: list) -> list:
    """Fills in line ends and marks instrumental breaks.

    A line's `w` stays empty unless the source really timed its words. The view checks that: word
    timings drive a per word sweep, no word timings drive a smooth wipe across the whole line.
    Guessing per word times from character counts was worse than not guessing -- every singer who
    holds a syllable or rushes a phrase makes the guess visibly wrong.
    """
    lines = []
    for index, entry in enumerate(entries):
        start = float(entry["t"])
        following = float(entries[index + 1]["t"]) if index + 1 < len(entries) else start + 8.0
        text = (entry.get("x") or "").strip()
        words = entry.get("w") or []
        if words:
            end = min(following, max(words[-1][1], start + 0.4))
        elif text:
            end = min(following, start + reading_span(text))
        else:
            end = following
        lines.append({
            "t": round(start, 3),
            "e": round(max(end, start + 0.2), 3),
            "x": text,
            "w": [[round(w[0], 3), round(w[1], 3), w[2]] for w in words],
            "i": not text,
        })
    return insert_interludes(lines)


def insert_interludes(lines: list) -> list:
    """Turns long silences into their own entries so the view can show a countdown there."""
    if not lines:
        return lines
    result = []
    first = lines[0]["t"]
    if first >= INTERLUDE_GAP:
        result.append({"t": 0.0, "e": round(first, 3), "x": "", "w": [], "i": True})
    for index, line in enumerate(lines):
        # Empty source lines already mark breaks; give them the whole gap and drop the duplicates
        if line["i"] and result and result[-1]["i"]:
            result[-1]["e"] = line["e"]
            continue
        result.append(line)
        following = lines[index + 1]["t"] if index + 1 < len(lines) else None
        if following is None:
            continue
        if following - line["e"] >= INTERLUDE_GAP:
            result.append({"t": line["e"], "e": round(following, 3), "x": "", "w": [], "i": True})
    return result


# ---------------------------------------------------------------- network routes

# Requests can go out two ways: straight out, or through a proxy already running on this machine --
# v2rayN/xray's SOCKS inbound, or whatever $ALL_PROXY names. Direct is always tried first. It is
# faster, and a proxy is not automatically an improvement: a source that answers a home connection
# fine may refuse the datacenter IP a VPN exits from, which is exactly what Musixmatch does.
PROXY_ENV = ("LYRICS_PROXY", "ALL_PROXY", "all_proxy", "HTTPS_PROXY", "https_proxy")
# v2rayN/xray's default SOCKS inbound, the generic SOCKS port, then v2rayN's HTTP inbound
PROXY_PORTS = (("socks5", 10808), ("socks5", 1080), ("http", 10809))
# Only bounds the wait on a proxy that swallows connections: a port with nothing behind it refuses
# instantly, so the usual "no proxy running" case costs nothing measurable
PROXY_PROBE_TIMEOUT = 0.6


def port_open(host: str, port: int) -> bool:
    try:
        with socket.create_connection((host, port), timeout=PROXY_PROBE_TIMEOUT):
            return True
    except Exception:
        return False


@functools.lru_cache(maxsize=1)
def local_proxy() -> tuple:
    """(kind, host, port) of a proxy that is actually listening, or () when there is none."""
    for name in PROXY_ENV:
        parsed = urllib.parse.urlparse(os.environ.get(name) or "")
        if parsed.hostname and parsed.port:
            kind = "http" if parsed.scheme.startswith("http") else "socks5"
            if port_open(parsed.hostname, parsed.port):
                return (kind, parsed.hostname, parsed.port)
    for kind, port in PROXY_PORTS:
        if port_open("127.0.0.1", port):
            return (kind, "127.0.0.1", port)
    return ()


@functools.lru_cache(maxsize=2)
def opener(route: str):
    """A urllib opener for "direct" or "proxy"; None when that route isn't available here."""
    if route != "proxy":
        # An explicit empty ProxyHandler, so an environment proxy can't quietly redirect the route
        # that is meant to be the unproxied one
        return urllib.request.build_opener(urllib.request.ProxyHandler({}))
    found = local_proxy()
    if not found:
        return None
    kind, host, port = found
    if kind == "http":
        address = f"http://{host}:{port}"
        return urllib.request.build_opener(urllib.request.ProxyHandler({"http": address, "https": address}))
    try:
        import socks  # PySocks; urllib has no SOCKS support of its own
    except ImportError:
        return None
    # rdns keeps name resolution at the proxy, which matters when the local resolver is the thing
    # answering wrongly
    dial = functools.partial(socks.create_connection, proxy_type=socks.SOCKS5,
                             proxy_addr=host, proxy_port=port, proxy_rdns=True)

    class SocksHTTPSConnection(http.client.HTTPSConnection):
        def __init__(self, *args, **kwargs):
            super().__init__(*args, **kwargs)
            # http.client dials through this attribute, so the proxy swaps in as one function and
            # everything above it -- TLS, SNI, redirects -- stays stock
            self._create_connection = dial

    class SocksHTTPSHandler(urllib.request.HTTPSHandler):
        def https_open(self, request):
            return self.do_open(SocksHTTPSConnection, request, context=self._context)

    return urllib.request.build_opener(SocksHTTPSHandler(context=ssl.create_default_context()),
                                       urllib.request.ProxyHandler({}))


def routes() -> tuple:
    """The routes to try, in order. Just ("direct",) unless a proxy is up."""
    return ("direct", "proxy") if opener("proxy") is not None else ("direct",)


# ---------------------------------------------------------------- sources

def http_json(url: str, route: str = "direct"):
    request = urllib.request.Request(url, headers={"User-Agent": UA, "Accept": "application/json"})
    with opener(route).open(request, timeout=TIMEOUT) as response:
        return json.loads(response.read().decode("utf-8", "replace"))


def score(candidate: dict, title: str, artist: str, duration: float) -> float:
    got_title = norm(candidate.get("trackName") or "")
    got_artist = norm(candidate.get("artistName") or "")
    want_title = norm(title)
    want_artist = norm(artist)

    title_score = max(
        similar(got_title, want_title),
        1.0 if (want_title and (want_title in got_title or got_title in want_title)) else 0.0,
    )
    artist_score = max(
        similar(got_artist, want_artist),
        1.0 if (want_artist and (want_artist in got_artist or got_artist in want_artist)) else 0.0,
    )
    if title_score < 0.55:
        return -1.0
    if want_artist and artist_score < 0.4:
        return -1.0

    total = title_score * 3.0 + artist_score * 2.0
    got_duration = candidate.get("duration") or 0
    if duration > 0 and got_duration:
        total += 2.0 * max(0.0, 1.0 - min(1.0, abs(got_duration - duration) / 12.0))
    if candidate.get("syncedLyrics"):
        total += 1.5
    return total


MAX_REQUESTS = 7
GOOD_ENOUGH = 6.5


def lrclib_lookup(variants: list, album: str, duration: float, route: str = "direct") -> tuple:
    """Returns (best_candidate, best_score, answered) across a few phrasings of the same search.

    `answered` distinguishes "asked and it has nothing" from "could not ask", so a network failure
    can be retried through the proxy while an honest miss is not searched for twice.
    """
    best = None
    best_score = 0.0
    answered = False
    seen_urls = set()
    requests_left = MAX_REQUESTS

    for title, artist in variants:
        if requests_left <= 0:
            break
        for url in _urls_for(title, artist, album, duration):
            if requests_left <= 0 or url in seen_urls:
                continue
            seen_urls.add(url)
            requests_left -= 1
            try:
                data = http_json(url, route)
                answered = True
            except urllib.error.HTTPError:
                # A 404 is lrclib saying it has no such track, which is still an answer
                answered = True
                continue
            except Exception:
                continue
            for candidate in (data if isinstance(data, list) else [data]):
                if not isinstance(candidate, dict):
                    continue
                value = score(candidate, title, artist, duration)
                # Prefer a synced hit even when a plain one scores marginally higher
                if value > best_score or (value > 0 and candidate.get("syncedLyrics")
                                          and not (best or {}).get("syncedLyrics")):
                    best, best_score = candidate, value
            if best_score >= GOOD_ENOUGH and (best or {}).get("syncedLyrics"):
                return best, best_score, True
    return best, best_score, answered


def _urls_for(title: str, artist: str, album: str, duration: float) -> list:
    if not title:
        return []
    urls = []
    if artist:
        exact = {"track_name": title, "artist_name": artist}
        if album:
            exact["album_name"] = album
        if duration > 0:
            exact["duration"] = str(int(round(duration)))
        if len(exact) > 2:
            urls.append(f"{API}/get?{urllib.parse.urlencode(exact)}")
        urls.append(f"{API}/get?{urllib.parse.urlencode({'track_name': title, 'artist_name': artist})}")
        urls.append(f"{API}/search?{urllib.parse.urlencode({'track_name': title, 'artist_name': artist})}")
    urls.append(f"{API}/search?{urllib.parse.urlencode({'q': f'{title} {artist}'.strip()})}")
    return urls


# ---------------------------------------------------------------- musixmatch (word timings)

# lrclib only stores line timings, so word level sync comes from Musixmatch's richsync, the one free
# source that publishes it.
#
# `apic-desktop.musixmatch.com`, the host every third party lyrics tool used for this, now resolves
# to 127.0.0.1 worldwide: Musixmatch retired it by pointing its own DNS at loopback. That is worth
# writing down because of how the failure presents -- the connection is refused instantly, which
# reads exactly like a local firewall or a censored domain, and sends you looking for a proxy that
# cannot help. The Android player's endpoint still answers and still hands out a token for nothing,
# so it goes first; the dead host stays behind it in case this one is retired the same way.
MXM_ENDPOINTS = (
    ("https://apic.musixmatch.com/ws/1.1/", "android-player-v1.0"),
    ("https://apic-desktop.musixmatch.com/ws/1.1/", "web-desktop-app-v1.0"),
)
MXM_TIMEOUT = 6.0
MXM_TOKEN_TTL = 12 * 3600
MXM_BLOCK_TTL = 600
BROWSER_UA = "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Safari/537.36"


def mxm_get(base: str, app: str, path: str, params: dict, route: str):
    query = {**params, "format": "json", "app_id": app}
    request = urllib.request.Request(
        base + path + "?" + urllib.parse.urlencode(query),
        # These endpoints answer 401 without a browser agent and want the load balancer cookies
        # present
        headers={"User-Agent": BROWSER_UA, "Cookie": "AWSELB=0; AWSELBCORS=0"},
    )
    with opener(route).open(request, timeout=MXM_TIMEOUT) as response:
        payload = json.loads(response.read().decode("utf-8", "replace"))
    message = payload.get("message") or {}
    # The status lives in the body, not the HTTP status. 401 with hint "upgrade" or "captcha" means
    # this app_id is not welcome at this endpoint, which is a reason to try the next endpoint rather
    # than to give up on the route
    if (message.get("header") or {}).get("status_code") != 200:
        return None
    return message.get("body") or {}


def _mxm_marker(name: str) -> Path:
    return CACHE_DIR / f"musixmatch.{name}"


def mxm_blocked(route: str) -> bool:
    try:
        marker = _mxm_marker(f"unreachable.{route}")
        return marker.is_file() and time.time() - marker.stat().st_mtime < MXM_BLOCK_TTL
    except Exception:
        return False


def mxm_block(route: str) -> None:
    # Per route, so bringing a proxy up is not shut out by a marker the direct attempt left behind
    try:
        CACHE_DIR.mkdir(parents=True, exist_ok=True)
        _mxm_marker(f"unreachable.{route}").write_text("", encoding="utf-8")
    except Exception:
        pass


def mxm_token(base: str, app: str, route: str) -> str:
    # Tokens are tied to the app_id, and plausibly to the address that asked for one, so a token
    # minted through the proxy is not reused on the direct route
    path = _mxm_marker(f"token.{app}.{route}.json")
    try:
        if path.is_file() and time.time() - path.stat().st_mtime < MXM_TOKEN_TTL:
            token = json.loads(path.read_text(encoding="utf-8")).get("token") or ""
            if token:
                return token
    except Exception:
        pass
    body = mxm_get(base, app, "token.get", {"t": str(int(time.time()))}, route) or {}
    token = body.get("user_token") or ""
    if token and token != "UpgradeOnlyUponRegistration":
        try:
            CACHE_DIR.mkdir(parents=True, exist_ok=True)
            path.write_text(json.dumps({"token": token}), encoding="utf-8")
        except Exception:
            pass
        return token
    return ""


def parse_richsync(raw: str) -> list:
    """Richsync bodies are JSON: per line `ts`/`te` plus `l`, the chunks with offsets from `ts`."""
    try:
        items = json.loads(raw)
    except Exception:
        return []
    entries = []
    for item in items if isinstance(items, list) else []:
        if not isinstance(item, dict):
            continue
        try:
            start = float(item.get("ts") or 0)
            end = float(item.get("te") or 0) or start
        except (TypeError, ValueError):
            continue
        chunks = [c for c in (item.get("l") or []) if isinstance(c, dict)]
        words = []
        for index, chunk in enumerate(chunks):
            text = str(chunk.get("c") or "")
            try:
                offset = float(chunk.get("o") or 0)
            except (TypeError, ValueError):
                continue
            # A word ends where the next chunk begins; the spaces between words are chunks too,
            # which is exactly the boundary wanted here
            following = offset
            if index + 1 < len(chunks):
                try:
                    following = float(chunks[index + 1].get("o") or offset)
                except (TypeError, ValueError):
                    following = offset
            else:
                following = max(offset, end - start)
            if not text.strip():
                continue
            words.append([start + offset, start + max(following, offset + 0.08), text.strip()])
        # Rebuilt from the chunks, spaces included, rather than taken from `x`: the view finds each
        # word inside this string to know where to draw, so it has to be the string the words came
        # from. `x` is the same line, but not always character for character.
        text = "".join(str(c.get("c") or "") for c in chunks).strip() or (item.get("x") or "").strip()
        if not text:
            continue
        entries.append({"t": start, "x": text, "w": words})
    entries.sort(key=lambda e: e["t"])
    return entries


def musixmatch_richsync(variants: list, duration: float) -> tuple:
    """(word timed lyrics for the first variant Musixmatch matches or {}, whether it was asked).

    The second half matters: "asked, and this track has no word timings" is worth remembering,
    while "could not ask" must not be, or one unreachable moment would mark a track as having no
    word timings for as long as its lyrics stay cached. Never raises.
    """
    asked = False
    for route in routes():
        if mxm_blocked(route):
            continue
        got_token = False
        for base, app in MXM_ENDPOINTS:
            # Per endpoint, so the retired host failing to connect says nothing about the route
            try:
                token = mxm_token(base, app, route)
                if not token:
                    continue
                got_token = True
                found = mxm_match(base, app, route, token, variants, duration)
                if found:
                    return found, True
                asked = True
            except Exception:
                continue
        # No endpoint would hand out a token, from unreachability or refusal. Either way this route
        # can do nothing right now, so remember that briefly instead of paying for it every track.
        if not got_token:
            mxm_block(route)
    return {}, asked


def mxm_match(base: str, app: str, route: str, token: str, variants: list, duration: float) -> dict:
    for title, artist in variants[:2]:
        if not artist:
            continue
        query = {"q_track": title, "q_artist": artist, "usertoken": token}
        if duration > 0:
            query["q_duration"] = str(int(round(duration)))
        track = (mxm_get(base, app, "matcher.track.get", query, route) or {}).get("track") or {}
        if not track.get("has_richsync"):
            continue
        # The matcher answers with something for almost any query -- asking for "APT." returns
        # "Rose" -- so its answer has to clear the same bar as an lrclib candidate
        if score({"trackName": track.get("track_name") or "",
                  "artistName": track.get("artist_name") or "",
                  "duration": track.get("track_length") or 0}, title, artist, duration) < 0:
            continue
        body = mxm_get(base, app, "track.richsync.get",
                       {"track_id": track.get("track_id"), "usertoken": token,
                        "subtitle_format": "mxm"}, route)
        entries = parse_richsync(((body or {}).get("richsync") or {}).get("richsync_body") or "")
        if entries:
            return {"entries": entries,
                    "title": track.get("track_name") or title,
                    "artist": track.get("artist_name") or artist}
    return {}


def local_lrc(url: str, title: str, artist: str) -> str:
    """A `.lrc` next to the audio file, or one dropped in the user's lyrics folder, wins."""
    paths = []
    if url and url.startswith("file://"):
        try:
            audio = Path(urllib.parse.unquote(urllib.parse.urlparse(url).path))
            paths += [audio.with_suffix(".lrc"), audio.with_suffix(".LRC"), audio.with_suffix(".txt")]
        except Exception:
            pass
    for stem in (f"{artist} - {title}", f"{title} - {artist}", title):
        if stem.strip(" -"):
            paths.append(USER_LYRICS_DIR / f"{stem}.lrc")
    for path in paths:
        try:
            if path.is_file():
                return path.read_text(encoding="utf-8", errors="replace")
        except Exception:
            continue
    return ""


# ---------------------------------------------------------------- cache

def cache_key(title: str, artist: str) -> str:
    return hashlib.sha1(f"{norm(title)}|{norm(artist)}".encode("utf-8")).hexdigest()


# Bumped whenever a lookup can produce something the previous one couldn't. Cached answers from
# before the bump get one more attempt at the better source instead of serving the old shape for the
# rest of their 120 days.
RICH_GENERATION = 3


def needs_rich_upgrade(payload: dict, want_richsync: bool) -> bool:
    return (want_richsync and payload.get("status") == "ok" and not payload.get("instrumental")
            and not payload.get("wordSynced") and payload.get("rich") != RICH_GENERATION)


def read_cache(key: str) -> dict:
    path = CACHE_DIR / f"{key}.json"
    try:
        if not path.is_file():
            return {}
        age = time.time() - path.stat().st_mtime
        payload = json.loads(path.read_text(encoding="utf-8"))
        ttl = POSITIVE_TTL if payload.get("status") == "ok" else NEGATIVE_TTL
        if age > ttl:
            return {}
        return payload
    except Exception:
        return {}


def from_cache(payload: dict) -> dict:
    """The same answer, labelled for the view. Kept out of read_cache so a payload that came off
    disk can be written back without the label being baked into its source."""
    return {**payload, "source": f"{payload.get('source', 'cache')} (cached)"}


def write_cache(key: str, payload: dict) -> None:
    try:
        CACHE_DIR.mkdir(parents=True, exist_ok=True)
        target = CACHE_DIR / f"{key}.json"
        temporary = CACHE_DIR / f".{key}.{os.getpid()}.tmp"
        temporary.write_text(json.dumps(payload, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
        temporary.replace(target)
    except Exception:
        pass


# ---------------------------------------------------------------- entry point

def synced_payload(entries: list, source: str, title: str, artist: str) -> dict:
    lines = build_lines(entries)
    return {
        "status": "ok", "synced": True, "instrumental": False, "source": source,
        "title": title, "artist": artist, "plain": "",
        # Whether the view may sweep word by word, or should wipe across whole lines instead
        "wordSynced": any(line["w"] for line in lines),
        "lines": lines,
    }


def payload_from_lrc(lrc: str, plain: str, source: str, title: str, artist: str) -> dict:
    entries, synced = parse_lrc(lrc) if lrc else ([], False)
    if synced and entries:
        return synced_payload(entries, source, title, artist)
    text = plain or ("\n".join(entries) if entries and not synced else "")
    if text.strip():
        return {
            "status": "ok", "synced": False, "instrumental": False, "source": source,
            "title": title, "artist": artist, "plain": text, "wordSynced": False,
            "lines": [{"t": -1, "e": -1, "x": line.strip(), "w": [], "i": not line.strip()}
                      for line in text.splitlines()],
        }
    return {}


def main() -> None:
    flags = {a for a in sys.argv[1:] if a.startswith("--")}
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    refresh = "--refresh" in flags
    want_richsync = "--no-richsync" not in flags
    if len(args) < 3:
        fail("no_info")
    raw_title = args[0]
    raw_artist = args[1]
    try:
        duration = float(args[2] or 0)
    except ValueError:
        duration = 0.0
    album = clean_title(args[3]) if len(args) > 3 else ""
    url = args[4] if len(args) > 4 else ""

    if not (raw_title or "").strip():
        fail("no_info")

    title = clean_title(raw_title) or raw_title.strip()
    artist = clean_artist(raw_artist)
    title, artist = split_embedded_artist(title, artist)

    # Cleaning can be too eager -- "Chicago (Remix)" really is its own track sometimes -- so the
    # untouched strings get a turn as well, after the tidied ones.
    variants = []
    for pair in ((title, artist),
                 (clean_title(raw_title, keep_feat=True), artist),
                 ((raw_title or "").strip(), (raw_artist or "").strip()),
                 (title, "")):
        if pair[0] and pair not in variants:
            variants.append(pair)

    key = cache_key(title, artist)
    cached = {} if refresh else read_cache(key)
    if cached:
        # Answer from disk first, always. An upgrade attempt costs a few round trips and there is no
        # reason to make a track that already has lyrics wait through them.
        out(from_cache(cached))
        if not needs_rich_upgrade(cached, want_richsync):
            return
        rich, asked = musixmatch_richsync(variants, duration)
        if rich:
            payload = synced_payload(rich["entries"], "musixmatch", rich["title"], rich["artist"])
            payload["rich"] = RICH_GENERATION
            write_cache(key, payload)
            out(payload)
        elif asked:
            # Asked and this track has none; don't ask again. If it couldn't be asked, the cache is
            # left alone so the next play tries once more.
            cached["rich"] = RICH_GENERATION
            write_cache(key, cached)
        return

    payload = payload_from_lrc(local_lrc(url, title, artist), "", "local file", title, artist)
    if payload:
        write_cache(key, payload)
        out(payload)
        return

    best, _, answered = lrclib_lookup(variants, album, duration)
    if not best and not answered and "proxy" in routes():
        # Nothing answered at all, so this is the network rather than a track nobody has synced
        best, _, _ = lrclib_lookup(variants, album, duration, "proxy")
    if best:
        if best.get("instrumental"):
            payload = {"status": "ok", "synced": False, "instrumental": True, "source": "lrclib",
                       "title": best.get("trackName") or title, "artist": best.get("artistName") or artist,
                       "plain": "", "wordSynced": False, "lines": []}
        else:
            payload = payload_from_lrc(
                best.get("syncedLyrics") or "", best.get("plainLyrics") or "", "lrclib",
                best.get("trackName") or title, best.get("artistName") or artist)

    # lrclib timings are per line. If the track is one Musixmatch timed per word, that is a strictly
    # better answer, so it gets a turn -- but only when there is something to gain.
    upgrade = want_richsync and not payload.get("instrumental") and not payload.get("wordSynced")
    interim = False
    if upgrade and payload.get("status") == "ok":
        # Show the line timed answer now; the better one replaces it when it lands
        out(payload)
        interim = True
    upgraded = False
    asked = False
    if upgrade:
        rich, asked = musixmatch_richsync(variants, duration)
        if rich:
            payload = synced_payload(rich["entries"], "musixmatch", rich["title"], rich["artist"])
            upgraded = True

    if not payload:
        payload = {"status": "not_found", "lines": []}
    elif upgrade and (upgraded or asked):
        payload["rich"] = RICH_GENERATION
    write_cache(key, payload)
    if not interim or upgraded:
        out(payload)


if __name__ == "__main__":
    try:
        main()
    except Exception:
        fail()
