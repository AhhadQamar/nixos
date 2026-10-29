// LockStage.qml
// What the lock and the login screen show on one screen. Lock.qml and
// Greeter.qml make one of these per screen and hand it the same LockModel, so
// every screen, and both the lock and the login screen, look the same.
//
// The composition is "the corner": a big dial whose middle sits in the
// bottom-right corner of the screen, so only a quarter of it shows. It is two
// rings of the power menu's fine ruler (ticks 12px apart, a taller one every
// fifth and tenth) and one thin marker, and nothing else: no plate, no glow,
// nothing that lights up. Opposite it, on the left, the time is set large and
// light at the top (a small line saying what this is above it, the date under
// it) and the greeting and a line saying what is going on sit at the foot.
//
// It is kept lean because it runs on every screen at once on a laptop's
// graphics: the wallpaper is blurred once at a quarter of the screen size, and
// each ring is drawn once into a texture and only ever turned. Only the part
// of each ring that can be seen is built: a ruler repeats every ten ticks, so
// turning it by any angle looks exactly like turning a short stretch of it by
// that angle modulo one repeat. While the lock waits nothing moves.
//
// There is no password box. Typing only turns the dial: each character
// clicks the outer ring round a little clockwise and the inner one the other
// way, and Backspace turns them back. While the password is checked the outer
// ring creeps round steadily. A wrong password turns the marker red, and the
// rings spring back to the start, going a little past it and settling, with a
// small shake. A right one opens it like a safe: the two dials spin, one each
// way, and come to rest at nought with a tenth tick under the marker, then
// the rings open outwards, one a little ahead of the other, and fade as the
// text slides away to the left.
//
// Keys (an invisible field keeps the keyboard, so typing is never affected):
//   type                the password
//   Enter               check it
//   Esc                 clear what you typed
//
// It reads and writes the LockModel it is given (see LockModel.qml).
//
// Note: an inline component cannot see this file's ids, so everything a
// component needs is handed to it as a property.

