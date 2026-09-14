require("hyprland/lib")

hl.on("hyprland.start", function()
    -- GDM's direct Hyprland entry never activates graphical-session.target, so
    -- xdg-desktop-portal refuses to start (Requisite=) and OBS finds no
    -- ScreenCast backend. This script brings the target and portals up.
    hl.exec_cmd("$HOME/.local/bin/hyprland-session-init")

    -- Start the VPN at login. Amnezia's own "auto start" toggle only writes an
    -- XDG autostart entry, and this session never activates
    -- xdg-desktop-autostart.target, so launch it from here instead. The delay
    -- lets the network and the tray settle first; Conf/autoConnect in
    -- ~/.config/AmneziaVPN.ORG/AmneziaVPN.conf makes it connect on launch.
    hl.exec_cmd("sh -c 'sleep 5; exec /usr/local/bin/AmneziaVPN'")

    -- Cursor theme. Overrides the Bibata default set in hyprland/execs.lua.
    -- Sleep 2 guarantees this runs after the Bibata command even if the
    -- hyprland.start handlers fire in an unpredictable order. Theme lives in
    -- ~/.local/share/icons/ and is symlinked into ~/.icons/ for xcursor.
    hl.exec_cmd("sh -c 'sleep 2; hyprctl setcursor Future-cyan-cursors 30'")
end)
