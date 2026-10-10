-----------------------
---- LOOK AND FEEL ----
-----------------------

-- Refer to https://wiki.hypr.land/Configuring/Basics/Variables/
--
-- The look in one line: quiet by default, one accent. Windows are solid,
-- only the focused one carries colour and a deeper shadow, everything else
-- recedes a little. Nothing here moves or glows on its own.

-- Pulls in whatever `wal -i` last generated. If it hasn't run yet
-- (empty/missing file), we skip setting col.* and Hyprland just
-- uses its own built-in default border colors.
local walColorsPath = os.getenv("HOME") .. "/.cache/wal/colors-hyprland.lua"
local ok, walColors = pcall(dofile, walColorsPath)
local hasWalColors = ok and type(walColors) == "table" and walColors.active_border and walColors.inactive_border

-- Same colour at a given alpha ("rgb(a1b2c3)" -> "rgba(a1b2c340)"). If the
-- string is in some other shape it is returned untouched.
local function withAlpha(color, aa)
	return (color:gsub("^rgb%((%x+)%)$", "rgba(%1" .. aa .. ")"))
end

-- Spacing follows the bar (quickshell/config/Style.qml, barGap = 8): the
-- space between windows and between a window and the screen edge is the
-- same 8px the bar floats from the edge. gaps_in applies on every side of a
-- window, so two neighbours are 2 * gaps_in apart.
local barGap = 8

local generalConfig = {
	gaps_in = math.floor(barGap / 2),
	gaps_out = barGap,

	border_size = 2,

	-- Resize windows by dragging their borders and the gaps between them
	resize_on_border = true,
	-- ...and make the grab area a little wider than the 2px border
	extend_border_grab_area = 12,

	-- Please see https://wiki.hypr.land/Configuring/Advanced-and-Cool/Tearing/ before you turn this on
	allow_tearing = false,
}

if hasWalColors then
	generalConfig.col = {
		-- Focus is the one place colour is used on a window: a solid accent.
		active_border = walColors.active_border,
		-- Unfocused borders are the same wal colour at ~25% so the tiling grid
		-- stays readable without a second loud colour.
		inactive_border = withAlpha(walColors.inactive_border, "40"),
	}
end

hl.config({
	general = generalConfig,

	decoration = {
		-- Power 2 is a plain circle; 4 is the smoother "squircle" corner.
		-- 14 sits just inside the bar's 16 radius, so the two read as one family.
		rounding = 14,
		rounding_power = 4,

		-- Windows stay solid when focused, so text is never washed out, and
		-- recede only slightly when not. (kitty has its own background_opacity
		-- of 0.80 which multiplies with these: 0.80 focused, ~0.76 unfocused.)
		-- Video and document windows opt out of the dip in windowrules.lua.
		active_opacity = 1.0,
		inactive_opacity = 0.95,
		fullscreen_opacity = 1.0,

		-- Gently darken whatever is not focused. The dim and the opacity dip
		-- together are what tell you where focus is without a loud border.
		dim_inactive = true,
		dim_strength = 0.06,
		-- The Super+S / pypr scratchpad floats over a workspace; dim what is
		-- behind it a bit more so it reads as a layer above, not a window.
		dim_special = 0.3,

		shadow = {
			enabled = true,
			range = 24,
			render_power = 3,
			-- Soft and low: depth, not a halo. The focused window gets the
			-- stronger one.
			color = 0x66000000,
			color_inactive = 0x33000000,
		},

		blur = {
			enabled = true,
			size = 6,
			passes = 2,
			noise = 0.012,
			contrast = 0.9,
			vibrancy = 0.17,
			popups = true,
		},
	},

	animations = {
		enabled = true,
	},
})

-- ╭──────────────────────────────────────────────╮
-- │                   Motion                     │
-- ╰──────────────────────────────────────────────╯
-- Rules for the whole file, so motion stays useful and never tiring:
--   * Motion explains a change (a window arrived, the view moved), nothing
--     animates on its own, and nothing loops.
--   * Things you cause are fast and settle softly; things leaving are faster
--     and accelerate away.
--   * Windows never overshoot. They arrive and stop.
--   * One easing family everywhere, so it all feels like one hand.
-- Speeds are in tenths of a second: speed 3 is roughly 300ms.

-- ╭──────────────────────────────────────────────╮
-- │                  Curves                      │
-- ╰──────────────────────────────────────────────╯
--   premium  fast start, long soft landing (ease-out quint). Entrances.
--   snappy   even sharper start (ease-out expo). Workspace slides.
--   exit     ease-in. Things leaving should accelerate away, not float.
--   quick    short, crisp. Fade-outs.

hl.curve("premium", { type = "bezier", points = { { 0.22, 1 }, { 0.36, 1 } } })
hl.curve("snappy", { type = "bezier", points = { { 0.16, 1 }, { 0.3, 1 } } })
hl.curve("exit", { type = "bezier", points = { { 0.4, 0 }, { 0.68, 0.06 } } })
hl.curve("quick", { type = "bezier", points = { { 0.15, 0 }, { 0.1, 1 } } })
hl.curve("almostLinear", { type = "bezier", points = { { 0.5, 0.5 }, { 0.75, 1 } } })

-- Spring for moving and resizing windows. Damping is set at the critical
-- value for this stiffness (2 * sqrt(stiffness * mass) is about 29.7), so a
-- window glides into its new slot and stops dead: no overshoot, no wobble
-- when the tiling grid reflows around it.
hl.curve("windowSpring", { type = "spring", mass = 1, stiffness = 220, dampening = 30 })

