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

    // ---- Music lyrics ---------------------------------------------------------
    // Lyrics come from LRCLIB (free, no account). With this on, lyrics found for
    // a file in your library are saved next to it as Song.lrc, so any player, and
    // this one offline, can use them.
    readonly property bool musicLyricsSave: true
    // Online search: how many results come at first, and how many more each time
    // you scroll near the end of the list, up to musicSearchMax. (Each page costs
    // a request; YouTube Music itself hands out about 20 at a time.)
    readonly property int musicSearchPage: 30
    readonly property int musicSearchMax: 200
    // The bar's music chip shows the line being sung, in place of the title and
    // artist (they come back in the gaps, and when a song has no synced lyrics).
    // Lyrics are then looked up for every song that plays, not only while the
    // panel shows them.
    readonly property bool musicBarLyrics: true

    // ---- Download manager ---------------------------------------------------
    // New downloads go into a folder by file type, unless you pick one yourself
    // under "Save to" (folders are relative to $HOME, and are made when needed)
    readonly property bool downloadAutoCategory: true
    readonly property var downloadCategories: [
        {
            "name": "Videos",
            "dir": "Videos",
            "exts": ["mp4", "mkv", "webm", "avi", "mov", "wmv", "flv", "m4v", "mpg", "mpeg", "ts"]
        },
        {
            "name": "Music",
            "dir": "Music",
            "exts": ["mp3", "flac", "ogg", "opus", "m4a", "aac", "wav", "wma"]
        },
        {
            "name": "Documents",
            "dir": "Documents",
            "exts": ["pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "odt", "ods", "odp", "epub", "djvu", "mobi"]
        },
        {
            "name": "Archives",
            "dir": "Downloads/Archives",
            "exts": ["zip", "rar", "7z", "tar", "gz", "xz", "bz2", "zst", "tgz", "iso", "img"]
        },
        {
            "name": "Programs",
            "dir": "Downloads/Programs",
            "exts": ["exe", "msi", "deb", "rpm", "appimage", "apk", "dmg"]
        }
    ]
    // The scheduler (Z in the panel, or `qs ipc call downloads schedule on`):
    // downloads run inside this window and wait outside it. A window that ends
    // before it starts runs over midnight.
    readonly property var downloadSchedule: ({
            "start": "02:00",
            "stop": "07:00"
        })
    // Add links to the downloads as soon as you copy them, if they are files
    // (an archive, a video, a torrent, a magnet link...). Off, because copying a
    // link to send to someone then starts a download.
    readonly property bool downloadClipboardAdd: false
    // Torrents and magnet links are added paused, and a list of their files opens
    // for you to tick the ones you want (P opens it again on any torrent). A
    // torrent with a single file just starts.
    readonly property bool downloadTorrentPick: true
    // The monthly data counter always runs: it is the "this month" figure by the
    // speed. Give it a limit in GB (0 = none) and you are told at 80% and at 100%.
    // With downloadPauseAtCap on, everything also pauses at 100%, and carries on
    // when the next month starts.
    readonly property real downloadMonthlyCapGB: 0
    readonly property bool downloadPauseAtCap: false

    // ---- Video grabber --------------------------------------------------------
    // Any link to a web page is downloaded with yt-dlp (it knows well over a
    // thousand sites, and looks for videos on the rest); your yt-dlp config decides
    // the folder and the default quality. Links to files go to aria2. A link that
    // could be either is asked about first. These sites skip the question:
    readonly property var downloadVideoSites: ["youtube.com", "youtu.be", "vimeo.com", "twitch.tv", "dailymotion.com", "twitter.com", "x.com", "reddit.com", "tiktok.com", "facebook.com", "instagram.com", "bilibili.com", "rumble.com", "streamable.com", "odysee.com", "soundcloud.com", "bandcamp.com", "nicovideo.jp", "vk.com", "ok.ru"]
    // Q in the panel steps through these. Default: whatever ~/.config/yt-dlp says.
    readonly property var downloadVideoQualities: [
        {
            "label": "Default",
            "args": []
        },
        {
            "label": "Best",
            "args": ["-f", "bv*+ba/b"]
        },
        {
            "label": "1080p",
            "args": ["-f", "bv*[height<=1080]+ba/b[height<=1080]"]
        },
        {
            "label": "720p",
            "args": ["-f", "bv*[height<=720]+ba/b[height<=720]"]
        },
        {
            "label": "480p",
            "args": ["-f", "bv*[height<=480]+ba/b[height<=480]"]
        },
        {
            "label": "Audio",
            "audio": true,
            "args": ["-f", "ba[ext=m4a]/ba/b", "-x", "--audio-format", "m4a"]
        }
    ]
    // How many videos are fetched at once
    readonly property int downloadVideoParallel: 2
    // A browser to take your logins from, for sites that want you signed in
    // (age-restricted or members-only videos), e.g. "firefox". Empty: none.
    readonly property string downloadVideoCookies: ""

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
    // While a Pomodoro focus session runs, hold back notification toasts (they
    // still land in the notification centre) and let them through again at the
    // break. Super+Z starts and pauses a session.
    readonly property bool focusSilencesNotifications: true
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
