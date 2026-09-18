-------------------
---- AUTOSTART ----
-------------------

hl.on("hyprland.start", function()
	-- Idempotent safety net for graphical-session.target -- see the comment
	-- on systemd.user.targets.hyprland-session in default.nix for why this
	-- was added despite the polkit prompt already working without it.
	hl.exec_cmd(
		"dbus-update-activation-environment --systemd "
			.. "WAYLAND_DISPLAY XDG_CURRENT_DESKTOP XDG_SESSION_TYPE HYPRLAND_INSTANCE_SIGNATURE; "
			.. "systemctl --user start hyprland-session.target"
	)

	hl.exec_cmd("awww-daemon")
	hl.exec_cmd("hypridle")
	hl.exec_cmd("quickshell")
	hl.exec_cmd("wl-paste --type text --watch cliphist store")
	hl.exec_cmd("wl-paste --type image --watch cliphist store")
	hl.exec_cmd("wl-clip-persist --clipboard regular")
	-- pypr only ever reads ~/.config/hypr/pyprland.toml by default; since
	-- the live config now lives at ~/.config/pypr/config.toml instead
	-- (see modules/pyprland/default.nix), it has to be pointed there
	-- explicitly or it starts with zero plugins configured.
	hl.exec_cmd("pypr --config ~/.config/pypr/config.toml")
end)
