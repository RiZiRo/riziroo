-- Apply the readable transparency/blur profile to every application window.
-- Use .+ instead of .* so the default empty-class XWayland context-menu
-- exception remains unblurred.
hl.window_rule({
    name = "all-app-transparency",
    match = {class = ".+"},
    no_blur = false,
    opacity = "0.94 override 0.76 override 0.94 override"
})

-- Keep Zen at full window opacity. Zen exposes alpha only for its transparent
-- browser chrome, so Hyprland blurs those regions without fading webpage
-- images or video.
hl.window_rule({
    name = "zen-opaque",
    match = {class = "^app\\.zen_browser\\.zen$"},
    no_blur = false,
    opacity = "1 override 1 override 1 override"
})

-- VLC at full window opacity. The all-app transparency profile above fades
-- every window to 0.94, which visibly washes out video playback. VLC's whole
-- surface is the video frame, so it gets the same opaque treatment as Zen.
-- Qt5 on Wayland reports the app_id/class as lowercase "vlc"; cover XWayland
-- capitalisation too.
hl.window_rule({
    name = "vlc-opaque",
    match = {class = "^(vlc|VLC)$"},
    no_blur = false,
    opacity = "1 override 1 override 1 override"
})

-- Claude Desktop opts out of the transparency/blur profile entirely. Its own
-- UI is already flat dark surfaces, so the frost only muddied body text.
--
-- Chromium takes the window class from the asar package.json desktopName
-- (com.anthropic.Claude, see WM_CLASS in
-- /usr/lib/claude-desktop-unofficial/launcher-common.sh). The launcher
-- defaults to XWayland on Hyprland, so the character classes below cover
-- either capitalisation Chromium might hand the compositor.
hl.window_rule({
    name = "claude-desktop-opaque",
    match = {class = "^[Cc]om\\.[Aa]nthropic\\.[Cc]laude$"},
    no_blur = true,
    opacity = "1 override 1 override 1 override"
})

-- Claude Desktop always opens as a floating window at a fixed size, centered
-- in the usable area (center respects the reserved bar/dock space, so neither
-- gets covered). Chromium does remember its own window bounds, but a tiling
-- compositor overrules them on open, so the size has to live here.
--
-- The size below is rewritten in place by custom/scripts/pin-claude-size.sh:
-- drag the window to the size you want, run the script, and that becomes the
-- launch size. Keep this rule on one line with the size spelled
-- `size = {"W", "H"}` - that is what the script's sed anchors to.
hl.window_rule({ name = "claude-desktop-float",  match = {class = "^[Cc]om\\.[Aa]nthropic\\.[Cc]laude$"}, float = true })
hl.window_rule({ name = "claude-desktop-size",   match = {class = "^[Cc]om\\.[Aa]nthropic\\.[Cc]laude$"}, size = {"1190", "885"} })
hl.window_rule({ name = "claude-desktop-center", match = {class = "^[Cc]om\\.[Aa]nthropic\\.[Cc]laude$"}, center = true })

-- Hyprland's blur radius is global (there is no inactive-only blur control).
-- A small inactive dim makes the lower-opacity inactive windows feel less
-- visually heavy without changing the focused-window blur profile.
hl.config({ decoration = { dim_inactive = true, dim_strength = 0.08 } })

-- Translucent dock. These override the generic `quickshell:.*` rules in
-- hyprland/rules.lua, which this file is loaded after.
--
-- ignore_alpha is the important one: Hyprland skips blurring any pixel whose
-- alpha is below it, and the shared value of 0.79 is far above the dock's
-- see-through fill, so without this the dock would be transparent but flat.
-- Keep it under (1 - dockTransparency) * colLayer0's own alpha, which is
-- itself 1 - Appearance.backgroundTransparency (auto, capped at 0.22 and
-- wallpaper-dependent). At dockTransparency 0.94 that floor is about 0.047,
-- so 0.02 leaves headroom for a wallpaper change to move it.
hl.layer_rule({ match = { namespace = "quickshell:dock" }, blur = true })
hl.layer_rule({ match = { namespace = "quickshell:dock" }, ignore_alpha = 0.02 })

-- Sample the windows underneath rather than only the wallpaper, so the dock
-- actually refracts what it is sitting on top of. Set this back to true for
-- the cheaper wallpaper-only frost.
hl.layer_rule({ match = { namespace = "quickshell:dock" }, xray = false })

-- Glassy bar popups. Every StyledPopup window (clock/calendar/todo, weather,
-- battery, resources, tray, network speed) opens in the shared
-- `quickshell:popup` namespace, which hyprland/rules.lua blur-kills with
-- ignore_alpha = 1 ("no weird color for bar tooltips") and would otherwise
-- flat-frost at the generic quickshell:.* ignore_alpha of 0.79. Same recipe
-- as the dock above: drop the ignore_alpha floor so the popup's own
-- translucent fill (popupTransparency in
-- modules/common/widgets/StyledPopup.qml) gets blurred instead of skipped.
-- Opaque popups are unaffected - blurring a fully opaque pixel is invisible.
hl.layer_rule({ match = { namespace = "quickshell:popup" }, blur = true })
hl.layer_rule({ match = { namespace = "quickshell:popup" }, ignore_alpha = 0.02 })

-- Frost what the popup actually covers, not just the wallpaper, matching the
-- dock: a calendar opened over a browser window should frost that window.
hl.layer_rule({ match = { namespace = "quickshell:popup" }, xray = false })

-- Glassy notification toasts. Third instance of the dock recipe. The toast used
-- to fill with colBackgroundSurfaceContainer, whose alpha is 1 minus the
-- automatic background transparency (capped at 0.22 and usually far under it),
-- so it was a near-opaque slab sitting next to a frosted dock. It now fills at
-- Config.options.notifications.transparency instead, which only reads as glass
-- if Hyprland stops skipping it: the generic quickshell:.* rule in
-- hyprland/rules.lua sets ignore_alpha = 0.79, far above the toast's new fill.
hl.layer_rule({ match = { namespace = "quickshell:notificationPopup" }, blur = true })
hl.layer_rule({ match = { namespace = "quickshell:notificationPopup" }, ignore_alpha = 0.02 })

-- Frost the window the toast lands on, not just the wallpaper. Notifications
-- arrive over whatever you are working in, so this is the case that matters.
hl.layer_rule({ match = { namespace = "quickshell:notificationPopup" }, xray = false })

-- Frosted workspace overview: fourth instance of the dock recipe. The generic
-- quickshell:.* rule in hyprland/rules.lua sets ignore_alpha = 0.79, which is
-- at or above the overview panel's translucent fill (colBackgroundSurface-
-- Container and the colSurfaceContainerLow tiles), so Hyprland skipped
-- blurring those pixels and the see-through areas showed the raw wallpaper.
-- Drop the floor and sample the windows underneath, so the overview frosts
-- what it actually covers instead of only the background.
hl.layer_rule({ match = { namespace = "quickshell:overview" }, blur = true })
hl.layer_rule({ match = { namespace = "quickshell:overview" }, ignore_alpha = 0.02 })
hl.layer_rule({ match = { namespace = "quickshell:overview" }, xray = false })
