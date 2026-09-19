-----------------------
---- LOOK AND FEEL ----
-----------------------

-- Refer to https://wiki.hypr.land/Configuring/Basics/Variables/

-- Pulls in whatever `wal -i` last generated. If it hasn't run yet
-- (empty/missing file), we skip setting col.* and Hyprland just
-- uses its own built-in default border colors.
local walColorsPath = os.getenv("HOME") .. "/.cache/wal/colors-hyprland.lua"
local ok, walColors = pcall(dofile, walColorsPath)
local hasWalColors = ok and type(walColors) == "table"
	and walColors.active_border and walColors.inactive_border

local generalConfig = {
	gaps_in = 4,
	gaps_out = 8,

	border_size = 1,

	-- Set to true to enable resizing windows by clicking and dragging on borders and gaps
	resize_on_border = true,

	-- Please see https://wiki.hypr.land/Configuring/Advanced-and-Cool/Tearing/ before you turn this on
	allow_tearing = false,
}

if hasWalColors then
	generalConfig.col = {
		active_border = walColors.active_border,
		inactive_border = walColors.inactive_border,
	}
end

hl.config({
	general = generalConfig,

	decoration = {
		rounding = 15,
		rounding_power = 10,

		-- Change transparency of focused and unfocused windows
		active_opacity = 0.9,
		inactive_opacity = 0.8,

		shadow = {
			enabled = true,
			range = 15,
			render_power = 3,
			color = 0xee121212,
		},

		blur = {
			enabled = true,
			size = 3,
			passes = 1,
			vibrancy = 0.1696,
		},
	},

	animations = {
		enabled = true,
	},
})
-- ╭──────────────────────────────────────────────╮
-- │          Minimal Premium Animations          │
-- ╰──────────────────────────────────────────────╯

-- Smooth, elegant curves
hl.curve("premium", {
	type = "bezier",
	points = { { 0.22, 1 }, { 0.36, 1 } },
})

hl.curve("premiumInOut", {
	type = "bezier",
	points = { { 0.4, 0 }, { 0.2, 1 } },
})

hl.curve("quick", {
	type = "bezier",
	points = { { 0.15, 0 }, { 0.1, 1 } },
})

hl.curve("linear", {
	type = "bezier",
	points = { { 0, 0 }, { 1, 1 } },
})

hl.curve("almostLinear", {
	type = "bezier",
	points = { { 0.5, 0.5 }, { 0.75, 1 } },
})

-- Elegant, controlled spring
hl.curve("premiumSpring", {
	type = "spring",
	mass = 1,
	stiffness = 220,
	dampening = 25,
})

-- ╭──────────────────────────────────────────────╮
-- │                  Global                      │
-- ╰──────────────────────────────────────────────╯

hl.animation({
	leaf = "global",
	enabled = true,
	speed = 10,
	bezier = "default",
})

-- ╭──────────────────────────────────────────────╮
-- │                  Border                      │
-- ╰──────────────────────────────────────────────╯

hl.animation({
	leaf = "border",
	enabled = true,
	speed = 6,
	bezier = "premium",
})

-- ╭──────────────────────────────────────────────╮
-- │                  Windows                     │
-- ╰──────────────────────────────────────────────╯

-- Smooth movement / resizing
hl.animation({
	leaf = "windows",
	enabled = true,
	speed = 5,
	spring = "premiumSpring",
})

-- Very subtle entrance
hl.animation({
	leaf = "windowsIn",
	enabled = true,
	speed = 4.8,
	bezier = "premium",
	style = "popin 96%",
})

-- Fast, clean exit
hl.animation({
	leaf = "windowsOut",
	enabled = true,
	speed = 2.4,
	bezier = "quick",
	style = "popin 96%",
})

-- ╭──────────────────────────────────────────────╮
-- │                    Fade                      │
-- ╰──────────────────────────────────────────────╯

hl.animation({
	leaf = "fadeIn",
	enabled = true,
	speed = 2.4,
	bezier = "premium",
})

hl.animation({
	leaf = "fadeOut",
	enabled = true,
	speed = 2,
	bezier = "quick",
})

hl.animation({
	leaf = "fade",
	enabled = true,
	speed = 3.5,
	bezier = "premium",
})

-- ╭──────────────────────────────────────────────╮
-- │                   Layers                     │
-- ╰──────────────────────────────────────────────╯

hl.animation({
	leaf = "layers",
	enabled = true,
	speed = 4.2,
	bezier = "premium",
})

hl.animation({
	leaf = "layersIn",
	enabled = true,
	speed = 4.5,
	bezier = "premium",
	style = "fade",
})

hl.animation({
	leaf = "layersOut",
	enabled = true,
	speed = 2.2,
	bezier = "quick",
	style = "fade",
})

hl.animation({
	leaf = "fadeLayersIn",
	enabled = true,
	speed = 2.2,
	bezier = "almostLinear",
})

hl.animation({
	leaf = "fadeLayersOut",
	enabled = true,
	speed = 1.8,
	bezier = "almostLinear",
})

-- ╭──────────────────────────────────────────────╮
-- │                 Workspaces                   │
-- ╰──────────────────────────────────────────────╯

-- Smooth and understated
hl.animation({
	leaf = "workspaces",
	enabled = true,
	speed = 2.5,
	bezier = "premium",
	style = "fade",
})

hl.animation({
	leaf = "workspacesIn",
	enabled = true,
	speed = 2.2,
	bezier = "premium",
	style = "fade",
})

hl.animation({
	leaf = "workspacesOut",
	enabled = true,
	speed = 2.2,
	bezier = "quick",
	style = "fade",
})

-- ╭──────────────────────────────────────────────╮
-- │                   Zoom                       │
-- ╰──────────────────────────────────────────────╯

hl.animation({
	leaf = "zoomFactor",
	enabled = true,
	speed = 7,
	bezier = "quick",
})
