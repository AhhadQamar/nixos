// Lock.qml
// The screen lock. This file holds the mechanics; the state and motion are
// LockModel.qml and the look of each screen is LockStage.qml, both shared with
// the login screen (the greeter's Greeter.qml) so the two never drift apart.
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
//
// Success is not instant: the ruler fills green, the dial collapses, and only
// then does the lock open (about a second). The password has been checked by
// then, and if anything goes wrong in that second the screen simply stays
// locked.
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
// Volume, brightness and mute are not buttons here: their keys are bound with
// `locked = true` in Hyprland, so they work on the lock screen as they are.

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Pam

Scope {
    id: root

    // ---- Settings -------------------------------------------------------
    // The wallpaper switcher keeps this link pointing at the current one
    readonly property string wallpaper: Config.wallpaperDir + "/.current_wallpaper"

    // The buttons under the greeting, in groups (see LockModel.qml). The list
    // only changes when a track is loaded; what changes while it is up (Play
    // and Pause) is read through functions, so it is not rebuilt under your
    // finger.
    readonly property var actions: {
        const list = [];
        if (Music.hasTrack) {
            list.push({
                "key": "prev",
                "label": "Previous",
                "group": "Now playing",
                "glyph": Icons.chevronLeft,
                "run": () => Music.prev()
            });
            list.push({
                "key": "play",
                "label": "Play / Pause",
                "group": "Now playing",
                "glyph": Icons.play,
                "glyphNow": () => Music.playing ? Icons.pause : Icons.play,
                "run": () => Music.playPause()
            });
            list.push({
                "key": "next",
                "label": "Next",
                "group": "Now playing",
                "glyph": Icons.chevronRight,
                "run": () => Music.next()
            });
        }
        list.push({
            "key": "suspend",
            "label": "Suspend",
            "group": "Power",
            "glyph": String.fromCodePoint(0xF0904),
            "showLabel": true,
            "run": () => Quickshell.execDetached(["systemctl", "suspend"])
        });
        list.push({
            "key": "reboot",
            "label": "Reboot",
            "group": "Power",
            "glyph": String.fromCodePoint(0xF0709),
            "showLabel": true,
            "critical": true,
            "run": () => Quickshell.execDetached(["systemctl", "reboot"])
        });
        list.push({
            "key": "shutdown",
            "label": "Shutdown",
            "group": "Power",
            "glyph": String.fromCodePoint(0xF0425),
            "showLabel": true,
            "critical": true,
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
