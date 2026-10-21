// LockModel.qml
// The state and the motion behind the screen lock (Lock.qml) and the login
// screen (the greeter's Greeter.qml). Both make one of these and keep only
// what is their own: Lock.qml the compositor lock and PAM, Greeter.qml greetd.
// Every screen shows the same model (see LockStage.qml), so they all move as
// one and the two screens can never drift apart.
//
// The owner sets what it knows (who, what to say, which buttons, whether
// something is being checked) and calls:
//   arrive()   start from the dome and unfurl into the dial
//   deny()     the password was refused: the disc shakes, the ruler flushes red
//   breakDown() the thing that checks passwords could not run: the same, but it
//              stays until the next attempt
//   accept()   the password was right: green fills the ruler, the dial curls
//              away, and `finished` is sent about a second later
//   reset()    back to nothing (arrive() does this first)
// and listens to:
//   submitRequested   Enter was pressed with something typed: check it
//   finished          the screen has said yes and collapsed: open now
//
// Nothing here ever opens anything by itself: `finished` follows accept(), and
// accept() is only called by the owner when the password was checked and right.
//
// Time is a timer, not the animation's end, so a hiccup in an animation can
// never leave you stuck behind a lock you already opened.
//
// Each entry of `actions` is a button on the stage:
//   key        a stable name
//   label      what it is called
//   group      buttons of one group sit together, a divider between groups
//   glyph      an icon from Icons.qml (glyphNow(), if present, says it right now)
//   showLabel  true: the label is shown beside the icon (default: icon only)
//   critical   needs a second press: it turns red and says "Press again"
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
    // How long the unlock is on show before the dial collapses
    property int holdMs: 950
    // How long a destructive button waits for its second press
    property int confirmMs: 3000

    signal submitRequested
    signal finished

    // ---- State ----------------------------------------------------------
    // What has been typed. Shared by every screen's field.
    property string password: ""
    // The last attempt was refused
    property bool failed: false
    // The checker could not run at all. The screen stays shut and says so.
    property bool broken: false
    // Yes: the crest runs, the dial collapses, then `finished`
    property bool succeeded: false
    // The button picked with the keyboard (-1 = none), and the one waiting
    // for its second press (-1 = none)
    property int pick: -1
    property int armed: -1

    // 0 = hidden below the edge, 1 = in place
    property real reveal: 0
    // How far the dial is swung round while arriving (and back when leaving)
    property real spinIn: 3.2
    // 1 = tight dome, 0 = the resting dial
    property real fan: 1
    // A slow pulse (0..1) for the disc's ring
    property real breath: 0
    // Sideways offset of the disc while it shakes
    property real shakeX: 0
    // Where the scan along the ruler is (-1 = far left, 1 = far right)
    property real scan: -1
    // 0..1 while a ring leaves the disc
    property real ring: 0

    // The colour of the moment: green once it has worked, red after a refusal
    property color tone: succeeded ? Colors.success : ((failed || broken) ? Colors.critical : Colors.accent)
    // 0..1 red over the whole ruler while the refusal is on show
    property real flush: (failed || broken) ? 1 : 0
    // 0..1 how far the green has filled the ruler outward from the middle
    property real okFill: succeeded ? 1 : 0
    // 0..1 how visible the scan is (only while checking)
    property real scanOn: checking ? 1 : 0
    // How far typing has turned the ruler (px). It glides, so each key is a
    // small step and Backspace turns it back.
    property real turn: password.length * 5

    // ---- What the screen says -------------------------------------------
    readonly property string statusText: succeeded ? okText : (broken ? brokenText : (failed ? "Incorrect password. Try again." : (checking ? "Checking\u2026" : readyText)))
    readonly property bool statusIsError: failed || broken

    // A 12 hour clock: 1 to 12, with AM or PM said separately
    readonly property string hourText: {
        const h = clock.date.getHours() % 12;
        return String(h === 0 ? 12 : h);
    }
    readonly property string periodText: clock.date.getHours() < 12 ? "AM" : "PM"
    readonly property string minuteText: Qt.formatDateTime(clock.date, "mm")
    readonly property string dateText: Qt.formatDateTime(clock.date, "dddd d MMMM")
    readonly property string greeting: {
        const h = clock.date.getHours();
        const word = h < 5 ? "Good night" : (h < 12 ? "Good morning" : (h < 18 ? "Good afternoon" : "Good evening"));
        return user !== "" ? word + ", " + user : word;
    }

    onPasswordChanged: if (password !== "")
        failed = false
    // Moving the pick cancels a pending second press
    onPickChanged: armed = -1
    onArmedChanged: {
        if (armed >= 0)
            armTimer.restart();
        else
            armTimer.stop();
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
    function reset() {
        holdTimer.stop();
        finishTimer.stop();
        armTimer.stop();
        openAnim.stop();
        closeAnim.stop();
        password = "";
        failed = false;
        broken = false;
        succeeded = false;
        pick = -1;
        armed = -1;
        reveal = 0;
        spinIn = 3.2;
        fan = 1;
        ring = 0;
        shakeX = 0;
    }

    function arrive() {
        reset();
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
        pick = -1;
        armed = -1;
        succeeded = true;
        pingAnim.restart();
        holdTimer.restart();
    }

    // ---- Buttons --------------------------------------------------------
    // Press one. A destructive one asks twice.
    function press(i) {
        const a = actions[i];
        if (!a || a.enabled === false || succeeded)
            return;
        if (a.critical) {
            if (armed === i) {
                armed = -1;
                a.run();
            } else {
                armed = i;
            }
        } else {
            armed = -1;
            a.run();
        }
    }

    function pressPicked() {
        if (pick >= 0)
            press(pick);
    }

    // Tab and Shift+Tab: through the buttons, then back to none
    function movePick(d) {
        const n = actions.length;
        if (n === 0)
            return;
        pick = ((pick + 1 + d) % (n + 1) + (n + 1)) % (n + 1) - 1;
    }

    // ---- Timers ---------------------------------------------------------
    Timer {
        id: armTimer

        interval: root.confirmMs
        onTriggered: root.armed = -1
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
    // Arriving: the disc and the ruler swing in from the left over a tight
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

    // Leaving: the dial curls back into the dome and sweeps off right
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

    // Slow breath for the ring around the disc
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

    // A ring leaves the disc: on a refusal (red) and on success (green)
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
}
