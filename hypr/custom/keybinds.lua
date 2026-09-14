hl.bind("CTRL+SUPER+ALT+Slash", hl.dsp.exec_cmd("xdg-open ~/.config/hypr/custom/keybinds.lua"), {description = "Edit user keybinds"} )
hl.bind("SUPER + Escape", hl.dsp.global("quickshell:settingsToggle"), { description = "Shell: Toggle settings" })
hl.bind("SUPER + I", hl.dsp.global("quickshell:sidebarLeftToggle"), { description = "Shell: Toggle Intelligence (AI chat)" })
hl.bind("SUPER + A", hl.dsp.exec_cmd("kitty --class claude-code --title 'Claude Code' -- $HOME/.local/bin/claude-term"),
    { description = "App: Claude Code terminal" })
-- Resolve the newest ZCode AppImage at press time: the filename carries the
-- version, so a hardcoded path dies silently on every update (it did -- this
-- pointed at 3.8.1 long after 3.11.2 was installed).
hl.bind("SUPER + Z", hl.dsp.exec_cmd("sh -c 'exec $(ls -1t $HOME/Downloads/ZCode-*.AppImage | head -1) --no-sandbox'"),
    { description = "App: ZCode" })
hl.bind("SUPER + mouse:273", hl.dsp.exec_cmd("$HOME/.config/hypr/custom/scripts/fullscreen-double.sh"),
    { description = "Window: Toggle fullscreen (double right-click)" })
-- Super-tap / Super+Tab show workspaces only. Alt+Space opens the island,
-- including with hidden bars; clipboard and emoji shortcuts route into it.
hl.bind("ALT + Space", hl.dsp.global("quickshell:islandToggle"),
    { description = "Shell: Toggle island search" })
hl.bind("ALT + SHIFT + Space", hl.dsp.global("quickshell:islandDashboardToggle"),
    { description = "Shell: Toggle island dashboard" })
hl.bind("SUPER + B", hl.dsp.global("quickshell:barToggle"),
    { description = "Shell: Toggle top bar (free screen space)" })
hl.bind("SUPER + O", hl.dsp.global("quickshell:typingTestToggle"),
    { description = "Shell: Toggle typing test" })
hl.bind("SUPER + SHIFT + T", hl.dsp.exec_cmd("$HOME/.local/bin/thumbnail-shot"),
    { description = "Utilities: YouTube thumbnail (desktop rendered 25% bigger)" })

--# Display scale: cycle 1 -> 1.25 -> 1.5; reset always lands on 1.
--# Restore by hand if needed: cp ~/.config/hypr/monitors.lua.bak-scale1 ~/.config/hypr/monitors.lua && hyprctl reload
hl.bind("SUPER + CTRL + S", hl.dsp.exec_cmd("$HOME/.config/hypr/custom/scripts/set-scale.sh"),
    { description = "Display: Cycle scale 1 / 1.25 / 1.5" })
hl.bind("SUPER + CTRL + SHIFT + S", hl.dsp.exec_cmd("$HOME/.config/hypr/custom/scripts/set-scale.sh 1"),
    { description = "Display: Reset scale to 1" })
