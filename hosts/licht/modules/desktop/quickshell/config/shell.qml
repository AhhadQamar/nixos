//@ pragma UseQApplication
import QtQuick
import Quickshell

ShellRoot {
    Bar {}
    Launcher {}

    NotificationPopups {}

    NotificationCenter {
        id: notifCenter
    }

    ClipboardManager {
        id: clipboardManager
    }

    PowerMenu {
        id: powerMenu
    }
    Lock {}
    Polkit {}
    VolumeBrightnessOSD {}

    WallpaperSwitcher {
        id: wallpaperSwitcher
    }

    CavaVisualizer {}
    SystemUpdater {}
    MusicPlayer {}
    PackageSearch {}
    NightLight {}
    Screenshot {}
    ScreenTime {}
    DownloadManager {}
    Inbox {}
    ClockIpc {}
}
