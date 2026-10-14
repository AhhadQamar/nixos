// The screen the compositor has focused right now. Panels read this when they
// open, so they show up on the monitor you are looking at.

pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Hyprland

Singleton {
    readonly property var screen: {
        const name = Hyprland.focusedMonitor?.name ?? "";
        const all = Quickshell.screens;
        for (let i = 0; i < all.length; i++) {
            if (all[i].name === name)
                return all[i];
        }
        return all.length > 0 ? all[0] : null;
    }
}
