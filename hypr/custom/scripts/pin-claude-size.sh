#!/usr/bin/env bash
# Pin Claude Desktop's current window size as its launch size.
#
# The launch geometry lives in ~/.config/hypr/custom/rules.lua as three window
# rules (float / size / center). This script reads the size of the running
# Claude Desktop window and rewrites the `claude-desktop-size` rule, so the way
# to change the launch size is: drag the window to the size you want, then run
# this. Position is not pinned - the center rule handles that.
#
# NOTE: this setup uses Hyprland's Lua config, where `hyprctl keyword` cannot
# add window rules, which is why the size is edited in the file and reloaded.

set -euo pipefail

RULES="$HOME/.config/hypr/custom/rules.lua"
ANCHOR='name = "claude-desktop-size"'

[ -f "$RULES" ] || { echo "not found: $RULES" >&2; exit 1; }
grep -q "$ANCHOR" "$RULES" || {
    echo "no claude-desktop-size rule in $RULES" >&2; exit 1
}

# Biggest matching window wins, so a stray dialog can't be picked up. Chromium
# takes the class from the asar desktopName; case depends on XWayland vs native.
read -r W H <<<"$(hyprctl clients -j | jq -r '
    [ .[] | select(.class | test("^com\\.anthropic\\.Claude$"; "i")) ]
    | sort_by(.size[0] * .size[1])
    | last
    | if . == null then "" else "\(.size[0]) \(.size[1])" end
')"

if [ -z "${W:-}" ] || [ -z "${H:-}" ]; then
    echo "No Claude Desktop window found - is it running?" >&2
    exit 1
fi

sed -i -E "s/($ANCHOR.*)size = \{\"[0-9]+\", \"[0-9]+\"\}/\1size = {\"$W\", \"$H\"}/" "$RULES"

grep -qF "size = {\"$W\", \"$H\"}" "$RULES" || {
    echo "could not rewrite the size rule - check the one-line spelling in $RULES" >&2
    exit 1
}

hyprctl reload >/dev/null
echo "Claude Desktop will now open at ${W}x${H}, floating and centered."
