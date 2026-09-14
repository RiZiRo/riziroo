#!/usr/bin/env bash
# Toggle a pinned floating Dolphin (bound to SUPER+E).
# Pinned = Dolphin floats on top of every workspace, so whatever app you are
# using (browser, editor, ...) stays visible underneath and you can drag
# files straight from Dolphin into it.
#   press 1: Dolphin appears floating, centered, always on top
#   press 2: stashes it away (window keeps running, so state is kept)
#   press 3: brings the same window back on the current workspace
#
# NOTE: this setup uses Hyprland's Lua dispatch API
# (plain `hyprctl dispatch <classic-syntax>` is not supported on this build).
#
# Scratch window identification (normal Dolphin windows are untouched):
#   visible = dolphin-class window with pinned = true
#   hidden  = dolphin-class window stashed on workspace special:dolphin

SPECIAL="special:dolphin"

eval_lua() { hyprctl -q eval "$1"; }

visible_addr() {
    hyprctl clients -j 2>/dev/null | jq -r \
        '.[] | select((.class | test("dolphin"; "i")) and .pinned == true) | .address' \
        | head -n1
}

hidden_addr() {
    hyprctl clients -j 2>/dev/null | jq -r \
        '.[] | select((.class | test("dolphin"; "i")) and .workspace.name == "special:dolphin") | .address' \
        | head -n1
}

ADDR=$(visible_addr)
if [ -n "$ADDR" ]; then
    # Hide: unpin first (pin blocks the workspace move), then stash.
    eval_lua "hl.dispatch(hl.dsp.window.pin({action = \"off\", window = \"address:$ADDR\"}))"
    eval_lua "hl.dispatch(hl.dsp.window.move({workspace = \"$SPECIAL\", follow = false, window = \"address:$ADDR\"}))"
    exit 0
fi

ADDR=$(hidden_addr)
if [ -n "$ADDR" ]; then
    # Show: move back to the active workspace, re-pin, raise and focus.
    eval_lua "hl.dispatch(hl.dsp.window.move({workspace = hl.get_active_workspace(), follow = true, window = \"address:$ADDR\"}))"
    eval_lua "hl.dispatch(hl.dsp.window.pin({action = \"on\", window = \"address:$ADDR\"}))"
    eval_lua "hl.dispatch(hl.dsp.window.alter_zorder({mode = \"top\", window = \"address:$ADDR\"}))"
    eval_lua "hl.dispatch(hl.dsp.focus({window = \"address:$ADDR\"}))"
    exit 0
fi

# No scratch window yet: launch one floating, centered, pinned on this workspace.
# pin = visible on all workspaces, always on top of other windows, never tiled.
eval_lua 'hl.dispatch(hl.dsp.exec_cmd("[float; center; size 1150 700; pin] dolphin --new-window"))'