import QtQuick
import QtQuick.Effects
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
    readonly property real innerR: ringR - Math.max(22, Math.round(ringR * 0.05))
    // Angles are in degrees, clockwise from straight up: 270 is straight left
    // of the middle and 360 straight up, the two edges of what shows. The
    // marker stands on the diagonal of the quarter, pointing at the middle.
    readonly property real markAng: 315
    // The left margin of the text, and the space above and below it
    readonly property int padX: Math.round(Math.max(48, width * 0.06))
    readonly property int padTop: Math.round(height * 0.13)
    readonly property int padBottom: Math.round(height * 0.12)
    // The time, as large as the screen allows
    readonly property int clockSize: Math.round(Math.min(height * 0.18, width * 0.105))
    // Both rulers: ticks about 12px apart. The count is a multiple of ten so
    // the ruler repeats every ten ticks.
    readonly property int outerCount: Math.max(40, Math.round(2 * Math.PI * ringR / 12 / 10) * 10)
    readonly property int innerCount: Math.max(40, Math.round(2 * Math.PI * innerR / 12 / 10) * 10)
    readonly property real stepO: 360 / outerCount
    readonly property real stepI: 360 / innerCount
    // How far each ruler is turned so that a tenth tick stands under the
    // marker: where it rests, at nought
    readonly property real restO: markAng % (stepO * 10)
    readonly property real restI: markAng % (stepI * 10)
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

    // The rings click round a character at a time: the outer one two ticks
    // clockwise, the inner one three the other way. At nought once it has
    // worked.
    property real outerBase: lock.succeeded ? 0 : Math.min(dotCount, 64) * 2 * stepO
    property real innerBase: lock.succeeded ? 0 : -Math.min(dotCount, 64) * 3 * stepI

    // Clicking round is quick and settles; winding back after a refusal goes a
    // little past the start and settles; the safe opening is slow and long
    Behavior on outerBase {
        NumberAnimation {
            duration: scene.lock.succeeded ? Style.sweepMs : (scene.lock.failed ? Style.enterMs : Style.moveMs)
            easing.type: scene.lock.succeeded ? Style.easeEnter : (scene.lock.failed ? Easing.OutBack : Style.easeMove)
            easing.overshoot: 1.6
        }
    }

    Behavior on innerBase {
        NumberAnimation {
            duration: scene.lock.succeeded ? Style.sweepMs : (scene.lock.failed ? Style.enterMs : Style.moveMs)
            easing.type: scene.lock.succeeded ? Style.easeEnter : (scene.lock.failed ? Easing.OutBack : Style.easeMove)
            easing.overshoot: 1.6
        }
    }

    // While the password is checked the outer ring creeps round: one repeat
    // of the ruler a lap. A ruler repeats, so it looks the same at the end of
    // a lap as at the start, and it can stop on either without a jump.
    property real crawlU: 0

    NumberAnimation {
        id: crawlAnim

        target: scene
        property: "crawlU"
        from: 0
        to: 1
        duration: 1200
        loops: Animation.Infinite
        easing.type: Easing.Linear
    }

    NumberAnimation {
        id: crawlSettle

        target: scene
        property: "crawlU"
        duration: Style.moveMs
        easing.type: Style.easeMove
    }

    // The safe: when the password is right the two dials spin, the outer one a
    // full turn clockwise and the inner one two turns back, slowing as they
    // come to rest at nought under the marker. 0 to 1.
    property real spin: 0

    NumberAnimation {
        id: spinAnim

        target: scene
        property: "spin"
        from: 0
        to: 1
        duration: Style.sweepMs
        easing.type: Style.easeEnter
    }

    Connections {
        target: scene.lock

        function onSucceededChanged() {
            if (scene.lock.succeeded) {
                spinAnim.restart();
            } else {
                spinAnim.stop();
                scene.spin = 0;
            }
        }

        function onCheckingChanged() {
            if (scene.lock.checking) {
                crawlSettle.stop();
                scene.crawlU = 0;
                crawlAnim.restart();
            } else {
                crawlAnim.stop();
                crawlSettle.from = scene.crawlU;
                crawlSettle.to = scene.crawlU >= 0.5 ? 1 : 0;
                crawlSettle.restart();
            }
        }
    }

    // What each ring shows: its turn, the swing in as the dial arrives, the
    // creep while checking and the spin of the safe
    readonly property real outerA: restO + outerBase + (1 - lock.reveal) * 10 + crawlU * stepO * 10 + 360 * spin
    readonly property real innerA: restI + innerBase - (1 - lock.reveal) * 14 - 720 * spin

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

        // Where the middle of the dial is (in the parent), the radius of the
        // ticks, how many there are in a whole turn (a multiple of ten), how
        // far it is turned (degrees), how strong it is and how far it has
        // opened outwards (0 to 1)
        property real dialX: 0
        property real dialY: 0
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

        x: dialX - mid
        y: dialY - mid
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

                x: ruler.mid + (ruler.r - 1) * Math.sin(a * Math.PI / 180) - 0.75
                y: ruler.mid - (ruler.r - 1) * Math.cos(a * Math.PI / 180)
                width: 1.5
                height: major ? 13 : (half ? 9 : 5)
                radius: 0.75
                antialiasing: true
                transformOrigin: Item.Top
                rotation: a
                color: Qt.alpha(Colors.foreground, (major ? 1 : (half ? 0.85 : 0.65)) * ruler.ink)
            }
        }
    }

    // ---- The lock ---------------------------------------------------------
    // It fades in and out and shakes after a refusal
    Item {
        id: stage

        anchors.fill: parent
        opacity: scene.lock.reveal * (1 - scene.lock.leave)
        // It rises a little as it arrives, and shakes after a refusal
        transform: Translate {
            x: scene.lock.shakeX
            y: (1 - scene.lock.reveal) * 8
        }

        // The outer ruler. It opens outwards as it leaves, a little ahead of
        // the inner one.
        Ruler {
            dialX: scene.dialX
            dialY: scene.dialY
            r: scene.ringR
            count: scene.outerCount
            turn: scene.outerA
            open: 0.14 * scene.lock.leave
        }

        // The inner ruler: the same ruler a little inside and fainter, so the
        // two read as two. It turns the other way.
        Ruler {
            dialX: scene.dialX
            dialY: scene.dialY
            r: scene.innerR
            count: scene.innerCount
            turn: scene.innerA
            ink: 0.85
            open: 0.07 * scene.lock.leave
        }

        // The fine marker on the ruler, on the diagonal of the quarter,
        // pointing in. It turns red after a refusal.
        Rectangle {
            x: scene.dialX + scene.ringR * Math.sin(scene.markAng * Math.PI / 180) - width / 2
            y: scene.dialY - scene.ringR * Math.cos(scene.markAng * Math.PI / 180)
            width: 2
            height: 20
            radius: 1
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

            // The date
            Txt {
                id: dateLine

                text: scene.lock.dateText
                color: Qt.alpha(Colors.foreground, 0.7)
                font.pixelSize: Math.max(12, Math.round(scene.clockSize * 0.11))
                font.letterSpacing: 4
                font.capitalization: Font.AllUppercase
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
