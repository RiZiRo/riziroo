#!/usr/bin/env bash
#
# Installs this shell as the quickshell config `end4-pC` and puts the supervised
# launcher on PATH. Safe to re-run: it never overwrites a directory it did not
# create, and it changes nothing until every required check has passed.
#
# Usage:
#   install.sh            shell only
#   install.sh --hypr     shell + the Hyprland config in hypr/
#   install.sh --hypr-only    only the Hyprland config

set -uo pipefail

REPO="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
TARGET="$CONFIG_HOME/quickshell/end4-pC"
BINDIR="$HOME/.local/bin"
LAUNCHER="start-end4-pC"
HYPR_SRC="$REPO/hypr"
HYPR_DST="$CONFIG_HOME/hypr"

do_shell=1
do_hypr=0
for arg in "$@"; do
    case "$arg" in
        --hypr)      do_hypr=1 ;;
        --hypr-only) do_hypr=1; do_shell=0 ;;
        -h|--help)
            sed -n '3,11p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
            exit 0 ;;
        *)
            printf 'unknown option: %s (try --help)\n' "$arg" >&2
            exit 2 ;;
    esac
done


if [[ -t 1 ]]; then
    BOLD=$'\e[1m'; RED=$'\e[31m'; YELLOW=$'\e[33m'; GREEN=$'\e[32m'; DIM=$'\e[2m'; OFF=$'\e[0m'
else
    BOLD=''; RED=''; YELLOW=''; GREEN=''; DIM=''; OFF=''
fi

errors=0
ok()   { printf '  %s✓%s %s\n' "$GREEN" "$OFF" "$*"; }
warn() { printf '  %s!%s %s\n' "$YELLOW" "$OFF" "$*"; }
bad()  { printf '  %s✗%s %s\n' "$RED" "$OFF" "$*"; errors=$((errors + 1)); }
section() { printf '\n%s%s%s\n' "$BOLD" "$*" "$OFF"; }

section "Checking requirements"

if (( do_shell )); then
    if command -v qs >/dev/null 2>&1; then
        ok "quickshell: $(command -v qs)"
    else
        bad "quickshell (qs) not found. Install quickshell first."
    fi
fi

if command -v hyprctl >/dev/null 2>&1; then
    ok "Hyprland tooling present"
else
    bad "hyprctl not found. This is a Hyprland shell and will not work without it."
fi

if (( do_shell )); then
    # illogical-impulse is a hard prerequisite: this fork reads its config.json and
    # runs helper scripts out of its Python environment. It is not vendored here.
    if [[ -f "$CONFIG_HOME/illogical-impulse/config.json" ]]; then
        ok "illogical-impulse config found"
    else
        bad "$CONFIG_HOME/illogical-impulse/config.json is missing."
        printf '      %sThis fork builds on illogical-impulse and shares its config.\n' "$DIM"
        printf '      Install it first: https://github.com/end-4/dots-hyprland%s\n' "$OFF"
    fi

    VENV="${ILLOGICAL_IMPULSE_VIRTUAL_ENV:-$STATE_HOME/quickshell/.venv}"
    if [[ -x "$VENV/bin/python" ]]; then
        ok "Python environment: $VENV"
    else
        bad "No Python environment at $VENV"
        printf '      %sSome helper scripts run from illogical-impulse'"'"'s venv.%s\n' "$DIM" "$OFF"
    fi
fi

if (( do_hypr )); then
    if [[ -d "$HYPR_SRC" ]]; then
        ok "Hyprland config present in the checkout"
    else
        bad "$HYPR_SRC is missing from this checkout."
    fi
fi

if (( do_shell )); then
section "Checking optional tools"
for tool in jq python3 kitty curl cliphist brightnessctl wpctl ddcutil cava secret-tool convert; do
    if command -v "$tool" >/dev/null 2>&1; then
        ok "$tool"
    else
        warn "$tool missing - the features using it will be inert"
    fi
done

if "${VENV}/bin/python" -c 'import socks' >/dev/null 2>&1; then
    ok "PySocks (lyrics fetching through a SOCKS proxy)"
