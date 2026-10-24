// LockModel.qml
// The state and the motion behind the screen lock (Lock.qml) and the login
// screen (Greeter.qml). Both make one of these and keep only what is their
// own: Lock.qml the compositor lock and PAM, Greeter.qml greetd. Every screen
// shows the same model (see LockStage.qml), so they all move as one and the
// two screens can never drift apart.
//
// The screen is a dial, like the launcher and the power menu. The lock itself
// is the middle disc ("home"); the other things you can do sit on the dial
// either side of it. Turn the dial to one and its name is read out. Typing
// always brings it home again, so the password is never lost to a stray key.
//
// The owner sets what it knows (who, what to say, which buttons, whether
// something is being checked) and calls:
//   arrive()    start from the dome and unfurl into the dial
//   deny()      the password was refused: the disc shakes, the ruler flushes red
//   breakDown() the thing that checks passwords could not run: the same, but it
//               stays until the next attempt
//   accept()    the password was right. First it is accepted: the dial locks
//               on (brackets close in, a ring leaves it, a ripple runs round
//               the rulers) and "Welcome back" is read out. Then the screen
//               leaves, as the power menu does: the rings turn away, the
//               clock rises, the wash clears and the wallpaper comes into
//               focus. `finished` follows, about a second and a quarter
//               after accept().
//   wake()      a key or the pointer moved: undo the settling (see `calm`) and
//               start the wait again
//   reset()     back to nothing (arrive() does this first)
// and listens to:
//   submitRequested   Enter was pressed at home with something typed: check it
//   finished          the screen has said yes and collapsed: open now
//
// Nothing here ever opens anything by itself: `finished` follows accept(), and
// accept() is only called by the owner when the password was checked and right.
//
// Time is a timer, not the animation's end, so a hiccup in an animation can
// never leave you stuck behind a lock you already opened.
//
// Each entry of `actions` is a disc on the dial. The first half of the list
// sits left of the lock disc and the rest right of it, in order. With an odd
// count the right side has one more; the dial always turns about the lock.
//   key        a stable name
//   label      what it is called (labelNow(), if present, says it right now)
//   hint       the small line under the name (hintNow(), if present, says it right now)
//   glyph      an icon from Icons.qml (glyphNow(), if present, says it right now)
//   activeNow  true lights the disc up like a selected one (optional): used
//              for "muted"
//   critical   needs a second press: it turns red and counts down
//   enabled    false dims it (optional)
//   run()      what it does

import QtQuick
import Quickshell

