-----------------------------
---- HYPRLAND CONFIG ENTRY ----
-----------------------------

-- Load order matters in two places:
--   monitors    first: workspaces.lua reads its monitor table and slot count.
--   workspaces  before binds that rely on its slot helpers (none do today).
-- Everything else is independent. Shared sizes (gaps, radius) are kept in
-- step with quickshell/config/Style.qml; decorations.lua says where.

require("modules.monitors")
require("modules.autostart")
require("modules.binds")
require("modules.workspaces")
require("modules.env")
require("modules.input")
require("modules.decorations")
require("modules.layout")
require("modules.misc")
require("modules.windowrules")