else
    warn "PySocks missing - only needed to fetch lyrics through a SOCKS proxy"
    printf '      %s%s/bin/pip install PySocks%s\n' "$DIM" "$VENV" "$OFF"
fi
fi

if (( errors > 0 )); then
    printf '\n%s%d requirement(s) missing. Nothing was changed.%s\n' "$RED" "$errors" "$OFF"
    exit 1
fi

if (( do_shell )); then

section "Installing the config"

mkdir -p "$CONFIG_HOME/quickshell"

if [[ "$REPO" == "$TARGET" ]]; then
    ok "already checked out at $TARGET"
elif [[ -L "$TARGET" ]]; then
    current="$(readlink -f -- "$TARGET")"
    if [[ "$current" == "$REPO" ]]; then
        ok "already linked: $TARGET -> $REPO"
    else
        printf '  %s->%s relinking %s (was %s)\n' "$BOLD" "$OFF" "$TARGET" "$current"
        ln -sfn -- "$REPO" "$TARGET" && ok "linked $TARGET -> $REPO"
    fi
elif [[ -e "$TARGET" ]]; then
    # Never clobber somebody else's config directory.
    bad "$TARGET already exists and is not a link to this checkout."
    printf '      %sMove or remove it first, then re-run this script.%s\n' "$DIM" "$OFF"
    exit 1
else
    ln -s -- "$REPO" "$TARGET" && ok "linked $TARGET -> $REPO"
fi

section "Installing the launcher"

mkdir -p "$BINDIR"
if install -m 755 "$REPO/scripts/$LAUNCHER" "$BINDIR/$LAUNCHER"; then
    ok "$BINDIR/$LAUNCHER"
else
    bad "could not install the launcher into $BINDIR"
    exit 1
fi

case ":$PATH:" in
    *":$BINDIR:"*) ok "$BINDIR is on PATH" ;;
    *) warn "$BINDIR is not on this shell's PATH."
       printf '      %sGraphical sessions often miss it too, so use the full path\n' "$DIM"
       printf '      in Hyprland configs and .desktop files: %s/%s%s\n' "$BINDIR" "$LAUNCHER" "$OFF" ;;
esac

fi # do_shell

if (( do_hypr )); then

section "Installing the Hyprland config"

# Everything here is a symlink back into the checkout, so editing the live
# config edits the repo. The exception is monitors.lua: set-scale.sh rewrites
# it in place, and it is machine-specific, so it is copied once and then left
# alone.
#
# ~/.config/hypr/hyprland/ is upstream's (end-4's) tree and is never touched.

link_one() {
    # link_one <path relative to hypr/> -- links $HYPR_SRC/$1 to $HYPR_DST/$1
    local rel="$1" src="$HYPR_SRC/$1" dst="$HYPR_DST/$1"

    [[ -e "$src" ]] || { bad "missing from the checkout: hypr/$rel"; return 1; }
    mkdir -p -- "$(dirname -- "$dst")"

    if [[ -L "$dst" ]]; then
        if [[ "$(readlink -f -- "$dst")" == "$(readlink -f -- "$src")" ]]; then
            ok "already linked: $rel"
            return 0
        fi
        ln -sfn -- "$src" "$dst" && ok "relinked: $rel"
        return 0
    fi

    if [[ -e "$dst" ]]; then
        # A real file is in the way. Keep it -- never silently discard somebody's
        # config -- and only then take over the path.
        local backup="$dst.bak-$(date +%Y%m%d-%H%M%S)"
        cp -p -- "$dst" "$backup" || { bad "could not back up $rel"; return 1; }
        printf '  %s->%s kept your %s as %s\n' "$BOLD" "$OFF" "$rel" "$(basename -- "$backup")"
    fi

    ln -sfn -- "$src" "$dst" && ok "linked: $rel"
}

for rel in custom/env.lua custom/execs.lua custom/general.lua \
           custom/keybinds.lua custom/rules.lua custom/variables.lua \
           custom/scripts/set-scale.sh custom/scripts/toggle-dolphin.sh \
           custom/scripts/pin-claude-size.sh custom/scripts/fullscreen-double.sh \
           hyprland.lua hyprlock.conf hypridle.conf; do
    link_one "$rel"
done

