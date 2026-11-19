-------------------
---- AUTOSTART ----
-------------------

hl.on("hyprland.start", function()
	hl.exec_cmd(
		"dbus-update-activation-environment --systemd "
			.. "WAYLAND_DISPLAY XDG_CURRENT_DESKTOP XDG_SESSION_TYPE HYPRLAND_INSTANCE_SIGNATURE; "
			.. "systemctl --user start hyprland-session.target"
	)

	hl.exec_cmd("awww-daemon")
	hl.exec_cmd("hypridle")
	hl.exec_cmd("quickshell")
	hl.exec_cmd("screentime log")
	hl.exec_cmd("pywalfox start")
	-- Skip copies a password manager marks as secret (the KDE hint most of them set)
	hl.exec_cmd("wl-paste --type text --watch sh -c 'if wl-paste --list-types | grep -qx x-kde-passwordManagerHint; then cat > /dev/null; else cliphist store; fi'")
	hl.exec_cmd("wl-paste --type image --watch cliphist store")
	hl.exec_cmd("wl-clip-persist --clipboard regular")
end)
