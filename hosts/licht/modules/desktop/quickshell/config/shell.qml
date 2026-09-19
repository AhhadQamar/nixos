import QtQuick
import Quickshell

ShellRoot {
    Bar {
    }

    AppLauncher {
        id: appLauncher
    }

    NotificationPopups {
    }

    NotificationCenter {
        id: notifCenter
    }

    ClipboardManager {
        id: clipboardManager
    }

    PowerMenu {
        id: powerMenu
    }

    VolumeBrightnessOSD {
    }

    WallpaperSwitcher {
        id: wallpaperSwitcher
    }

    CavaVisualizer {
    }

}