# Machine-specific, and rewritten in place by set-scale.sh -- copy, never link.
if [[ -e "$HYPR_DST/monitors.lua" ]]; then
    ok "monitors.lua already present (left as-is)"
elif cp -- "$HYPR_SRC/monitors.lua.example" "$HYPR_DST/monitors.lua"; then
    ok "monitors.lua created from the example"
    printf '      %sEdit it to match your display: hyprctl monitors all%s\n' "$DIM" "$OFF"
else
    bad "could not create $HYPR_DST/monitors.lua"
fi

# hyprlock.conf sources hyprlock/colors.conf on its first line, and matugen
# regenerates that file on every wallpaper change -- so it is not tracked here.
# Without it hyprlock refuses to start, so lay down a neutral fallback that
# matugen will overwrite the first time the colours are regenerated.
if [[ -e "$HYPR_DST/hyprlock/colors.conf" ]]; then
    ok "hyprlock/colors.conf already present (left as-is)"
else
    mkdir -p "$HYPR_DST/hyprlock"
    if cat > "$HYPR_DST/hyprlock/colors.conf" <<'COLORS'
# Fallback colours. matugen overwrites this whole file when it regenerates
# the theme from your wallpaper; these values only matter until it does.

$text_color = rgba(e0e0e0FF)
$entry_background_color = rgba(ffffff11)
$entry_border_color = rgba(91919155)
$entry_color = rgba(e0e0e0FF)
$font_family = sans-serif
$font_family_clock = sans-serif
$font_material_symbols = Material Symbols Rounded
COLORS
    then
        ok "hyprlock/colors.conf fallback written"
        printf '      %smatugen replaces it on the next wallpaper change.%s\n' "$DIM" "$OFF"
    else
        bad "could not write $HYPR_DST/hyprlock/colors.conf"
    fi
fi

mkdir -p "$BINDIR"
if install -m 755 "$HYPR_SRC/bin/hyprland-session-init" "$BINDIR/hyprland-session-init"; then
    ok "$BINDIR/hyprland-session-init"
else
    bad "could not install hyprland-session-init into $BINDIR"
fi

fi # do_hypr

if (( errors > 0 )); then
    printf '\n%s%d step(s) failed.%s\n' "$RED" "$errors" "$OFF"
    exit 1
fi

if (( do_shell )); then
cat <<EOF

$(printf '%s' "$BOLD")Next steps$(printf '%s' "$OFF")

Start it now:

    $BINDIR/$LAUNCHER &
EOF

if (( do_hypr )); then
cat <<EOF

The Hyprland config is installed, so \`qsConfig\` and the shell keybinds
(SUPER+escape settings, SUPER+O typing test, ALT+space island) are already
set up. Reload with \`hyprctl reload\`.
EOF
else
cat <<EOF

To make it your default shell instead of \`ii\`, edit
$CONFIG_HOME/hypr/hyprland/variables.lua and set:

    hl.env("qsConfig", "end4-pC")

Useful keybinds to add to your Hyprland config:

    hl.bind("SUPER + escape", hl.dsp.global("quickshell:settingsToggle"),
            {description = "Toggle settings"})
    hl.bind("SUPER + O", hl.dsp.global("quickshell:typingTestToggle"),
            {description = "Toggle typing test"})
    hl.bind("ALT + Space", hl.dsp.global("quickshell:islandToggle"),
            {description = "Toggle island search"})

Then reload with \`hyprctl reload\`.

$(printf '%s' "$DIM")Or install the whole thing with: ./install.sh --hypr$(printf '%s' "$OFF")
EOF
fi

printf '\n%sLogs live in %s/end4-pC/ (shell.out and supervisor.log).%s\n' "$DIM" "$STATE_HOME" "$OFF"

else
cat <<EOF

$(printf '%s' "$BOLD")Next steps$(printf '%s' "$OFF")

Reload Hyprland to pick up the config:

    hyprctl reload && hyprctl configerrors

$(printf '%s' "$DIM")Your live config now symlinks into this checkout, so edits here are edits
to the repo. monitors.lua is the exception: it is yours, and untracked.$(printf '%s' "$OFF")
EOF
fi

