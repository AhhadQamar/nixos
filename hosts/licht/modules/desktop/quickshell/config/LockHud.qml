// LockHud.qml
// What the lock and the login screen show on one screen, in the shell's dial
// language (see Polkit.qml and the launcher). Lock.qml and Greeter.qml make one
// of these per screen and keep all the state, so both are the same design and
// every screen moves as one.
//
// The original dial, made useful. The backdrop is your wallpaper, blurred,
// light at the top and darker toward the foot. The time is the hero of the
// screen, with the day under it (and, on the lock, what is playing). A
// borderless stage rises from the bottom edge: one glass disc on the dial,
// ringed in the accent, with a thin arc around it that is the seconds, and the
// fine ruler curving across the whole width of the screen over it.
//
// What it does, beyond looking like a dial:
//   - Battery, top right: how full it is, and whether it is charging. Red at
//     15% and under, green while charging (the same reading as the bar).
//   - Action discs under the greeting, small glass discs you click:
//       lock:   previous, play or pause, next (while something is loaded)
//               and suspend
//       login:  suspend, reboot, shutdown
//     Reboot and shutdown ask for a second press (the disc turns red and says
//     so) and let go after a few seconds. Hovering one names it.
//   - Now playing, on the lock: artist and title under the date, with a thin
//     progress line.
//   - The ruler is the state, and it answers your keys. Each key you type turns
//     it a little (Backspace turns it back). It scans while PAM (or greetd)
//     checks, flushes red on a wrong password (and the disc shakes), and fills
//     green from the middle to both edges on a right one, after which the dial
//     curls away and the screen opens.
//   - The small label top left says which screen this is.
//
// Like the launcher it arrives as a rainbow: the disc and the ruler swing in
// from the left over a tight dome, washed with the wallpaper's colours, and
// unfurl into the calm dial. Closing plays it in reverse.
//
// It reads these from `lock` (the same names in Lock.qml and Greeter.qml):
//   password failed broken succeeded checking          what is going on
//   reveal spinIn fan breath shakeX scan ring turn     the animation clocks
//   tone flush okFill scanOn                           colour of the moment
//   hourText minuteText periodText dateText greeting   the clock and the hello
//   secFrac modeText wallpaper                         the seconds, the label, the picture
//   actions nowActive nowTitle nowArtist nowProgress   what the discs and the player offer
//   submit()                                           Enter was pressed
//
// Each entry of `actions` is { label, icon (a glyph), critical (optional, asks
// twice), enabled (optional), run() }.

