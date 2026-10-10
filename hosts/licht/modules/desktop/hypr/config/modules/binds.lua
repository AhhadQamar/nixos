-------------------------------
---- PROGRAMS ----
-------------------------------
local terminal = "kitty"
local fileManager = "nautilus"
local browser = "firefox"
local altBrowser = "brave"

-------------------------------
---- KEYBINDINGS ----
-------------------------------
local mainMod = "SUPER"

-- Windows ------------------------------------------------------------------
hl.bind(mainMod .. " + Return", hl.dsp.exec_cmd(terminal))
hl.bind(mainMod .. " + Q", hl.dsp.window.close())
hl.bind(mainMod .. " + E", hl.dsp.exec_cmd(fileManager))
hl.bind(mainMod .. " + B", hl.dsp.exec_cmd(browser))
hl.bind(mainMod .. " + SHIFT + B", hl.dsp.exec_cmd(altBrowser))

hl.bind(mainMod .. " + SHIFT + V", hl.dsp.window.float({ action = "toggle" }))
hl.bind(mainMod .. " + SHIFT + J", hl.dsp.layout("togglesplit"))

-- Fullscreen / maximise
hl.bind(mainMod .. " + F", hl.dsp.window.fullscreen({ mode = "fullscreen", action = "toggle" }))
hl.bind(mainMod .. " + SHIFT + F", hl.dsp.window.fullscreen({ mode = "maximized", action = "toggle" }))

-- Focus: arrows and vim keys
hl.bind(mainMod .. " + left", hl.dsp.focus({ direction = "left" }))
hl.bind(mainMod .. " + right", hl.dsp.focus({ direction = "right" }))
hl.bind(mainMod .. " + up", hl.dsp.focus({ direction = "up" }))
hl.bind(mainMod .. " + down", hl.dsp.focus({ direction = "down" }))

hl.bind(mainMod .. " + h", hl.dsp.focus({ direction = "left" }))
hl.bind(mainMod .. " + l", hl.dsp.focus({ direction = "right" }))
hl.bind(mainMod .. " + k", hl.dsp.focus({ direction = "up" }))
hl.bind(mainMod .. " + j", hl.dsp.focus({ direction = "down" }))

-- Move a window through the layout. Super+Shift + arrows swaps with the
-- neighbour and carries on to the next monitor.
hl.bind(mainMod .. " + SHIFT + left", hl.dsp.window.swap({ direction = "left" }))
hl.bind(mainMod .. " + SHIFT + right", hl.dsp.window.swap({ direction = "right" }))
hl.bind(mainMod .. " + SHIFT + up", hl.dsp.window.swap({ direction = "up" }))
hl.bind(mainMod .. " + SHIFT + down", hl.dsp.window.swap({ direction = "down" }))

-- Resize the focused window from the keyboard: Super+Alt + h j k l, or up /
-- down for the height. Hold to keep going. Left / right change the width, up /
-- down the height, so it behaves the same for tiled and floating windows.
-- (Super+Alt + 1..0, Tab, comma, period and Left / Right belong to workspaces.lua, so those
-- do not clash; use h / l for the width.)
local resizeStep = 30
local function resizeBind(key, dx, dy)
	hl.bind(
		mainMod .. " + ALT + " .. key,
		hl.dsp.window.resize({ x = dx, y = dy, relative = true }),
		{ repeating = true }
	)
end

resizeBind("h", -resizeStep, 0)
resizeBind("l", resizeStep, 0)
resizeBind("k", 0, -resizeStep)
resizeBind("j", 0, resizeStep)
resizeBind("up", 0, -resizeStep)
resizeBind("down", 0, resizeStep)

-- Super + left / right mouse button: drag / resize. These two need the
-- `mouse` flag: without it the button is bound but does nothing, because the
-- dispatchers follow the pointer's movement.
hl.bind(mainMod .. " + mouse:272", hl.dsp.window.drag(), { mouse = true })
hl.bind(mainMod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })

