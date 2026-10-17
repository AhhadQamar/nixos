// Lock.qml
// The screen lock. This file holds the mechanics and all the state; the look
// of each screen is LockHud.qml, which the login screen (Greeter.qml) shares.
//
// How it works: WlSessionLock asks the compositor to lock the session. From
// then on the compositor shows nothing but our surfaces (one per screen) and
// sends no input anywhere else, so no window can be seen or clicked until we
// unlock. The password is checked by PAM (PamContext, service "qs-lock",
// declared in system/desktop.nix). The lock only opens when PAM says Success;
// a wrong password, a PAM error or anything unexpected leaves it locked.
//
// One PAM context and one shared password for the whole lock: every screen
// shows the same dots, and you can type with either screen focused. Two
// contexts would mean two attempts running at once for a single password.
// The animation state lives here too, so every screen moves as one.
//
// What makes it alive: the time is a poster on the left, and the dial (a rail
// of glass discs under the ruler) is the interface. Meters (battery, volume,
// brightness) sit left of the lock disc, actions (media, suspend, reboot,
// shutdown) right of it; the selected disc is read out below. Every key you
// type turns the ruler, and a right password sends a crest the whole width.
//
// Success is not instant: a crest runs out along the ruler, the dial collapses, and only
// then does the lock open (about a second). The password has been checked by
// then, and if anything goes wrong in that second the screen simply stays
// locked.
//
//   qs ipc call lock lock
//
// There is deliberately no unlock command: the only way out is the password.
// Keys: type the password, Enter unlocks. Tab / Shift+Tab (or Ctrl+Left / Right)
// turn the dial, Ctrl+Enter presses a disc, Ctrl+Up / Down adjust volume or
// brightness, Esc goes back to the lock disc (see LockHud.qml).
//
// Everything that locks goes through logind: Super+Shift+L, the power menu and
// hypridle (idle, and before sleep) run `loginctl lock-session`, and
// hypridle's lock_cmd calls the command above.

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Pam
import Quickshell.Services.Pipewire

