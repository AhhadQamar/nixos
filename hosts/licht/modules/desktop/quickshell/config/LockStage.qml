// LockStage.qml
// What the lock and the login screen show on one screen. Lock.qml and
// Greeter.qml make one of these per screen and hand it the same LockModel, so
// every screen, and both the lock and the login screen, look the same.
//
// The composition is "the corner": one enormous dial whose middle sits in the
// bottom-right corner of the screen, so only a quarter of it shows, sweeping
// from the top of the right edge down to the foot of the screen. It has the
// power menu's fine ruler (the same ticks, the same spacing, a taller one every
// fifth and tenth) in two rings, an outer ruler and an inner one turning the
// other way, on a quarter of bar-style glass with a hairline outline, with the
// same fine marker and soft bead, a feathered shade and a soft light in the
// colour of the highlight. Opposite it, on the left, the time is set large and
// light at the top (a small line saying what this is above it, the date under
// it) and the greeting and a line saying what is going on sit at the foot.
//
// It is kept lean because it runs on every screen at once on a laptop's
// graphics: the wallpaper is blurred once at a quarter of the screen size, and
// each ring is drawn once into a texture and only ever turned. Only the part of
// each ring that can be seen is built: a ruler repeats every ten ticks, so
// turning it by any angle looks exactly like turning a short stretch of it by
// that angle modulo one repeat. That is a couple of hundred ticks and a small
// texture instead of a thousand ticks and a texture the size of the whole
// dial. Everything that moves is an angle, a size or a fade, and moves at the
// shell's speeds.
//
// There is no password box. Typing shows almost nothing: the two rings turn a
// little, the outer one clockwise and the inner one back, a character at a
// time, and Backspace turns them back. A wrong password lets them wind back to
// nought, with a small shake and the marker turning red. A right one opens it
// like a safe: the two dials spin round, one each way, and come to rest at
// nought under the marker, then the rings open outwards, one a little ahead of
// the other, and fade as the text slides away to the left.
//
// One taller tick on the outer ring goes up the quarter once a minute, from
// the foot of the screen to the top of the right edge: the seconds. While the
// lock waits it is the only thing that moves.
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

    // Nothing of the dial may draw outside the screen
    clip: true

    // ---- Layout ---------------------------------------------------------
    // The dial: its middle is the bottom-right corner of the screen, and the
    // radius of the outer ruler reaches nearly to the top and to the middle of
    // the foot, whatever the shape of the screen
    readonly property real dialX: width
    readonly property real dialY: height
    readonly property real ringR: Math.round(Math.min(height * 0.9, width * 0.5))
    readonly property real innerR: ringR - Math.max(10, Math.round(ringR * 0.05))
    // The glass plate reaches a little past the outer ruler
    readonly property real plateR: ringR + 8
    // The marker sits on the diagonal of the quarter, pointing in at the
    // middle of the dial. Angles are in degrees, clockwise from straight up:
    // 270 is straight left of the middle and 360 straight up, the two edges of
    // what shows.
    readonly property real markAng: 315
    // The left margin of the text, and the space above and below it
    readonly property int padX: Math.round(Math.max(48, width * 0.06))
    readonly property int padTop: Math.round(height * 0.13)
    readonly property int padBottom: Math.round(height * 0.12)
    // The time, as large as the screen allows
    readonly property int clockSize: Math.round(Math.min(height * 0.18, width * 0.105))
    // Both rulers are the power menu's: ticks about 12px apart, a taller one
    // every fifth and every tenth. The count is a multiple of ten so the ruler
    // repeats every ten ticks.
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

    // A deeper veil down the left, behind the text, so it reads on any
    // wallpaper without a box around it
    Rectangle {
        anchors.fill: parent

        gradient: Gradient {
            orientation: Gradient.Horizontal

            GradientStop {
                position: 0
                color: Qt.alpha(scene.wash, 0.5)
            }
            GradientStop {
                position: 0.5
                color: Qt.alpha(scene.wash, 0.16)
            }
            GradientStop {
                position: 1
                color: Qt.alpha(scene.wash, 0)
            }
        }
    }

    // ---- A ruler ----------------------------------------------------------
    // One ring of the dial. Only the stretch of it that can be seen is built
    // (the quarter that falls on the screen, and a little either side so
    // turning it never shows a gap). The ruler repeats every ten ticks, so it
    // is turned by `turn` modulo that repeat, which looks the same as turning
    // the whole ring. It is drawn once into a texture and only ever turned.
    component Ruler: Item {
        id: ruler

        // Radius of the ticks, how many there are in a whole turn (a multiple
        // of ten), how far it is turned (degrees), how strong it is and how
        // far it has opened outwards (0 to 1)
        property real r: 100
        property int count: 40
        property real turn: 0
        property real ink: 1
        property real open: 0

        // The middle of the dial within this item, and room on the far sides of
        // it for the ticks that lie just past the edges of the screen
        readonly property real pad: 4
        readonly property real mid: r + pad
        readonly property real step: 360 / count
        readonly property real period: 3600 / count
        readonly property real ex: Math.ceil(r * Math.sin(Math.min(80, step * 14) * Math.PI / 180)) + 8
        // Which ticks are built: from a repeat before the left edge of the
        // screen to a couple past the top one
        readonly property int first: Math.round(count * 0.75) - 12
        readonly property int built: Math.ceil(count / 4) + 14

        x: scene.dialX - mid
        y: scene.dialY - mid
        width: mid + ex
        height: mid + ex
        layer.enabled: true
        layer.smooth: true
        layer.textureSize: Qt.size(width * 1.5, height * 1.5)
        transform: [
            Rotation {
                origin.x: ruler.mid
                origin.y: ruler.mid
                angle: ((ruler.turn % ruler.period) + ruler.period) % ruler.period
            },
            Scale {
                origin.x: ruler.mid
                origin.y: ruler.mid
                xScale: 1 + ruler.open
                yScale: 1 + ruler.open
            }
        ]

        Repeater {
            model: ruler.built

            delegate: Rectangle {
                required property int index

                readonly property int tick: ruler.first + index
                readonly property real a: tick * ruler.step
                readonly property bool major: tick % 10 === 0
                readonly property bool half: tick % 5 === 0

                x: ruler.mid + (ruler.r - 1) * Math.sin(a * Math.PI / 180) - 0.5
                y: ruler.mid - (ruler.r - 1) * Math.cos(a * Math.PI / 180)
                width: 1
                height: major ? 9 : (half ? 6 : 3)
                radius: 0.5
                antialiasing: true
                transformOrigin: Item.Top
                rotation: a
                color: Qt.alpha(Colors.foreground, (major ? 0.95 : (half ? 0.7 : 0.5)) * ruler.ink)
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

        // A soft dark pool in the corner behind the dial, with no visible
        // edge, so the ticks read on any wallpaper
        Shape {
            id: shade

            readonly property real r: scene.ringR * 1.2

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
                        position: 0.8
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

        // Wide, low light in the corner in the colour of the highlight, as the
        // power menu puts on its horizon
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
                        color: Qt.alpha(scene.lock.tone, 0.12)
                    }
                    GradientStop {
                        position: 0.6
                        color: Qt.alpha(scene.lock.tone, 0.05)
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
            opacity: 0.4
            border.width: 1
            border.color: Style.outline
            // Swells a little as the dial opens
            scale: 1 + 0.1 * scene.lock.leave
        }

        Rectangle {
            readonly property real r: scene.innerR - Math.max(22, Math.round(scene.ringR * 0.035))

            width: r * 2
            height: width
            x: scene.dialX - width / 2
            y: scene.dialY - height / 2
            radius: width / 2
            color: "transparent"
            border.width: 1
            border.color: Style.outline
            scale: 1 + 0.1 * scene.lock.leave
        }

        // The outer ruler, a taller tick every fifth and tenth. Opens outwards
        // as it leaves, a little ahead of the inner one.
        Ruler {
            r: scene.ringR
            count: scene.outerCount
            turn: scene.outerA
            ink: 1
            open: 0.18 * scene.lock.leave
        }

        // The inner ruler: the same ruler a little inside, a touch fainter so
        // the two read as two. It turns the other way.
        Ruler {
            r: scene.innerR
            count: scene.innerCount
            turn: scene.innerA
            ink: 0.74
            open: 0.1 * scene.lock.leave
        }

        // The fine marker on the ruler, with a soft bead at its foot, exactly
        // as on the power menu's: on the diagonal of the quarter, pointing in.
        // Both turn red after a refusal.
        Rectangle {
            x: scene.dialX + scene.ringR * Math.sin(scene.markAng * Math.PI / 180) - width / 2
            y: scene.dialY - scene.ringR * Math.cos(scene.markAng * Math.PI / 180)
            width: 1.5
            height: 12
            radius: 0.5
            antialiasing: true
            transformOrigin: Item.Top
            rotation: scene.markAng
            color: scene.lock.tone

            Behavior on color {
                ColorAnimation {
                    duration: Style.moveMs
                }
            }
        }

        Rectangle {
            readonly property real br: scene.ringR - 16

            x: scene.dialX + br * Math.sin(scene.markAng * Math.PI / 180) - width / 2
            y: scene.dialY - br * Math.cos(scene.markAng * Math.PI / 180) - height / 2
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

        // The seconds: one taller accent tick on the outer ring, going up the
        // quarter once a minute, from the foot of the screen to the top of the
        // right edge. It wakes once a second, and only while it shows, and
        // fades at either end so it never jumps.
        SystemClock {
            id: secClock

            precision: SystemClock.Seconds
            enabled: scene.lock.reveal > 0.01 && !scene.lock.succeeded
        }

        Rectangle {
            readonly property int sec: secClock.date.getSeconds()
            readonly property real ang: 270 + sec * 1.5

            x: scene.dialX + scene.ringR * Math.sin(ang * Math.PI / 180) - width / 2
            y: scene.dialY - scene.ringR * Math.cos(ang * Math.PI / 180)
            width: 2
            height: 16
            radius: 1
            antialiasing: true
            transformOrigin: Item.Top
            rotation: ang
            color: Colors.accent
            opacity: scene.lock.succeeded ? 0 : 0.7 * Math.min(1, sec / 2, (60 - sec) / 2)
        }

        // ---- The time ------------------------------------------------------
        // Top left: a small line saying what this is, the time large and
        // light, and the date under it after a short hairline. It slides in
        // from the left as the screen arrives and away to the left as it
        // leaves.
        Column {
            id: block

            x: scene.padX
            y: scene.padTop
            spacing: 0
            transform: Translate {
                x: -16 * (1 - scene.lock.reveal) - 24 * scene.lock.leave
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
                height: Math.round(scene.clockSize * 0.1)
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

            Item {
                width: 1
                height: Math.round(scene.clockSize * 0.04)
            }

            // The date, after a short hairline in the accent
            Row {
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
            }
        }

        // ---- The greeting --------------------------------------------------
        // Bottom left, on the same margin: the greeting and what is going on,
        // in words.
        Column {
            id: foot

            x: scene.padX
            y: scene.height - scene.padBottom - height
            spacing: Style.spaceXs
            transform: Translate {
                x: -16 * (1 - scene.lock.reveal) - 24 * scene.lock.leave
            }

            Txt {
                text: scene.lock.greeting
                color: Colors.foreground
                font.pixelSize: Math.max(22, Math.round(scene.clockSize * 0.15))
                font.bold: true
                font.letterSpacing: -0.2
            }

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
