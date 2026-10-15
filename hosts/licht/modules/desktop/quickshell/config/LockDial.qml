// LockDial.qml
// What the lock shows on one screen, in the shell's dial language (see
// Polkit.qml, which this follows closely). Lock.qml makes one of these for
// every screen and keeps all the state, so every screen moves as one.
//
// The backdrop is your wallpaper, blurred, light at the top and darker toward
// the foot. The time is the hero of the screen: big, with the colon breathing
// and the day under it. A borderless stage rises from the bottom edge: one
// glass disc on the dial, holding your picture (a lock if there is none) and
// ringed in the accent, with a thin arc around it that is the seconds. The
// fine ruler curves across the whole width of the screen over it. Below the
// ruler a small head line greets you, and the password pill floats above the
// bottom edge.
// The ruler is the state, and it answers your keys. Each key you type turns it
// a little (Backspace turns it back). It scans while PAM checks, flushes red
// on a wrong password (and the disc shakes), and fills green from the middle
// to both edges on a right one, after which the dial curls away and the lock
// opens.
// There is nothing to click and no buttons: the only thing to do is type.
//
// Like the launcher it arrives as a rainbow: the disc and the ruler swing in
// from the left over a tight dome, washed with the wallpaper's colours, and
// unfurl into the calm dial. Closing plays it in reverse.

import QtQuick
import QtQuick.Effects
import QtQuick.Shapes

