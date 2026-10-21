// LockStage.qml
// What the lock and the login screen show on one screen, in the shell's dial
// language (see Polkit.qml, the other password prompt, which this follows).
// Lock.qml and the greeter make one of these per screen and hand it the same
// LockModel, so every screen moves as one.
//
// The backdrop is your wallpaper, blurred, light at the top and darker toward
// the foot. The time is the hero of the screen. A borderless stage rises from
// the bottom edge: one glass disc on the dial, ringed in the accent, with the
// fine ruler curving across the whole width of the screen over it. Below the
// ruler: what this screen is, the greeting, and one line for what is going on.
// Under that a few small buttons (now playing, power), and the password pill
// rests at the foot.
//
// The ruler is the state, as everywhere else in the shell. Each key you type
// turns it a little (Backspace turns it back). It scans while the password is
// checked, flushes red on a wrong one (and the disc shakes), and fills green
// from the middle to both edges on a right one, after which the dial curls
// away.
//
// Like the launcher it arrives as a rainbow: the disc and the ruler swing in
// from the left over a tight dome, washed with the wallpaper's colours, and
// unfurl into the calm dial. Closing plays it in reverse.
//
// Keys (the password field keeps focus, so typing is never affected):
//   type            the password        Enter    check it
//   Tab, Shift+Tab  pick a button       Ctrl+Left, Ctrl+Right   the same
//   Ctrl+Enter, Ctrl+Space   press the picked button
//   Enter on an empty field  presses the picked button
//   Esc             unpick the button; again to clear the field
// Mouse: click a button. Reboot and Shutdown ask for a second press; the
// button turns red and says so. The eye shows what you type.
//
// It reads and writes the LockModel it is given (see LockModel.qml): the
// password, the pick, the animation clocks, the colour of the moment, the
// words, and the buttons.

import QtQuick
import QtQuick.Effects
import QtQuick.Shapes

