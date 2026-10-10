--------------------------------
---- WINDOW RULES ----
--------------------------------

-- See https://wiki.hypr.land/Configuring/Basics/Window-Rules/
-- Match values are regexes and have to match the whole class / title, so
-- they are anchored with ^ and $. Rules apply top to bottom; a later rule
-- wins when two set the same effect.

-- ╭──────────────────────────────────────────────╮
-- │                 Behaviour                    │
-- ╰──────────────────────────────────────────────╯

hl.window_rule({
	-- Ignore maximize requests from all apps. You'll probably like this.
	name = "suppress-maximize-events",
	match = { class = ".*" },

	suppress_event = "maximize",
})

hl.window_rule({
	-- Fix some dragging issues with XWayland
	name = "fix-xwayland-drags",
	match = {
		class = "^$",
		title = "^$",
		xwayland = true,
		float = true,
		fullscreen = false,
		pin = false,
	},

	no_focus = true,
})

-- Hyprland-run windowrule
hl.window_rule({
	name = "move-hyprland-run",
	match = { class = "hyprland-run" },

	move = "20 monitor_h-120",
	float = true,
})

-- Anything fullscreen keeps the screen awake (hypridle respects this), on
-- top of the apps that ask for it themselves over D-Bus.
hl.window_rule({
	name = "fullscreen-keeps-awake",
	match = { class = ".*" },

	idle_inhibit = "fullscreen",
})

-- ╭──────────────────────────────────────────────╮
-- │            Solid where it matters            │
-- ╰──────────────────────────────────────────────╯
-- The global opacity dip for unfocused windows (decorations.lua) is meant
-- for terminals and editors. Anything you read or watch, often on the other
-- monitor while you work, stays fully solid: a video on screen two should
-- not look washed out because you are typing on screen one.

hl.window_rule({
	name = "opaque-video-players",
	match = { class = "^(mpv|vlc|imv|io\\.github\\.celluloid_player\\.Celluloid)$" },

	opaque = true,
	-- Players hold the screen awake for as long as they are focused, even
	-- when paused on a frame, which is what you want while watching.
	idle_inhibit = "focus",
})

-- Browsers can't be matched by "is a video playing", but the tab title is
-- a good proxy. Re-evaluates when the title changes.
hl.window_rule({
	name = "opaque-video-sites",
	match = { title = "^.*(YouTube|Netflix|Twitch|Prime Video|Disney\\+).*$" },

	opaque = true,
})

-- Web pages are designed against an opaque background; seeing through them
-- only hurts legibility.
hl.window_rule({
	name = "opaque-browsers",
	match = { class = "^(firefox|brave-browser|Brave-browser)$" },

	opaque = true,
})

-- Documents, images and notes: for reading, so no see-through.
hl.window_rule({
	name = "opaque-readers",
	match = {
		class = "^(org\\.pwmt\\.zathura|org\\.gnome\\.Evince|org\\.gnome\\.Loupe|org\\.gnome\\.eog|obsidian)$",
	},

	opaque = true,
})

-- ╭──────────────────────────────────────────────╮
-- │                 Picture in picture           │
-- ╰──────────────────────────────────────────────╯
-- Small, parked in the bottom-right corner (24px off the edges, the same
-- rhythm as the bar), on every workspace, and never takes the keyboard
-- from what you are typing in.

hl.window_rule({
	name = "pip-float-pin",
	match = { title = "^(Picture-in-Picture|Picture in picture)$" },

	float = true,
	pin = true,
	opaque = true,
	size = "480 270",
	move = "monitor_w-window_w-24 monitor_h-window_h-24",
	-- Resizing keeps the video's shape
	keep_aspect_ratio = true,
	no_initial_focus = true,
})

-- ╭──────────────────────────────────────────────╮
-- │            Dialogs and utilities             │
-- ╰──────────────────────────────────────────────╯

-- Windows that mark themselves as modal (confirmation and settings dialogs)
-- sit in the middle instead of being tiled next to their parent.
hl.window_rule({
	name = "float-modal-dialogs",
	match = { modal = true },

	float = true,
	center = true,
})

-- Small tools float centred at a sensible size instead of being tiled
-- into a full-height column.
hl.window_rule({
	name = "float-utilities",
	match = {
		class = "^(org\\.pulseaudio\\.pavucontrol|pavucontrol|nm-connection-editor|\\.blueman-manager-wrapped|blueman-manager)$",
	},

	float = true,
	center = true,
	size = "760 520",
})

-- The password prompt is small by nature: float and centre, keep its own size.
hl.window_rule({
	name = "float-polkit",
	match = { class = "^polkit-gnome-authentication-agent-1$" },

	float = true,
	center = true,
})

hl.window_rule({
	name = "float-calculator",
	match = { class = "^org\\.gnome\\.Calculator$" },

	float = true,
	center = true,
	size = "360 540",
})

-- Compact archive and disk tools
hl.window_rule({
	name = "float-system-tools",
	match = { class = "^(org\\.gnome\\.FileRoller|org\\.gnome\\.baobab|gnome-disks)$" },

	float = true,
	center = true,
	size = "780 540",
})

-- File pickers get room to browse in
hl.window_rule({
	name = "float-portal-file-dialogs",
	match = { class = "^(xdg-desktop-portal-gtk|xdg-desktop-portal-hyprland)$" },

	float = true,
	center = true,
	size = "960 620",
})

-- Titles of file pickers that don't identify themselves by class. "Select"
-- and "Choose" only count when the title also names what is picked, so a
-- page or document that merely starts with "Select" stays tiled.
hl.window_rule({
	name = "float-file-dialog-titles",
	match = {
		title = "^(Open File|Open Files|Open Folder|Save File|Save As|File Upload|(?i:(select|choose) .*(file|files|folder|directory|image).*))$",
	},

	float = true,
	center = true,
	size = "960 620",
})

-- ╭──────────────────────────────────────────────╮
-- │                 Quickshell                   │
-- ╰──────────────────────────────────────────────╯
-- The bar, launcher, power menu, clipboard, notifications, OSD and the other
-- panels are layers named "quickshell" (check with `hyprctl layers`). The
-- audio visualizer uses its own namespace so it gets neither rule.
--   blur         frosted glass behind the translucent surfaces. ignore_alpha
--                keeps the blur to the drawn shapes only, so the fullscreen
--                transparent launcher / power menu windows are not blurred
--                end to end.
--   no_anim      each panel already fades and scales itself in QML; a second
--                compositor fade on top would just make everything lag.
hl.layer_rule({
	name = "quickshell-glass",
	match = { namespace = "^quickshell$" },

	blur = true,
	ignore_alpha = 0.3,
	no_anim = true,
})