import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import Quickshell.Services.UPower

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
    // The action discs sit between the greeting and the pill, with a line
    // under them for their names
    readonly property var acts: lock.actions || []
    readonly property bool hasActions: acts.length > 0
    readonly property int actionH: 44
    readonly property int capH: 20
    readonly property real actionsY: readoutTop + readout.height + 12
    readonly property real pillY: actionsY + (hasActions ? actionH + capH + 10 : 0) + 6
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

    // ---- Battery (read the same way as the bar) ---------------------------
    readonly property var bat: UPower.displayDevice
    readonly property bool hasBattery: bat?.isPresent ?? false
    readonly property real batLevel: {
        const p = bat?.percentage ?? 0;
        return p > 1 ? p / 100 : p;
    }
    readonly property int batPercent: Math.round(batLevel * 100)
    readonly property bool charging: bat ? bat.state === UPowerDeviceState.Charging : false
    readonly property color batColor: charging ? Colors.success : (batPercent <= 15 ? Colors.critical : Colors.foreground)

    // ---- Actions ----------------------------------------------------------
    // The disc waiting for a second press (-1 = none), and the one the pointer
    // is over
    property int armed: -1
    property int hovered: -1
    // How long a pending confirmation stays armed, in ms
    readonly property int armMs: 3000

    // A new set of discs (a track started, say) starts clean
    onActsChanged: {
        armed = -1;
        hovered = -1;
    }

    function press(i) {
        const a = acts[i];
        if (lock.succeeded || !a || a.enabled === false)
            return;
        // Destructive ones ask for a second press
        if (a.critical === true && armed !== i) {
            armed = i;
            return;
        }
        armed = -1;
        a.run();
    }

    Timer {
        interval: dial.armMs
        running: dial.armed >= 0
        onTriggered: dial.armed = -1
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

        // AM or PM, small, at the shoulder of the minutes
        Txt {
            x: timeRow.x + timeRow.width + 10
            y: hero.size * 0.2
            text: dial.lock.periodText
            color: Qt.alpha(Colors.foreground, 0.7)
            style: Text.Outline
            styleColor: Qt.alpha(Colors.background, 0.8)
            font.pixelSize: Math.round(hero.size * 0.16)
            font.letterSpacing: 2
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

        // What is playing (the lock only; the discs below are its controls),
        // with a thin line for how far through it is
        Item {
            id: nowLine

            anchors.top: dateLine.bottom
            anchors.topMargin: 18
            anchors.horizontalCenter: parent.horizontalCenter
            width: Math.min(520, dial.width - 96)
            height: nowText.implicitHeight + 10
            visible: dial.lock.nowActive === true

            Txt {
                id: nowText

                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                text: (dial.lock.nowArtist ? dial.lock.nowArtist + "  \u00b7  " : "") + dial.lock.nowTitle
                color: Qt.alpha(Colors.foreground, 0.8)
                style: Text.Outline
                styleColor: Qt.alpha(Colors.background, 0.8)
                font.pixelSize: Style.fontMd
            }

            Rectangle {
                anchors.top: nowText.bottom
                anchors.topMargin: 6
                anchors.horizontalCenter: parent.horizontalCenter
                width: 160
                height: 2
                radius: 1
                color: Qt.alpha(Colors.foreground, 0.15)

                Rectangle {
                    width: parent.width * dial.clamp(dial.lock.nowProgress, 0, 1)
                    height: parent.height
                    radius: 1
                    color: dial.lock.tone
                }
            }
        }
    }

    // ---- The corners: which screen this is, and the battery ---------------
    Row {
        x: 56
        y: 48
        spacing: 8
        enabled: false
        opacity: dial.stage_(0.3, 0.8)

        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: 6
            height: width
            radius: width / 2
            color: dial.lock.tone
            opacity: 0.5 + 0.5 * dial.lock.breath
        }

        Txt {
            text: dial.lock.modeText
            color: Qt.alpha(Colors.foreground, 0.7)
            style: Text.Outline
            styleColor: Qt.alpha(Colors.background, 0.6)
            font.pixelSize: Style.fontSm
            font.letterSpacing: 2
            font.capitalization: Font.AllUppercase
        }
    }

    Row {
        anchors.right: parent.right
        anchors.rightMargin: 56
        y: 46
        spacing: 8
        visible: dial.hasBattery
        enabled: false
        opacity: dial.stage_(0.3, 0.8)

        // A little battery, drawn: an outline, a nub, and the charge inside
        Item {
            anchors.verticalCenter: parent.verticalCenter
            width: 30
            height: 14

            Rectangle {
                width: 27
                height: parent.height
                radius: 3
                color: "transparent"
                border.width: 1
                border.color: Qt.alpha(dial.batColor, 0.8)

                Rectangle {
                    x: 2
                    y: 2
                    width: Math.max(2, (parent.width - 4) * dial.batLevel)
                    height: parent.height - 4
                    radius: 1.5
                    color: dial.batColor
                }
            }

            Rectangle {
                x: 28
                anchors.verticalCenter: parent.verticalCenter
                width: 2
                height: 6
                radius: 1
                color: Qt.alpha(dial.batColor, 0.8)
            }
        }

        Txt {
            text: dial.batPercent + "%"
            color: dial.batColor
            style: Text.Outline
            styleColor: Qt.alpha(Colors.background, 0.6)
            font.pixelSize: Style.fontMd
        }

        Txt {
            visible: dial.charging
            text: "Charging"
            color: Qt.alpha(Colors.foreground, 0.7)
            style: Text.Outline
            styleColor: Qt.alpha(Colors.background, 0.6)
            font.pixelSize: Style.fontSm
            font.letterSpacing: 1
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

        // ---- The disc: a lock in glass ----------------------------------
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

            // A lock, held upright while the disc tilts with the dial; a tick
            // once it has worked
            Txt {
                anchors.centerIn: parent
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

        // ---- Actions: small glass discs you can click -----------------------
        Item {
            id: actionsRow

            x: stage.cx - width / 2
            y: dial.actionsY
            width: Math.min(520, stage.width - 48)
            height: dial.actionH + dial.capH
            visible: dial.hasActions
            opacity: dial.stage_(0.35, 0.9) * (dial.lock.succeeded ? 0.4 : 1)
            transform: Translate {
                y: (1 - dial.stage_(0.35, 0.9)) * 12
            }

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 14

                Repeater {
                    model: dial.acts

                    delegate: Item {
                        id: act

                        required property int index
                        required property var modelData

                        readonly property bool armedNow: dial.armed === index
                        readonly property bool hot: area.containsMouse || armedNow
                        // Accent on hover, red while it waits for a second press
                        readonly property color ink: armedNow ? Colors.critical : (hot ? Colors.accent : Colors.foreground)

                        width: dial.actionH
                        height: dial.actionH
                        opacity: modelData.enabled === false ? 0.35 : 1
                        scale: area.pressed ? 0.94 : (hot ? 1.06 : 1)

                        Behavior on scale {
                            NumberAnimation {
                                duration: Style.pressMs
                                easing.type: Style.easePress
                            }
                        }

                        // Glass, like the discs on the dial
                        Rectangle {
                            anchors.fill: parent
                            radius: width / 2
                            antialiasing: true
                            color: Style.card
                            border.width: 1
                            border.color: act.hot ? Qt.alpha(act.ink, 0.8) : Style.outline

                            Behavior on border.color {
                                ColorAnimation {
                                    duration: Style.baseMs
                                }
                            }
                        }

                        // The soft tint inside the glass
                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: 1
                            radius: width / 2
                            antialiasing: true
                            color: Qt.alpha(act.ink, act.hot ? Style.tintAlpha : 0)

                            Behavior on color {
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

                        Txt {
                            anchors.centerIn: parent
                            text: act.modelData.icon
                            color: act.ink
                            font.pixelSize: parent.width * 0.42
                        }

                        MouseArea {
                            id: area

                            anchors.fill: parent
                            hoverEnabled: true
                            enabled: !dial.lock.succeeded
                            cursorShape: Qt.PointingHandCursor
                            onEntered: dial.hovered = act.index
                            onExited: {
                                if (dial.hovered === act.index)
                                    dial.hovered = -1;
                            }
                            onClicked: dial.press(act.index)
                        }
                    }
                }
            }

            // The name of the disc under the pointer, or the question while one
            // waits for its second press. The line is always there, so nothing
            // jumps.
            Txt {
                anchors.horizontalCenter: parent.horizontalCenter
                y: dial.actionH + 4
                height: dial.capH - 4
                verticalAlignment: Text.AlignVCenter
                text: dial.armed >= 0 && dial.acts[dial.armed] ? "Press again to " + dial.acts[dial.armed].label.toLowerCase() : (dial.hovered >= 0 && dial.acts[dial.hovered] ? dial.acts[dial.hovered].label : "")
                color: dial.armed >= 0 ? Colors.critical : Colors.muted
                style: Text.Outline
                styleColor: Qt.alpha(Colors.background, 0.7)
                font.pixelSize: Style.fontSm
                font.letterSpacing: 1
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
