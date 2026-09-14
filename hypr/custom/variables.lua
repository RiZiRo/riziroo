-- Use the pctrade fork as the default Quickshell profile.
hl.env("qsConfig", "end4-pC")

-- Super+W opens Zen browser (overrides the launch_first_available.sh default).
browser = "flatpak run app.zen_browser.zen"

-- Super+E toggles a floating, on-top Dolphin scratchpad (show/hide same window).
-- Overrides hyprland/variables.lua so the existing SUPER+E bind needs no changes.
fileManager = "$HOME/.config/hypr/custom/scripts/toggle-dolphin.sh"