Scope {
    id: root

    // ---- Settings -------------------------------------------------------
    // How long the unlock animation plays before the dial collapses
    readonly property int holdMs: 950
    // The wallpaper switcher keeps this link pointing at the current one
    readonly property string wallpaper: Config.wallpaperDir + "/.current_wallpaper"

    // Said in the corner of the screen
    readonly property string modeText: "Session locked"

    // ---- What the dial offers ---------------------------------------------
    // What the music player has loaded (the dial shows it under the date)
    readonly property bool nowActive: Music.hasTrack
    readonly property string nowTitle: Music.title
    readonly property string nowArtist: Music.artist
    readonly property real nowProgress: Music.progress

    // Said on the button of the lock disc
    readonly property string goText: "Unlock"

    // The default speaker, for the volume disc (tracked, so its volume is read)
    readonly property var sink: Pipewire.defaultAudioSink

    // The discs of the dial: a label, a glyph, and what each does. The list
    // only changes when a track is loaded or the backlight is found; what
    // changes while it is up (Play and Pause, the volume) is read through
    // functions, so the dial is not rebuilt under your finger. See the header
    // of LockHud.qml for the optional fields.
    readonly property var actions: {
        const list = [];
        if (Brightness.available)
            list.push({
                "key": "brightness",
                "label": "Brightness",
                "head": "Screen",
                "icon": String.fromCodePoint(0xF00DF),
                "level": () => Brightness.percent / 100,
                "adjust": dir => Brightness.step(dir * 5)
            });
        list.push({
            "key": "volume",
            "label": "Volume",
            "head": "Sound",
            "icon": String.fromCodePoint(0xF057E),
            "level": () => Math.min(1, root.sink?.audio?.volume ?? 0),
            "sub": () => (root.sink?.audio?.muted ?? false) ? "Muted" : "",
            "adjust": dir => {
                const au = root.sink?.audio;
                if (au)
                    au.volume = Math.max(0, Math.min(1, au.volume + dir * 0.05));
            },
            "run": () => {
                const au = root.sink?.audio;
                if (au)
                    au.muted = !au.muted;
            }
        });
        if (Music.hasTrack) {
            const now = () => (Music.artist ? Music.artist + "  \u00b7  " : "") + Music.title;
            list.push({"key": "prev", "label": "Previous", "head": "Now playing", "icon": Icons.chevronLeft, "sub": now, "run": () => Music.prev()});
            list.push({"key": "play", "label": "Play / Pause", "head": "Now playing", "icon": Icons.play, "name": () => Music.playing ? "Pause" : "Play", "glyph": () => Music.playing ? Icons.pause : Icons.play, "sub": now, "run": () => Music.playPause()});
            list.push({"key": "next", "label": "Next", "head": "Now playing", "icon": Icons.chevronRight, "sub": now, "run": () => Music.next()});
        }
        list.push({"key": "suspend", "label": "Suspend", "head": "Power", "icon": String.fromCodePoint(0xF0904), "run": () => Quickshell.execDetached(["systemctl", "suspend"])});
        list.push({"key": "reboot", "label": "Reboot", "head": "Power", "icon": String.fromCodePoint(0xF0709), "critical": true, "run": () => Quickshell.execDetached(["systemctl", "reboot"])});
        list.push({"key": "shutdown", "label": "Shutdown", "head": "Power", "icon": String.fromCodePoint(0xF0425), "critical": true, "run": () => Quickshell.execDetached(["systemctl", "poweroff"])});
        return list;
    }

    // ---- State ----------------------------------------------------------
    // What has been typed. Shared by every screen's field, emptied the moment
    // it is handed to PAM and again once the lock opens.
    property string password: ""
    // The last attempt was refused
    property bool failed: false
    // PAM could not run at all (missing service, no PAM). The screen stays
    // locked, and says so.
    property bool broken: false
    // PAM said yes: the crest and the swell play, then the dial collapses and it opens
    property bool succeeded: false
    // Password sent, waiting for PAM's answer
    readonly property bool checking: pam.active

    // Which disc of the dial is selected (-1 = the lock disc), and which one
    // waits for a second press (-1 = none). LockHud turns and presses; they
    // live here so every screen shows the same dial.
    property int dialIndex: -1
    property int armed: -1

    // 0 = hidden below the edge, 1 = in place
    property real reveal: 0
    // How far the scale is swung round while arriving (and back when leaving)
    property real spinIn: 3.2
    // 1 = collapsed and small, 0 = the resting instrument
    property real fan: 1
    // A slow pulse (0..1) for the disc's ring
    property real breath: 0
    // Sideways offset of the disc while it shakes after a wrong password
    property real shakeX: 0
    // Where the scan along the ruler is (-1 = far left, 1 = far right)
    property real scan: -1
    // 0..1 while a ring leaves the disc
    property real ring: 0

    // The colour of the moment: red after a refusal, the accent otherwise
    property color tone: (failed || broken) ? Colors.critical : Colors.accent
    // 0..1 red over the whole ruler while the refusal is on show
    property real flush: (failed || broken) ? 1 : 0
    // 0..1 how far the unlock crest has run outward from the middle
    property real okFill: succeeded ? 1 : 0
    // 0..1 how visible the scan is (only while PAM checks)
    property real scanOn: checking ? 1 : 0

    // A 12 hour clock: 1 to 12, with AM or PM said separately
    readonly property string hourText: {
        const h = clock.date.getHours() % 12;
        return String(h === 0 ? 12 : h);
    }
    readonly property string periodText: clock.date.getHours() < 12 ? "AM" : "PM"
    // Minutes on a line that never wraps (local time), which the ruler follows
    readonly property real minutesNow: clock.date.getTime() / 60000 - clock.date.getTimezoneOffset()
    readonly property string minuteText: Qt.formatDateTime(clock.date, "mm")
    readonly property string dateText: Qt.formatDateTime(clock.date, "dddd d MMMM")
    // 0..1 through the current minute
    readonly property real secFrac: clock.date.getSeconds() / 60
    readonly property string greeting: {
        const h = clock.date.getHours();
        const word = h < 5 ? "Good night" : (h < 12 ? "Good morning" : (h < 18 ? "Good afternoon" : "Good evening"));
        const who = Quickshell.env("USER") || "";
        return who !== "" ? word + ", " + who : word;
    }
    // How far typing has turned the ruler (px). It glides, so each key is a
    // small step and Backspace turns it back.
    property real turn: password.length * 5

    onPasswordChanged: if (password !== "")
        failed = false

    Behavior on tone {
        ColorAnimation {
            duration: Style.baseMs
        }
    }
    Behavior on flush {
        NumberAnimation {
            duration: Style.baseMs
            easing.type: Style.easeMove
        }
    }
    Behavior on okFill {
        NumberAnimation {
            duration: Style.sweepMs
            easing.type: Style.easeMove
        }
    }
    Behavior on scanOn {
        NumberAnimation {
            duration: Style.fadeMs
        }
    }
    Behavior on turn {
        NumberAnimation {
            duration: Style.moveMs
            easing.type: Style.easeMove
        }
    }

    // Seconds drive the arc around the disc, but only while the lock is up
    SystemClock {
        id: clock

        precision: sessionLock.locked ? SystemClock.Seconds : SystemClock.Minutes
    }

    // Pipewire only reports a node's volume while something tracks it
    PwObjectTracker {
        objects: root.sink ? [root.sink] : []
    }

    // ---- Actions --------------------------------------------------------
    function submit() {
        // Nothing to check, already checking, or already through
        if (password === "" || pam.active || succeeded)
            return;
        failed = false;
        broken = false;
        pam.start();
    }

    function lock() {
        // Already locked: a second request (hypridle can send several) must
        // not wipe what is being typed
        if (sessionLock.locked)
            return;
        holdTimer.stop();
        unlockTimer.stop();
        closeAnim.stop();
        password = "";
        failed = false;
        broken = false;
        succeeded = false;
        dialIndex = -1;
        armed = -1;
        // Start from the dome, hidden below the edge
        reveal = 0;
        spinIn = 3.2;
        fan = 1;
        ring = 0;
        sessionLock.locked = true;
        openAnim.restart();
    }

    // ---- PAM ------------------------------------------------------------
    PamContext {
        id: pam

        config: "qs-lock"
        configDirectory: "/etc/pam.d"

        // PAM asks for the password: answer with what was typed, and empty
        // the field so the password does not linger on screen or in memory
        onPamMessage: {
            if (!pam.responseRequired)
                return;
            if (root.password === "") {
                pam.abort();
                return;
            }
            const typed = root.password;
            root.password = "";
            pam.respond(typed);
        }

        // The only place the lock is ever let go. Nothing opens yet: the
        // screen says so first (holdTimer), collapses, and then unlockTimer
        // opens the lock.
        onCompleted: result => {
            if (result == PamResult.Success) {
                root.password = "";
                root.succeeded = true;
                pingAnim.restart();
                holdTimer.restart();
            } else {
                root.failed = true;
                shake.restart();
                pingAnim.restart();
            }
        }

        // Anything other than a clean yes or no: stay locked
        onError: {
            root.broken = true;
            shake.restart();
            pingAnim.restart();
        }
    }

    // The unlock has been seen: the dial collapses, and the lock opens
    // once it has (a timer, not the animation's end, so that a hiccup in the
    // animation can never leave you stuck behind a lock you already opened)
    Timer {
        id: holdTimer

        interval: root.holdMs
        onTriggered: {
            closeAnim.restart();
            unlockTimer.restart();
        }
    }

    Timer {
        id: unlockTimer

        interval: Style.moveMs + Style.fadeMs + Style.pressMs
        onTriggered: sessionLock.locked = false
    }

    // ---- Motion ---------------------------------------------------------
    // Arriving: the disc and the ruler swing in from the left over a tight
    // dome and unfurl into the instrument.
    ParallelAnimation {
        id: openAnim

        NumberAnimation {
            target: root
            property: "reveal"
            to: 1
            duration: Style.sweepMs
            easing.type: Style.easeEnter
        }
        NumberAnimation {
            target: root
            property: "spinIn"
            to: 0
            duration: Style.sweepMs + Style.moveMs
            easing.type: Style.easeEnter
        }
        NumberAnimation {
            target: root
            property: "fan"
            to: 0
            duration: Style.sweepMs + Style.ambientMs / 2
            easing.type: Style.easeMove
        }
    }

    // Leaving: the instrument collapses back.
    ParallelAnimation {
        id: closeAnim

        NumberAnimation {
            target: root
            property: "reveal"
            to: 0
            duration: Style.moveMs + Style.fadeMs
            easing.type: Style.easeExit
        }
        NumberAnimation {
            target: root
            property: "spinIn"
            to: -3.2
            duration: Style.moveMs + Style.fadeMs
            easing.type: Style.easeExit
        }
        NumberAnimation {
            target: root
            property: "fan"
            to: 1
            duration: Style.moveMs + Style.fadeMs
            easing.type: Style.easeExit
        }
    }

    // Slow breath for the ring around the disc. Loops only run while locked.
    SequentialAnimation {
        running: sessionLock.locked
        loops: Animation.Infinite

        NumberAnimation {
            target: root
            property: "breath"
            from: 0
            to: 1
            duration: Style.ambientMs * 2
            easing.type: Style.easeAmbient
        }
        NumberAnimation {
            target: root
            property: "breath"
            from: 1
            to: 0
            duration: Style.ambientMs * 2
            easing.type: Style.easeAmbient
        }
    }

    // PAM is checking: a bright patch runs along the ruler and back
    SequentialAnimation {
        running: root.checking && sessionLock.locked
        loops: Animation.Infinite

        NumberAnimation {
            target: root
            property: "scan"
            to: 1.15
            duration: Style.sweepMs + Style.ambientMs
            easing.type: Style.easeAmbient
        }
        NumberAnimation {
            target: root
            property: "scan"
            to: -1.15
            duration: Style.sweepMs + Style.ambientMs
            easing.type: Style.easeAmbient
        }
    }

    // A ring leaves the disc: on a refusal (red) and on success
    NumberAnimation {
        id: pingAnim

        target: root
        property: "ring"
        from: 0
        to: 1
        duration: Style.sweepMs
        easing.type: Style.easeMove
    }

    // A wrong password: the disc shakes
    SequentialAnimation {
        id: shake

        NumberAnimation {
            target: root
            property: "shakeX"
            to: -9
            duration: Style.pressMs
            easing.type: Style.easePress
        }
        NumberAnimation {
            target: root
            property: "shakeX"
            to: 8
            duration: Style.pressMs
            easing.type: Style.easeAmbient
        }
        NumberAnimation {
            target: root
            property: "shakeX"
            to: -5
            duration: Style.pressMs
            easing.type: Style.easeAmbient
        }
        NumberAnimation {
            target: root
            property: "shakeX"
            to: 3
            duration: Style.pressMs
            easing.type: Style.easeAmbient
        }
        NumberAnimation {
            target: root
            property: "shakeX"
            to: 0
            duration: Style.pressMs
            easing.type: Style.easePress
        }
    }

    // ---- The lock -------------------------------------------------------
    // The surface below is a template: while locked, WlSessionLock makes one
    // for every screen.
    WlSessionLock {
        id: sessionLock

        WlSessionLockSurface {
            // Shows until the wallpaper has loaded
            color: Colors.background

            LockHud {
                anchors.fill: parent
                lock: root
            }
        }
    }

    IpcHandler {
        function lock() {
            root.lock();
        }

        target: "lock"
    }
}