-- Scratch workspace (Super+S shows / hides it, Super+Shift+S sends a window there)
hl.bind(mainMod .. " + S", hl.dsp.workspace.toggle_special("magic"))
hl.bind(mainMod .. " + SHIFT + S", hl.dsp.window.move({ workspace = "special:magic" }))
hl.bind(mainMod .. " + SHIFT + T", hl.dsp.exec_cmd("pypr toggle term"))

-- Quickshell panels (workspace keys live in workspaces.lua) ---------------------
--   Space  launcher        M  power menu        V  clipboard
--   A      notifications   Shift+A  do not disturb on / off
--   W      wallpaper       N  night light       Shift+N  night light on / off
--   T      screen time     D  downloads         I  capture
--   U      system updates  Shift+U  check for updates now (opens the panel)
-- Applying an update is deliberately not bound: press "a" twice inside the
-- updater panel, so a stray key can never start a switch.
local function qs(target, fn)
	return hl.dsp.exec_cmd("qs ipc call " .. target .. " " .. fn)
end

hl.bind(mainMod .. " + Space", qs("launcher", "toggle"))
hl.bind(mainMod .. " + M", qs("powermenu", "toggle"))
hl.bind(mainMod .. " + V", qs("clipboard", "toggle"))
hl.bind(mainMod .. " + A", qs("notifications", "toggle"))
hl.bind(mainMod .. " + SHIFT + A", qs("notifications", "dnd"))
hl.bind(mainMod .. " + W", qs("wallpaper", "toggle"))
hl.bind(mainMod .. " + N", qs("nightlight", "toggle"))
hl.bind(mainMod .. " + SHIFT + N", qs("nightlight", "power"))
hl.bind(mainMod .. " + T", qs("screentime", "toggle"))
hl.bind(mainMod .. " + D", qs("downloads", "toggle"))
hl.bind(mainMod .. " + I", qs("capture", "toggle"))
hl.bind(mainMod .. " + U", qs("sysupd", "toggle"))
hl.bind(mainMod .. " + SHIFT + U", qs("sysupd", "check"))

-- Session --------------------------------------------------------------------
-- Goes through logind so hypridle's lock_cmd runs. That keeps one hyprlock
-- instance and lets "lock before suspend" know the session is already locked.
hl.bind(mainMod .. " + SHIFT + L", hl.dsp.exec_cmd("loginctl lock-session"))

-- Screenshots --------------------------------------------------------------------
-- Print: region straight to the clipboard. Shift+Print: a window, same.
-- Super+F12 / Super+Shift+F12 save a file of the screen / a region.
hl.bind("Print", hl.dsp.exec_cmd("hyprshot -m region --clipboard-only"))
hl.bind("SHIFT + Print", hl.dsp.exec_cmd("hyprshot -m window --clipboard-only"))
hl.bind(mainMod .. " + F12", hl.dsp.exec_cmd("hyprshot -m output"))
hl.bind(mainMod .. " + SHIFT + F12", hl.dsp.exec_cmd("hyprshot -m region"))

-- Media keys (work on the lock screen too) --------------------------------------
hl.bind(
	"XF86AudioRaiseVolume",
	hl.dsp.exec_cmd("wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+"),
	{ locked = true, repeating = true }
)
hl.bind(
	"XF86AudioLowerVolume",
	hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"),
	{ locked = true, repeating = true }
)
hl.bind("XF86AudioMute", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"), { locked = true })
hl.bind("XF86AudioMicMute", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"), { locked = true })
hl.bind("XF86MonBrightnessUp", hl.dsp.exec_cmd("brightnessctl -e4 -n2 set 5%+"), { locked = true, repeating = true })
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("brightnessctl -e4 -n2 set 5%-"), { locked = true, repeating = true })
hl.bind("XF86AudioNext", hl.dsp.exec_cmd("playerctl next"), { locked = true })
hl.bind("XF86AudioPause", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioPlay", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioPrev", hl.dsp.exec_cmd("playerctl previous"), { locked = true })
