// LockStage.qml
// What the lock and the login screen show on one screen: the launcher's dial.
// Lock.qml and Greeter.qml make one of these per screen and hand it the same
// LockModel, so every screen moves as one.
//
// The backdrop is your wallpaper, blurred and washed with the shell's dim. The
// time is the hero of the screen. A borderless stage rises from the bottom
// edge, as in the launcher and the power menu: glass discs along the dial with
// the fine ruler curving under them. The middle disc is the lock. The others
// are what you can do without unlocking (music, suspend, reboot, shutdown);
// turn the dial to one and its name is read out. The password pill rests under
// the readout.
//
// The ruler is the state, as everywhere else in the shell. Each key you type
// turns it a little (Backspace turns it back). It scans while the password is
// checked, flushes red on a wrong one (and the lock disc shakes), and sends a
// ripple out from the middle to both edges on a right one (no green: it is
// told in motion) while the lock disc swells into a tick and the others fall
// back, as when an action is chosen in the power menu. Then it leaves as the
// power menu does: the dial curls back into its dome and the discs sweep off,
// while the clock lifts and the wallpaper comes into focus as the wash clears.
//
// The ruler is an arch: its middle stands a little above the bottom of the
// screen and both sides run down to the bottom edge, so it spans the whole
// width. Under the dial are what it is on (name and line) and the password
// pill.
//
// Like the launcher it arrives as a rainbow: the discs and the ruler swing in
// from the left over a tight dome, washed with the wallpaper's colours, and
// unfurl into the calm dial. Closing plays it in reverse.
//
// Keys (the password field keeps focus, so typing is never affected):
//   type                the password (brings the dial home first)
//   Enter               at home: check it. On another disc: press it.
//   Left, Right, Tab    turn the dial        Shift+Tab   turn it back
//   Esc                 back to the lock disc; again to clear the field
// Mouse: hover reads a disc out, click turns the dial to it, click the disc
// the dial is on to press it. The wheel (or a touchpad swipe, either axis)
// turns the dial one disc at a time. Reboot and Shutdown
// ask for a second press: the disc turns red and a line counts down. The eye
// shows what you type.
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
    // The same dial as the launcher and the power menu
    readonly property int topY: 62
    readonly property int ruleDrop: 52
    readonly property int ruleY: topY + ruleDrop
    readonly property real stepPx: 100
    // The curve is the circle through the middle of the ruler and the two
    // bottom corners, so the ruler meets the bottom edge at both sides
    readonly property real sag: bodyH - ruleY
    readonly property real dialR: (width * width / 4 + sag * sag) / (2 * sag) + ruleDrop
    // The dome the dial starts as when it opens (and ends as when it closes)
    readonly property real rainbowR: Math.min(380, Math.max(280, width * 0.2))
    readonly property int itemSize: 54
    readonly property int selectedSize: 78
    readonly property int tickGap: 12
    readonly property int tickCount: Math.ceil(width / tickGap / 10) * 10 + 20
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
    // The eye button: show what you type (per screen)
    property bool showPw: false
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
    // Radius of the dial right now: curvature eases from the dome to the dial
    readonly property real dialNow: 1 / (1 / dialR + (1 / rainbowR - 1 / dialR) * fan)

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

    // ---- The dots in the pill -----------------------------------------------
    // One soft dot per character. The password is emptied the moment it is
    // sent, so the dots keep the count they had until the answer is in.
    property int held: 0
    readonly property int dotCount: (lock.checking || lock.succeeded) ? held : lock.password.length

    // ---- Layout under the dial ---------------------------------------------
    readonly property int readoutTop: ruleY + 30
    readonly property int readH: 70
    readonly property int pillH: Style.fieldHeight
    readonly property real pillY: readoutTop + readH + 14
    readonly property int foot: 40
    readonly property real bodyH: pillY + pillH + foot

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

    // The keys the password field leaves to the stage
    function handleKey(event) {
        scene.lock.wake();
        const ctrl = (event.modifiers & Qt.ControlModifier) !== 0;
        switch (event.key) {
        case Qt.Key_Return:
        case Qt.Key_Enter:
            event.accepted = true;
            lock.activate();
            return;
        case Qt.Key_Tab:
        case Qt.Key_Right:
            event.accepted = true;
            lock.step(1);
            return;
        case Qt.Key_Backtab:
        case Qt.Key_Left:
            event.accepted = true;
            lock.step(-1);
            return;
        case Qt.Key_Escape:
            event.accepted = true;
            if (!lock.onHome)
                lock.goHome();
            else if (lock.password !== "")
                lock.password = "";
            return;
        }
        // Anything typed is the password: bring the dial home first
        if (!ctrl && event.text !== "")
            lock.goHome();
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
                centerY: vignette.height * 0.46
                centerRadius: Math.sqrt(vignette.width * vignette.width + vignette.height * vignette.height) * 0.62
                focalX: vignette.width / 2
                focalY: vignette.height * 0.46

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
                scene.lock.step(scene.wheelAcc < 0 ? 1 : -1);
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
        readonly property int size: Math.round(scene.height * 0.17)

        anchors.horizontalCenter: parent.horizontalCenter
        y: Math.round(scene.height * 0.14)
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

    // ---- Stage ------------------------------------------------------------
    Item {
        id: stage

        readonly property real cx: width / 2

        anchors.bottom: parent.bottom
        width: scene.width
        height: scene.bodyH
        opacity: Math.min(1, scene.reveal * 3) * (1 - 0.3 * scene.lock.calm)
        transform: Translate {
            y: (1 - scene.reveal) * (stage.height + 40)
        }

        // The launcher's feathered backing: a soft dark ellipse, no visible
        // panel edge
        StageShade {
            yScale: 0.62
        }

        // Wide, low light on the horizon, in the colour of the moment: the
        // accent, red after a refusal, swelling once when it has worked
        Shape {
            id: horizon

            readonly property real r: stage.width * 0.36

            x: stage.cx - r
            y: stage.height - r
            width: r * 2
            height: r * 2
            layer.enabled: true
            layer.samples: 4
            transform: Scale {
                origin.x: horizon.r
                origin.y: horizon.r
                yScale: 0.42
            }

            ShapePath {
                strokeColor: "transparent"
                startX: 0
                startY: horizon.r

                fillGradient: RadialGradient {
                    centerX: horizon.r
                    centerY: horizon.r
                    centerRadius: horizon.r
                    focalX: horizon.r
                    focalY: horizon.r

                    GradientStop {
                        position: 0
                        color: Qt.alpha(scene.tone, 0.16 + 0.26 * Math.sin(Math.PI * scene.lock.unlock))
                    }
                    GradientStop {
                        position: 0.5
                        color: Qt.alpha(scene.tone, 0.06 + 0.1 * Math.sin(Math.PI * scene.lock.unlock))
                    }
                    GradientStop {
                        position: 1
                        color: Qt.alpha(scene.tone, 0)
                    }
                }

                PathArc {
                    x: horizon.r * 2
                    y: horizon.r
                    radiusX: horizon.r
                    radiusY: horizon.r
                }
                PathArc {
                    x: 0
                    y: horizon.r
                    radiusX: horizon.r
                    radiusY: horizon.r
                }
            }
        }

        // ---- The ruler: fine ticks curving across the screen under the
        // discs. It turns against the dial at half speed, and typing turns it
        // too. The ones by the middle rise like a magnifier; the rest show
        // the state (a scan while checking, red after a refusal, a
        // ripple running outward from the middle on success). ----------------
        Repeater {
            model: scene.tickCount

            delegate: Rectangle {
                id: tick

                required property int index

                readonly property real span: scene.tickCount * scene.tickGap
                readonly property real dx: ((index * scene.tickGap + scene.viewPos * scene.stepPx * 0.5 - scene.lock.turn) % span + span) % span - span / 2
                readonly property real a: dx / scene.dialNow
                readonly property real rr: scene.dialNow - scene.ruleDrop
                readonly property bool major: index % 10 === 0
                readonly property bool mid: index % 5 === 0
                // The magnifier by the middle, and the scan going past
                readonly property real near: Math.max(0, 1 - Math.abs(dx) / 90)
                readonly property real wave: Math.max(0, 1 - Math.abs(x - stage.cx - scene.lock.scan * stage.width / 2) / 90) * scene.lock.scanOn
                readonly property real hot: Math.max(near, wave)
                // The unlock ripple: `crest` is 1 on the wave as it runs out
                // from the middle, `okMix` is 1 once it has gone past
                readonly property real front: scene.lock.okFill * 1.35
                readonly property real dist: Math.abs(x - stage.cx) / (stage.width / 2)
                readonly property real okMix: scene.clamp((front - dist) / 0.3, 0, 1)
                readonly property real crest: Math.max(0, 1 - Math.abs(front - dist - 0.06) / 0.14) * (scene.lock.okFill > 0.001 ? 1 : 0)
                // Ticks the state is lighting get more solid
                readonly property real solid: {
                    const rest = major ? 0.7 : (mid ? 0.5 : 0.36);
                    return rest + (1 - rest) * Math.max(0.7 * hot, 0.6 * scene.lock.flush, 0.7 * okMix, crest);
                }
                readonly property color hue: Qt.tint(Qt.tint(Colors.foreground, Qt.alpha(Colors.accent, Math.max(0.7 * hot, 0.9 * crest))), Qt.alpha(Colors.critical, 0.85 * scene.lock.flush))

                x: stage.cx + rr * Math.sin(a) - 0.75
                y: scene.topY + scene.dialNow - rr * Math.cos(a)
                width: 1.5
                height: (major ? 9 : (mid ? 6 : 3)) + 6 * hot + 2 * okMix + 12 * crest
                radius: 0.75
                antialiasing: true
                visible: Math.abs(a) < 1.2 && y < stage.height + 40
                transformOrigin: Item.Top
                rotation: a * 180 / Math.PI
                color: scene.spectral(hue, x, solid)
                opacity: scene.clamp((stage.cx - Math.abs(x - stage.cx)) / 18, 0, 1) * scene.clamp(scene.reveal * 2 - Math.abs(x - stage.cx) / stage.cx * 0.9, 0, 1)
            }
        }

        // Fine centre marker on the ruler, with a soft bead at its foot
        Rectangle {
            x: stage.cx - 0.75
            y: scene.ruleY - 1
            width: 1.5
            height: 12
            radius: 0.5
            color: scene.selTone
        }
        Rectangle {
            x: stage.cx - width / 2
            y: scene.ruleY + 14
            width: 5
            height: 5
            radius: 2.5
            color: scene.selTone
            opacity: 0.55 + 0.4 * scene.breath
        }

        // A soft pool of light under the disc the dial is on, in the colour
        // of the moment. One shape for the whole dial: it follows the dial
        // as it turns, so the selection is lit rather than outlined.
        Shape {
            id: spot

            readonly property real k: scene.lock.selected - scene.viewPos
            readonly property real a: k * scene.stepPx / scene.dialNow
            readonly property real r: scene.selectedSize * 1.25

            x: stage.cx + scene.dialNow * Math.sin(a) - r
            y: scene.topY + scene.dialNow * (1 - Math.cos(a)) - r - 8
            width: r * 2
            height: r * 2
            opacity: scene.clamp(scene.reveal * 2 - 0.6, 0, 1) * (0.7 + 0.3 * scene.breath)
            layer.enabled: true
            layer.samples: 4

            ShapePath {
                strokeColor: "transparent"
                startX: 0
                startY: spot.r

                fillGradient: RadialGradient {
                    centerX: spot.r
                    centerY: spot.r
                    centerRadius: spot.r
                    focalX: spot.r
                    focalY: spot.r

                    GradientStop {
                        position: 0
                        color: Qt.alpha(scene.selTone, 0.22 + 0.2 * Math.sin(Math.PI * scene.lock.unlock))
                    }
                    GradientStop {
                        position: 0.55
                        color: Qt.alpha(scene.selTone, 0.07)
                    }
                    GradientStop {
                        position: 1
                        color: Qt.alpha(scene.selTone, 0)
                    }
                }

                PathArc {
                    x: spot.r * 2
                    y: spot.r
                    radiusX: spot.r
                    radiusY: spot.r
                }
                PathArc {
                    x: 0
                    y: spot.r
                    radiusX: spot.r
                    radiusY: spot.r
                }
            }
        }

        // Underline above the disc the dial is on; it breathes with the ring
        Rectangle {
            x: stage.cx - width / 2
            y: scene.topY - scene.selectedSize * 0.62 - 8
            width: 20 + 10 * scene.breath
            height: 2
            radius: 1
            color: scene.selTone
            opacity: scene.clamp(scene.reveal * 2 - 0.6, 0, 1)
        }

        // ---- The discs: the lock, and what you can do without it --------
        Repeater {
            model: scene.lock.slots.length

            delegate: Item {
                id: slot

                required property int index

                readonly property var info: scene.lock.slots[index] || ({})
                readonly property bool home: info.home === true
                readonly property bool spacer: info.spacer === true
                readonly property bool crit: info.critical === true
                // Lit like a selected disc while its state is "on" (muted)
                readonly property bool lit: info.activeNow ? info.activeNow() === true : false
                readonly property bool picked: index === scene.lock.selected
                readonly property bool isArmed: !home && scene.lock.armed === info.key
                readonly property color hue: home ? scene.tone : (crit ? Colors.critical : Colors.accent)

                readonly property real k: index - scene.viewPos
                readonly property real a: k * scene.stepPx / scene.dialNow
                readonly property real px: stage.cx + scene.dialNow * Math.sin(a)
                readonly property real py: scene.topY + scene.dialNow * (1 - Math.cos(a))
                // 1 while the dial is on it, 0 otherwise. It swells with a
                // little overshoot when the dial arrives and settles back
                // without one, as in the power menu.
                property real grow: picked ? 1 : 0
                readonly property real c: grow
                // The discs recede along the dial: a touch smaller each step
                // out, so it has depth
                readonly property real recede: Math.max(0, Math.min(3, Math.abs(k) - 1))
                readonly property real sz: (scene.itemSize + (scene.selectedSize - scene.itemSize) * c) * (1 - 0.035 * recede)
                // Shape: a squircle that rounds a little more as it is selected
                readonly property real corner: sz * (0.36 + 0.06 * c)
                // The discs arrive in a left-to-right wave, each with a small
                // overshoot, and leave the same way
                readonly property real delay: (scene.clamp(index - scene.lock.homeIndex, -4, 4) + 4) * 0.035
                readonly property real appear: scene.clamp((scene.reveal - delay) / 0.42, 0, 1)
                readonly property real edge: scene.clamp((stage.cx - Math.abs(px - stage.cx)) / 105, 0, 1)
                readonly property real floorFade: scene.clamp((stage.height - py + sz * 0.3) / (sz * 0.6), 0, 1)
                // 0 at rest, 1 under the pointer: a gentle lift
                property real hover: area.containsMouse && !picked ? 1 : 0
                // 0..1 while the ring around a newly selected disc expands
                property real ping: 0

                visible: info.key !== undefined && py - sz / 2 < stage.height
                x: px - sz / 2 + (home ? scene.lock.shakeX : 0)
                y: py - sz / 2 - 8 * c
                width: sz
                height: sz
                z: 10 - Math.abs(k)
                opacity: appear * edge * floorFade * (info.enabled === false ? 0.4 : 1) * (home ? 1 : 1 - 0.65 * scene.clamp(scene.lock.unlock * 3, 0, 1))
                scale: (0.55 + 0.45 * scene.backOut(appear)) * (1 + 0.14 * pulse)
                // Tilts along the dial, and rises from below as it arrives
                rotation: a * 180 / Math.PI * 0.6
                transform: Translate {
                    id: nudge

                    y: (1 - slot.appear) * 30 - 3 * slot.hover
                }

                Behavior on hover {
                    NumberAnimation {
                        duration: Style.baseMs
                        easing.type: Style.easeMove
                    }
                }

                Behavior on grow {
                    NumberAnimation {
                        duration: Style.moveMs
                        easing.type: slot.picked ? Style.easePop : Style.easeMove
                        easing.overshoot: 1.2
                    }
                }

                // A small shake when it arms, so the second press is noticed
                onIsArmedChanged: if (isArmed)
                    nudgeAnim.restart()

                SequentialAnimation {
                    id: nudgeAnim

                    NumberAnimation {
                        target: nudge
                        property: "x"
                        to: -4
                        duration: 50
                    }
                    NumberAnimation {
                        target: nudge
                        property: "x"
                        to: 4
                        duration: 80
                    }
                    NumberAnimation {
                        target: nudge
                        property: "x"
                        to: 0
                        duration: 110
                        easing.type: Style.easeMove
                    }
                }

                // Pressed: it swells a little, then settles, like the chosen
                // action in the power menu
                property real pulse: 0

                SequentialAnimation {
                    id: pulseAnim

                    NumberAnimation {
                        target: slot
                        property: "pulse"
                        to: 1
                        duration: Style.fadeMs
                        easing.type: Style.easeMove
                    }
                    NumberAnimation {
                        target: slot
                        property: "pulse"
                        to: 0
                        duration: Style.baseMs
                        easing.type: Style.easeMove
                    }
                }

                // The dial turned to this disc, or it was pressed: a ring leaves it
                onPickedChanged: if (picked && scene.lock.reveal > 0.8)
                    pingAnim.restart()

                Connections {
                    target: scene.lock

                    function onActivated(key) {
                        if (key !== slot.info.key)
                            return;
                        pingAnim.restart();
                        if (!slot.home)
                            pulseAnim.restart();
                    }
                }

                NumberAnimation {
                    id: pingAnim

                    target: slot
                    property: "ping"
                    from: 0
                    to: 1
                    duration: Style.sweepMs
                    easing.type: Style.easeMove
                }

                // Ring that leaves a newly selected disc
                Rectangle {
                    anchors.centerIn: parent
                    width: parent.width + 14 + 34 * slot.ping
                    height: width
                    radius: slot.corner + 7 + 17 * slot.ping
                    color: "transparent"
                    antialiasing: true
                    visible: slot.ping > 0.001 && slot.ping < 0.999
                    border.width: 1.5
                    border.color: Qt.alpha(slot.hue, 0.5 * (1 - slot.ping))
                }

                // Ring that leaves the lock on a refusal (red) and on success
                Rectangle {
                    anchors.centerIn: parent
                    width: parent.width + 14 + 34 * scene.lock.ring
                    height: width
                    radius: slot.corner + 7 + 17 * scene.lock.ring
                    color: "transparent"
                    antialiasing: true
                    visible: slot.home && scene.lock.ring > 0.001 && scene.lock.ring < 0.999
                    border.width: 1.5
                    border.color: Qt.alpha(scene.tone, 0.5 * (1 - scene.lock.ring))
                }

                // Breathing ring around the disc the dial is on. A disc
                // waiting for its second press rings in red, stronger.
                Rectangle {
                    anchors.centerIn: parent
                    width: parent.width + 14
                    height: width
                    radius: slot.corner + 7
                    color: "transparent"
                    antialiasing: true
                    visible: slot.c > 0.05
                    border.width: slot.isArmed ? 1.5 : 1
                    border.color: Qt.alpha(slot.hue, slot.c * (slot.isArmed ? 0.4 + 0.4 * scene.breath : 0.2 + 0.2 * scene.breath))
                }

                // The empty detent that keeps the dial balanced: just a faint ring
                Rectangle {
                    anchors.centerIn: parent
                    width: scene.itemSize * 0.34
                    height: width
                    radius: width / 2
                    color: "transparent"
                    antialiasing: true
                    visible: slot.spacer
                    border.width: 1
                    border.color: scene.spectral(Colors.foreground, slot.px, 0.18)
                }

                // Keep the mouse area stable while the disc subtly presses in
                Item {
                    anchors.fill: parent
                    visible: !slot.spacer
                    scale: (area.pressed ? 0.94 : 1) + (slot.home ? 0.04 * scene.lock.scanOn * scene.breath + 0.14 * scene.clamp(scene.lock.unlock * 3, 0, 1) : 0)

                    Behavior on scale {
                        NumberAnimation {
                            duration: Style.pressMs
                            easing.type: Style.easePress
                        }
                    }

                    // Glass, like the bar: one flat surface with a hairline
                    // outline. It takes the palette wash while the dial is
                    // arriving, and the disc's colour once selected.
                    Rectangle {
                        anchors.fill: parent
                        radius: slot.corner
                        antialiasing: true
                        color: slot.isArmed ? Qt.tint(scene.glass, Qt.alpha(Colors.critical, 0.3)) : scene.glass
                        border.width: 1
                        border.color: slot.c > 0.45 ? scene.spectral(slot.hue, slot.px, 0.6 + 0.4 * slot.c) : scene.spectral(slot.crit ? Colors.critical : Colors.foreground, slot.px, slot.crit ? 0.45 : 0.2)
                    }

                    // The soft tint inside the glass belongs to the lock disc
                    // alone: it is the colour of the moment. The other discs
                    // are told by their edge, as in the power menu.
                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: 1
                        radius: slot.corner
                        antialiasing: true
                        color: Qt.alpha(slot.hue, slot.home ? Style.tintAlpha : 0)
                    }

                    // Light catching the top edge, as on the bar
                    EdgeLight {
                        corner: slot.corner
                    }

                    // The shell's hover fill
                    Rectangle {
                        anchors.fill: parent
                        radius: slot.corner
                        antialiasing: true
                        color: area.containsMouse ? Style.hoverFill : "transparent"

                        Behavior on color {
                            ColorAnimation {
                                duration: Style.baseMs
                            }
                        }
                    }

                    // The glyph stays upright while the disc tilts with the dial.
                    // On the lock it turns into a tick once the password is right:
                    // the lock spins away small, the tick pops in with a little
                    // overshoot.
                    Txt {
                        id: glyph

                        // 1 as the icon changes, settling to 0: a small pop,
                        // so a press that flips a state (mute, play and
                        // pause) is felt
                        property real flip: 0

                        anchors.centerIn: parent
                        rotation: -slot.rotation - (slot.home ? 40 * scene.lock.unlock : 0)
                        scale: (slot.home ? 1 - 0.5 * scene.lock.unlock : 1) * (1 - 0.3 * flip)
                        opacity: (slot.home ? 1 - scene.clamp(scene.lock.unlock * 2, 0, 1) : (slot.picked || slot.crit || slot.lit ? 1 : 0.9)) * (1 - 0.6 * flip)
                        onTextChanged: flipAnim.restart()

                        NumberAnimation {
                            id: flipAnim

                            target: glyph
                            property: "flip"
                            from: 1
                            to: 0
                            duration: Style.baseMs
                            easing.type: Style.easePop
                        }
                        text: slot.home ? Icons.lock : (slot.info.glyphNow ? slot.info.glyphNow() : (slot.info.glyph || ""))
                        // Destructive glyphs stay red at rest; the rest sit back
                        color: slot.home ? scene.tone : (slot.crit ? Colors.critical : ((slot.picked || slot.lit) ? Colors.accent : Colors.foreground))
                        font.pixelSize: 22 + 8 * slot.c

                        Behavior on color {
                            ColorAnimation {
                                duration: Style.baseMs
                            }
                        }
                    }

                    Txt {
                        anchors.centerIn: parent
                        visible: slot.home && scene.lock.unlock > 0.01
                        rotation: -slot.rotation + 30 * (1 - scene.lock.unlock)
                        scale: 0.4 + 0.6 * scene.backOut(scene.clamp((scene.lock.unlock - 0.35) / 0.65, 0, 1))
                        opacity: scene.clamp((scene.lock.unlock - 0.35) / 0.4, 0, 1)
                        text: Icons.check
                        color: scene.tone
                        font.pixelSize: 22 + 8 * slot.c
                    }

                    // A small pip on a disc whose state is "on" (muted), so
                    // it reads even when the dial is elsewhere
                    Rectangle {
                        x: parent.width - width - parent.width * 0.16
                        y: parent.height * 0.14
                        width: 6
                        height: 6
                        radius: 3
                        antialiasing: true
                        color: Colors.accent
                        scale: slot.lit ? 1 : 0
                        visible: scale > 0.01

                        Behavior on scale {
                            NumberAnimation {
                                duration: Style.baseMs
                                easing.type: Style.easePop
                            }
                        }
                    }
                }

                MouseArea {
                    id: area

                    anchors.fill: parent
                    enabled: !slot.spacer
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onPositionChanged: scene.lock.wake()
                    onEntered: scene.peek = slot.index
                    onExited: if (scene.peek === slot.index)
                        scene.peek = -1
                    onClicked: {
                        if (slot.picked)
                            scene.lock.activate();
                        else
                            scene.lock.select(slot.info.key);
                        pw.forceActiveFocus();
                    }
                }
            }
        }

        // ---- The middle: what this is, which disc, what is going on ------
        Item {
            id: readout

            x: stage.cx - width / 2
            y: scene.readoutTop
            width: Math.min(520, stage.width - 48)
            height: scene.readH
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

                // What this screen is
                Soft {
                    id: modeLine

                    width: parent.width
                    height: 14
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                    text: scene.lock.modeLine
                    color: scene.succeeded ? Colors.foreground : Qt.alpha(Colors.foreground, 0.78)
                    font.pixelSize: Style.fontSm
                    font.letterSpacing: 1.4
                    font.capitalization: Font.AllUppercase
                }

                // The name of the disc: the greeting for the lock
                Item {
                    id: nameBox

                    y: modeLine.height + Style.spaceXs
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

        // ---- The password pill, under the readout -------------------------
        // The shell's SearchField on a glass backing, so it reads on any
        // wallpaper.
        Item {
            id: pill

            // Dimmed once it has worked, and while the dial is elsewhere
            property real dim: scene.succeeded ? 1 : (scene.lock.onHome ? 1 : 0.55)

            x: stage.cx - width / 2 + scene.lock.shakeX * 0.6
            y: scene.pillY
            width: Math.min(340, stage.width - 96)
            height: scene.pillH
            opacity: scene.stage_(0.4, 0.95) * dim
            transform: Translate {
                y: (1 - scene.stage_(0.4, 0.95)) * 10
            }
            Behavior on dim {
                NumberAnimation {
                    duration: Style.moveMs
                    easing.type: Style.easeMove
                }
            }

            Rectangle {
                anchors.fill: parent
                radius: height / 2
                antialiasing: true
                color: scene.glassDeep
                border.width: 1
                // Red after a refusal (the field is empty again, so the
                // field's own edge does not cover it)
                border.color: scene.lock.statusIsError ? Qt.alpha(Colors.critical, 0.7) : (scene.succeeded ? Qt.alpha(scene.tone, 0.65) : Style.outline)

                Behavior on border.color {
                    ColorAnimation {
                        duration: Style.baseMs
                    }
                }
            }

            // Light catching the top edge, as on the bar
            EdgeLight {
                corner: pill.height
            }

            SearchField {
                id: pw

                anchors.fill: parent
                // The lock becomes a tick when the password is right
                glyph: scene.succeeded ? Icons.check : Icons.lock
                placeholder: scene.succeeded ? "" : (scene.lock.onHome ? scene.lock.placeholder : "Type to unlock")
                // The lock breathes while the password is checked
                busy: scene.checking
                // Esc clears it; the eye sits at its right end instead
                clearable: false

                // One password for every screen: this field writes it, and
                // shows it again when the owner empties it
                onTextChanged: {
                    if (scene.lock.password !== text)
                        scene.lock.password = text;
                }
                Keys.onPressed: event => scene.handleKey(event)
            }

            Connections {
                target: scene.lock

                function onPasswordChanged() {
                    if (pw.text !== scene.lock.password)
                        pw.text = scene.lock.password;
                    if (scene.lock.password.length > 0)
                        scene.held = scene.lock.password.length;
                }
            }

            // A password field is a TextInput that hides what you type (unless
            // you ask to see it) and takes no suggestions. Read-only rather
            // than disabled, so it keeps the cursor.
            Binding {
                target: pw.input
                property: "echoMode"
                value: scene.showPw ? TextInput.Normal : TextInput.Password
            }
            Binding {
                target: pw.input
                property: "readOnly"
                value: scene.checking || scene.succeeded
            }

            // The field keeps the text and the focus; the dots below are what
            // you see (unless you ask to see the text), so the field's own
            // bullets and cursor are hidden
            Binding {
                target: pw.input
                property: "color"
                value: scene.showPw ? Colors.foreground : "transparent"
            }

            Component {
                id: noCursor

                Item {}
            }

            Component.onCompleted: {
                pw.input.cursorDelegate = noCursor;
                pw.input.passwordCharacter = "\u2022";
                pw.input.inputMethodHints = Qt.ImhSensitiveData | Qt.ImhNoPredictiveText;
            }

            // The dots. Each pops in as you type; while the password is
            // checked a bright patch runs along them, as along the ruler. A
            // long password scrolls, so the newest dots stay in view.
            Item {
                id: dotsClip

                x: 14 + Style.fontXl + Style.spaceMd + 4
                width: pill.width - x - 50
                height: pill.height
                clip: true
                visible: !scene.showPw

                Row {
                    id: dotRow

                    x: Math.min(0, dotsClip.width - width)
                    height: dotsClip.height
                    // On success the dots draw together and go, making room
                    // for the welcome
                    spacing: 7 - 5 * scene.clamp(scene.lock.unlock * 1.5, 0, 1)
                    opacity: 1 - scene.clamp(scene.lock.unlock * 1.6, 0, 1)

                    Behavior on x {
                        NumberAnimation {
                            duration: Style.baseMs
                            easing.type: Style.easeMove
                        }
                    }

                    Repeater {
                        model: scene.dotCount

                        delegate: Item {
                            id: dotSlot

                            required property int index

                            // The bright patch going past while checking
                            readonly property real hot: Math.max(0, 1 - Math.abs(index - (scene.lock.scan + 1.15) / 2.3 * scene.dotCount) / 2.5) * scene.lock.scanOn

                            width: 8
                            height: dotRow.height

                            Rectangle {
                                id: dot

                                anchors.centerIn: parent
                                width: 8
                                height: 8
                                radius: 4
                                antialiasing: true
                                color: Qt.tint(Colors.foreground, Qt.alpha(scene.tone, Math.max(0.55 * dotSlot.hot, scene.lock.flush)))
                                opacity: 0.85 + 0.15 * dotSlot.hot
                            }
                        }
                    }
                }
            }

            // The welcome, where the dots were: it rises in once they have
            // gone
            Txt {
                readonly property real t: scene.clamp((scene.lock.unlock - 0.3) / 0.6, 0, 1)

                x: dotsClip.x
                anchors.verticalCenter: parent.verticalCenter
                anchors.verticalCenterOffset: (1 - t) * 8
                text: scene.lock.okText
                color: scene.tone
                opacity: t
                font.pixelSize: Style.fontMd
                font.letterSpacing: 1
            }

            // Show what you type, inside the pill's right end, so the pill
            // itself stays centred
            IconButton {
                x: parent.width - width - 6
                anchors.verticalCenter: parent.verticalCenter
                size: parent.height - 8
                opacity: scene.checking || scene.succeeded ? 0 : 1
                enabled: !scene.checking && !scene.succeeded
                glyph: scene.showPw ? Icons.eyeOff : Icons.eye
                on: scene.showPw
                onClicked: {
                    scene.showPw = !scene.showPw;
                    pw.forceActiveFocus();
                }

                Behavior on opacity {
                    NumberAnimation {
                        duration: Style.baseMs
                    }
                }
            }
        }
    }
}
