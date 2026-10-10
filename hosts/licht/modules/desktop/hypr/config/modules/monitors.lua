------------------
---- MONITORS ----
------------------

-- Single source of truth for screens (names from `hyprctl monitors`).
-- Order matters: the first monitor owns workspaces 1..slots, the second the
-- next block (11..20), and so on. Keep `slots` equal to slotsPerMonitor in
-- quickshell/config/SlotLayout.qml.
--
-- position: "0x0" pins a monitor to the origin; "auto-right" / "auto-left"
-- place a monitor beside the others, so detection order doesn't matter.
-- If the external screen sits on the LEFT of the laptop, use "auto-left".
local layout = {
	slots = 10,
	monitors = {
		{ name = "eDP-1", position = "0x0", scale = "1" },
		{ name = "DP-1", position = "auto-right", scale = "1" },
	},
}

for _, m in ipairs(layout.monitors) do
	hl.monitor({
		output = m.name,
		mode = "preferred",
		position = m.position,
		scale = m.scale,
	})
end

-- workspaces.lua reads the same table.
return layout
