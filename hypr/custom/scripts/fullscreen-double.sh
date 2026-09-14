#!/usr/bin/env bash
# Toggle fullscreen when invoked twice quickly (Super + double right-click).
state="/tmp/hypr-fullscreen-double-$(id -u)"
now=$(date +%s%3N)
if [[ -f "$state" ]]; then
    prev=$(<"$state")
    if (( now - prev < 500 )); then
        rm -f "$state"
        hyprctl -q eval 'hl.dispatch(hl.dsp.window.fullscreen({ mode = "fullscreen", action = "toggle" }))'
        exit 0
    fi
fi
echo "$now" > "$state"
