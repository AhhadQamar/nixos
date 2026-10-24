// LockStage.qml
// What the lock and the login screen show on one screen. Lock.qml and
// Greeter.qml make one of these per screen and hand it the same LockModel, so
// every screen moves as one.
//
// The screen is the screenshot tool's frame, closed into a circle. Your
// wallpaper, blurred and washed with the shell's dim, the time in the middle,
// and round it what the screenshot tool draws round a selection:
//   an outer ruler ring, fine ticks every 10px and a taller one every 50, the
//     ones by the index at the top rising and turning accent, as the ticks
//     rise beside the pointer there, with the same 2px accent marker;
//   an inner ring, the small dial of ticks the tool turns at the middle of a
//     region (36 ticks, four of them accent), turning the other way;
//   a spark of accent with a trail that circles the outer ring while the lock
//     is waiting, and a dimmer one opposite it;
//   corner brackets that close in like an autofocus when the password is
//     right, with a ring leaving the dial, and the palette's spectrum running
//     round the ring while you work it and draining to the accent when you
//     let go.
// Behind it, the feathered shade and the soft light the launcher uses.
//
// There is no password box. What you type lights the outer ring from the
// index, a step for every character, and turns the two rings a few degrees
// against each other. While the password is checked a glow runs round both
// rings. A wrong one flushes them red and jolts the dial; a right one locks on,
// and then the rings turn away as the dial does elsewhere in the shell, while
// the clock lifts and the wallpaper comes into focus.
//
// Keys (an invisible field keeps the keyboard, so typing is never affected):
//   type                the password
//   Enter               check it
//   Esc                 clear what you typed
//   Tab, Right, Left    turn the rings a little, for the feel of it
// Mouse: the wheel (or a touchpad swipe, either axis) turns them too.
//
// It reads and writes the LockModel it is given (see LockModel.qml).

import QtQuick
import QtQuick.Effects
import QtQuick.Shapes

