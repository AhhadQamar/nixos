// Lock.qml
// The screen lock. This file holds the mechanics; the state and motion are
// LockModel.qml and the look of each screen is LockStage.qml, both shared with
// the login screen (Greeter.qml) so the two never drift apart.
//
// How it works: WlSessionLock asks the compositor to lock the session. From
// then on the compositor shows nothing but our surfaces (one per screen) and
// sends no input anywhere else, so no window can be seen or clicked until we
// unlock. The password is checked by PAM (PamContext, service "qs-lock",
// declared in system/desktop.nix). The lock only opens when PAM says Success;
// a wrong password, a PAM error or anything unexpected leaves it locked.
//
// One PAM context and one shared password for the whole lock: every screen
// shows the same dial, lit by what you type, and you can type with either
// screen focused. Two contexts would mean two attempts running at once for a
// single password.
//
// Success is not instant: the dial locks on (brackets close in, a ring leaves it
// and "Welcome back" is read out), then the rings turn away and the screen
// lifts, and only then does the lock open (about a second and a half). The
// password has been checked by then, and if anything goes wrong in that time
// the screen simply stays locked.
//
//   qs ipc call lock lock
//
// There is deliberately no unlock command: the only way out is the password.
// Keys and mouse: see LockStage.qml.
//
// Everything that locks goes through logind: Super+Shift+L, the power menu and
// hypridle (idle, and before sleep) run `loginctl lock-session`, and
// hypridle's lock_cmd calls the command above.
//
// Volume and brightness are not discs here: their keys are bound with
// `locked = true` in Hyprland, so they work on the lock screen as they are.
// Mute and Mute mic are discs, and show whether they are muted right now.

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Pam
import Quickshell.Services.Pipewire

