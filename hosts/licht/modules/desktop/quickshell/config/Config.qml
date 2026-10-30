// Everything personal about this shell in one place: which programs it starts,
// where your files live, and a few limits. Edit here, not in the panels.

pragma Singleton
import QtQuick
import Quickshell

Singleton {
    readonly property string home: Quickshell.env("HOME")

    // ---- Programs ---------------------------------------------------------
    // Terminal for apps that want one, and the file manager run inside it
    readonly property string terminal: "kitty"
    readonly property string fileManager: "yazi"

    // ---- aria2 ------------------------------------------------------------
    // File holding the aria2 RPC secret (the downloads panel reads it)
    readonly property string aria2SecretFile: "/run/agenix/aria2-rpc-secret"

    // ---- Folders ----------------------------------------------------------
    readonly property string wallpaperDir: home + "/Pictures/Wallpapers"
    readonly property string musicDir: home + "/Music"
    // Obsidian vault used by the capture panel
    readonly property string vaultDir: home + "/Documents/Vault"
    // save folder for the screenshot panel, relative to $HOME. The panel will create it if it doesn't exist.
    readonly property string screenshotDir: home + "/Pictures/Screenshots"
    // "Save to" choices in the downloads panel, relative to $HOME. The first
    // one (empty dir) means aria2's own default folder.
    readonly property var downloadFolders: [
        {
            "label": "",
            "dir": ""
        },
        {
            "label": "Videos",
            "dir": "Videos"
        },
        {
            "label": "Music",
            "dir": "Music"
        },
        {
            "label": "Documents",
            "dir": "Documents"
        }
    ]

    // ---- System updater ---------------------------------------------------
    // Same variable your `rebuild` script and nh use
    readonly property string flakeDir: {
        const e = Quickshell.env("SYS_FLAKE") || Quickshell.env("NH_FLAKE");
        return e && e.length > 0 ? e : home + "/nixos";
    }
    // Fallback until `hostname` answers
    readonly property string flakeHost: "licht"
    // Commit the new flake.lock (that file only, never pushed) after a good switch
    readonly property bool commitLock: true
    readonly property int updateCheckHours: 6
    // Scheduled checks are skipped on battery below this percentage
    readonly property int minBatteryForCheck: 30
    readonly property int generationKeepDays: 14

    // ---- Clock panel (timer, Pomodoro, stopwatch, alarms) -------------------
    // Pomodoro lengths in minutes, and how many focus sessions come before the
    // long break
    readonly property int pomodoroFocusMin: 25
    readonly property int pomodoroShortMin: 5
    readonly property int pomodoroLongMin: 15
    readonly property int pomodoroLongEvery: 4
    // Start the next phase by itself when one ends (false: wait for you)
    readonly property bool pomodoroAutoStart: false
    // The countdown timer: the length it starts with, and the discs on its dial
    // (minutes). +/- in the panel can set any other length.
    readonly property int timerDefaultMin: 10
    readonly property var timerPresets: [1, 3, 5, 10, 15, 20, 25, 30, 45, 60, 90]
    // Played when something rings. An empty list is silent. The default looks
    // for the freedesktop sound theme (sound-theme-freedesktop, see default.nix)
    // in the data folders and plays it through PipeWire; to use your own file
    // write ["pw-play", "/path/to/sound.oga"].
    readonly property var clockSound: ["bash", "-c", "IFS=:; for d in $XDG_DATA_DIRS /run/current-system/sw/share; do f=\"$d/sounds/freedesktop/stereo/alarm-clock-elapsed.oga\"; [ -f \"$f\" ] && exec pw-play \"$f\"; done"]

    // ---- Lock screen ------------------------------------------------------
    // The big clock: 12 hour with AM/PM (true) or 24 hour (false). The login
    // screen has no Config and always uses 12 hour.
    readonly property bool clock12h: true

    // ---- Screen time ------------------------------------------------------
    // Daily goal in minutes. 0 hides every goal marker.
    readonly property int dailyGoalMinutes: 360
}