Item {
    id: scene

    // The model every screen shows (LockModel.qml)
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
    readonly property int discSize: 80
    readonly property int tickGap: 12
    readonly property int tickN: Math.ceil(width / tickGap) + 24
    // The background colour with a breath of the accent, for the washes
    readonly property color wash: Qt.tint(Colors.background, Qt.alpha(Colors.accent, 0.08))
    // The eye button: show what you type (per screen)
    property bool showPw: false

    // ---- The model, under shorter names -----------------------------------
    readonly property real reveal: lock.reveal
    readonly property real spinIn: lock.spinIn
    readonly property real fan: lock.fan
    readonly property real breath: lock.breath
    readonly property real shakeX: lock.shakeX
    readonly property real scan: lock.scan
    readonly property real scanOn: lock.scanOn
    readonly property real flush: lock.flush
    readonly property real okFill: lock.okFill
    readonly property real ring: lock.ring
    readonly property color tone: lock.tone
    readonly property bool succeeded: lock.succeeded
    readonly property bool checking: lock.checking

    // Radius of the dial right now: curvature eases from the dome to the dial
    readonly property real dialNow: 1 / (1 / dialR + (1 / rainbowR - 1 / dialR) * fan)

    // ---- Layout of what is under the dial ---------------------------------
    readonly property int readoutTop: ruleY + 30
    readonly property int controlsH: Style.buttonCompact
    readonly property int pillH: Style.fieldHeight
    // The pill floats above the bottom edge. The stage is also tall enough for
    // the far ends of the ruler, which droop a little.
    readonly property int foot: 48
    readonly property real controlsY: readoutTop + readout.height + 14
    readonly property real pillY: controlsY + controlsH + 14
    readonly property real bodyH: pillY + pillH + foot

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
        return clamp((reveal - from) / (to - from), 0, 1);
    }

    // `base` washed with one of the palette's colours, chosen by screen
    // position x (colour1 on the left through colour6 on the right). The wash
    // is `fan` strong, so it only shows while the dial is arriving or leaving.
    function spectral(base, x, a) {
        const ramp = [Colors.color1, Colors.color2, Colors.color3, Colors.color4, Colors.color5, Colors.color6];
        const t = (clamp((x - stage.width / 2) / (stage.width * 0.34), -1, 1) * 0.5 + 0.5) * (ramp.length - 1);
        const i = Math.min(ramp.length - 2, Math.floor(t));
        const c = Qt.tint(ramp[i], Qt.alpha(ramp[i + 1], t - i));
        return Qt.alpha(Qt.tint(base, Qt.alpha(c, 0.9 * fan)), a);
    }

    // The keys the password field leaves to the stage
    function handleKey(event) {
        const ctrl = (event.modifiers & Qt.ControlModifier) !== 0;
        switch (event.key) {
        case Qt.Key_Return:
        case Qt.Key_Enter:
            event.accepted = true;
            if (ctrl || (lock.password === "" && lock.pick >= 0))
                lock.pressPicked();
            else if (lock.password !== "")
                lock.submitRequested();
            break;
        case Qt.Key_Space:
            if (ctrl) {
                event.accepted = true;
                lock.pressPicked();
            }
            break;
        case Qt.Key_Tab:
            event.accepted = true;
            lock.movePick(1);
            break;
        case Qt.Key_Backtab:
            event.accepted = true;
            lock.movePick(-1);
            break;
        case Qt.Key_Left:
            if (ctrl) {
                event.accepted = true;
                lock.movePick(-1);
            }
            break;
        case Qt.Key_Right:
            if (ctrl) {
                event.accepted = true;
                lock.movePick(1);
            }
            break;
        case Qt.Key_Escape:
            event.accepted = true;
            if (lock.pick >= 0)
                lock.pick = -1;
            else if (lock.password !== "")
                lock.password = "";
            break;
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

    // ---- Backdrop: the wallpaper, blurred ---------------------------------
    // A blurred picture needs no detail, so the image is read and blurred at a
    // quarter of the screen size and scaled up: the same look for a sixteenth
    // of the work, which matters on a laptop's integrated graphics.
    Item {
        id: backdrop

        width: Math.round(scene.width / 4)
        height: Math.round(scene.height / 4)
        scale: 4
        transformOrigin: Item.TopLeft
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

    // A wash of the background colour over it: light at the top, where the
    // time sits and the wallpaper can show, and darker toward the foot, where
    // the stage needs the calm
    Rectangle {
        anchors.fill: parent

        gradient: Gradient {
            GradientStop {
                position: 0
                color: Qt.alpha(scene.wash, 0.3)
            }
            GradientStop {
                position: 0.55
                color: Qt.alpha(scene.wash, 0.5)
            }
            GradientStop {
                position: 1
                color: Qt.alpha(scene.wash, 0.82)
            }
        }
    }

    // ---- The hero: the time -----------------------------------------------
    // Big enough to read from across the room. The colon breathes with the
    // disc's ring and takes the colour of the moment.
    Item {
        id: hero

        // A read-out, so the size is a one-off (it follows the screen)
        readonly property int size: Math.round(scene.height * 0.17)

        anchors.horizontalCenter: parent.horizontalCenter
        y: Math.round(scene.height * 0.13)
        width: timeRow.implicitWidth
        height: timeRow.implicitHeight + dateLine.implicitHeight
        // Clicks pass through to the stage
        enabled: false
        opacity: scene.stage_(0.2, 0.75)
        transform: Translate {
            y: (1 - scene.stage_(0.2, 0.75)) * 24
        }

        Row {
            id: timeRow

            anchors.horizontalCenter: parent.horizontalCenter

            Soft {
                text: scene.lock.hourText
                color: Colors.foreground
                font.pixelSize: hero.size
            }

            Soft {
                text: ":"
                color: scene.tone
                opacity: 0.35 + 0.65 * scene.breath
                font.pixelSize: hero.size
            }

            Soft {
                text: scene.lock.minuteText
                color: Colors.foreground
                font.pixelSize: hero.size
            }
        }

        Soft {
            id: dateLine

            anchors.top: timeRow.bottom
            anchors.horizontalCenter: parent.horizontalCenter
            text: scene.lock.dateText
            color: Qt.alpha(Colors.foreground, 0.85)
            font.pixelSize: Math.round(hero.size * 0.17)
            font.letterSpacing: 3
            font.capitalization: Font.AllUppercase
        }

        // What the music player has loaded
        Soft {
            anchors.top: dateLine.bottom
            anchors.topMargin: Style.spaceXl
            anchors.horizontalCenter: parent.horizontalCenter
            width: Math.min(implicitWidth, scene.contentW)
            elide: Text.ElideRight
            text: (scene.lock.nowArtist !== "" ? scene.lock.nowArtist + "  \u00b7  " : "") + scene.lock.nowTitle
            color: Qt.alpha(Colors.foreground, 0.78)
            font.pixelSize: Style.fontMd
            opacity: scene.lock.nowActive ? 1 : 0

            Behavior on opacity {
                NumberAnimation {
                    duration: Style.baseMs
                }
            }
        }
    }

    // ---- Stage ------------------------------------------------------------
    Item {
        id: stage

        readonly property real cx: width / 2

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        width: scene.width
        height: scene.bodyH
        clip: true
        opacity: Math.min(1, scene.reveal * 3)
        transform: Translate {
            y: (1 - scene.reveal) * (stage.height + 40)
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
            width: scene.contentW
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
                        color: Qt.alpha(scene.tone, 0.18)
                    }
                    GradientStop {
                        position: 0.5
                        color: Qt.alpha(scene.tone, 0.07)
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

        // ---- The ruler: fine ticks curving across the screen over the disc.
        // The ones by the middle rise like a magnifier; the rest of the ruler
        // shows the state (a scan while checking, red after a refusal, green
        // filling outward from the middle on success). Typing turns it. -----
        Repeater {
            model: scene.tickN

            delegate: Rectangle {
                id: tick

                required property int index

                readonly property real s: (index - scene.tickN / 2) * scene.tickGap - scene.mod(scene.lock.turn - scene.spinIn * scene.stepPx * 0.5, scene.tickGap * 10)
                readonly property real a: s / scene.dialNow
                readonly property real rr: scene.dialNow - scene.ruleDrop
                readonly property bool major: index % 10 === 0
                // The magnifier by the middle, and the scan going past
                readonly property real near: Math.max(0, 1 - Math.abs(s) / 90)
                readonly property real wave: Math.max(0, 1 - Math.abs(x - stage.cx - scene.scan * stage.width / 2) / 90) * scene.scanOn
                readonly property real hot: Math.max(near, wave)
                // 1 once the green has reached this tick
                readonly property real okMix: scene.clamp((scene.okFill * 1.35 - Math.abs(x - stage.cx) / (stage.width / 2)) / 0.35, 0, 1)
                // Ticks the state is lighting get more solid
                readonly property real solid: {
                    const rest = major ? 0.46 : 0.28;
                    return rest + (1 - rest) * Math.max(0.7 * hot, 0.6 * scene.flush, 0.85 * okMix);
                }
                readonly property color hue: Qt.tint(Qt.tint(Qt.tint(Colors.foreground, Qt.alpha(Colors.accent, 0.7 * hot)), Qt.alpha(Colors.critical, 0.85 * scene.flush)), Qt.alpha(Colors.success, 0.95 * okMix))

                x: stage.cx + rr * Math.sin(a) - 0.75
                y: scene.topY + scene.dialNow - rr * Math.cos(a)
                width: 1.5
                height: (major ? 9 : 5) + 6 * hot + 4 * okMix
                radius: 0.75
                antialiasing: true
                visible: Math.abs(a) < 1.2
                transformOrigin: Item.Top
                rotation: a * 180 / Math.PI
                color: scene.spectral(hue, x, solid)
                opacity: scene.clamp((stage.cx - Math.abs(x - stage.cx)) / 90, 0, 1) * scene.clamp(scene.reveal * 2 - Math.abs(x - stage.cx) / stage.cx * 0.9, 0, 1)
            }
        }

        // The middle of the ruler: the 2px marker, in the colour of the moment
        Rectangle {
            x: stage.cx - 1
            y: scene.ruleY - 3
            width: 2
            height: 16
            radius: 1
            color: scene.tone
            opacity: scene.clamp(scene.reveal * 2 - 0.5, 0, 1)
        }

        // ---- The disc: a lock, and a tick once it has worked ------------
        Item {
            id: disc

            // Swung left while arriving, right while leaving
            readonly property real s: -scene.spinIn * scene.stepPx
            readonly property real a: s / scene.dialNow
            readonly property real px: stage.cx + scene.dialNow * Math.sin(a)
            // It lifts a little off the dial, like a selected disc
            readonly property real py: scene.topY + scene.dialNow * (1 - Math.cos(a)) - 5
            readonly property real appear: scene.stage_(0.1, 0.6)
            readonly property real edge: scene.clamp((stage.cx - Math.abs(px - stage.cx)) / 90, 0, 1)

            width: scene.discSize
            height: scene.discSize
            x: px - width / 2 + scene.shakeX
            y: py - height / 2
            z: 20
            opacity: appear * edge
            scale: 0.55 + 0.45 * scene.backOut(appear)
            // Tilts along the dial, and rises from below as it arrives
            rotation: a * 180 / Math.PI * 0.6
            transform: Translate {
                y: (1 - disc.appear) * 30
            }

            // Ring that leaves the disc: on a refusal and on success
            Rectangle {
                anchors.centerIn: parent
                width: parent.width + 14 + 34 * scene.ring
                height: width
                radius: width / 2
                color: "transparent"
                antialiasing: true
                visible: scene.ring > 0.001 && scene.ring < 0.999
                border.width: 1.5
                border.color: Qt.alpha(scene.tone, 0.5 * (1 - scene.ring))
            }

            // Breathing ring around the disc
            Rectangle {
                anchors.centerIn: parent
                width: parent.width + 12
                height: width
                radius: width / 2
                color: "transparent"
                antialiasing: true
                border.width: 1
                border.color: Qt.alpha(scene.tone, 0.25 + 0.25 * scene.breath)
            }

            // Glass, like the bar: one flat surface with a hairline outline in
            // the colour of the moment (washed with the palette while the
            // dial arrives)
            Rectangle {
                anchors.fill: parent
                radius: width / 2
                antialiasing: true
                color: Style.card
                border.width: 1
                border.color: scene.spectral(scene.tone, disc.px, 0.9)
            }

            // The soft tint inside the glass
            Rectangle {
                anchors.fill: parent
                anchors.margins: 1
                radius: width / 2
                antialiasing: true
                color: Qt.alpha(scene.tone, Style.tintAlpha)
            }

            // Light catching the top edge, as on the bar
            EdgeLight {
                corner: disc.width * 0.4
            }

            // Upright while the disc tilts with the dial
            Txt {
                anchors.centerIn: parent
                text: scene.succeeded ? Icons.check : Icons.lock
                color: scene.tone
                font.pixelSize: disc.width * 0.38
                rotation: -disc.rotation
            }
        }

        // Underline under the disc; it breathes with the ring
        Rectangle {
            width: 20 + 10 * scene.breath
            height: 2
            radius: 1
            color: scene.tone
            x: disc.px - width / 2 + scene.shakeX
            y: disc.py + scene.discSize / 2 + 6
            rotation: disc.a * 180 / Math.PI
            opacity: scene.clamp(scene.reveal * 2 - 0.6, 0, 1)
        }

        // ---- The middle: what this is, who it greets, what is going on ---
        Item {
            id: readout

            x: stage.cx - width / 2
            y: scene.readoutTop
            width: Math.min(520, stage.width - 48)
            height: readCol.implicitHeight
            // Clicks pass through to the stage
            enabled: false
            opacity: scene.stage_(0.25, 0.8)
            transform: Translate {
                y: (1 - scene.stage_(0.25, 0.8)) * 12
            }

            Column {
                id: readCol

                width: parent.width
                spacing: Style.spaceXs

                // What this screen is
                Soft {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                    text: scene.lock.modeText
                    color: scene.succeeded ? Colors.success : Qt.alpha(Colors.foreground, 0.78)
                    font.pixelSize: Style.fontSm
                    font.letterSpacing: 1.4
                    font.capitalization: Font.AllUppercase
                }

                // The hello
                Soft {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                    text: scene.lock.greeting
                    color: Colors.foreground
                    font.pixelSize: Style.fontLg
                    font.bold: true
                }

                // What is going on. The line is always there, so the dial
                // never jumps.
                Item {
                    width: parent.width
                    height: 18

                    Soft {
                        width: parent.width
                        height: parent.height
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        elide: Text.ElideRight
                        text: scene.lock.statusText
                        color: scene.lock.statusIsError ? Colors.critical : (scene.succeeded ? Colors.success : Colors.muted)
                        font.pixelSize: Style.fontMd

                        Behavior on color {
                            ColorAnimation {
                                duration: Style.baseMs
                            }
                        }
                    }
                }
            }
        }

        // ---- Under the readout: the few things you can do ---------------
        Row {
            id: controls

            x: stage.cx - width / 2
            y: scene.controlsY
            spacing: Style.spaceMd
            // The net under the stage width: if the row is still wider than
            // the stage it shrinks to fit
            scale: Math.min(1, (stage.width - 32) / Math.max(1, controls.implicitWidth))
            opacity: scene.stage_(0.35, 0.9)
            transform: Translate {
                y: (1 - scene.stage_(0.35, 0.9)) * 10
            }

            // Show what you type
            IconButton {
                anchors.verticalCenter: parent.verticalCenter
                visible: !scene.checking && !scene.succeeded
                glyph: scene.showPw ? Icons.eyeOff : Icons.eye
                on: scene.showPw
                onClicked: {
                    scene.showPw = !scene.showPw;
                    pw.forceActiveFocus();
                }
            }

            Repeater {
                model: scene.lock.actions

                delegate: Row {
                    id: entry

                    required property var modelData
                    required property int index

                    readonly property bool armed: scene.lock.armed === index

                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Style.spaceMd

                    // A divider where one group ends and the next begins
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 1
                        height: 16
                        color: Style.outline
                        visible: entry.index > 0 && scene.lock.actions[entry.index - 1].group !== entry.modelData.group
                    }

                    TextButton {
                        compact: true
                        enabled: entry.modelData.enabled !== false && !scene.succeeded
                        glyph: entry.modelData.glyphNow ? entry.modelData.glyphNow() : entry.modelData.glyph
                        text: entry.armed ? "Press again" : (entry.modelData.showLabel === true ? entry.modelData.label : "")
                        danger: entry.armed
                        armed: entry.armed
                        onClicked: {
                            scene.lock.press(entry.index);
                            pw.forceActiveFocus();
                        }

                        // The button picked with the keyboard
                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: -3
                            radius: parent.radius + 3
                            color: "transparent"
                            border.width: 1.5
                            border.color: Colors.accent
                            antialiasing: true
                            opacity: scene.lock.pick === entry.index ? 0.8 : 0

                            Behavior on opacity {
                                NumberAnimation {
                                    duration: Style.fadeMs
                                }
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
            property real dim: scene.succeeded ? 0.5 : 1

            x: stage.cx - width / 2
            y: scene.pillY
            width: Math.min(340, stage.width - 48)
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
                color: Style.surface
                border.width: 1
                // Red after a refusal (the field is empty again, so the
                // field's own edge does not cover it)
                border.color: scene.lock.statusIsError ? Qt.alpha(Colors.critical, 0.7) : Style.outline

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
                glyph: Icons.lock
                placeholder: scene.lock.placeholder
                // The lock breathes while the password is checked
                busy: scene.checking
                clearable: !scene.checking && !scene.succeeded

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

            Component.onCompleted: {
                pw.input.passwordCharacter = "\u2022";
                pw.input.inputMethodHints = Qt.ImhSensitiveData | Qt.ImhNoPredictiveText;
            }
        }
    }
}