Item {
    id: scene

    // The model every screen shows (LockModel.qml)
    required property var lock

    // ---- Settings -------------------------------------------------------
    // The lock: its middle, the radius of the outer ruler, and of the inner
    // dial a little inside it. What is left inside is for the time.
    readonly property real ringX: width / 2
    readonly property real ringY: Math.round(height * 0.5)
    readonly property real ringR: Math.round(Math.min(height * 0.3, width * 0.28))
    readonly property real innerR: ringR - 36
    readonly property real hubR: innerR - 14
    // The outer ruler's ticks sit 10px apart and every fifth is a major, as on
    // the screenshot frame; the inner dial has 36, every ninth in the accent
    readonly property int outerCount: Math.round(twoPi * ringR / 10 / 5) * 5
    readonly property int innerCount: 36
    readonly property real twoPi: Math.PI * 2
    readonly property int contentW: Math.min(780, Math.round(width * 0.9))
    // The background colour with a breath of the accent, as Dim.qml has it
    readonly property color wash: Qt.tint(Colors.background, Qt.alpha(Colors.accent, 0.08))
    // The shell's glass, with a little of the wash under it so a disc or the
    // pill still reads over a bright wallpaper
    readonly property color glass: Qt.tint(Style.card, Qt.alpha(wash, 0.35))
    readonly property color glassDeep: Qt.tint(Style.surface, Qt.alpha(wash, 0.4))
    // Secondary text: the palette's muted, lifted a little toward the
    // foreground so it holds on any wallpaper
    readonly property color softText: Qt.tint(Colors.muted, Qt.alpha(Colors.foreground, 0.4))
    // The disc under the pointer (-1 = none): its name is read out
    property int peek: -1
    // Sideways nudge of the name when the dial turns
    property real readShift: 0
    property int lastShown: 0

    // ---- The model, under shorter names -----------------------------------
    readonly property real reveal: lock.reveal
    // 0..1 while the whole screen lifts away after an unlock
    readonly property real leave: lock.leave
    // The arrival, which stays complete while the screen leaves, so the things
    // that settle in on arrival (the wallpaper's focus, the clock's rise) are
    // not undone by the dial's own exit
    readonly property real settle: leave > 0.0001 ? 1 : reveal
    readonly property real fan: lock.fan
    readonly property real breath: lock.breath
    readonly property bool succeeded: lock.succeeded
    readonly property bool checking: lock.checking
    readonly property color tone: lock.tone
    readonly property real viewPos: lock.pos + lock.spinIn

    // The colour of the disc the dial is on: the moment's for the lock, red
    // for a destructive one, the accent for the rest
    property color selTone: lock.onHome ? lock.tone : ((lock.current && lock.current.critical === true) ? Colors.critical : Colors.accent)

    Behavior on selTone {
        ColorAnimation {
            duration: Style.baseMs
        }
    }

    // ---- What the readout says --------------------------------------------
    readonly property int shown: peek >= 0 && peek < lock.slots.length ? peek : lock.selected
    readonly property var shownInfo: lock.slots[shown] || ({})
    readonly property bool shownHome: shownInfo.home === true
    readonly property bool shownArmed: !shownHome && lock.armed === shownInfo.key
    readonly property string shownName: shownHome ? lock.greeting : (shownInfo.labelNow ? shownInfo.labelNow() : (shownInfo.label || ""))
    readonly property string shownLine: shownHome ? lock.statusText : (shownArmed ? "Press again to confirm" : (shownInfo.hintNow ? shownInfo.hintNow() : (shownInfo.hint || "")))
    readonly property color shownLineColor: shownHome ? (lock.statusIsError ? Colors.critical : (succeeded ? Colors.foreground : softText)) : (shownArmed ? Colors.critical : softText)

    onShownChanged: {
        readShift = shown > lastShown ? 16 : -16;
        lastShown = shown;
        pop.restart();
    }

    // ---- The two dials ----------------------------------------------------
    // One click for every character you typed. The password is emptied the
    // moment it is sent, so the dials keep the count they had until the answer
    // is in.
    property int held: 0
    readonly property int dotCount: (lock.checking || lock.succeeded) ? held : lock.password.length
    // The marker at the index breathes while the lock is waiting for you
    readonly property real caretOn: (!checking && !succeeded && reveal > 0.8) ? 0.45 + 0.55 * breath : 0
    // How far round what you typed reaches, from the index (radians): ten
    // degrees a character, easing to each new place so fast typing sweeps
    readonly property real litStep: twoPi / 36
    readonly property real litTo: Math.min(dotCount, 36) * litStep
    property real litSmooth: litTo

    Behavior on litSmooth {
        NumberAnimation {
            duration: Style.moveMs
            easing.type: Style.easeMove
        }
    }

    // The spectrum, as the screenshot tool has it: while you work the dial the
    // palette's colours run round the ring, and drain to the accent when you
    // let go. It wakes fast and drains slowly.
    readonly property real heatTarget: (dotCount > 0 || checking) ? 1 : 0
    property real heat: heatTarget
    property real chase: 0

    Behavior on heat {
        NumberAnimation {
            duration: scene.heatTarget > 0 ? Style.fadeMs : Style.ambientMs * 2
            easing.type: Style.easeMove
        }
    }

    NumberAnimation on chase {
        from: 0
        to: 1
        duration: 5000
        loops: Animation.Infinite
        running: scene.heat > 0.01 && scene.reveal > 0.01
    }

    // A colour round the ring of the palette (color1 to color6 and back to
    // color1) at t, 0..1: the same ramp the launcher washes its dial with
    function ringColor(t) {
        const ramp = [Colors.color1, Colors.color2, Colors.color3, Colors.color4, Colors.color5, Colors.color6, Colors.color1];
        const n = ramp.length - 1;
        const x = (((t % 1) + 1) % 1) * n;
        const i = Math.min(n - 1, Math.floor(x));
        return Qt.tint(ramp[i], Qt.alpha(ramp[i + 1], x - i));
    }

    // The spark: a bead of accent with a trail that circles the outer ring
    // while the lock waits for you, and a dimmer one opposite. It rests while
    // you type and while the password is checked.
    readonly property bool sparkOn: dotCount === 0 && !checking && !succeeded
    property real spark: sparkOn ? 1 : 0
    // Distance in pixels the spark has run round the ring
    property real orbit: 0

    Behavior on spark {
        NumberAnimation {
            duration: Style.baseMs
        }
    }

    NumberAnimation on orbit {
        from: 0
        to: 100000
        duration: 300000
        loops: Animation.Infinite
        running: scene.reveal > 0.05
        paused: !scene.sparkOn
    }

    // The dial locks on when the password is right: the brackets start outside
    // and close in, a little past home, and settle, and a ring leaves. 1 at the
    // start, running to 0.
    property real snap: 0

    onSucceededChanged: if (succeeded)
        snapAnim.restart()

    NumberAnimation {
        id: snapAnim

        target: scene
        property: "snap"
        from: 1
        to: 0
        duration: Style.moveMs + Style.fadeMs
        easing.type: Style.easePop
    }

    // The two rings turn opposite ways, a few degrees: the outer one clockwise
    // for every character, the inner one back, a little further. Each settles with a
    // small overshoot, like a detent. The wheel and the arrow keys turn them
    // for the feel of it (`extra`).
    property real extra: 0
    readonly property real rawOuter: Math.min(dotCount, 40) * 3 + extra
    readonly property real rawInner: -(Math.min(dotCount, 40) * 4.5 + extra * 1.5)
    // Once it has worked they come to rest at nought under the index mark
    readonly property real outerTarget: succeeded ? Math.round(rawOuter / 360) * 360 : rawOuter
    readonly property real innerTarget: succeeded ? Math.round(rawInner / 360) * 360 : rawInner
    property real outerBase: outerTarget
    property real innerBase: innerTarget

    Behavior on outerBase {
        NumberAnimation {
            duration: scene.succeeded ? 520 : 260
            easing.type: Easing.OutBack
            easing.overshoot: 1.8
        }
    }

    Behavior on innerBase {
        NumberAnimation {
            duration: scene.succeeded ? 520 : 260
            easing.type: Easing.OutBack
            easing.overshoot: 1.8
        }
    }

    // While the password is checked the two sway against each other, a few
    // degrees either way
    property real whirl: 0

    SequentialAnimation on whirl {
        loops: Animation.Infinite
        running: scene.checking

        NumberAnimation {
            to: 1
            duration: 520
            easing.type: Easing.InOutSine
        }
        NumberAnimation {
            to: -1
            duration: 520
            easing.type: Easing.InOutSine
        }
    }

    // What each dial shows: its click, the whirl, and the turn as it arrives
    readonly property real outerA: outerBase + whirl * 7 * lock.scanOn + lock.spinIn * 4
    readonly property real innerA: innerBase - whirl * 10 * lock.scanOn - lock.spinIn * 6

    function turnBy(dir) {
        extra += dir * 3;
    }

    // ---- Helpers --------------------------------------------------------
    function clamp(v, a, b) {
        return Math.max(a, Math.min(b, v));
    }

    // A smooth 0..1 over part of the unlock's release (in `leave` units), so
    // each thing goes in its own time: the dial first, then the clock, then
    // the wash and the blur
    function lv(from, to) {
        return clamp((leave - from) / (to - from), 0, 1);
    }

    // Ease-out with a small overshoot for the arrival of each disc (0..1 in,
    // about 1.04 at the peak): the shell's `pop`, kept gentle.
    function backOut(t) {
        const c1 = 0.8;
        const u = t - 1;
        return 1 + (c1 + 1) * u * u * u + c1 * u * u;
    }

    // Staggered arrival: 0 until `from`, 1 at `to` (in reveal units).
    function stage_(from, to) {
        return clamp((settle - from) / (to - from), 0, 1);
    }

    // `base` washed with one of the palette's colours, chosen by screen
    // position x (colour1 on the left through colour6 on the right). The wash
    // is `fan` strong, so it only shows while the dial is arriving or leaving.
    function spectral(base, x, a) {
        const ramp = [Colors.color1, Colors.color2, Colors.color3, Colors.color4, Colors.color5, Colors.color6];
        const t = (clamp((x - width / 2) / (width * 0.34), -1, 1) * 0.5 + 0.5) * (ramp.length - 1);
        const i = Math.min(ramp.length - 2, Math.floor(t));
        const c = Qt.tint(ramp[i], Qt.alpha(ramp[i + 1], t - i));
        return Qt.alpha(Qt.tint(base, Qt.alpha(c, 0.9 * fan)), a);
    }

    // The password goes into a field nobody sees: it keeps the keyboard, and
    // the ring is what shows how much you have typed
    TextInput {
        id: pw

        width: 1
        height: 1
        opacity: 0
        focus: true
        echoMode: TextInput.Password
        inputMethodHints: Qt.ImhSensitiveData | Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase
        // Read-only rather than disabled, so it keeps the focus
        readOnly: scene.checking || scene.succeeded

        // One password for every screen: this field writes it, and shows it
        // again when the owner empties it
        onTextChanged: {
            if (scene.lock.password !== text)
                scene.lock.password = text;
        }
        Keys.onPressed: event => scene.handleKey(event)

        Connections {
            target: scene.lock

            function onPasswordChanged() {
                if (pw.text !== scene.lock.password)
                    pw.text = scene.lock.password;
                if (scene.lock.password.length > 0)
                    scene.held = scene.lock.password.length;
            }
        }
    }

    // The keys the password field leaves to the stage
    function handleKey(event) {
        scene.lock.wake();
        switch (event.key) {
        case Qt.Key_Return:
        case Qt.Key_Enter:
            event.accepted = true;
            lock.activate();
            return;
        case Qt.Key_Tab:
        case Qt.Key_Right:
            event.accepted = true;
            scene.turnBy(1);
            return;
        case Qt.Key_Backtab:
        case Qt.Key_Left:
            event.accepted = true;
            scene.turnBy(-1);
            return;
        case Qt.Key_Escape:
            event.accepted = true;
            if (lock.password !== "")
                lock.password = "";
            return;
        }
    }

    // Text that stays readable over any wallpaper: the shell font with a thin
    // outline in the background colour
    component Soft: Txt {
        style: Text.Outline
        styleColor: Qt.alpha(Colors.background, 0.82)
    }

    // Focus set before the window is shown can be lost; ask again once it is
    onVisibleChanged: if (visible)
        Qt.callLater(pw.forceActiveFocus)
    Component.onCompleted: Qt.callLater(pw.forceActiveFocus)

    ParallelAnimation {
        id: pop

        NumberAnimation {
            target: readInner
            property: "opacity"
            from: 0.25
            to: 1
            duration: Style.baseMs
            easing.type: Style.easeMove
        }
        NumberAnimation {
            target: readInner
            property: "scale"
            from: 0.94
            to: 1
            duration: Style.baseMs
            easing.type: Style.easeMove
        }
        NumberAnimation {
            target: scene
            property: "readShift"
            to: 0
            duration: Style.moveMs
            easing.type: Style.easeMove
        }
    }

    // ---- Backdrop: the wallpaper, blurred ---------------------------------
    // A blurred picture needs no detail, so the image is read and blurred at a
    // quarter of the screen size and scaled up: the same look for a sixteenth
    // of the work, which matters on a laptop's integrated graphics.
    Item {
        id: backdrop

        // `drift` is a very slow push in and out, so the wallpaper is never
        // quite still
        property real drift: 0

        width: Math.round(scene.width / 4)
        height: Math.round(scene.height / 4)
        scale: 4 * (1 + (0.02 + 0.03 * drift) * (1 - scene.lv(0, 0.9))) * (1.07 - 0.07 * scene.clamp(scene.settle * 1.2, 0, 1))
        // Scaled about the middle, so it breathes rather than slides
        transformOrigin: Item.Center
        x: (scene.width - width) / 2
        y: (scene.height - height) / 2
        // Fades in once it has loaded; until then the window's own
        // background colour shows
        opacity: wall.status === Image.Ready ? 1 : 0
        layer.enabled: true
        layer.effect: MultiEffect {
            blurEnabled: true
            // Comes into focus as the screen arrives; on an unlock it goes
            // fully sharp, as the desktop behind it will be
            blur: (0.35 + 0.65 * scene.clamp(scene.settle * 1.2, 0, 1)) * (1 - scene.lv(0, 0.9))
            blurMax: 12
        }

        Behavior on opacity {
            NumberAnimation {
                duration: Style.baseMs
            }
        }

        SequentialAnimation on drift {
            running: scene.lock.live && scene.visible
            loops: Animation.Infinite

            NumberAnimation {
                to: 1
                duration: 22000
                easing.type: Style.easeAmbient
            }
            NumberAnimation {
                to: 0
                duration: 22000
                easing.type: Style.easeAmbient
            }
        }

        Image {
            id: wall

            anchors.fill: parent
            source: scene.lock.wallpaper !== "" ? "file://" + scene.lock.wallpaper : ""
            asynchronous: true
            fillMode: Image.PreserveAspectCrop
            sourceSize: Qt.size(backdrop.width, backdrop.height)
        }
    }

    // The shell's dim over it: light at the top, where the time sits and the
    // wallpaper can show, darker toward the foot, where the dial needs calm
    Rectangle {
        anchors.fill: parent
        // Clears as the screen lifts away
        opacity: 1 - scene.lv(0.15, 1)

        gradient: Gradient {
            GradientStop {
                position: 0
                color: Qt.alpha(scene.wash, 0.34)
            }
            GradientStop {
                position: 0.55
                color: Qt.alpha(scene.wash, 0.52)
            }
            GradientStop {
                position: 1
                color: Qt.alpha(scene.wash, 0.82)
            }
        }
    }

    // Left alone, the wash deepens a little. Any key or movement wakes it.
    Rectangle {
        anchors.fill: parent
        color: Qt.alpha(scene.wash, 0.32 * scene.lock.calm * (1 - scene.lv(0.15, 1)))
        visible: scene.lock.calm > 0.002
    }

    // A soft vignette: the corners fall away a little so the eye settles on
    // the time and the dial, as in a lens. Same feathered radial as
    // StageShade, just turned inside out.
    Shape {
        id: vignette

        anchors.fill: parent
        opacity: scene.clamp(scene.settle * 1.5, 0, 1) * (1 - scene.lv(0.15, 1))
        layer.enabled: true
        layer.samples: 4

        ShapePath {
            strokeColor: "transparent"
            startX: 0
            startY: 0

            fillGradient: RadialGradient {
                centerX: vignette.width / 2
                centerY: scene.ringY
                centerRadius: Math.sqrt(vignette.width * vignette.width + vignette.height * vignette.height) * 0.62
                focalX: vignette.width / 2
                focalY: scene.ringY

                GradientStop {
                    position: 0.55
                    color: Qt.alpha(Colors.background, 0)
                }
                GradientStop {
                    position: 1
                    color: Qt.alpha(Colors.background, 0.5)
                }
            }

            PathLine {
                x: vignette.width
                y: 0
            }
            PathLine {
                x: vignette.width
                y: vignette.height
            }
            PathLine {
                x: 0
                y: vignette.height
            }
            PathLine {
                x: 0
                y: 0
            }
        }
    }

    // Pressing anywhere gives the keyboard back to the password field; the
    // wheel turns the dial
    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        onPositionChanged: scene.lock.wake()
        onPressed: pw.forceActiveFocus()
        onWheel: wheel => {
            scene.lock.wake();
            // A mouse notch is 120; a touchpad sends many small ones, so they
            // are added up. Either axis turns it, and after a step it rests a
            // moment, so a flick does not spin it through every disc.
            const d = Math.abs(wheel.angleDelta.x) > Math.abs(wheel.angleDelta.y) ? wheel.angleDelta.x : wheel.angleDelta.y;
            wheelIdle.restart();
            if (wheelRest.running)
                return;
            scene.wheelAcc += d;
            if (Math.abs(scene.wheelAcc) >= 120) {
                scene.turnBy(scene.wheelAcc < 0 ? 1 : -1);
                scene.wheelAcc = 0;
                wheelRest.restart();
            }
        }
    }

    // The wheel's running total, forgotten once the scrolling stops
    property real wheelAcc: 0

    Timer {
        id: wheelIdle

        interval: 240
        onTriggered: scene.wheelAcc = 0
    }

    Timer {
        id: wheelRest

        interval: 170
    }

    // ---- The hero: the time -----------------------------------------------
    // Big enough to read from across the room. The colon breathes with the
    // rings and takes the colour of the moment. Each digit group slides up
    // into place when it changes. Under it, the date between two hairlines,
    // and nothing else.
    Item {
        id: hero

        // A read-out, so the size is a one-off (it follows the screen)
        readonly property int size: Math.round(Math.min(scene.height * 0.17, scene.hubR * 0.62))

        // Above the lock: the stage is drawn after it and would cover it
        z: 5
        anchors.horizontalCenter: parent.horizontalCenter
        y: Math.round(scene.ringY - hero.height * 0.62)
        // A layer is clipped to the item, so it is as wide as its widest line
        width: Math.max(timeRow.implicitWidth, dateRow.width)
        height: timeRow.implicitHeight + dateRow.height
        // Clicks pass through to the stage
        enabled: false
        // One soft shadow under the whole group reads far finer on a big
        // clock than an outline on every glyph (it is drawn once, and again
        // only when the minute changes)
        layer.enabled: true
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: Qt.alpha(Colors.background, 0.55)
            shadowBlur: 0.9
            shadowVerticalOffset: 6
            shadowHorizontalOffset: 0
        }
        opacity: scene.stage_(0.2, 0.75) * (1 - 0.2 * scene.lock.calm) * (1 - scene.lv(0.1, 0.7))
        // It rises with the stage, and lifts away a little once you are in
        transform: Translate {
            x: 0
            y: (1 - scene.stage_(0.2, 0.75)) * 24 - 44 * scene.lv(0.1, 0.8)
        }

        Row {
            id: timeRow

            anchors.horizontalCenter: parent.horizontalCenter

            Txt {
                id: hourTxt

                text: scene.lock.hourText
                color: Colors.foreground
                font.pixelSize: hero.size
                font.weight: Font.Light
                font.letterSpacing: -Math.round(hero.size * 0.035)
                transform: Translate {
                    id: hourSlide
                }
            }

            Txt {
                text: ":"
                color: scene.tone
                opacity: 0.35 + 0.65 * scene.breath
                font.pixelSize: hero.size
                font.weight: Font.Light
                // Lifted to the optical middle of the digits
                transform: Translate {
                    y: -Math.round(hero.size * 0.05)
                }
            }

            Txt {
                id: minTxt

                text: scene.lock.minuteText
                color: Colors.foreground
                font.pixelSize: hero.size
                font.weight: Font.Light
                font.letterSpacing: -Math.round(hero.size * 0.035)
                transform: Translate {
                    id: minSlide
                }
            }

            // AM or PM, small, on the line of the digits
            Item {
                width: period.implicitWidth + 12
                height: 1

                Txt {
                    id: period

                    x: 12
                    y: Math.round(hero.size * 1.0 - implicitHeight * 0.82)
                    text: scene.lock.periodText
                    color: Qt.alpha(Colors.foreground, 0.78)
                    font.pixelSize: Math.round(hero.size * 0.2)
                    font.letterSpacing: 2
                }
            }
        }

        // The minute (and now and then the hour) slides up into place
        Connections {
            target: scene.lock

            function onMinuteTextChanged() {
                minAnim.restart();
            }

            function onHourTextChanged() {
                hourAnim.restart();
            }
        }

        ParallelAnimation {
            id: minAnim

            NumberAnimation {
                target: minSlide
                property: "y"
                from: 16
                to: 0
                duration: Style.moveMs
                easing.type: Style.easeMove
            }
            NumberAnimation {
                target: minTxt
                property: "opacity"
                from: 0.2
                to: 1
                duration: Style.moveMs
                easing.type: Style.easeMove
            }
        }

        ParallelAnimation {
            id: hourAnim

            NumberAnimation {
                target: hourSlide
                property: "y"
                from: 16
                to: 0
                duration: Style.moveMs
                easing.type: Style.easeMove
            }
            NumberAnimation {
                target: hourTxt
                property: "opacity"
                from: 0.2
                to: 1
                duration: Style.moveMs
                easing.type: Style.easeMove
            }
        }

        // The date between two hairlines that fade out toward the ends
        Row {
            id: dateRow

            anchors.top: timeRow.bottom
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Style.spaceXl
            height: dateLine.implicitHeight
            opacity: scene.stage_(0.3, 0.85)

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: 56
                height: 1
                gradient: Gradient {
                    orientation: Gradient.Horizontal

                    GradientStop {
                        position: 0
                        color: Qt.alpha(Colors.foreground, 0)
                    }
                    GradientStop {
                        position: 1
                        color: Qt.alpha(Colors.foreground, 0.4)
                    }
                }
            }

            Txt {
                id: dateLine

                anchors.verticalCenter: parent.verticalCenter
                text: scene.lock.dateText
                color: Qt.alpha(Colors.foreground, 0.85)
                font.pixelSize: Math.round(hero.size * 0.13)
                font.letterSpacing: 4 + 8 * (1 - scene.stage_(0.3, 0.95))
                font.capitalization: Font.AllUppercase
            }

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: 56
                height: 1
                gradient: Gradient {
                    orientation: Gradient.Horizontal

                    GradientStop {
                        position: 0
                        color: Qt.alpha(Colors.foreground, 0.4)
                    }
                    GradientStop {
                        position: 1
                        color: Qt.alpha(Colors.foreground, 0)
                    }
                }
            }
        }
    }

    // What this screen is, small, above the clock
    Soft {
        id: modeLine

        z: 5
        x: scene.ringX - width / 2
        y: hero.y - 34
        width: Math.round(scene.hubR * 1.3)
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
        text: scene.lock.modeLine
        color: scene.succeeded ? Colors.foreground : Qt.alpha(Colors.foreground, 0.78)
        font.pixelSize: Style.fontSm
        font.letterSpacing: 1.4
        font.capitalization: Font.AllUppercase
        // Clicks pass through to the stage
        enabled: false
        opacity: scene.stage_(0.1, 0.6) * (1 - scene.lv(0.1, 0.7))
        transform: Translate {
            y: (1 - scene.stage_(0.1, 0.6)) * 14 - 44 * scene.lv(0.1, 0.8)
        }
    }

    // ---- The lock ---------------------------------------------------------
    Item {
        id: stage

        anchors.fill: parent
        opacity: Math.min(1, scene.reveal * 3) * (1 - 0.3 * scene.lock.calm)
        // It settles in as it arrives, and a wrong password jolts the whole
        // lock
        transform: [
            Scale {
                origin.x: scene.ringX
                origin.y: scene.ringY
                xScale: 0.94 + 0.06 * scene.clamp(scene.reveal, 0, 1)
                yScale: 0.94 + 0.06 * scene.clamp(scene.reveal, 0, 1)
            },
            Translate {
                x: scene.lock.shakeX
            }
        ]

        // A soft dark pool behind the lock, no visible edge, so the dials and
        // the time read on any wallpaper
        Shape {
            id: shade

            readonly property real r: scene.ringR * 1.35

            x: scene.ringX - r
            y: scene.ringY - r
            width: r * 2
            height: r * 2
            layer.enabled: true
            layer.samples: 4

            ShapePath {
                strokeColor: "transparent"
                startX: 0
                startY: shade.r

                fillGradient: RadialGradient {
                    centerX: shade.r
                    centerY: shade.r
                    centerRadius: shade.r
                    focalX: shade.r
                    focalY: shade.r

                    GradientStop {
                        position: 0
                        color: Qt.alpha(scene.wash, 0.42)
                    }
                    GradientStop {
                        position: 0.7
                        color: Qt.alpha(scene.wash, 0.3)
                    }
                    GradientStop {
                        position: 1
                        color: Qt.alpha(scene.wash, 0)
                    }
                }

                PathArc {
                    x: shade.r * 2
                    y: shade.r
                    radiusX: shade.r
                    radiusY: shade.r
                }
                PathArc {
                    x: 0
                    y: shade.r
                    radiusX: shade.r
                    radiusY: shade.r
                }
            }
        }

        // Light behind the time, in the colour of the moment: the accent, red
        // after a refusal, swelling once when it has worked. The same soft
        // light the launcher puts on its horizon.
        Shape {
            id: glow

            readonly property real r: scene.ringR * 0.95

            x: scene.ringX - r
            y: scene.ringY - r
            width: r * 2
            height: r * 2
            layer.enabled: true
            layer.samples: 4

            ShapePath {
                strokeColor: "transparent"
                startX: 0
                startY: glow.r

                fillGradient: RadialGradient {
                    centerX: glow.r
                    centerY: glow.r
                    centerRadius: glow.r
                    focalX: glow.r
                    focalY: glow.r

                    GradientStop {
                        position: 0
                        color: Qt.alpha(scene.tone, 0.1 + 0.2 * Math.sin(Math.PI * scene.lock.unlock))
                    }
                    GradientStop {
                        position: 0.55
                        color: Qt.alpha(scene.tone, 0.04 + 0.1 * Math.sin(Math.PI * scene.lock.unlock))
                    }
                    GradientStop {
                        position: 1
                        color: Qt.alpha(scene.tone, 0)
                    }
                }

                PathArc {
                    x: glow.r * 2
                    y: glow.r
                    radiusX: glow.r
                    radiusY: glow.r
                }
                PathArc {
                    x: 0
                    y: glow.r
                    radiusX: glow.r
                    radiusY: glow.r
                }
            }
        }

        // ---- The outer ruler: fine ticks, a taller one every fifth, as on the
        // screenshot frame. The ticks by the index rise and turn accent. What
        // you typed lights it from the index (in the spectrum while you work,
        // draining to the accent), the rest shows the state (a glow running
        // round while checking, red after a refusal, a ripple on success).
        Repeater {
            model: scene.outerCount

            delegate: Rectangle {
                id: otick

                required property int index

                // Where this tick is, clockwise from the top (radians, wrapped
                // to plus or minus a half turn): 0 is the index
                readonly property real d: ((((index * 360 / scene.outerCount + scene.outerA) * Math.PI / 180) + Math.PI) % scene.twoPi + scene.twoPi) % scene.twoPi - Math.PI
                readonly property real r: scene.ringR
                readonly property bool major: index % 5 === 0
                // Rises by the index, and where the glow is
                readonly property real near: Math.max(0, 1 - Math.abs(d) * r / 80)
                readonly property real wave: Math.max(0, 1 - Math.abs(((d - scene.lock.scan * Math.PI + Math.PI) % scene.twoPi + scene.twoPi) % scene.twoPi - Math.PI) * r / 80) * scene.lock.scanOn
                readonly property real hot: Math.max(near, wave)
                // The unlock ripple, from the index round both ways
                readonly property real front: scene.lock.okFill * 1.35
                readonly property real dist: Math.abs(d) / Math.PI
                readonly property real okMix: scene.clamp((front - dist) / 0.3, 0, 1)
                readonly property real crest: Math.max(0, 1 - Math.abs(front - dist - 0.06) / 0.14) * (scene.lock.okFill > 0.001 ? 1 : 0)
                // What you typed, clockwise from the index, and the marker at
                // the next place
                readonly property real phi: (d + scene.twoPi) % scene.twoPi
                readonly property real typed: scene.dotCount > 0 ? scene.clamp((scene.litSmooth - phi) / 0.05 + 0.5, 0, 1) : 0
                readonly property real care: Math.max(0, 1 - Math.abs(phi - scene.litSmooth) / 0.08) * scene.caretOn
                readonly property real lit: Math.max(0.8 * hot, 0.9 * typed, crest, 0.8 * okMix, 0.9 * care)
                // The accent, with its slice of the spectrum while you work
                readonly property color tone: Qt.tint(Colors.accent, Qt.alpha(scene.ringColor(scene.chase + phi / scene.twoPi), 0.9 * scene.heat))
                readonly property real rest: major ? 0.5 : 0.3
                readonly property color hue: Qt.tint(Qt.tint(Colors.foreground, Qt.alpha(tone, lit)), Qt.alpha(Colors.critical, 0.85 * scene.lock.flush))

                x: scene.ringX + r * Math.sin(d) - width / 2
                y: scene.ringY - r * Math.cos(d)
                width: 1.5
                height: (major ? 9 : 5) + 6 * hot + 3 * okMix + 8 * crest + 4 * typed + 4 * care
                radius: 0.75
                antialiasing: true
                // Points in at the middle
                transformOrigin: Item.Top
                rotation: d * 180 / Math.PI
                color: scene.spectral(hue, x, rest + (1 - rest) * Math.max(lit, 0.7 * scene.lock.flush))
                opacity: scene.clamp(scene.reveal * 2 - dist * 0.9, 0, 1)
            }
        }

        // ---- The inner dial: the small dial of ticks the screenshot tool
        // turns at the middle of a region. 36 ticks, every ninth in the accent.
        // It turns the other way. ---------------------------------------------
        Repeater {
            model: scene.innerCount

            delegate: Rectangle {
                id: itick

                required property int index

                readonly property real d: ((((index * 360 / scene.innerCount + scene.innerA) * Math.PI / 180) + Math.PI) % scene.twoPi + scene.twoPi) % scene.twoPi - Math.PI
                readonly property real r: scene.innerR
                readonly property bool major: index % 9 === 0
                readonly property real wave: Math.max(0, 1 - Math.abs(((d + scene.lock.scan * Math.PI + Math.PI) % scene.twoPi + scene.twoPi) % scene.twoPi - Math.PI) * r / 60) * scene.lock.scanOn
                readonly property real front: scene.lock.okFill * 1.35
                readonly property real dist: Math.abs(d) / Math.PI
                readonly property real crest: Math.max(0, 1 - Math.abs(front - dist - 0.06) / 0.14) * (scene.lock.okFill > 0.001 ? 1 : 0)
                readonly property real okMix: scene.clamp((front - dist) / 0.3, 0, 1)
                // The accent ticks take their slice of the spectrum while you work
                readonly property color tone: Qt.tint(Colors.accent, Qt.alpha(scene.ringColor(scene.chase + (d + Math.PI) / scene.twoPi), 0.9 * scene.heat))
                readonly property real lit: Math.max(wave, crest, okMix)

                x: scene.ringX + r * Math.sin(d) - width / 2
                y: scene.ringY - r * Math.cos(d)
                width: 1.5
                height: (major ? 9 : 4) + 4 * wave + 5 * crest
                radius: 0.75
                antialiasing: true
                transformOrigin: Item.Top
                rotation: d * 180 / Math.PI
                color: Qt.tint(Qt.tint(major ? tone : Qt.alpha(Colors.foreground, 0.55), Qt.alpha(Colors.accent, lit)), Qt.alpha(Colors.critical, 0.85 * scene.lock.flush))
                opacity: scene.clamp(scene.reveal * 2 - dist * 0.9, 0, 1)
            }
        }

        // ---- The spark: a bead of accent with a trail that circles the outer
        // ring while the lock waits, and a dimmer one opposite --------------
        Repeater {
            model: 2

            delegate: Item {
                id: comet

                required property int index

                Repeater {
                    model: 9

                    delegate: Rectangle {
                        id: bead

                        required property int index

                        // The point this far round the ring, clockwise from the top
                        readonly property real at: (scene.orbit + comet.index * scene.twoPi * scene.ringR / 2 - index * 9) / scene.ringR

                        width: 6 - index * 0.5
                        height: width
                        radius: width / 2
                        x: scene.ringX + (scene.ringR + 10) * Math.sin(at) - width / 2
                        y: scene.ringY - (scene.ringR + 10) * Math.cos(at) - height / 2
                        color: Colors.accent
                        opacity: scene.spark * (1 - index / 9) * (comet.index === 0 ? 0.9 : 0.4) * scene.clamp(scene.reveal * 2, 0, 1)
                        visible: opacity > 0.02
                    }
                }
            }
        }

        // ---- The brackets: four of them just outside the ring, as on the
        // frame. They close in like an autofocus when it locks on, a little
        // past home, then settle. They take their slice of the spectrum
        // while you work, red after a refusal. ------------------------------
        Repeater {
            model: 4

            delegate: Shape {
                id: bracket

                required property int index

                // Where this bracket is round the ring (the diagonals)
                readonly property real mid: 45 + index * 90
                readonly property real rb: scene.ringR + 16 + 14 * scene.snap
                readonly property real half: 14

                x: scene.ringX - rb - 4
                y: scene.ringY - rb - 4
                width: (rb + 4) * 2
                height: (rb + 4) * 2
                opacity: (scene.succeeded ? 1 : 0.5) * scene.clamp(scene.reveal * 2, 0, 1)
                layer.enabled: true
                layer.samples: 4

                ShapePath {
                    strokeColor: Qt.tint(Qt.tint(Colors.accent, Qt.alpha(scene.ringColor(scene.chase + bracket.mid / 360), 0.9 * scene.heat)), Qt.alpha(Colors.critical, 0.85 * scene.lock.flush))
                    strokeWidth: 3
                    fillColor: "transparent"
                    capStyle: ShapePath.RoundCap

                    PathAngleArc {
                        centerX: bracket.rb + 4
                        centerY: bracket.rb + 4
                        radiusX: bracket.rb
                        radiusY: bracket.rb
                        startAngle: bracket.mid - 90 - bracket.half
                        sweepAngle: bracket.half * 2
                    }
                }
            }
        }

        // The flash: a ring that leaves the dial when it locks on
        Rectangle {
            width: (scene.ringR + 4 + 16 * (1 - scene.snap)) * 2
            height: width
            x: scene.ringX - width / 2
            y: scene.ringY - height / 2
            radius: width / 2
            color: "transparent"
            antialiasing: true
            border.width: 1.5
            border.color: Qt.alpha(Qt.tint(Colors.accent, Qt.alpha(scene.ringColor(0.3), 0.7)), 0.8 * scene.snap)
            visible: scene.snap > 0.01
        }

        // The index: the screenshot ruler's marker, a 2px accent line that
        // stands where the pointer is, here at the top, pointing in
        Rectangle {
            x: scene.ringX - 1
            y: scene.ringY - scene.ringR - 2
            width: 2
            height: 14
            radius: 1
            color: Colors.accent
            opacity: 0.85 + 0.15 * scene.caretOn
        }

        // ---- In the middle, under the time: the greeting, and what is going on
        Item {
            id: readout

            x: scene.ringX - width / 2
            y: hero.y + hero.height + 22
            width: Math.round(Math.min(360, scene.hubR * 1.5))
            height: 52
            // Clicks pass through to the stage
            enabled: false
            opacity: scene.stage_(0.25, 0.8)
            transform: Translate {
                y: (1 - scene.stage_(0.25, 0.8)) * 12
            }

            Item {
                id: readInner

                width: parent.width
                height: parent.height
                transform: Translate {
                    x: scene.readShift
                }

                // The name of the disc: the greeting for the lock
                Item {
                    id: nameBox

                    y: 0
                    width: parent.width
                    height: 30

                    Soft {
                        id: nameText

                        width: parent.width
                        height: parent.height
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        elide: Text.ElideRight
                        text: scene.shownName
                        color: scene.shownArmed ? Colors.critical : Colors.foreground
                        font.pixelSize: 22
                        font.bold: true
                        font.letterSpacing: -0.2

                        Behavior on color {
                            ColorAnimation {
                                duration: Style.baseMs
                            }
                        }
                    }

                    // The red line shrinking while the second press is waited for
                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.bottom
                        width: Math.min(nameText.contentWidth, parent.width) * scene.lock.armLeft
                        height: 2
                        radius: 1
                        color: Colors.critical
                        visible: scene.shownArmed
                    }
                }

                // What is going on. The line is always there, so the dial
                // never jumps.
                Soft {
                    id: statusLine

                    y: nameBox.y + nameBox.height + Style.spaceXs
                    width: parent.width
                    height: 18
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    elide: Text.ElideRight
                    text: scene.shownLine
                    color: scene.shownLineColor
                    font.pixelSize: Style.fontMd
                    onTextChanged: lineFade.restart()

                    NumberAnimation {
                        id: lineFade

                        target: statusLine
                        property: "opacity"
                        from: 0.2
                        to: 1
                        duration: Style.baseMs
                        easing.type: Style.easeMove
                    }

                    Behavior on color {
                        ColorAnimation {
                            duration: Style.baseMs
                        }
                    }
                }
            }
        }
    }
}
