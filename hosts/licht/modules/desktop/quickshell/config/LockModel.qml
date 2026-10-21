// LockModel.qml
// The state behind the screen lock (Lock.qml) and the login screen
// (Greeter.qml). Both make one of these and keep only what is their own:
// Lock.qml the compositor lock and PAM, Greeter.qml greetd. Every screen shows
// the same model (see LockStage.qml), so they all agree.
//
// It is kept small. Nothing here loops: the only things that move are a fade
// in, a short shake after a refusal and a fade out after an unlock, each a
// single short animation.
//
// The owner sets what it knows (who, what to say, whether something is being
// checked) and calls:
//   arrive()    the screen fades in
//   deny()      the password was refused: the marker turns red, the dial shakes
//   breakDown() the thing that checks passwords could not run: the same, but it
//               stays until the next attempt
//   accept()    the password was right: "Welcome back" is read out, the two
//               dials spin and come to rest at nought, like a safe opening,
//               then the rings open outwards and the screen fades.
//               `finished` follows.
// and listens to:
//   submitRequested   Enter was pressed with something typed: check it
//   finished          the screen has said yes and faded: open now
//
// Nothing here ever opens anything by itself: `finished` follows accept(), and
// accept() is only called by the owner when the password was checked and right.
//
// Time is a timer, not the animation's end, so a hiccup in an animation can
// never leave you stuck behind a lock you already opened.

import QtQuick
import Quickshell

Scope {
    id: root

    // ---- Set by the owner -----------------------------------------------
    // Password sent, waiting for the answer
    property bool checking: false
    property string user: ""
    property string wallpaper: ""
    // The small line above the greeting
    property string modeText: ""
    // The line under it, in each state
    property string readyText: "Type your password"
    property string okText: "Welcome back"
    property string brokenText: "Something went wrong"
    // Say how long the screen has been locked, beside the small line above the
    // greeting (the lock does; the login screen has nothing to say here)
    property bool showAway: false
    // How long the unlock is on show before the screen fades
    property int holdMs: Style.sweepMs

    signal submitRequested
    signal finished

    // ---- State ----------------------------------------------------------
    // What has been typed. Shared by every screen's field.
    property string password: ""
    // The last attempt was refused
    property bool failed: false
    // The checker could not run at all. The screen stays shut and says so.
    property bool broken: false
    // Yes: "Welcome back", the ring fills, then the screen fades and `finished`
    property bool succeeded: false
    // 0 = hidden, 1 = shown
    property real reveal: 0
    // 0..1 while the screen fades away after an unlock
    property real leave: 0
    // Sideways offset of the dial while it shakes
    property real shakeX: 0

    // The colour of the moment: the accent, red after a refusal
    readonly property color tone: (failed || broken) ? Colors.critical : Colors.accent

    // ---- What the screen says -------------------------------------------
    readonly property string statusText: succeeded ? okText : (broken ? brokenText : (failed ? "Incorrect password. Try again." : (checking ? "Checking\u2026" : readyText)))
    readonly property bool statusIsError: failed || broken

    // When this screen came up, and how long ago that was ("" while it is
    // still just now). It follows the clock, so it moves on once a minute.
    property real lockedAt: Date.now()
    readonly property string awayText: {
        const mins = Math.floor(Math.max(0, clock.date.getTime() - lockedAt) / 60000);
        if (mins < 1)
            return "";
        if (mins < 60)
            return mins + " min";
        const h = Math.floor(mins / 60);
        const r = mins % 60;
        return r === 0 ? h + "h" : h + "h " + r + "m";
    }
    // The small line above the greeting, with the time away when there is some
    readonly property string modeLine: modeText + (showAway && awayText !== "" ? "  \u00b7  " + awayText : "")

    // A 12 hour clock: 1 to 12, with AM or PM said separately
    readonly property string hourText: {
        const h = clock.date.getHours() % 12;
        return String(h === 0 ? 12 : h);
    }
    readonly property string periodText: clock.date.getHours() < 12 ? "AM" : "PM"
    readonly property string minuteText: Qt.formatDateTime(clock.date, "mm")
    readonly property string dateText: Qt.formatDateTime(clock.date, "dddd d MMMM")
    // Which of the greetings for the hour this visit uses (picked in arrive())
    property int greetPick: 0
    readonly property string greeting: {
        const h = clock.date.getHours();
        const sets = h < 5 ? ["Good night", "Up late", "Hello"] : (h < 12 ? ["Good morning", "Hello", "Morning"] : (h < 18 ? ["Good afternoon", "Hello", "Nice to see you"] : ["Good evening", "Hello", "Nice to see you"]));
        const word = sets[greetPick % sets.length];
        return user !== "" ? word + ", " + user : word;
    }

    onPasswordChanged: if (password !== "")
        failed = false

    // Only the minute is shown, so the clock wakes once a minute
    SystemClock {
        id: clock

        precision: SystemClock.Minutes
    }

    // ---- Calls ----------------------------------------------------------
    function reset() {
        holdTimer.stop();
        finishTimer.stop();
        openAnim.stop();
        closeAnim.stop();
        shake.stop();
        password = "";
        failed = false;
        broken = false;
        succeeded = false;
        reveal = 0;
        leave = 0;
        shakeX = 0;
    }

    function arrive() {
        reset();
        lockedAt = Date.now();
        greetPick = Math.floor(Math.random() * 3);
        openAnim.restart();
    }

    function deny() {
        failed = true;
        shake.restart();
    }

    function breakDown() {
        broken = true;
        shake.restart();
    }

    function accept() {
        if (succeeded)
            return;
        password = "";
        succeeded = true;
        holdTimer.restart();
    }

    // Enter: check the password
    function activate() {
        if (!succeeded && password !== "")
            submitRequested();
    }

    // ---- Timers ---------------------------------------------------------
    // The unlock has been seen: the screen fades, and `finished` follows once
    // it has
    Timer {
        id: holdTimer

        interval: root.holdMs
        onTriggered: {
            closeAnim.restart();
            finishTimer.restart();
        }
    }

    Timer {
        id: finishTimer

        interval: Style.moveMs + Style.fadeMs + Style.pressMs
        onTriggered: root.finished()
    }

    // ---- Motion ---------------------------------------------------------
    NumberAnimation {
        id: openAnim

        target: root
        property: "reveal"
        from: 0
        to: 1
        duration: Style.sweepMs
        easing.type: Style.easeEnter
    }

    NumberAnimation {
        id: closeAnim

        target: root
        property: "leave"
        to: 1
        duration: Style.moveMs + Style.fadeMs
        easing.type: Style.easeExit
    }

    // A small, soft shake after a refusal: a few pixels either way, slowing as
    // it settles
    SequentialAnimation {
        id: shake

        NumberAnimation {
            target: root
            property: "shakeX"
            to: -5
            duration: 90
            easing.type: Easing.InOutSine
        }
        NumberAnimation {
            target: root
            property: "shakeX"
            to: 5
            duration: 120
            easing.type: Easing.InOutSine
        }
        NumberAnimation {
            target: root
            property: "shakeX"
            to: -3
            duration: 120
            easing.type: Easing.InOutSine
        }
        NumberAnimation {
            target: root
            property: "shakeX"
            to: 0
            duration: 140
            easing.type: Easing.InOutSine
        }
    }
}
