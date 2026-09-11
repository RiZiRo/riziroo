#!/usr/bin/env bash
#
# Installs this shell as the quickshell config `end4-pC` and puts the supervised
# launcher on PATH. Safe to re-run: it never overwrites a directory it did not
# create, and it changes nothing until every required check has passed.

set -uo pipefail

REPO="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
TARGET="$CONFIG_HOME/quickshell/end4-pC"
BINDIR="$HOME/.local/bin"
LAUNCHER="start-end4-pC"

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

if command -v qs >/dev/null 2>&1; then
    ok "quickshell: $(command -v qs)"
else
    bad "quickshell (qs) not found. Install quickshell first."
fi

if command -v hyprctl >/dev/null 2>&1; then
    ok "Hyprland tooling present"
else
    bad "hyprctl not found. This is a Hyprland shell and will not work without it."
fi

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

if (( errors > 0 )); then
    printf '\n%s%d requirement(s) missing. Nothing was changed.%s\n' "$RED" "$errors" "$OFF"
    exit 1
fi

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

cat <<EOF

$(printf '%s' "$BOLD")Next steps$(printf '%s' "$OFF")

Start it now:

    $BINDIR/$LAUNCHER &

To make it your default shell instead of \`ii\`, edit
$CONFIG_HOME/hypr/hyprland/variables.lua and set:

    hl.env("qsConfig", "end4-pC")

Useful keybinds to add to your Hyprland config:

    hl.bind("SUPER + escape", hl.dsp.global("quickshell:settingsToggle"),
            {description = "Toggle settings"})
    hl.bind("SUPER + O", hl.dsp.global("quickshell:typingTestToggle"),
            {description = "Toggle typing test"})

Then reload with \`hyprctl reload\`.

$(printf '%s' "$DIM")Logs live in $STATE_HOME/end4-pC/ (shell.out and supervisor.log).$(printf '%s' "$OFF")
EOF
