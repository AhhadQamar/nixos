// LockStage.qml
// What the lock and the login screen show on one screen. Lock.qml and
// Greeter.qml make one of these per screen and hand it the same LockModel, so
// every screen, and both the lock and the login screen, look the same.
//
// The composition is two things side by side. On the left, set against your
// wallpaper, the time: large and light, with the date under it, then a
// greeting and a line saying what is going on. On the right, a large dial that
// bleeds off the edge of the screen like the face of a safe: two rings of fine
// ticks, the launcher's and the screenshot frame's ruler closed into circles,
// an outer ruler and an inner dial, with a 2px accent marker on the side that
// faces the time.
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
    // The dial: its middle (right of centre, so it runs off the edge) and the
    // radius of the outer ruler; the inner dial sits a little inside it
    readonly property real dialX: Math.round(width * 0.8)
    readonly property real dialY: Math.round(height * 0.5)
    readonly property real ringR: Math.round(Math.min(height * 0.46, width * 0.34))
    readonly property real innerR: ringR - 40
    // The time: its left edge, and how large it can be before it meets the dial
    readonly property real textX: Math.round(width * 0.09)
    readonly property int clockSize: Math.round(Math.min(height * 0.2, (dialX - ringR - textX - 70) / 3.3))
    // The outer ruler's ticks sit 10px apart and every fifth is a major, as on
    // the screenshot frame; in whole twenties so the marker, on the side that
    // faces the time, stands on a major. The inner dial has 36, every ninth in
    // the accent.
    readonly property int outerCount: Math.round(twoPi * ringR / 10 / 20) * 20
    readonly property int innerCount: 36
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

    // The shell's dim over it, deepest on the side the time is on and easing
    // off toward the dial, and a little darker toward the foot
    Rectangle {
        anchors.fill: parent

        gradient: Gradient {
            orientation: Gradient.Horizontal

            GradientStop {
                position: 0
                color: Qt.alpha(scene.wash, 0.78)
            }
            GradientStop {
                position: 0.55
                color: Qt.alpha(scene.wash, 0.56)
            }
            GradientStop {
                position: 1
                color: Qt.alpha(scene.wash, 0.4)
            }
        }
    }

    Rectangle {
        anchors.fill: parent

        gradient: Gradient {
            GradientStop {
                position: 0.6
                color: Qt.alpha(scene.wash, 0)
            }
            GradientStop {
                position: 1
                color: Qt.alpha(scene.wash, 0.34)
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

        // The outer ruler: fine ticks, a taller one every fifth, as on the
        // screenshot frame. Drawn once into a texture; turning it is nearly
        // free.
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

                    readonly property bool major: index % 5 === 0

                    x: outerRing.r - width / 2
                    y: 1
                    width: 1.5
                    height: major ? 11 : 6
                    radius: 0.75
                    antialiasing: true
                    color: Qt.alpha(Colors.foreground, major ? 0.42 : 0.22)
                    transform: Rotation {
                        origin.x: width / 2
                        origin.y: outerRing.r - 1
                        angle: index * 360 / scene.outerCount
                    }
                }
            }
        }

        // The inner dial: the small dial of ticks the screenshot tool turns at
        // the middle of a region. 36 ticks, every ninth in the accent. It
        // turns the other way, and is also drawn once.
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

                    readonly property bool major: index % 9 === 0

                    x: innerRing.r - width / 2
                    y: 1
                    width: 1.5
                    height: major ? 11 : 5
                    radius: 0.75
                    antialiasing: true
                    color: major ? Colors.accent : Qt.alpha(Colors.foreground, 0.4)
                    transform: Rotation {
                        origin.x: width / 2
                        origin.y: innerRing.r - 1
                        angle: index * 360 / scene.innerCount
                    }
                }
            }
        }

        // The marker: the screenshot ruler's 2px accent line, on the side of
        // the dial that faces the time, pointing in. It turns red after a
        // refusal.
        Rectangle {
            x: scene.dialX - scene.ringR - 2
            y: scene.dialY - 1
            width: 16
            height: 2
            radius: 1
            color: scene.lock.tone
            opacity: 0.9

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
        // Left-aligned, vertically centred on the dial: a small line saying what
        // this is, the time large and light, the date under it, then the
        // greeting and what is going on. It slides away to the left as the
        // dial opens.
        Column {
            id: block

            x: scene.textX
            y: Math.round(scene.dialY - height / 2)
            spacing: 0
            transform: Translate {
                x: -28 * scene.lock.leave
            }

            // What this screen is
            Txt {
                text: scene.lock.modeLine
                color: Qt.alpha(Colors.foreground, 0.62)
                font.pixelSize: Style.fontSm
                font.letterSpacing: 2
                font.capitalization: Font.AllUppercase
            }

            Item {
                width: 1
                height: Math.round(scene.clockSize * 0.12)
            }

            // The time: large and light
            Row {
                id: timeRow

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
                    width: period.implicitWidth + 14
                    height: 1

                    Txt {
                        id: period

                        x: 14
                        y: Math.round(scene.clockSize * 1.0 - implicitHeight * 0.82)
                        text: scene.lock.periodText
                        color: Qt.alpha(Colors.foreground, 0.62)
                        font.pixelSize: Math.round(scene.clockSize * 0.16)
                        font.letterSpacing: 2
                    }
                }
            }

            // The date, after a short hairline in the accent
            Row {
                spacing: Style.spaceLg
                height: dateLine.implicitHeight

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 36
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
            }

            Item {
                width: 1
                height: Math.round(scene.clockSize * 0.3)
            }

            // The greeting
            Txt {
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