Scope {
    id: root

    // ---- Set by the owner -----------------------------------------------
    // The loops (the breath, the scan) only run while this is true
    property bool live: true
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
    property string placeholder: "Password"
    property var actions: []
    // What the music player has loaded (shown under the date)
    property bool nowActive: false
    property string nowTitle: ""
    property string nowArtist: ""
    // Say how long the screen has been locked, beside the small line above the
    // greeting (the lock does; the login screen has nothing to say here)
    property bool showAway: false
    // How long the unlock is on show before the dial collapses
    property int holdMs: 950
    // How long a destructive disc waits for its second press
    property int confirmMs: 3000

    signal submitRequested
    signal finished
    // A disc was pressed (its key): the disc rings, so a press is never silent
    signal activated(string key)

    // ---- State ----------------------------------------------------------
    // What has been typed. Shared by every screen's field.
    property string password: ""
    // The last attempt was refused
    property bool failed: false
    // The checker could not run at all. The screen stays shut and says so.
    property bool broken: false
    // Yes: the ruler ripples, the lock becomes a tick, the dial collapses, then `finished`
    property bool succeeded: false
    // The disc the dial is turned to ("home" is the lock), and the one
    // waiting for its second press ("" = none)
    property string selectedKey: "home"
    property string armed: ""
    // 1 right after arming, running down to 0 as the confirmation lapses
    property real armLeft: 0
    // Off while resetting, so the dial does not glide back across the screen
    property bool glide: true

    // The discs in order, the lock among them
    readonly property var slots: {
        const h = Math.floor(actions.length / 2);
        const left = actions.slice(0, h);
        const right = actions.slice(h);
        return left.concat([
            {
                "key": "home",
                "home": true
            }
        ], right);
    }
    readonly property int homeIndex: Math.floor(actions.length / 2)
    readonly property int selected: {
        for (let i = 0; i < slots.length; i++) {
            if (slots[i].key === selectedKey)
                return i;
        }
        return homeIndex;
    }
    readonly property bool onHome: selectedKey === "home"
    readonly property var current: slots[selected]

    // Where the dial is turned to, in slots. It glides.
    property real pos: selected
    // How far the dial is swung round while arriving (and back when leaving)
    property real spinIn: 3.2
    // 0 = hidden below the edge, 1 = in place
    property real reveal: 0
    // 0..1 while the whole screen lifts away after an unlock
    property real leave: 0
    // Left alone for a while the screen settles (0 awake, 1 settled): the
    // wash deepens and the clock and dial sit back. wake() undoes it.
    property real calm: 0
    property int calmAfterMs: 30000
    // 1 = tight dome, 0 = the resting dial
    property real fan: 1
    // A slow pulse (0..1) for the rings
    property real breath: 0
    // Sideways offset of the lock disc while it shakes
    property real shakeX: 0
    // Where the scan along the ruler is (-1 = far left, 1 = far right)
    property real scan: -1
    // 0..1 while a ring leaves the lock disc
    property real ring: 0

    // The colour of the moment: the accent, red after a refusal. Success has no
    // colour of its own: it is told in motion (the ruler ripples, the lock
    // turns into a tick, rings leave the disc).
    property color tone: (failed || broken) ? Colors.critical : Colors.accent
    // 0..1 red over the whole ruler while the refusal is on show
    property real flush: (failed || broken) ? 1 : 0
    // 0..1 how far the unlock ripple has run outward from the middle of the ruler
    property real okFill: succeeded ? 1 : 0
    // 0..1 the lock turning into a tick, and the horizon swelling once
    property real unlock: succeeded ? 1 : 0
    // 0..1 how visible the scan is (only while checking)
    property real scanOn: checking ? 1 : 0
    // How far typing has turned the ruler (px). It glides, so each key is a
    // small step and Backspace turns it back.
    property real turn: password.length * 5

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
    // Turning the dial cancels a pending second press
    onSelectedKeyChanged: armed = ""
    onArmedChanged: {
        if (armed !== "") {
            armTimer.restart();
            armAnim.restart();
        } else {
            armTimer.stop();
            armAnim.stop();
            armLeft = 0;
        }
    }
    // A disc that goes away (the music stops) while the dial is on it
    onSlotsChanged: {
        for (let i = 0; i < slots.length; i++) {
            if (slots[i].key === selectedKey)
                return;
        }
        selectedKey = "home";
    }

    Behavior on pos {
        enabled: root.glide

        // The dial glides to the next disc and settles, with no bounce: the
        // same glide as the power menu's underline
        NumberAnimation {
            duration: Style.moveMs
            easing.type: Style.easeMove
        }
    }
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
    Behavior on unlock {
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

    // Only the minute is shown, so the clock wakes once a minute
    SystemClock {
        id: clock

        precision: SystemClock.Minutes
    }

    // ---- Calls ----------------------------------------------------------
    // Any key or pointer movement: wake the screen, and start the wait again
    function wake() {
        calmAnim.stop();
        if (calm > 0)
            wakeAnim.restart();
        calmTimer.restart();
    }

    function reset() {
        calmAnim.stop();
        wakeAnim.stop();
        calm = 0;
        leave = 0;
        calmTimer.restart();
        holdTimer.stop();
        finishTimer.stop();
        openAnim.stop();
        closeAnim.stop();
        pingAnim.stop();
        shake.stop();
        glide = false;
        selectedKey = "home";
        glide = true;
        armed = "";
        password = "";
        failed = false;
        broken = false;
        succeeded = false;
        reveal = 0;
        spinIn = 3.2;
        fan = 1;
        ring = 0;
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
        pingAnim.restart();
    }

    function breakDown() {
        broken = true;
        shake.restart();
        pingAnim.restart();
    }

    function accept() {
        if (succeeded)
            return;
        password = "";
        armed = "";
        selectedKey = "home";
        succeeded = true;
        pingAnim.restart();
        holdTimer.restart();
    }

    // ---- The dial -------------------------------------------------------
    // Turn it one disc left (-1) or right (1). It stops at the ends.
    function step(d) {
        if (succeeded)
            return;
        // Skip an empty detent; stop at the ends
        let i = selected + d;
        while (i >= 0 && i < slots.length && slots[i].spacer === true)
            i += d;
        if (i < 0 || i >= slots.length)
            return;
        selectedKey = slots[i].key;
    }

    function select(key) {
        if (!succeeded)
            selectedKey = key;
    }

    function goHome() {
        selectedKey = "home";
    }

    // Enter, or a click on the disc the dial is on: at home it checks the
    // password, anywhere else it does what the disc says
    function activate() {
        if (succeeded)
            return;
        if (onHome) {
            if (password !== "")
                submitRequested();
        } else {
            press(selected);
        }
    }

    // Press a disc. A destructive one asks twice.
    function press(i) {
        const a = slots[i];
        if (!a || a.home === true || a.spacer === true || a.enabled === false || succeeded)
            return;
        if (a.critical) {
            if (armed === a.key) {
                armed = "";
                activated(a.key);
                a.run();
            } else {
                armed = a.key;
            }
        } else {
            armed = "";
            activated(a.key);
            a.run();
        }
    }

    // ---- Timers ---------------------------------------------------------
    Timer {
        id: armTimer

        interval: root.confirmMs
        onTriggered: root.armed = ""
    }

    // The red line under the name shrinks while the confirmation runs out
    NumberAnimation {
        id: armAnim

        target: root
        property: "armLeft"
        from: 1
        to: 0
        duration: root.confirmMs
        easing.type: Easing.Linear
    }

    // Nobody about: settle slowly. Not while a password is being checked.
    Timer {
        id: calmTimer

        interval: root.calmAfterMs
        onTriggered: {
            if (root.succeeded)
                return;
            if (root.checking) {
                calmTimer.restart();
                return;
            }
            wakeAnim.stop();
            calmAnim.restart();
        }
    }

    NumberAnimation {
        id: calmAnim

        target: root
        property: "calm"
        to: 1
        duration: 2600
        easing.type: Style.easeAmbient
    }

    NumberAnimation {
        id: wakeAnim

        target: root
        property: "calm"
        to: 0
        duration: Style.moveMs
        easing.type: Style.easeMove
    }

    // The unlock has been seen: the dial collapses, and `finished` follows
    // once it has
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
    // Arriving: the discs and the ruler swing in from the left over a tight
    // dome and unfurl into the dial, as every panel in the shell does.
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

    // Leaving, as the power menu and the launcher leave: the dial curls back
    // into the dome and the discs sweep off right. `leave` runs with it, and
    // LockStage lifts the clock and clears the wash and the blur on it, so the
    // desktop behind is the picture you were looking at.
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
        NumberAnimation {
            target: root
            property: "leave"
            to: 1
            duration: Style.moveMs + Style.fadeMs
            easing.type: Style.easeExit
        }
    }

    // Slow breath for the rings
    SequentialAnimation {
        running: root.live
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

    // Checking: a bright patch runs along the ruler and back
    SequentialAnimation {
        running: root.checking && root.live
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

    // A ring leaves the lock disc: on a refusal (red) and on success
    NumberAnimation {
        id: pingAnim

        target: root
        property: "ring"
        from: 0
        to: 1
        duration: Style.sweepMs
        easing.type: Style.easeMove
    }

    // A wrong password: the lock disc shakes
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
}
