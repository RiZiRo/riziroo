#!/usr/bin/env bash
# Switch display scaling on the primary monitor: 1 -> 1.25 -> 1.5 -> 1 ...
# Usage:
#   set-scale.sh            cycle 1 / 1.25 / 1.5
#   set-scale.sh <value>    set directly (1, 1.25 or 1.5)
#
# The Lua-config Hyprland here ignores `hyprctl keyword`, so the scale value
# in ~/.config/hypr/monitors.lua is the source of truth: edit it, then reload.
# Reset to 1 by hand if this script ever disappears:
#   cp ~/.config/hypr/monitors.lua.bak-scale1 ~/.config/hypr/monitors.lua && hyprctl reload

set -euo pipefail

MON_FILE="$HOME/.config/hypr/monitors.lua"
VALID="1 1.25 1.5"

current=$(grep -oE 'scale *= *[0-9.]+' "$MON_FILE" | head -1 | grep -oE '[0-9.]+$')
[ -n "$current" ] || { hyprctl notify 3 3000 0 "Display scale error" "no scale value found in monitors.lua" || true; exit 1; }

if [ $# -eq 0 ]; then
    case "$current" in
        1)    target=1.25 ;;
        1.25) target=1.5 ;;
        1.5)  target=1 ;;
        *)    target=1 ;;
    esac
elif [ $# -eq 1 ]; then
    target=$1
    # normalize 1.0 / 1.50 spellings
    case "$target" in
        1|1.0) target=1 ;;
        1.25)  target=1.25 ;;
        1.5|1.50) target=1.5 ;;
        *)
            hyprctl notify 3 3000 0 "Display scale error" "invalid value '$target' — use 1, 1.25 or 1.5" || true
            exit 1 ;;
    esac
else
    echo "usage: $0 [1|1.25|1.5]" >&2; exit 1
fi

[ "$target" = "$current" ] && { hyprctl notify 0 2000 0 "Display scale" "already at $target"; exit 0; }

# Rewrite only the scale fragment on the matching line; keep output/mode/position intact.
sed -i "s/\(scale *= *\)[0-9.]\+/\1$target/" "$MON_FILE"

hyprctl reload >/dev/null
sleep 1

# Read back what Hyprland actually applied.
applied=$(hyprctl monitors | grep -E '^\s*scale:' | head -1 | grep -oE '[0-9.]+$')
res=$(hyprctl monitors | grep -E '^\s*[0-9]+x[0-9]+@' | head -1 | awk '{print $1}')

if [ "$applied" = "$target" ]; then
    hyprctl notify 0 3000 0 "Display scale" "set to $target ($res)"
else
    hyprctl notify 3 5000 0 "Display scale warning" "wanted $target, Hyprland reports $applied — check monitors.lua"
fi
