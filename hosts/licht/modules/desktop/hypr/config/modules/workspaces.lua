------------------------------------------
---- PER-MONITOR WORKSPACES + BINDS ----
------------------------------------------
--   Super+1..0               go to slot on this monitor
--   Super+Shift+1..0         send window there and follow it
--   Super+Shift+Alt+1..0     send window there, stay here
--   Super+Alt+1..0           go to that slot on the OTHER monitor's block
--                            (also how you reach workspaces 11..20 while
--                            only one screen is connected)
--   Super+Alt+Left/Right     previous / next open workspace on this monitor
--   Super+Tab                back to the previous workspace on this monitor
--   Super+, / Super+.        focus previous / next monitor
--   Super+Shift+, / .        send window to previous / next monitor and follow
--   Super+Alt+, / .          send this whole workspace to previous / next monitor
--   Super+Alt+Tab            swap the two screens' workspaces

local mainMod = "SUPER"

-- Monitor names, positions and the slot count come from monitors.lua.
local layout = require("modules.monitors")
local SLOTS = layout.slots
local COUNT = #layout.monitors

-- Stable block per monitor name, so plug order can't reshuffle the numbers.
local blocks = {}
for i, m in ipairs(layout.monitors) do
	blocks[m.name] = i - 1
end

-- Monitors not listed in monitors.lua get the next free block after the
-- known ones, in the order they first show up, and keep it. (Using the
-- monitor id here skipped blocks: a third screen landed on 41..50.)
-- With a single screen connected (e.g. lid closed, docked) that screen is
-- always block 0, so Super+1..0 reach workspaces 1..10 whatever it is called.
local extra = {}
local extraCount = 0

local function block_of(monitor)
	if #hl.get_monitors() == 1 then
		return 0
	end
	if blocks[monitor.name] ~= nil then
		return blocks[monitor.name]
	end
	if extra[monitor.name] == nil then
		extra[monitor.name] = COUNT + extraCount
		extraCount = extraCount + 1
	end
	return extra[monitor.name]
end

local function slot_id(n)
	local monitor = hl.get_active_monitor()
	if not monitor then
		return tostring(n)
	end
	return tostring(block_of(monitor) * SLOTS + n)
end

-- Same slot, next monitor's block (wraps; an unlisted monitor goes to block 0).
local function other_slot_id(n)
	local monitor = hl.get_active_monitor()
	if not monitor then
		return tostring(n)
	end
	local next_block = block_of(monitor) + 1
	if next_block >= COUNT then
		next_block = 0
	end
	return tostring(next_block * SLOTS + n)
end

-- Pin a block of workspaces to a monitor; the first slot is where it starts.
local function create_rules(name, block)
	for i = 1, SLOTS do
		hl.workspace_rule({
			workspace = tostring(block * SLOTS + i),
			monitor = name,
			default = (i == 1),
		})
	end
end

-- Rules for every configured monitor, plugged in or not, so a monitor that
-- shows up later finds its block already waiting.
for name, block in pairs(blocks) do
	create_rules(name, block)
end

-- Monitors that aren't in monitors.lua still get a pinned block.
hl.on("monitor.added", function(monitor)
	if blocks[monitor.name] == nil then
		create_rules(monitor.name, block_of(monitor))
	end
end)

for i = 1, SLOTS do
	local key = tostring(i % 10)
	hl.bind(mainMod .. " + " .. key, function()
		hl.dispatch(hl.dsp.focus({ workspace = slot_id(i) }))
	end)
	hl.bind(mainMod .. " + SHIFT + " .. key, function()
		hl.dispatch(hl.dsp.window.move({ workspace = slot_id(i), follow = true }))
	end)
	hl.bind(mainMod .. " + SHIFT + ALT + " .. key, function()
		hl.dispatch(hl.dsp.window.move({ workspace = slot_id(i), follow = false }))
	end)
	hl.bind(mainMod .. " + ALT + " .. key, function()
		hl.dispatch(hl.dsp.focus({ workspace = other_slot_id(i) }))
	end)
end

-- Open workspaces on the current monitor only ("e" = existing)
hl.bind(mainMod .. " + ALT + right", hl.dsp.focus({ workspace = "e+1" }))
hl.bind(mainMod .. " + ALT + left", hl.dsp.focus({ workspace = "e-1" }))
hl.bind(mainMod .. " + mouse_down", hl.dsp.focus({ workspace = "e+1" }))
hl.bind(mainMod .. " + mouse_up", hl.dsp.focus({ workspace = "e-1" }))
hl.bind(mainMod .. " + Tab", hl.dsp.focus({ workspace = "previous_per_monitor" }))

-- Monitors
-- The name of the monitor before (-1) or after (+1) the active one, wrapping
-- around. Window moves go by name: "+" / "-" are not accepted as a monitor by
-- window.move, which is what raised "Invalid monitor".
local function neighbour_monitor(step)
	local monitors = hl.get_monitors()
	local active = hl.get_active_monitor()
	if not active or #monitors < 2 then
		return nil
	end
	for i, m in ipairs(monitors) do
		if m.name == active.name then
			return monitors[(i - 1 + step) % #monitors + 1].name
		end
	end
	return nil
end

local function move_window_to_monitor(step)
	local name = neighbour_monitor(step)
	if name then
		hl.dispatch(hl.dsp.window.move({ monitor = name, follow = true }))
	end
end

local function move_workspace_to_monitor(step)
	local name = neighbour_monitor(step)
	if name then
		hl.dispatch(hl.dsp.workspace.move({ monitor = name }))
	end
end

hl.bind(mainMod .. " + comma", hl.dsp.focus({ monitor = "-" }))
hl.bind(mainMod .. " + period", hl.dsp.focus({ monitor = "+" }))
hl.bind(mainMod .. " + SHIFT + comma", function()
	move_window_to_monitor(-1)
end)
hl.bind(mainMod .. " + SHIFT + period", function()
	move_window_to_monitor(1)
end)
hl.bind(mainMod .. " + ALT + comma", function()
	move_workspace_to_monitor(-1)
end)
hl.bind(mainMod .. " + ALT + period", function()
	move_workspace_to_monitor(1)
end)

-- Swap whatever two monitors are connected right now. With one monitor (or
-- three or more) it does nothing instead of naming outputs that may not exist.
hl.bind(mainMod .. " + ALT + Tab", function()
	local monitors = hl.get_monitors()
	if #monitors == 2 then
		hl.dispatch(hl.dsp.workspace.swap_monitors({
			monitor1 = monitors[1].name,
			monitor2 = monitors[2].name,
		}))
	end
end)

hl.config({
	binds = {
		-- Pressing the slot you are already on jumps back to where you were
		workspace_back_and_forth = true,
		allow_workspace_cycles = true,

		-- Switching workspace closes an open Super+S / pypr scratchpad
		-- instead of leaving it floating over the new one.
		hide_special_on_workspace_change = true,
	},

	cursor = {
		-- Going to a workspace on another monitor (Super+Ctrl+1..0, a click
		-- in the bar) also moves the pointer to the window you land on, so
		-- follow_mouse does not pull focus straight back to the screen you
		-- left. warp_on_monitor_change follows this one by default.
		warp_on_change_workspace = 1,

		-- When a window is refocused, the pointer returns to where it last
		-- was inside it instead of jumping to its centre.
		persistent_warps = true,
	},
})