Scope {
    id: root

    // ---- Settings -------------------------------------------------------
    // The wallpaper switcher keeps this link pointing at the current one
    readonly property string wallpaper: Config.wallpaperDir + "/.current_wallpaper"

    // Whether the speakers and the microphone are muted right now. Pipewire
    // objects only report this while something tracks them.
    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var source: Pipewire.defaultAudioSource
    readonly property bool soundMuted: sink?.audio?.muted ?? false
    readonly property bool micMuted: source?.audio?.muted ?? false

    PwObjectTracker {
        objects: [root.sink, root.source]
    }

    // The discs on the dial (see LockModel.qml): the first half left of the
    // lock, the rest right of it, in this order. With a track loaded the player's
    // three discs lead, then Mute, Screen off, Suspend, Reboot and Shutdown (eight,
    // four each side of the lock); with none, Mute mic joins them (six, three
    // each side). The list only
    // changes when a track is loaded; what changes while it is up (Play and
    // Pause) is read through functions, so it is not rebuilt under your finger.
    readonly property var actions: {
        const list = [];
        if (Music.hasTrack) {
            list.push({
                "key": "prev",
                "label": "Previous",
                "hintNow": () => Music.title !== "" ? Music.title : "Previous track",
                "glyph": Icons.chevronLeft,
                "run": () => Music.prev()
            });
            list.push({
                "key": "play",
                "label": "Play / Pause",
                "labelNow": () => Music.playing ? "Pause" : "Play",
                "hintNow": () => Music.artist !== "" ? Music.artist : "Now playing",
                "glyph": Icons.play,
                "glyphNow": () => Music.playing ? Icons.pause : Icons.play,
                "run": () => Music.playPause()
            });
            list.push({
                "key": "next",
                "label": "Next",
                "hintNow": () => Music.title !== "" ? Music.title : "Next track",
                "glyph": Icons.chevronRight,
                "run": () => Music.next()
            });
        }
        // Quick things you want without unlocking: sound off, screen off.
        // Mute and Mute mic say how things are right now, and light up
        // (like a selected disc) while muted.
        list.push({
            "key": "mute",
            "label": "Sound",
            "labelNow": () => root.soundMuted ? "Sound is off" : "Sound is on",
            "hintNow": () => root.soundMuted ? "Press to turn it on" : "Press to mute",
            "glyph": String.fromCodePoint(0xF057E),
            "glyphNow": () => String.fromCodePoint(root.soundMuted ? 0xF0581 : 0xF057E),
            "activeNow": () => root.soundMuted,
            "run": () => {
                if (root.sink?.audio)
                    root.sink.audio.muted = !root.sink.audio.muted;
                else
                    Quickshell.execDetached(["wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", "toggle"]);
            }
        });
        // With no track loaded the player's three discs are missing, which
        // would leave the dial one disc short on the left: the microphone
        // takes the place, so both sides always hold the same number
        if (!Music.hasTrack) {
            list.push({
                "key": "micmute",
                "label": "Microphone",
                "labelNow": () => root.micMuted ? "Microphone is off" : "Microphone is on",
                "hintNow": () => root.micMuted ? "Press to turn it on" : "Press to mute",
                "glyph": String.fromCodePoint(0xF036C),
                "glyphNow": () => String.fromCodePoint(root.micMuted ? 0xF036D : 0xF036C),
                "activeNow": () => root.micMuted,
                "run": () => {
                    if (root.source?.audio)
                        root.source.audio.muted = !root.source.audio.muted;
                    else
                        Quickshell.execDetached(["wpctl", "set-mute", "@DEFAULT_AUDIO_SOURCE@", "toggle"]);
                }
            });
        }
        list.push({
            "key": "screenoff",
            "label": "Screen off",
            "hint": "Any key wakes it",
            "glyph": String.fromCodePoint(0xF0D90),
            // Hyprland turns the screen back on at the next key or mouse
            // move; hypridle re-applies the night light on wake, so this
            // does the same once the screen is back
            "run": () => Quickshell.execDetached(["sh", "-c", "hyprctl dispatch 'hl.dsp.dpms({ action = \"disable\" })'; sleep 2; while hyprctl monitors -j | grep -q '\"dpmsStatus\": false'; do sleep 1; done; qs ipc call nightlight reapply"])
        });
        list.push({
            "key": "suspend",
            "label": "Suspend",
            "hint": "Enter to sleep",
            "glyph": String.fromCodePoint(0xF0904),
            "run": () => Quickshell.execDetached(["systemctl", "suspend"])
        });
        list.push({
            "key": "reboot",
            "label": "Reboot",
            "hint": "Needs a second press",
            "critical": true,
            "glyph": String.fromCodePoint(0xF0709),
            "run": () => Quickshell.execDetached(["systemctl", "reboot"])
        });
        list.push({
            "key": "shutdown",
            "label": "Shutdown",
            "hint": "Needs a second press",
            "critical": true,
            "glyph": String.fromCodePoint(0xF0425),
            "run": () => Quickshell.execDetached(["systemctl", "poweroff"])
        });
        return list;
    }

    // ---- State and motion -----------------------------------------------
    LockModel {
        id: model

        live: sessionLock.locked
        checking: pam.active
        user: Quickshell.env("USER") || ""
        wallpaper: root.wallpaper
        modeText: "Session locked"
        showAway: true
        okText: "Welcome back"
        brokenText: "Can't check the password"
        actions: root.actions
        nowActive: Music.hasTrack
        nowTitle: Music.title
        nowArtist: Music.artist

        onSubmitRequested: root.submit()
        // The unlock has been seen and the dial has collapsed
        onFinished: sessionLock.locked = false
    }

    // ---- Actions --------------------------------------------------------
    function submit() {
        // Nothing to check, already checking, or already through
        if (model.password === "" || pam.active || model.succeeded)
            return;
        model.failed = false;
        model.broken = false;
        pam.start();
    }

    function lock() {
        // Already locked: a second request (hypridle can send several) must
        // not wipe what is being typed
        if (sessionLock.locked)
            return;
        // Start from the dome, hidden below the edge
        model.arrive();
        sessionLock.locked = true;
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
            if (model.password === "") {
                pam.abort();
                return;
            }
            const typed = model.password;
            model.password = "";
            pam.respond(typed);
        }

        // The only place the lock is ever let go. Nothing opens yet: the
        // screen says so first, collapses, and then `finished` opens the lock.
        onCompleted: result => {
            if (result == PamResult.Success)
                model.accept();
            else
                model.deny();
        }

        // Anything other than a clean yes or no: stay locked
        onError: model.breakDown()
    }

    // ---- The lock -------------------------------------------------------
    // The surface below is a template: while locked, WlSessionLock makes one
    // for every screen.
    WlSessionLock {
        id: sessionLock

        WlSessionLockSurface {
            // Shows until the wallpaper has loaded
            color: Colors.background

            LockStage {
                anchors.fill: parent
                lock: model
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
