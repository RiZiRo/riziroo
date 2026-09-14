#!/usr/bin/env bash
# Headless check for the typing test module.
#
# Runs the real shell config under the offscreen platform with isolated XDG
# dirs, instantiating TypingTestSurface directly. WAYLAND_DISPLAY and
# HYPRLAND_INSTANCE_SIGNATURE must be unset or quickshell tries to use the
# live compositor; services/Idle.qml is stubbed because it owns a PanelWindow,
# which the offscreen platform has no backend for.
set -euo pipefail

SRC="${SRC:-$HOME/.config/quickshell/end4-pC}"
H="${TT_HARNESS_DIR:-${TMPDIR:-/tmp}/tt-check}"
SUITE="${1:-$SRC/scripts/typingTest/harness-shell.qml}"

rm -rf "$H/config"
mkdir -p "$H/xdgconfig" "$H/xdgcache" "$H/xdgstate" "$H/runtime"
chmod 700 "$H/runtime"
cp -r "$SRC" "$H/config"
rm -rf "$H/config/.git" "$H/config/graphify-out" "$H/config/.archive"

cat > "$H/config/services/Idle.qml" <<'EOF'
pragma Singleton
import qs.modules.common
import QtQuick
import Quickshell

// Harness stub: the real Idle.qml owns a PanelWindow, which the offscreen
// platform has no backend for. Keeps the same surface for callers.
Singleton {
    id: root
    property bool inhibit: false
    function toggleInhibit(active = null) {
        root.inhibit = active !== null ? active : !root.inhibit;
    }
}
EOF

cp "$SUITE" "$H/config/shell.qml"
mkdir -p "$H/config/shots" "$H/shots"

env -u WAYLAND_DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE -u DISPLAY \
    QT_QPA_PLATFORM=offscreen \
    XDG_RUNTIME_DIR="$H/runtime" \
    XDG_CONFIG_HOME="$H/xdgconfig" \
    XDG_CACHE_HOME="$H/xdgcache" \
    XDG_STATE_HOME="$H/xdgstate" \
    timeout 60 qs -p "$H/config" > "$H/run.log" 2>&1 || true

# The config dir is rebuilt on every run, so keep any renders outside it.
cp -f "$H/config/shots/"*.png "$H/shots/" 2>/dev/null || true

grep -E "PASS |FAIL |SHOT |HARNESS DONE|ERROR|Type .* unavailable" "$H/run.log" \
    | grep -v "quickshell.ipc" || true
echo "full log: $H/run.log"
echo "renders:  $H/shots"
grep -qE "FAIL |FAILED" "$H/run.log" && exit 1 || exit 0
