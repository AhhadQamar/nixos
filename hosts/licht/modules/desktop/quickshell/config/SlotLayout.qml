pragma Singleton
import QtQuick
import Quickshell

// Workspace ids are laid out in blocks of `slotsPerMonitor` per monitor
// (1..10, 11..20, ...). Keep this equal to `slots` in hypr/config/modules/monitors.lua.
Singleton {
    readonly property int slotsPerMonitor: 10

    // The number to show for workspace `id`: the key you press to reach it.
    function labelFor(id) {
        return String((id - 1) % slotsPerMonitor + 1);
    }

    // Which block of ids `id` belongs to: 0 for 1..10, 1 for 11..20, ...
    function blockOf(id) {
        return Math.floor((id - 1) / slotsPerMonitor);
    }

    // 1 -> "¹", 12 -> "¹²". Marks which block a slot number comes from.
    function superscript(n) {
        const digits = "\u2070\u00B9\u00B2\u00B3\u2074\u2075\u2076\u2077\u2078\u2079";
        return String(n).split("").map(d => digits.charAt(Number(d))).join("");
    }
}