-- ╭──────────────────────────────────────────────╮
-- │                  Global                      │
-- ╰──────────────────────────────────────────────╯

hl.animation({ leaf = "global", enabled = true, speed = 10, bezier = "premium" })

-- ╭──────────────────────────────────────────────╮
-- │                  Windows                     │
-- ╰──────────────────────────────────────────────╯

-- Moving / resizing / re-tiling
hl.animation({ leaf = "windows", enabled = true, speed = 5, spring = "windowSpring" })
hl.animation({ leaf = "windowsMove", enabled = true, speed = 5, spring = "windowSpring" })

-- Open: a short, shallow grow-in (94%) so a new window is noticed but never
-- held up. Close: quicker still, accelerating away, so you are not waiting
-- on a window you have already dismissed.
hl.animation({ leaf = "windowsIn", enabled = true, speed = 3.5, bezier = "premium", style = "popin 94%" })
hl.animation({ leaf = "windowsOut", enabled = true, speed = 2.4, bezier = "exit", style = "popin 94%" })

-- ╭──────────────────────────────────────────────╮
-- │                  Border                      │
-- ╰──────────────────────────────────────────────╯
-- The border follows focus: the accent hands over from one window to the
-- next instead of snapping.

hl.animation({ leaf = "border", enabled = true, speed = 6, bezier = "premium" })
-- Borders are a single wal colour, so a rotating gradient angle is wasted work.
hl.animation({ leaf = "borderangle", enabled = false, speed = 1, bezier = "premium" })

-- ╭──────────────────────────────────────────────╮
-- │                    Fade                      │
-- ╰──────────────────────────────────────────────╯

hl.animation({ leaf = "fade", enabled = true, speed = 3.5, bezier = "premium" })
hl.animation({ leaf = "fadeIn", enabled = true, speed = 2.6, bezier = "premium" })
hl.animation({ leaf = "fadeOut", enabled = true, speed = 1.8, bezier = "quick" })
-- Focus change: opacity, dim and shadow cross-fade instead of snapping. This
-- is the main "where am I" cue, so it is quick but not instant.
hl.animation({ leaf = "fadeSwitch", enabled = true, speed = 2.5, bezier = "premium" })
hl.animation({ leaf = "fadeShadow", enabled = true, speed = 2.5, bezier = "premium" })
hl.animation({ leaf = "fadeDim", enabled = true, speed = 3, bezier = "premium" })

-- ╭──────────────────────────────────────────────╮
-- │                   Layers                     │
-- ╰──────────────────────────────────────────────╯
-- Quickshell panels (bar, launcher, OSD, notifications) animate themselves in
-- QML, and windowrules.lua switches the compositor's layer animation off for
-- them so the two never stack. These only apply to other layers (the
-- wallpaper daemon, anything else that is not Quickshell): plain, quick fades.

hl.animation({ leaf = "layers", enabled = true, speed = 3, bezier = "premium" })
hl.animation({ leaf = "layersIn", enabled = true, speed = 3, bezier = "premium", style = "fade" })
hl.animation({ leaf = "layersOut", enabled = true, speed = 2, bezier = "quick", style = "fade" })
hl.animation({ leaf = "fadeLayersIn", enabled = true, speed = 2, bezier = "almostLinear" })
hl.animation({ leaf = "fadeLayersOut", enabled = true, speed = 1.6, bezier = "almostLinear" })

-- ╭──────────────────────────────────────────────╮
-- │                 Workspaces                   │
-- ╰──────────────────────────────────────────────╯
-- Plain slide (not fade) so the 3-finger swipe follows your fingers. Left
-- exactly as it was: the direction of the slide tells you which way you went.

hl.animation({ leaf = "workspaces", enabled = true, speed = 3, bezier = "snappy", style = "slide" })
hl.animation({ leaf = "workspacesIn", enabled = true, speed = 3, bezier = "snappy", style = "slide" })
hl.animation({ leaf = "workspacesOut", enabled = true, speed = 3, bezier = "snappy", style = "slide" })

-- Plugging in or unplugging a screen fades it in instead of popping
hl.animation({ leaf = "monitorAdded", enabled = true, speed = 4, bezier = "premium" })

-- Super+S scratch workspace drops in from the top
hl.animation({ leaf = "specialWorkspace", enabled = true, speed = 3.2, bezier = "premium", style = "slidefadevert 15%" })
hl.animation({
	leaf = "specialWorkspaceIn",
	enabled = true,
	speed = 3.2,
	bezier = "premium",
	style = "slidefadevert 15%",
})
hl.animation({ leaf = "specialWorkspaceOut", enabled = true, speed = 2.4, bezier = "exit", style = "slidefadevert 15%" })

-- ╭──────────────────────────────────────────────╮
-- │                  Popups                      │
-- ╰──────────────────────────────────────────────╯
-- Right-click menus and tooltips from GTK/Qt apps: a quick fade, out faster.

hl.animation({ leaf = "fadePopups", enabled = true, speed = 2.5, bezier = "premium" })
hl.animation({ leaf = "fadePopupsIn", enabled = true, speed = 2.5, bezier = "premium" })
hl.animation({ leaf = "fadePopupsOut", enabled = true, speed = 1.6, bezier = "quick" })

-- ╭──────────────────────────────────────────────╮
-- │                   Zoom                       │
-- ╰──────────────────────────────────────────────╯

hl.animation({ leaf = "zoomFactor", enabled = true, speed = 7, bezier = "quick" })
