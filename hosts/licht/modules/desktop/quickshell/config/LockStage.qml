// LockStage.qml
// What the lock and the login screen show on one screen. Lock.qml and
// Greeter.qml make one of these per screen and hand it the same LockModel, so
// every screen, and both the lock and the login screen, look the same.
//
// The composition is one large radial dial, centred: the power menu's dial
// closed into a circle, like the face of a safe. It has the power menu's fine
// ruler (the same ticks, the same spacing, a taller one every fifth and tenth)
// in two rings, an outer ruler and an inner one turning the other way, on a
// plate of bar-style glass with a hairline outline, with the same fine marker
// and soft bead at the top, a feathered shade behind it and a soft light in the
// colour of the highlight. The time sits in the middle of it, like a watch: a
// small line saying what this is, the time large and light, the date under it,
// then the greeting and a line saying what is going on.
//
// It is kept lean because it runs on every screen at once on a laptop's
// graphics: the wallpaper is blurred once at a quarter of the screen size and
// each ring is drawn once into a texture and only ever turned. Everything that
// moves is an angle, a size or a fade, and moves at the shell's speeds.
//
// There is no password box. Typing shows almost nothing: the two rings turn a
// little, the outer one clockwise and the inner one back, a character at a
// time, and Backspace turns them back. A wrong password lets them wind back to
// nought, with a small shake and the marker turning red. A right one opens it
// like a safe: the two dials spin round, one each way, and come to rest at
// nought under the marker, then the rings open outwards, one a little ahead of
// the other, and fade as the time slides away.
//
// One taller tick on the outer ring goes round once a minute: the seconds.
// While the lock waits it is the only thing that moves.
//
// Keys (an invisible field keeps the keyboard, so typing is never affected):
//   type                the password
//   Enter               check it
//   Esc                 clear what you typed
//
// It reads and writes the LockModel it is given (see LockModel.qml).

import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import Quickshell

