#!/bin/bash
# Music recognition helper for end-4 quickshell.
#
# Captures audio from the default output monitor (or mic) with parec,
# then recognizes it with `songrec recognize <file> -j`.
#
# Why not `songrec listen`: distro songrec builds (e.g. Fedora 0.4.3) use
# cpal/ALSA for capture and cannot open PipeWire/PulseAudio source names
# (e.g. "<sink>.monitor"), and they do not support --request-interval.
#
# Network: songrec talks to amp.shazam.com (Google-hosted), which returns
# 403 for Iranian egress IPs. songrec's HTTP client supports HTTP proxies
# only (no SOCKS), so if v2rayN's SOCKS proxy (127.0.0.1:10808) is up,
# we transparently route through a local SOCKS bridge.
# Override: SONGREC_PROXY="http://host:port", or SONGREC_PROXY="direct"
# to force a direct connection.

INTERVAL=4
TOTAL_DURATION=16
SOURCE_TYPE="monitor"  # monitor | input

while getopts "i:t:s:" opt; do
  case $opt in
    i) INTERVAL=$OPTARG ;;
    t) TOTAL_DURATION=$OPTARG ;;
    s) SOURCE_TYPE=$OPTARG ;;
    *) exit 1 ;;
  esac
done

command -v songrec >/dev/null 2>&1 || exit 1
command -v parec >/dev/null 2>&1 || exit 1
command -v pactl >/dev/null 2>&1 || exit 1

if [ "$SOURCE_TYPE" = "monitor" ]; then
    AUDIO_DEVICE="$(pactl get-default-sink 2>/dev/null).monitor"
elif [ "$SOURCE_TYPE" = "input" ]; then
    AUDIO_DEVICE="$(pactl get-default-source 2>/dev/null)"
else
    exit 1
fi

if [ -z "$AUDIO_DEVICE" ] || ! pactl list short sources 2>/dev/null | grep -q "$AUDIO_DEVICE"; then
    exit 1
fi

# songrec fingerprints up to ~12s of audio
REC_SECS=$(( TOTAL_DURATION < 13 ? TOTAL_DURATION : 12 ))
[ "$REC_SECS" -lt 6 ] && REC_SECS=6

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
port_open() { timeout 1 bash -c "exec 3<>/dev/tcp/127.0.0.1/$1" 2>/dev/null; }

BRIDGE_PID=""
PAREC_PID=""
cleanup() {
    [ -n "$PAREC_PID" ] && kill "$PAREC_PID" 2>/dev/null
    [ -n "$BRIDGE_PID" ] && kill "$BRIDGE_PID" 2>/dev/null
    rm -rf "$WORKDIR"
}
trap cleanup EXIT INT TERM

# --- proxy setup ---------------------------------------------------------
if [ -n "$SONGREC_PROXY" ] && [ "$SONGREC_PROXY" != "direct" ]; then
    export HTTPS_PROXY="$SONGREC_PROXY"
elif [ -z "$SONGREC_PROXY" ] && port_open 10808; then
    # v2rayN SOCKS detected: start a local HTTP->SOCKS bridge for songrec
    for BRIDGE_PORT in 18308 18309 18310; do
        if port_open "$BRIDGE_PORT"; then
            export HTTPS_PROXY="http://127.0.0.1:$BRIDGE_PORT"
            break
        fi
        python3 "$SCRIPT_DIR/socks-bridge.py" "$BRIDGE_PORT" 127.0.0.1 10808 >/dev/null 2>&1 &
        BRIDGE_PID=$!
        for _ in $(seq 1 30); do
            port_open "$BRIDGE_PORT" && break
            kill -0 "$BRIDGE_PID" 2>/dev/null || break
            sleep 0.1
        done
        if port_open "$BRIDGE_PORT"; then
            export HTTPS_PROXY="http://127.0.0.1:$BRIDGE_PORT"
            break
        fi
        kill "$BRIDGE_PID" 2>/dev/null
        BRIDGE_PID=""
    done
fi

# --- capture -------------------------------------------------------------
WORKDIR=$(mktemp -d /tmp/songrec_XXXXXX)
SNIPPET="$WORKDIR/snippet.wav"

parec -d "$AUDIO_DEVICE" --file-format=wav "$SNIPPET" &
PAREC_PID=$!

( sleep "$REC_SECS" && kill "$PAREC_PID" 2>/dev/null ) &
wait "$PAREC_PID" 2>/dev/null
PAREC_PID=""

[ -s "$SNIPPET" ] || exit 0

# --- recognize -----------------------------------------------------------
JSON="$(songrec recognize "$SNIPPET" -j 2>/dev/null)"

# Only emit output when a track was actually matched (Shazam JSON contains track.title)
if [ -n "$JSON" ] && printf '%s' "$JSON" | grep -q '"title"'; then
    printf '%s\n' "$JSON"
fi

exit 0
