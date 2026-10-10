----------------
----  MISC  ----
----------------

hl.config({
	misc = {
		force_default_wallpaper = -1, -- Set to 0 or 1 to disable the anime mascot wallpapers
		disable_hyprland_logo = true, -- If true disables the random hyprland logo / anime girl background. :(

		-- Animate windows while you drag/resize them by hand
		animate_manual_resizes = true,
		animate_mouse_windowdragging = true,

		-- Wake the screen from DPMS on any mouse move or key press
		mouse_move_enables_dpms = true,
		key_press_enables_dpms = true,

		-- Already Hyprland's default, kept explicit because the bar depends on
		-- it: a window asking for attention lights up its workspace (red)
		-- instead of pulling focus to another monitor.
		focus_on_activate = false,
	},

	cursor = {
		-- The pointer gets out of the way while you type
		hide_on_key_press = true,
	},
})