Item {
    id: scene

    // The model every screen shows (LockModel.qml)
    required property var lock

    // ---- Layout ---------------------------------------------------------
    // The dial: its middle and the radius of the outer ruler; the inner ruler
    // sits a little inside it
    readonly property real dialX: Math.round(width * 0.5)
    readonly property real dialY: Math.round(height * 0.5)
    readonly property real ringR: Math.round(Math.min(height * 0.37, width * 0.28))
    readonly property real innerR: ringR - Math.round(ringR * 0.085)
    // The glass plate the rulers sit on reaches a little past the outer ruler
    readonly property real plateR: ringR + 8
    // What is left in the middle of the rulers, for the time, and how large the
    // time can be in it
    readonly property real hubR: innerR - 24
    readonly property int clockSize: Math.round(Math.min(height * 0.18, hubR * 0.5))
    // Both rulers are the power menu's: ticks about 12px apart, a taller one
    // every fifth and every tenth
    readonly property int outerCount: Math.max(40, Math.round(twoPi * ringR / 12 / 10) * 10)
    readonly property int innerCount: Math.max(40, Math.round(twoPi * innerR / 12 / 10) * 10)
    readonly property real twoPi: Math.PI * 2
    // The background colour with a breath of the accent, as Dim.qml has it
    readonly property color wash: Qt.tint(Colors.background, Qt.alpha(Colors.accent, 0.08))
    // Secondary text: the palette's muted, lifted a little toward the
    // foreground so it holds on any wallpaper
    readonly property color softText: Qt.tint(Colors.muted, Qt.alpha(Colors.foreground, 0.22))

    // ---- What you typed ---------------------------------------------------
    // The password is emptied the moment it is sent, so the dial keeps the
    // count it had until the answer is in.
    property int held: 0
    readonly property int dotCount: (lock.checking || lock.succeeded) ? held : lock.password.length

    // The rings sway a little against each other while the password is
    // checked: the phase runs only then, and the amount eases in and out so
    // nothing jumps
    property real phase: 0
    property real checkAmt: lock.checking ? 1 : 0

    Behavior on checkAmt {
        NumberAnimation {
            duration: Style.moveMs
            easing.type: Style.easeMove
        }
    }

    NumberAnimation on phase {
        from: 0
        to: Math.PI * 2
        duration: 2000
        loops: Animation.Infinite
        running: scene.lock.checking
    }

    // The two rings turn against each other, a couple of degrees a character
    // (degrees). At nought once it has worked.
    property real outerBase: lock.succeeded ? 0 : Math.min(dotCount, 40) * 2
    property real innerBase: lock.succeeded ? 0 : -Math.min(dotCount, 40) * 3

    Behavior on outerBase {
        NumberAnimation {
            duration: scene.lock.succeeded ? Style.sweepMs : Style.moveMs
            easing.type: scene.lock.succeeded ? Style.easeEnter : Style.easeMove
        }
    }

    Behavior on innerBase {
        NumberAnimation {
            duration: scene.lock.succeeded ? Style.sweepMs : Style.moveMs
            easing.type: scene.lock.succeeded ? Style.easeEnter : Style.easeMove
        }
    }

    // The safe: when the password is right the two dials spin, the outer one a
    // full turn clockwise and the inner one two turns back, slowing as they
    // come to rest at nought under the marker. 0 to 1.
    property real spin: 0

    Connections {
        target: scene.lock

        function onSucceededChanged() {
            if (scene.lock.succeeded)
                spinAnim.restart();
        }
    }

    NumberAnimation {
        id: spinAnim

        target: scene
        property: "spin"
        from: 0
        to: 1
        duration: Style.sweepMs
        easing.type: Style.easeEnter
    }

    // What each ring shows: its turn, the sway while checking, the swing in as
    // the dial arrives, and the spin of the safe
    readonly property real outerA: outerBase + (1 - lock.reveal) * 12 + Math.sin(phase) * 3 * checkAmt + 360 * spin
    readonly property real innerA: innerBase - (1 - lock.reveal) * 18 - Math.sin(phase) * 5 * checkAmt - 720 * spin

    // ---- Keyboard ---------------------------------------------------------
    // The password goes into a field nobody sees: it keeps the keyboard, and
    // the turning of the rings is all that shows you are typing
    TextInput {
        id: pw

        width: 1
        height: 1
        opacity: 0
        focus: true
        echoMode: TextInput.Password
        inputMethodHints: Qt.ImhSensitiveData | Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase
        // Read-only rather than disabled, so it keeps the focus
        readOnly: scene.lock.checking || scene.lock.succeeded

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
        switch (event.key) {
        case Qt.Key_Return:
        case Qt.Key_Enter:
            event.accepted = true;
            lock.activate();
            return;
        case Qt.Key_Escape:
            event.accepted = true;
            if (lock.password !== "")
                lock.password = "";
            return;
        }
    }

    Component.onCompleted: Qt.callLater(pw.forceActiveFocus)

    // Pressing anywhere gives the keyboard back to the field
    MouseArea {
        anchors.fill: parent
        onPressed: pw.forceActiveFocus()
    }

    // ---- Backdrop: the wallpaper, blurred ---------------------------------
    // A blurred picture needs no detail, so the image is read and blurred at a
    // quarter of the screen size and scaled up: the same look for a sixteenth
    // of the work. It is blurred once and never changes.
    Item {
        id: backdrop

        width: Math.round(scene.width / 4)
        height: Math.round(scene.height / 4)
        scale: 4
        transformOrigin: Item.Center
        x: (scene.width - width) / 2
        y: (scene.height - height) / 2
        // Fades in once it has loaded; until then the window's own
        // background colour shows
        opacity: wall.status === Image.Ready ? 1 : 0
        layer.enabled: true
        layer.effect: MultiEffect {
            blurEnabled: true
            blur: 1
            blurMax: 12
        }

        Behavior on opacity {
            NumberAnimation {
                duration: Style.baseMs
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

    // The shell's dim over it: lighter at the top, deeper toward the foot
    Rectangle {
        anchors.fill: parent

        gradient: Gradient {
            GradientStop {
                position: 0
                color: Qt.alpha(scene.wash, 0.46)
            }
            GradientStop {
                position: 0.55
                color: Qt.alpha(scene.wash, 0.58)
            }
            GradientStop {
                position: 1
                color: Qt.alpha(scene.wash, 0.84)
            }
        }
    }

    // ---- The lock ---------------------------------------------------------
    // It fades in and out and shakes after a refusal; nothing else on it moves
    Item {
        id: stage

        anchors.fill: parent
        opacity: scene.lock.reveal * (1 - scene.lock.leave)
        // It rises a little as it arrives, and shakes after a refusal
        transform: Translate {
            x: scene.lock.shakeX
            y: (1 - scene.lock.reveal) * 8
        }

        // A soft dark pool behind the dial, with no visible edge, so the ticks
        // read on any wallpaper
        Shape {
            id: shade

            readonly property real r: scene.ringR * 1.25

            x: scene.dialX - r
            y: scene.dialY - r
            width: r * 2
            height: r * 2

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
                        color: Qt.alpha(scene.wash, 0.5)
                    }
                    GradientStop {
                        position: 0.75
                        color: Qt.alpha(scene.wash, 0.34)
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

        // Wide, low light behind the dial in the colour of the highlight, as
        // the power menu puts on its horizon
        Shape {
            id: horizon

            readonly property real r: scene.ringR * 0.95

            x: scene.dialX - r
            y: scene.dialY - r
            width: r * 2
            height: r * 2

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
                        color: Qt.alpha(scene.lock.tone, 0.1)
                    }
                    GradientStop {
                        position: 0.6
                        color: Qt.alpha(scene.lock.tone, 0.04)
                    }
                    GradientStop {
                        position: 1
                        color: Qt.alpha(scene.lock.tone, 0)
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

        // The plate: glass, like the bar and the power menu's discs, one flat
        // surface with a hairline outline, big enough to carry both rulers. A
        // second hairline marks the middle.
        Rectangle {
            width: scene.plateR * 2
            height: width
            x: scene.dialX - width / 2
            y: scene.dialY - height / 2
            radius: width / 2
            color: Style.card
            opacity: 0.55
            border.width: 1
            border.color: Style.outline
            // Swells a little as the dial opens
            scale: 1 + 0.1 * scene.lock.leave
        }

        Rectangle {
            width: scene.hubR * 2
            height: width
            x: scene.dialX - width / 2
            y: scene.dialY - height / 2
            radius: width / 2
            color: "transparent"
            border.width: 1
            border.color: Style.outline
            scale: 1 + 0.1 * scene.lock.leave
        }

        // The outer ruler: the power menu's fine ruler closed into a circle,
        // a taller tick every fifth and tenth. Drawn once into a texture;
        // turning it is nearly free.
        Item {
            id: outerRing

            readonly property real r: scene.ringR

            x: scene.dialX - r
            y: scene.dialY - r
            width: r * 2
            height: r * 2
            rotation: scene.outerA
            // Opens outwards as it leaves, a little ahead of the inner one
            scale: 1 + 0.18 * scene.lock.leave
            layer.enabled: true
            layer.smooth: true
            layer.textureSize: Qt.size(width * 1.5, height * 1.5)

            Repeater {
                model: scene.outerCount

                delegate: Rectangle {
                    required property int index

                    readonly property bool major: index % 10 === 0
                    readonly property bool mid: index % 5 === 0

                    x: outerRing.r - width / 2
                    y: 1
                    width: 1
                    height: major ? 9 : (mid ? 6 : 3)
                    radius: 0.5
                    antialiasing: true
                    color: Qt.alpha(Colors.foreground, major ? 0.95 : (mid ? 0.7 : 0.5))
                    transform: Rotation {
                        origin.x: width / 2
                        origin.y: outerRing.r - 1
                        angle: index * 360 / scene.outerCount
                    }
                }
            }
        }

        // The inner ruler: the same ruler a little inside, a touch fainter so
        // the two read as two. It turns the other way, and is also drawn once.
        Item {
            id: innerRing

            readonly property real r: scene.innerR

            x: scene.dialX - r
            y: scene.dialY - r
            width: r * 2
            height: r * 2
            rotation: scene.innerA
            scale: 1 + 0.1 * scene.lock.leave
            layer.enabled: true
            layer.smooth: true
            layer.textureSize: Qt.size(width * 1.5, height * 1.5)

            Repeater {
                model: scene.innerCount

                delegate: Rectangle {
                    required property int index

                    readonly property bool major: index % 10 === 0
                    readonly property bool mid: index % 5 === 0

                    x: innerRing.r - width / 2
                    y: 1
                    width: 1
                    height: major ? 9 : (mid ? 6 : 3)
                    radius: 0.5
                    antialiasing: true
                    color: Qt.alpha(Colors.foreground, major ? 0.7 : (mid ? 0.5 : 0.36))
                    transform: Rotation {
                        origin.x: width / 2
                        origin.y: innerRing.r - 1
                        angle: index * 360 / scene.innerCount
                    }
                }
            }
        }

        // The fine marker on the ruler, with a soft bead at its foot, exactly as
        // on the power menu's: at the top of the dial, pointing in. Both turn
        // red after a refusal.
        Rectangle {
            x: scene.dialX - 0.75
            y: scene.dialY - scene.ringR - 1
            width: 1.5
            height: 12
            radius: 0.5
            color: scene.lock.tone

            Behavior on color {
                ColorAnimation {
                    duration: Style.moveMs
                }
            }
        }

        Rectangle {
            x: scene.dialX - width / 2
            y: scene.dialY - scene.ringR + 14
            width: 5
            height: 5
            radius: 2.5
            color: scene.lock.tone
            opacity: 0.8

            Behavior on color {
                ColorAnimation {
                    duration: Style.moveMs
                }
            }
        }

        // The seconds: one taller accent tick on the outer ring, going round
        // once a minute from the top. It wakes once a second, and only while
        // it shows.
        SystemClock {
            id: secClock

            precision: SystemClock.Seconds
            enabled: scene.lock.reveal > 0.01 && !scene.lock.succeeded
        }

        Rectangle {
            readonly property real ang: secClock.date.getSeconds() * 6

            x: scene.dialX + scene.ringR * Math.sin(ang * Math.PI / 180) - width / 2
            y: scene.dialY - scene.ringR * Math.cos(ang * Math.PI / 180)
            width: 2
            height: 16
            radius: 1
            antialiasing: true
            transformOrigin: Item.Top
            rotation: ang
            color: Colors.accent
            opacity: scene.lock.succeeded ? 0 : 0.7
        }

        // ---- The time ------------------------------------------------------
        // In the middle of the dial, like a watch: a small line saying what
        // this is, the time large and light, the date under it between two
        // hairlines, then the greeting and what is going on. It lifts a little
        // as the dial opens.
        Column {
            id: block

            width: scene.hubR * 2 - 60
            x: scene.dialX - width / 2
            y: Math.round(scene.dialY - height / 2)
            spacing: 0
            transform: Translate {
                y: -14 * scene.lock.leave
            }

            // What this screen is
            Txt {
                anchors.horizontalCenter: parent.horizontalCenter
                text: scene.lock.modeLine
                color: Qt.alpha(Colors.foreground, 0.62)
                font.pixelSize: Style.fontSm
                font.letterSpacing: 2
                font.capitalization: Font.AllUppercase
            }

            Item {
                width: 1
                height: Math.round(scene.clockSize * 0.1)
            }

            // The time: large and light
            Row {
                id: timeRow

                anchors.horizontalCenter: parent.horizontalCenter

                Txt {
                    text: scene.lock.hourText
                    color: Qt.alpha(Colors.foreground, 0.94)
                    font.pixelSize: scene.clockSize
                    font.weight: Font.Light
                    font.letterSpacing: -Math.round(scene.clockSize * 0.035)
                }

                Txt {
                    text: ":"
                    color: scene.lock.tone
                    font.pixelSize: scene.clockSize
                    font.weight: Font.Light
                    // Lifted to the optical middle of the digits
                    transform: Translate {
                        y: -Math.round(scene.clockSize * 0.05)
                    }
                }

                Txt {
                    id: minTxt

                    text: scene.lock.minuteText
                    color: Qt.alpha(Colors.foreground, 0.94)
                    font.pixelSize: scene.clockSize
                    font.weight: Font.Light
                    font.letterSpacing: -Math.round(scene.clockSize * 0.035)
                    transform: Translate {
                        id: minSlide
                    }
                    // The minute slides up into place when it changes
                    onTextChanged: minAnim.restart()

                    ParallelAnimation {
                        id: minAnim

                        NumberAnimation {
                            target: minSlide
                            property: "y"
                            from: 6
                            to: 0
                            duration: Style.moveMs
                            easing.type: Style.easeMove
                        }
                        NumberAnimation {
                            target: minTxt
                            property: "opacity"
                            from: 0.35
                            to: 1
                            duration: Style.moveMs
                            easing.type: Style.easeMove
                        }
                    }
                }

                // AM or PM, small, on the line of the digits
                Item {
                    width: period.implicitWidth + 12
                    height: 1

                    Txt {
                        id: period

                        x: 12
                        y: Math.round(scene.clockSize * 1.0 - implicitHeight * 0.82)
                        text: scene.lock.periodText
                        color: Qt.alpha(Colors.foreground, 0.62)
                        font.pixelSize: Math.round(scene.clockSize * 0.16)
                        font.letterSpacing: 2
                    }
                }
            }

            // The date, between two short hairlines
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: Style.spaceLg
                height: dateLine.implicitHeight

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 28
                    height: 1.5
                    radius: 0.75
                    color: Colors.accent
                    opacity: 0.8
                }

                Txt {
                    id: dateLine

                    anchors.verticalCenter: parent.verticalCenter
                    text: scene.lock.dateText
                    color: Qt.alpha(Colors.foreground, 0.7)
                    font.pixelSize: Math.max(12, Math.round(scene.clockSize * 0.11))
                    font.letterSpacing: 4
                    font.capitalization: Font.AllUppercase
                }

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 28
                    height: 1.5
                    radius: 0.75
                    color: Colors.accent
                    opacity: 0.8
                }
            }

            Item {
                width: 1
                height: Math.round(scene.clockSize * 0.3)
            }

            // The greeting
            Txt {
                anchors.horizontalCenter: parent.horizontalCenter
                text: scene.lock.greeting
                color: Colors.foreground
                font.pixelSize: 22
                font.bold: true
                font.letterSpacing: -0.2
            }

            Item {
                width: 1
                height: Style.spaceXs
            }

            // What is going on, in words
            Txt {
                id: statusLine

                anchors.horizontalCenter: parent.horizontalCenter
                text: scene.lock.statusText
                color: scene.lock.statusIsError ? Colors.critical : (scene.lock.succeeded ? Colors.foreground : scene.softText)
                font.pixelSize: Style.fontMd
                onTextChanged: lineFade.restart()

                NumberAnimation {
                    id: lineFade

                    target: statusLine
                    property: "opacity"
                    from: 0.3
                    to: 1
                    duration: Style.moveMs
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