Item {
    id: dial

    // The lock this screen shows (Lock.qml): every screen reads the same state
    required property var lock

    // ---- Settings -------------------------------------------------------
    // The ruler and the glow use the whole width; the words and the pill keep
    // to a narrower column in the middle
    readonly property int contentW: Math.min(780, Math.round(width * 0.9))
    readonly property int topY: 62
    readonly property int ruleDrop: 50
    readonly property int ruleY: topY + ruleDrop
    // A gentle arc across the screen: wide enough that its edges drop only a
    // little, whatever the screen
    readonly property real dialR: Math.max(900, width * 1.6)
    // The dome the dial starts as when it opens (and ends as when it closes)
    readonly property real rainbowR: 360
    // Pixels per slot: only turns the arrival swing (spinIn) into distance
    readonly property real stepPx: 76
    readonly property int discSize: 88
    readonly property int tickGap: 12
    readonly property int tickN: Math.ceil(width / tickGap) + 24

    // Radius of the dial right now: curvature eases from the dome to the dial
    readonly property real dialNow: 1 / (1 / dialR + (1 / rainbowR - 1 / dialR) * lock.fan)

    // ---- Layout of what is under the dial ---------------------------------
    readonly property int readoutTop: ruleY + 30
    readonly property int pillH: Style.fieldHeight
    // The pill floats above the bottom edge. The stage is also tall enough for
    // the far ends of the ruler, which droop a little.
    readonly property int foot: 56
    readonly property real pillY: readoutTop + readout.height + 14
    readonly property real bodyH: pillY + pillH + foot
    // The background colour with a breath of the accent, for the washes
    readonly property color wash: Qt.tint(Colors.background, Qt.alpha(Colors.accent, 0.08))

    // ---- Helpers --------------------------------------------------------
    function clamp(v, a, b) {
        return Math.max(a, Math.min(b, v));
    }

    function mod(a, b) {
        return ((a % b) + b) % b;
    }

    // Ease-out with a small overshoot for the arrival of the disc (0..1 in,
    // about 1.04 at the peak): the shell's `pop`, kept gentle.
    function backOut(t) {
        const c1 = 0.8;
        const u = t - 1;
        return 1 + (c1 + 1) * u * u * u + c1 * u * u;
    }

    // Staggered arrival: 0 until `from`, 1 at `to` (in reveal units).
    function stage_(from, to) {
        return clamp((lock.reveal - from) / (to - from), 0, 1);
    }

    // `base` washed with one of the palette's colours, chosen by screen
    // position x (colour1 on the left through colour6 on the right). The wash
    // is `fan` strong, so it only shows while the dial is arriving or leaving.
    function spectral(base, x, a) {
        const ramp = [Colors.color1, Colors.color2, Colors.color3, Colors.color4, Colors.color5, Colors.color6];
        const t = (clamp((x - stage.width / 2) / (stage.width * 0.34), -1, 1) * 0.5 + 0.5) * (ramp.length - 1);
        const i = Math.min(ramp.length - 2, Math.floor(t));
        const c = Qt.tint(ramp[i], Qt.alpha(ramp[i + 1], t - i));
        return Qt.alpha(Qt.tint(base, Qt.alpha(c, 0.9 * lock.fan)), a);
    }

    // ---- Backdrop: the wallpaper, blurred ---------------------------------
    // A blurred picture needs no detail, so the image is read and blurred at a
    // quarter of the screen size and scaled up: the same look for a sixteenth
    // of the work, which matters on a laptop's integrated graphics.
    Item {
        id: backdrop

        width: Math.round(dial.width / 4)
        height: Math.round(dial.height / 4)
        scale: 4
        transformOrigin: Item.TopLeft
        // Fades in once it has loaded; until then the surface's own
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
            source: dial.lock.wallpaper !== "" ? "file://" + dial.lock.wallpaper : ""
            asynchronous: true
            fillMode: Image.PreserveAspectCrop
            sourceSize: Qt.size(backdrop.width, backdrop.height)
        }
    }

    // A wash of the background colour over it: light at the top, where the
    // time sits and the wallpaper can show, and darker toward the foot, where
    // the stage needs the calm
    Rectangle {
        anchors.fill: parent

        gradient: Gradient {
            GradientStop {
                position: 0
                color: Qt.alpha(dial.wash, 0.3)
            }
            GradientStop {
                position: 0.55
                color: Qt.alpha(dial.wash, 0.5)
            }
            GradientStop {
                position: 1
                color: Qt.alpha(dial.wash, 0.82)
            }
        }
    }

    // ---- The hero: the time -----------------------------------------------
    // Big enough to read from across the room. The colon breathes with the
    // disc's ring and takes the colour of the moment.
    Item {
        id: hero

        // A dial read-out, so the size is a one-off (it follows the screen)
        readonly property int size: Math.round(dial.height * 0.17)

        anchors.horizontalCenter: parent.horizontalCenter
        y: Math.round(dial.height * 0.13)
        width: timeRow.implicitWidth
        height: timeRow.implicitHeight + dateLine.implicitHeight
        // Clicks pass through to the stage
        enabled: false
        opacity: dial.stage_(0.2, 0.75)
        transform: Translate {
            y: (1 - dial.stage_(0.2, 0.75)) * 24
        }

        Row {
            id: timeRow

            anchors.horizontalCenter: parent.horizontalCenter

            Txt {
                text: dial.lock.hourText
                color: Colors.foreground
                style: Text.Outline
                styleColor: Qt.alpha(Colors.background, 0.8)
                font.pixelSize: hero.size
            }

            Txt {
                text: ":"
                color: dial.lock.tone
                opacity: 0.35 + 0.65 * dial.lock.breath
                style: Text.Outline
                styleColor: Qt.alpha(Colors.background, 0.8)
                font.pixelSize: hero.size
            }

            Txt {
                text: dial.lock.minuteText
                color: Colors.foreground
                style: Text.Outline
                styleColor: Qt.alpha(Colors.background, 0.8)
                font.pixelSize: hero.size
            }
        }

        Txt {
            id: dateLine

            anchors.top: timeRow.bottom
            anchors.horizontalCenter: parent.horizontalCenter
            text: dial.lock.dateText
            color: Qt.alpha(Colors.foreground, 0.85)
            style: Text.Outline
            styleColor: Qt.alpha(Colors.background, 0.8)
            font.pixelSize: Math.round(hero.size * 0.17)
            font.letterSpacing: 3
            font.capitalization: Font.AllUppercase
        }
    }

    // ---- Stage ------------------------------------------------------------
    Item {
        id: stage

        readonly property real cx: width / 2

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        width: dial.width
        height: dial.bodyH
        clip: true
        opacity: Math.min(1, dial.lock.reveal * 3)
        transform: Translate {
            y: (1 - dial.lock.reveal) * (stage.height + 40)
        }

        // Pressing anywhere on the stage gives the keyboard back to the
        // password field
        MouseArea {
            anchors.fill: parent
            onPressed: pw.forceActiveFocus()
        }

        // Feathered backing: a soft dark ellipse keeps the words and the
        // scale readable over any wallpaper without a visible panel edge. It
        // sits in the middle column, not the whole width.
        Item {
            anchors.horizontalCenter: parent.horizontalCenter
            width: dial.contentW
            height: parent.height

            StageShade {
                yScale: 0.62
            }
        }

        // Low light on the horizon, wide as the screen, in the colour of the
        // moment: the accent, red after a refusal, green once it has worked.
        Shape {
            id: horizon

            readonly property real r: stage.width * 0.4

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
                        color: Qt.alpha(dial.lock.tone, 0.18)
                    }
                    GradientStop {
                        position: 0.5
                        color: Qt.alpha(dial.lock.tone, 0.07)
                    }
                    GradientStop {
                        position: 1
                        color: Qt.alpha(dial.lock.tone, 0)
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

        // ---- The ruler: fine ticks curving across the screen over the disc.
        // The ones by the middle rise like a magnifier; the rest of the ruler
        // shows the state (a scan while checking, red after a refusal, green
        // filling outward from the middle on success). Typing turns it. -----
        Repeater {
            model: dial.tickN

            delegate: Rectangle {
                id: tick

                required property int index

                readonly property real s: (index - dial.tickN / 2) * dial.tickGap - dial.mod(-dial.lock.spinIn * dial.stepPx * 0.5 + dial.lock.turn, dial.tickGap * 10)
                readonly property real a: s / dial.dialNow
                readonly property real rr: dial.dialNow - dial.ruleDrop
                readonly property bool major: index % 10 === 0
                // The magnifier by the middle, and the scan going past
                readonly property real near: Math.max(0, 1 - Math.abs(s) / 90)
                readonly property real wave: Math.max(0, 1 - Math.abs(x - stage.cx - dial.lock.scan * stage.width / 2) / 90) * dial.lock.scanOn
                readonly property real hot: Math.max(near, wave)
                // 1 once the green has reached this tick
                readonly property real okMix: dial.clamp((dial.lock.okFill * 1.35 - Math.abs(x - stage.cx) / (stage.width / 2)) / 0.35, 0, 1)
                // Ticks the state is lighting get more solid
                readonly property real solid: {
                    const rest = major ? 0.46 : 0.28;
                    return rest + (1 - rest) * Math.max(0.7 * hot, 0.6 * dial.lock.flush, 0.85 * okMix);
                }
                readonly property color hue: Qt.tint(Qt.tint(Qt.tint(Colors.foreground, Qt.alpha(Colors.accent, 0.7 * hot)), Qt.alpha(Colors.critical, 0.85 * dial.lock.flush)), Qt.alpha(Colors.success, 0.95 * okMix))

                x: stage.cx + rr * Math.sin(a) - 0.75
                y: dial.topY + dial.dialNow - rr * Math.cos(a)
                width: 1.5
                height: (major ? 9 : 5) + 6 * hot + 4 * okMix
                radius: 0.75
                antialiasing: true
                visible: Math.abs(a) < 1.2
                transformOrigin: Item.Top
                rotation: a * 180 / Math.PI
                color: dial.spectral(hue, x, solid)
                opacity: dial.clamp((stage.cx - Math.abs(x - stage.cx)) / 240, 0, 1) * dial.clamp(dial.lock.reveal * 2 - Math.abs(x - stage.cx) / stage.cx * 0.9, 0, 1)
            }
        }

        // The middle of the ruler: the 2px marker, in the colour of the moment
        Rectangle {
            x: stage.cx - 1
            y: dial.ruleY - 3
            width: 2
            height: 16
            radius: 1
            color: dial.lock.tone
            opacity: dial.clamp(dial.lock.reveal * 2 - 0.5, 0, 1)
        }

        // ---- The disc: your picture, or a lock --------------------------
        Item {
            id: disc

            // Swung left while arriving, right while leaving
            readonly property real s: -dial.lock.spinIn * dial.stepPx
            readonly property real a: s / dial.dialNow
            readonly property real px: stage.cx + dial.dialNow * Math.sin(a)
            // It lifts a little off the dial, like a selected disc
            readonly property real py: dial.topY + dial.dialNow * (1 - Math.cos(a)) - 5
            readonly property real appear: dial.stage_(0.1, 0.6)
            readonly property real edge: dial.clamp((stage.cx - Math.abs(px - stage.cx)) / 90, 0, 1)
            // The seconds, as degrees of the arc. It steps once a second like
            // a watch; the wrap back to zero snaps.
            property real secSweep: dial.lock.secFrac * 360

            Behavior on secSweep {
                enabled: dial.lock.secFrac > 0.005

                NumberAnimation {
                    duration: Style.moveMs
                    easing.type: Style.easeMove
                }
            }

            width: dial.discSize
            height: dial.discSize
            x: px - width / 2 + dial.lock.shakeX
            y: py - height / 2
            z: 20
            opacity: appear * edge
            scale: 0.55 + 0.45 * dial.backOut(appear)
            // Tilts along the dial, and rises from below as it arrives
            rotation: a * 180 / Math.PI * 0.6
            transform: Translate {
                y: (1 - disc.appear) * 30
            }

            // Ring that leaves the disc: on a refusal (red) and on success
            // (green)
            Rectangle {
                anchors.centerIn: parent
                width: parent.width + 14 + 34 * dial.lock.ring
                height: width
                radius: width / 2
                color: "transparent"
                antialiasing: true
                visible: dial.lock.ring > 0.001 && dial.lock.ring < 0.999
                border.width: 1.5
                border.color: Qt.alpha(dial.lock.tone, 0.5 * (1 - dial.lock.ring))
            }

            // The seconds: a thin arc round the disc, filling once a minute
            Shape {
                id: secArc

                anchors.centerIn: parent
                width: parent.width + 24
                height: width
                layer.enabled: true
                layer.samples: 4

                ShapePath {
                    strokeColor: Qt.alpha(dial.lock.tone, 0.55)
                    strokeWidth: 2
                    fillColor: "transparent"
                    capStyle: ShapePath.RoundCap

                    PathAngleArc {
                        centerX: secArc.width / 2
                        centerY: secArc.height / 2
                        radiusX: secArc.width / 2 - 1
                        radiusY: secArc.height / 2 - 1
                        startAngle: -90
                        sweepAngle: disc.secSweep
                    }
                }
            }

            // Breathing ring around the disc.
            Rectangle {
                anchors.centerIn: parent
                width: parent.width + 12
                height: width
                radius: width / 2
                color: "transparent"
                antialiasing: true
                border.width: 1
                border.color: Qt.alpha(dial.lock.tone, 0.25 + 0.25 * dial.lock.breath)
            }

            // Glass, like the bar: one flat surface with a hairline outline
            // in the colour of the moment (washed with the palette while the
            // dial arrives).
            Rectangle {
                anchors.fill: parent
                radius: width / 2
                antialiasing: true
                color: Style.card
                border.width: 1
                border.color: dial.spectral(dial.lock.tone, disc.px, 0.9)
            }

            // The soft tint inside the glass
            Rectangle {
                anchors.fill: parent
                anchors.margins: 1
                radius: width / 2
                antialiasing: true
                color: Qt.alpha(dial.lock.tone, Style.tintAlpha)
            }

            // Light catching the top edge, as on the bar
            Rectangle {
                anchors.top: parent.top
                anchors.topMargin: 1
                anchors.horizontalCenter: parent.horizontalCenter
                width: parent.width * 0.5
                height: 1

                gradient: Gradient {
                    orientation: Gradient.Horizontal

                    GradientStop {
                        position: 0
                        color: Qt.alpha(Colors.foreground, 0)
                    }
                    GradientStop {
                        position: 0.5
                        color: Qt.alpha(Colors.foreground, 0.12)
                    }
                    GradientStop {
                        position: 1
                        color: Qt.alpha(Colors.foreground, 0)
                    }
                }
            }

            // Your picture, set into the glass; it stays upright while the
            // disc tilts with the dial
            Photo {
                id: face

                anchors.fill: parent
                anchors.margins: 5
                radius: width / 2
                source: dial.lock.avatar !== "" ? "file://" + dial.lock.avatar : ""
                visible: status === Image.Ready && !dial.lock.succeeded
                rotation: -disc.rotation
            }

            // Or a lock (no picture); a tick once it has worked
            Txt {
                anchors.centerIn: parent
                visible: !face.visible
                text: dial.lock.succeeded ? Icons.check : Icons.lock
                color: dial.lock.tone
                font.pixelSize: disc.width * 0.38
                rotation: -disc.rotation
            }
        }

        // Underline under the disc; it breathes with the ring.
        Rectangle {
            width: 20 + 10 * dial.lock.breath
            height: 2
            radius: 1
            color: dial.lock.tone
            x: disc.px - width / 2 + dial.lock.shakeX
            y: disc.py + dial.discSize / 2 + 6
            rotation: disc.a * 180 / Math.PI
            opacity: dial.clamp(dial.lock.reveal * 2 - 0.6, 0, 1)
        }

        // ---- The middle: a greeting, and what went wrong ------------------
        Item {
            id: readout

            x: stage.cx - width / 2
            y: dial.readoutTop
            width: Math.min(520, stage.width - 48)
            height: readCol.implicitHeight
            // Clicks pass through to the stage
            enabled: false
            opacity: dial.stage_(0.25, 0.8)
            transform: Translate {
                y: (1 - dial.stage_(0.25, 0.8)) * 12
            }

            Column {
                id: readCol

                width: parent.width
                spacing: Style.spaceXs

                // A greeting
                Txt {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                    text: dial.lock.succeeded ? "Unlocked" : dial.lock.greeting
                    // Brighter than the muted grey, with a thin outline in the
                    // background colour: it stays readable over any wallpaper
                    color: dial.lock.succeeded ? Colors.success : Qt.alpha(Colors.foreground, 0.78)
                    style: Text.Outline
                    styleColor: Qt.alpha(Colors.background, 0.85)
                    font.pixelSize: Style.fontSm
                    font.letterSpacing: 1.4
                    font.capitalization: Font.AllUppercase
                }

                // What went wrong. The line is always there, so the dial
                // never jumps.
                Item {
                    width: parent.width
                    height: 18

                    Txt {
                        width: parent.width
                        height: parent.height
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        elide: Text.ElideRight
                        text: dial.lock.broken ? "Could not check the password." : (dial.lock.failed ? "Incorrect password. Try again." : (dial.lock.checking ? "Checking\u2026" : ""))
                        color: (dial.lock.broken || dial.lock.failed) ? Colors.critical : Colors.muted
                        style: Text.Outline
                        styleColor: Qt.alpha(Colors.background, 0.8)
                        font.pixelSize: Style.fontMd
                        opacity: text !== "" ? 1 : 0

                        Behavior on opacity {
                            NumberAnimation {
                                duration: Style.fadeMs
                            }
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

        // ---- The password pill, at the foot -------------------------------
        // The shell's SearchField on a glass backing, so it reads on any
        // wallpaper.
        Item {
            id: pill

            // Dimmed once it has worked
            property real dim: dial.lock.succeeded ? 0.5 : 1

            x: stage.cx - width / 2
            y: dial.pillY
            width: Math.min(340, stage.width - 48)
            height: dial.pillH
            opacity: dial.stage_(0.4, 0.95) * dim
            transform: Translate {
                y: (1 - dial.stage_(0.4, 0.95)) * 10
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
                color: Style.surface
                border.width: 1
                // Red after a refusal (the field is empty again, so the
                // field's own edge does not cover it)
                border.color: (dial.lock.failed || dial.lock.broken) ? Qt.alpha(Colors.critical, 0.7) : Style.outline

                Behavior on border.color {
                    ColorAnimation {
                        duration: Style.baseMs
                    }
                }
            }

            // Light catching the top edge, as on the bar
            Rectangle {
                anchors.top: parent.top
                anchors.topMargin: 1
                anchors.horizontalCenter: parent.horizontalCenter
                width: parent.width - parent.height
                height: 1

                gradient: Gradient {
                    orientation: Gradient.Horizontal

                    GradientStop {
                        position: 0
                        color: Qt.alpha(Colors.foreground, 0)
                    }
                    GradientStop {
                        position: 0.5
                        color: Qt.alpha(Colors.foreground, 0.12)
                    }
                    GradientStop {
                        position: 1
                        color: Qt.alpha(Colors.foreground, 0)
                    }
                }
            }

            SearchField {
                id: pw

                anchors.fill: parent
                glyph: Icons.lock
                placeholder: "Password"
                // The lock breathes while PAM checks
                busy: dial.lock.checking
                clearable: false

                // Every screen's field follows the one shared password, so
                // what is typed on one shows on the other
                onTextChanged: {
                    if (text !== dial.lock.password)
                        dial.lock.password = text;
                }
                Keys.onReturnPressed: dial.lock.submit()
                Keys.onEnterPressed: dial.lock.submit()
            }

            Connections {
                function onPasswordChanged() {
                    if (pw.text !== dial.lock.password)
                        pw.text = dial.lock.password;
                }

                target: dial.lock
            }

            // A password field is a TextInput that hides what you type and
            // takes no suggestions. Read-only rather than disabled, so it
            // keeps the cursor.
            Binding {
                target: pw.input
                property: "echoMode"
                value: TextInput.Password
            }
            Binding {
                target: pw.input
                property: "readOnly"
                value: dial.lock.checking || dial.lock.succeeded
            }

            Component.onCompleted: {
                pw.input.passwordCharacter = "\u2022";
                pw.input.inputMethodHints = Qt.ImhSensitiveData | Qt.ImhNoPredictiveText;
                pw.forceActiveFocus();
            }
        }
    }
}
