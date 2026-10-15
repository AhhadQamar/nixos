// Greeter.qml
// The login screen. This file holds the mechanics and all the state; the look
// is LockHud.qml, the same design as the screen lock (see Lock.qml, whose
// state and animations this follows name for name).
//
// It runs in cage, a kiosk compositor started by greetd (see default.nix).
// Cage shows one fullscreen window, so the greeter is a single ordinary window
// on one screen (the shell's PanelWindows need layer-shell, which cage lacks).
//
// The order of things is greetd's: we ask for a session for the user, greetd
// runs PAM and asks for the password, we answer, and if PAM is happy greetd
// says it is ready. Then the screen says so (a crest runs out along the
// ruler and the dial collapses) and only after that do we hand greetd the command that
// starts your real session and quit. A wrong password ends that attempt, and
// we start a new one.
//
// There are no IPC commands: greetd starts it. Keys: type the password, Enter
// logs in. Pressing Enter before greetd has asked for the password is not
// lost: it is sent the moment the prompt arrives.
//
// default.nix passes in who to log in (GREETER_USER), what starts the session
// (GREETER_SESSION) and, when readable, the wallpaper (GREETER_WALLPAPER). Without a user or a session it says
// so in the journal (journalctl -b -t greeter) and does nothing.

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
    // Said in the corner of the screen
    readonly property string modeText: "Sign in"
    // How long the unlock animation plays before the dial collapses
    readonly property int holdMs: 950

    // ---- State (the same names as Lock.qml, which LockHud reads) ----------
    // What has been typed; emptied the moment it is handed to greetd
    property string password: ""
    // The last attempt was refused
    property bool failed: false
    // greetd could not be reached, or said something went wrong. Shown as an
    // error; the details are in the journal.
    property bool broken: false
    // greetd said yes: the crest and the swell play, then the dial collapses and the
    // session starts
    property bool succeeded: false
    // Password sent, waiting for greetd's answer
    property bool checking: false
    // greetd is waiting for the password
    property bool awaiting: false
    // Enter was pressed before greetd was ready for the password
    property bool pendingSubmit: false

    property real reveal: 0
    property real spinIn: 3.2
    property real fan: 1
    property real breath: 0
    property real shakeX: 0
    property real scan: -1
    property real ring: 0

    property color tone: (failed || broken) ? Colors.critical : Colors.accent
    property real flush: (failed || broken) ? 1 : 0
    property real okFill: succeeded ? 1 : 0
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
    readonly property real secFrac: clock.date.getSeconds() / 60
    readonly property string greeting: {
        const h = clock.date.getHours();
        const word = h < 5 ? "Good night" : (h < 12 ? "Good morning" : (h < 18 ? "Good afternoon" : "Good evening"));
        return user !== "" ? word + ", " + user : word;
    }
    // How far typing has turned the scale (px). It glides.
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

    SystemClock {
        id: clock

        precision: SystemClock.Seconds
    }

    // ---- Actions --------------------------------------------------------
    // Ask greetd for a session; it answers with the password prompt
    function begin() {
        if (user === "") {
            console.warn("greeter: no user to log in (GREETER_USER)");
            broken = true;
            return;
        }
        if (!Greetd.available) {
            console.warn("greeter: greetd is not running");
            broken = true;
            return;
        }
        Greetd.createSession(user);
    }

    function submit() {
        // Nothing to send, already checking, or already through
        if (password === "" || checking || succeeded)
            return;
        // greetd has not asked yet: send it as soon as it does
        if (!awaiting) {
            pendingSubmit = true;
            return;
        }
        send();
    }

    function send() {
        const typed = password;
        password = "";
        pendingSubmit = false;
        awaiting = false;
        checking = true;
        failed = false;
        broken = false;
        Greetd.respond(typed);
    }

    Component.onCompleted: {
        begin();
        openAnim.restart();
    }

    // ---- greetd ---------------------------------------------------------
    Connections {
        target: Greetd

        // greetd wants something: the password, or has something to tell us
        function onAuthMessage(message, error, responseRequired, echoResponse) {
            if (responseRequired) {
                root.checking = false;
                root.awaiting = true;
                if (root.pendingSubmit && root.password !== "")
                    root.send();
            } else if (error) {
                console.warn("greeter: greetd says:", message);
            }
        }

        // A wrong password (or a timeout): the session is over, start again
        function onAuthFailure(message) {
            root.checking = false;
            root.awaiting = false;
            root.failed = true;
            shake.restart();
            pingAnim.restart();
            root.begin();
        }

        // Logged in. The screen says so first; the session starts when the
        // rings have collapsed (launchTimer).
        function onReadyToLaunch() {
            if (root.sessionCmd.length === 0) {
                console.warn("greeter: no session to start (GREETER_SESSION)");
                root.checking = false;
                root.broken = true;
                return;
            }
            if (root.succeeded)
                return;
            root.checking = false;
            root.password = "";
            root.succeeded = true;
            pingAnim.restart();
            holdTimer.restart();
        }

        function onError(error) {
            console.warn("greeter: greetd error:", error);
            root.checking = false;
            root.broken = true;
            shake.restart();
            pingAnim.restart();
        }
    }

    // The unlock has been seen: the dial collapses, and the session
    // starts once they have (timers, not the animation's end, so a hiccup in
    // the animation can never leave you stuck at a login you already passed)
    Timer {
        id: holdTimer

        interval: root.holdMs
        onTriggered: {
            closeAnim.restart();
            launchTimer.restart();
        }
    }

    Timer {
        id: launchTimer

        interval: Style.moveMs + Style.fadeMs + Style.pressMs
        // greetd wants us gone as soon as the session is named, so launch
        // quits Quickshell (and with it cage).
        onTriggered: Greetd.launch(root.sessionCmd)
    }

    // ---- Motion (the same as Lock.qml) ----------------------------------
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

    SequentialAnimation {
        running: true
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

    SequentialAnimation {
        running: root.checking
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

    NumberAnimation {
        id: pingAnim

        target: root
        property: "ring"
        from: 0
        to: 1
        duration: Style.sweepMs
        easing.type: Style.easeMove
    }

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

    // ---- The window -----------------------------------------------------
    // Cage maximizes it to the screen it uses; the size here is only a hint.
    FloatingWindow {
        implicitWidth: 1280
        implicitHeight: 720
        color: Colors.background

        LockHud {
            anchors.fill: parent
            lock: root
        }
    }
}
