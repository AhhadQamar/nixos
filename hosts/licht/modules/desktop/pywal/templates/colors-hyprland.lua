-- Colors emitted by `wal -i`. active_border is picked using the same
-- heuristic as Quickshell's Colors.qml _pickAccent(): whichever of
-- color1..color6 is most saturated and closest to mid brightness.
-- This keeps the window border matching the active-workspace pill
-- color regardless of which wallpaper is currently applied.
local candidates = {
	"{color1.strip}",
	"{color2.strip}",
	"{color3.strip}",
	"{color4.strip}",
	"{color5.strip}",
	"{color6.strip}",
}

local function hexToSatVal(hex)
	local r = tonumber(hex:sub(1, 2), 16) / 255
	local g = tonumber(hex:sub(3, 4), 16) / 255
	local b = tonumber(hex:sub(5, 6), 16) / 255
	local max, min = math.max(r, g, b), math.min(r, g, b)
	local v = max
	local s = (max == 0) and 0 or (max - min) / max
	return s, v
end

local function pickAccent()
	local best, bestScore = candidates[4], -1 -- fall back to color4 if something's off
	for _, hex in ipairs(candidates) do
		local s, v = hexToSatVal(hex)
		local score = s * (1 - math.abs(v - 0.65))
		if score > bestScore then
			bestScore = score
			best = hex
		end
	end
	return best
end

return {
	active_border   = "rgb(" .. pickAccent() .. ")",
	inactive_border = "rgb({color8.strip})",
}
