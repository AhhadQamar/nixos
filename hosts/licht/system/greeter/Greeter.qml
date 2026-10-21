// Greeter.qml
// The login screen. This file holds the mechanics; the state and motion are
// LockModel.qml and the look is LockStage.qml, the same as the screen lock
// (see Lock.qml), so the two are one design.
//
// It runs in cage, a kiosk compositor started by greetd (see default.nix).
// Cage shows one fullscreen window, so the greeter is a single ordinary window
// on one screen (the shell's PanelWindows need layer-shell, which cage lacks).
//
// The order of things is greetd's: we ask for a session for the user, greetd
// runs PAM and asks for the password, we answer, and if PAM is happy greetd
// says it is ready. Then the screen says so (the ruler fills green and the
// dial collapses) and only after that do we hand greetd the command that
// starts your real session and quit. A wrong password ends that attempt, and
// we start a new one.
//
// There are no IPC commands: greetd starts it. Keys and mouse: see
// LockStage.qml. Pressing Enter before greetd has asked for the password is
// not lost: it is sent the moment the prompt arrives.
//
// default.nix passes in who to log in (GREETER_USER), what starts the session
// (GREETER_SESSION) and, when readable, the wallpaper (GREETER_WALLPAPER).
// Without a user or a session it says so in the journal
// (journalctl -b -t greeter) and does nothing.

import QtQuick
import Quickshell
import Quickshell.Services.Greetd

Scope {
    id: root

    // ---- Settings -------------------------------------------------------
    readonly property string user: Quickshell.env("GREETER_USER") || ""
    // The session command, split into words for greetd
    readonly property var sessionCmd: (Quickshell.env("GREETER_SESSION") || "").split(" ").filter(w => w !== "")
    readonly property string wallpaper: Quickshell.env("GREETER_WALLPAPER") || ""

    // Power, for when you do not want to log in. Reboot and shutdown ask twice.
    // (No player, volume or brightness here: the greeter has none of them.)
    readonly property string systemctl: "/run/current-system/sw/bin/systemctl"
    readonly property var actions: [
        {
            "key": "suspend",
            "label": "Suspend",
            "group": "Power",
            "glyph": String.fromCodePoint(0xF0904),
            "showLabel": true,
            "run": () => Quickshell.execDetached([systemctl, "suspend"])
        },
        {
            "key": "reboot",
            "label": "Reboot",
            "group": "Power",
            "glyph": String.fromCodePoint(0xF0709),
            "showLabel": true,
            "critical": true,
            "run": () => Quickshell.execDetached([systemctl, "reboot"])
        },
        {
            "key": "shutdown",
            "label": "Shutdown",
            "group": "Power",
            "glyph": String.fromCodePoint(0xF0425),
            "showLabel": true,
            "critical": true,
            "run": () => Quickshell.execDetached([systemctl, "poweroff"])
        }
    ]

    // ---- State ----------------------------------------------------------
    // Password sent, waiting for greetd's answer
    property bool checking: false
    // greetd is waiting for the password
    property bool awaiting: false
    // Enter was pressed before greetd was ready for the password
    property bool pendingSubmit: false

    // ---- State and motion -----------------------------------------------
    LockModel {
        id: model

        checking: root.checking
        user: root.user
        wallpaper: root.wallpaper
        modeText: "Sign in"
        okText: "Signing in\u2026"
        brokenText: "Can't reach the login service"
        actions: root.actions

        onSubmitRequested: root.submit()
        // The unlock has been seen and the dial has collapsed. greetd wants
        // us gone as soon as the session is named, so launch quits Quickshell
        // (and with it cage).
        onFinished: Greetd.launch(root.sessionCmd)
    }

    // ---- Actions --------------------------------------------------------
    // Ask greetd for a session; it answers with the password prompt
    function begin() {
        if (user === "") {
            console.warn("greeter: no user to log in (GREETER_USER)");
            model.breakDown();
            return;
        }
        if (!Greetd.available) {
            console.warn("greeter: greetd is not running");
            model.breakDown();
            return;
        }
        Greetd.createSession(user);
    }

    function submit() {
        // Nothing to send, already checking, or already through
        if (model.password === "" || checking || model.succeeded)
            return;
        // greetd has not asked yet: send it as soon as it does
        if (!awaiting) {
            pendingSubmit = true;
            return;
        }
        send();
    }

    function send() {
        const typed = model.password;
        model.password = "";
        pendingSubmit = false;
        awaiting = false;
        checking = true;
        model.failed = false;
        model.broken = false;
        Greetd.respond(typed);
    }

    Component.onCompleted: {
        model.arrive();
        begin();
    }

    // ---- greetd ---------------------------------------------------------
    Connections {
        target: Greetd

        // greetd wants something: the password, or has something to tell us
        function onAuthMessage(message, error, responseRequired, echoResponse) {
            if (responseRequired) {
                root.checking = false;
                root.awaiting = true;
                if (root.pendingSubmit && model.password !== "")
                    root.send();
            } else if (error) {
                console.warn("greeter: greetd says:", message);
            }
        }

        // A wrong password (or a timeout): the session is over, start again
        function onAuthFailure(message) {
            root.checking = false;
            root.awaiting = false;
            model.deny();
            root.begin();
        }

        // Logged in. The screen says so first; the session starts when the
        // dial has collapsed (the model's `finished`).
        function onReadyToLaunch() {
            if (root.sessionCmd.length === 0) {
                console.warn("greeter: no session to start (GREETER_SESSION)");
                root.checking = false;
                model.breakDown();
                return;
            }
            if (model.succeeded)
                return;
            root.checking = false;
            model.accept();
        }

        function onError(error) {
            console.warn("greeter: greetd error:", error);
            root.checking = false;
            model.breakDown();
        }
    }

    // ---- The window -----------------------------------------------------
    // Cage maximizes it to the screen it uses; the size here is only a hint.
    FloatingWindow {
        implicitWidth: 1280
        implicitHeight: 720
        color: Colors.background

        LockStage {
            anchors.fill: parent
            lock: model
        }
    }
}
