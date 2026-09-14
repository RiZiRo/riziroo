-- User overrides for hyprland/general.lua. This file loads after it, so
-- anything set here wins. Keep dotfile-managed files untouched.

-- hyprland/general.lua ships blur noise at 0.05, which is about 4x Hyprland's
-- own default (0.0117). At the dock's high transparency that grain was clearly
-- visible as speckle over the panel. 0.008 keeps just enough dither to hide
-- banding in the blur gradient without reading as noise.
-- Note: blur noise is a global setting - there is no per-layer rule - so this
-- also smooths the bar, the sidebars and window blur.
hl.config({ decoration = { blur = { noise = 0.008 } } })

-- hyprland/general.lua ships xray = true, which makes floating windows blur
-- only the background layers - so a floating window over a tiled one frosts
-- the wallpaper and the window underneath vanishes. With xray off, floating
-- blur samples the live framebuffer instead, which already holds the wallpaper,
-- the tiled windows and any floating window lower in the stack.
-- This is the window-level twin of the dock rule in custom/rules.lua.
-- Costs a little GPU on floating blur only (it loses the cached blur
-- framebuffer); set back to true for the cheaper wallpaper-only frost.
hl.config({ decoration = { blur = { xray = false } } })

-- Mouse pointer speed. Negative = slower (range -1.0 to 1.0).
-- accel_profile flat = no pointer acceleration: 1:1 hand-to-cursor
-- movement, which is what Windows' "Enhance pointer precision" OFF gives
-- you and removes the floaty/delayed feel of adaptive accel.
-- 2026-09-07: lowered from -0.5 to -0.52 (Hassan: ~2% slower; libinput
-- sensitivity is unitless, not a percent, so this is the nearest step).
hl.config({
    input = {
        sensitivity = -0.52,
        accel_profile = "flat"
    }
})

