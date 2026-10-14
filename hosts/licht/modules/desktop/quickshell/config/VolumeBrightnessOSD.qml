// VolumeBrightnessOSD.qml
// Shows by itself when the volume, mute state or screen brightness changes,
// or when the microphone is muted or un-muted, Caps Lock or Num Lock is
// switched, or do not disturb is turned on or off, then settles away. There is
// no IPC command and no keybind.
//
// Volume and brightness are levels: the disc sits on the ruler at the value and
// the middle reads the number. The rest are switches: the same ruler is the
// track, and the disc slides across to the on end (all the ticks lit, in the
// accent) or the off end (greyed), with the state in words under it: On / Off,
// Live / Muted for the microphone. A switch stays up a little longer than a
// level, since nothing is being held down to keep it there.
//
// The launcher's dial in miniature: the same borderless stage rising from the
// bottom edge, the same fine ruler, a glass disc and the accent underline.
// Nothing here is a box. The ruler is a short arc of 41 hairline ticks, the
// ones up to the value tinted; a glass disc holding the icon rides the arc
// above it, exactly where the value is, and the ticks around it swell. Under
// the arc the middle reads out the number, and under that what you are
// changing and on which device.
// Muted greys everything out and swaps the number for "Muted"; a volume pushed
// past 100% turns it red (the disc stops at the end of the ruler).
//
// Motion: the arc unfurls from a tight dome into the calm dial as the stage
// rises (the launcher's arrival, quickened, since this is up for a second and
// a half), the ticks sweep in from the left, the disc glides to each new value
// and the number rolls to it, every step nudges the disc and sends a ring off
// it, and the disc swells back into place when the icon or the kind changes.
// Leaving curls the arc back into the dome, a little quicker than it came.
//
// It never takes input: clicks go through to whatever is underneath.
// Caps Lock and Num Lock are read from the keyboard's LEDs under
// /sys/class/leds (the compositor does not announce them). The file is read
// four times a second, which costs nothing; nothing is polled if the machine
// has no such LEDs. Do not disturb is not announced while the notification
// centre is open: it is on the same edge, and shows the state itself.
// Test it with:  wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+
//                brightnessctl set 5%+
//                wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle

import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Pipewire

PanelWindow {
    id: osd

    // ---- Settings -------------------------------------------------------
    readonly property int hideAfterMs: 1500
    // Switches (mic, lock keys, do not disturb) stay up longer than levels
    readonly property int switchHideMs: 2200

    // The stage: same proportions as the launcher's dial, only as big as it
    // needs. A little larger than before, so the disc and the words read at a glance.
    readonly property int stageW: 480
    readonly property int stageH: 170
    readonly property int topY: 30
    readonly property int ruleDrop: 38
    readonly property int ruleY: topY + ruleDrop
    readonly property real dialR: 900
    // The dome the dial starts as when it appears (and ends as when it leaves)
    readonly property real rainbowR: 340
    // Length of the whole ruler, in pixels along the arc
    readonly property real spanW: 340
    readonly property int tickCount: 41
    readonly property int discSize: 54

    // ---- State ----------------------------------------------------------
    // What is showing: "volume", "brightness", "mic", "caps", "num" or "dnd"
    property string activeKind: "volume"
    // True while the stage should be on screen. The window itself stays alive
    // a little longer (see `visible` below) so the slide away can finish.
    property bool shown: false
    // 0 = hidden below the edge, 1 = in place
    property real reveal: 0
    // 1 = tight dome, 0 = the resting dial
    property real fan: 1
    // Stops it popping up once at startup, when the properties below get their
    // first values.
    property bool ready: false
    // True while switching between volume and brightness: the disc and the
    // number jump to the new value instead of sliding across from the other's.
    property bool snapping: false
    // 0 at rest, 1 for an instant on every step (a detent under the disc)
    property real kick: 0
    // A ring leaving the disc on every step, 0..1
    property real halo: 0
    // Radius of the dial right now: curvature eases from the dome to the dial
    readonly property real dialNow: 1 / (1 / dialR + (1 / rainbowR - 1 / dialR) * fan)

    function clamp(v, a, b) {
        return Math.max(a, Math.min(b, v));
    }

    // Ease-out with a small overshoot for the arrival of the disc (0..1 in,
    // about 1.04 at the peak): the shell's `pop`, kept gentle.
    function backOut(t) {
        const c1 = 0.8;
        const u = t - 1;
        return 1 + (c1 + 1) * u * u * u + c1 * u * u;
    }

    // Where a percentage sits along the ruler, in pixels from the middle
    function sFor(p) {
        return (p / 100 - 0.5) * spanW;
    }

    function showOsd(kind) {
        if (!ready)
            return;
        if (kind !== activeKind) {
            snapping = true;
            activeKind = kind;
            // A level jumps to its value. A switch starts at its other end and
            // slides across, so the change itself is what you see.
            shownNum = isLevel ? pct : 100 - pct;
            snapping = false;
            if (!isLevel)
                shownNum = pct;
            pop.restart();
        }
        shown = true;
        hideTimer.restart(); // restart = push the hide back if you keep adjusting
    }

    onShownChanged: {
        if (shown) {
            closeAnim.stop();
            openAnim.restart();
        } else {
            openAnim.stop();
            closeAnim.restart();
        }
    }

    Timer {
        id: hideTimer

        interval: osd.isLevel ? osd.hideAfterMs : osd.switchHideMs
        onTriggered: osd.shown = false
    }

    Timer {
        interval: 300
        running: true
        onTriggered: osd.ready = true
    }

    // ---- Volume (Pipewire) ----------------------------------------------
    // `?.` stops quietly if the thing on the left is null, and `??` supplies a
    // fallback, so these are safe while no audio device exists yet.
    readonly property var activeSink: Pipewire.defaultAudioSink
    readonly property real volumeLevel: activeSink?.audio?.volume ?? 0.0
    readonly property bool isMuted: activeSink?.audio?.muted ?? true
    readonly property string sinkName: (activeSink?.nickname || activeSink?.description || "") + ""

    // Pipewire only reports an object's volume while something is tracking it.
    PwObjectTracker {
        objects: osd.activeSink ? [osd.activeSink] : []
    }

    // These run whenever the value changes, whoever changed it (keybind,
    // the bar's scroll wheel, another app...).
    onVolumeLevelChanged: showOsd("volume")
    onIsMutedChanged: {
        showOsd("volume");
        pop.restart();
    }

    // ---- Brightness (shared with the bar, see Brightness.qml) ------------
    readonly property int brightnessPercent: Brightness.percent

    onBrightnessPercentChanged: showOsd("brightness")

    // ---- Microphone (Pipewire) -------------------------------------------
    readonly property var micSource: Pipewire.defaultAudioSource
    readonly property bool micMuted: micSource?.audio?.muted ?? false
    readonly property string micName: (micSource?.nickname || micSource?.description || "") + ""
    // When the default microphone last changed. A device that has only just
    // been picked up reports its mute state a moment later, and that is not
    // something you did, so mute changes in that window are not announced.
    property double micSwitchedAt: Date.now()

    onMicSourceChanged: micSwitchedAt = Date.now()

    PwObjectTracker {
        objects: osd.micSource ? [osd.micSource] : []
    }

    // Watches the microphone's own mute switch, so swapping devices (which
    // changes micMuted without anyone pressing anything) stays quiet
    Connections {
        target: osd.micSource ? osd.micSource.audio : null

        function onMutedChanged() {
            if (Date.now() - osd.micSwitchedAt > 900)
                osd.showOsd("mic");
        }
    }

    // ---- Caps Lock and Num Lock (keyboard LEDs) --------------------------
    // The first keyboard LED found for each; the compositor lights them all alike
    property string capsPath: ""
    property string numPath: ""
    property bool capsOn: false
    property bool numOn: false
    // The first reading is the starting state, not a change
    property bool capsKnown: false
    property bool numKnown: false

    function ledRead(kind, raw) {
        const on = raw !== "" && raw !== "0";
        if (kind === "caps") {
            if (!capsKnown) {
                capsKnown = true;
                capsOn = on;
            } else if (on !== capsOn) {
                capsOn = on;
                showOsd("caps");
            }
        } else {
            if (!numKnown) {
                numKnown = true;
                numOn = on;
            } else if (on !== numOn) {
                numOn = on;
                showOsd("num");
            }
        }
    }

    // Find the LEDs once. Nothing else runs if there are none.
    Process {
        running: true
        command: ["bash", "-c", "ls -d /sys/class/leds/*::capslock /sys/class/leds/*::numlock 2>/dev/null"]

        stdout: StdioCollector {
            onStreamFinished: {
                for (const line of text.split("\n")) {
                    const f = line.trim();
                    if (f.endsWith("::capslock") && osd.capsPath === "")
                        osd.capsPath = f + "/brightness";
                    else if (f.endsWith("::numlock") && osd.numPath === "")
                        osd.numPath = f + "/brightness";
                }
            }
        }
    }

    FileView {
        id: capsFile

        path: osd.capsPath
        onLoaded: osd.ledRead("caps", capsFile.text().trim())
    }

    FileView {
        id: numFile

        path: osd.numPath
        onLoaded: osd.ledRead("num", numFile.text().trim())
    }

    // The kernel does not announce an LED changing, so look every so often
    Timer {
        interval: 250
        repeat: true
        running: osd.capsPath !== "" || osd.numPath !== ""
        onTriggered: {
            if (osd.capsPath !== "")
                capsFile.reload();
            if (osd.numPath !== "")
                numFile.reload();
        }
    }

    // ---- Do not disturb ---------------------------------------------------
    readonly property bool dnd: NotificationServer.doNotDisturb

    onDndChanged: {
        // The centre is on this same edge and shows it already
        if (!NotificationServer.centerOpen)
            showOsd("dnd");
    }

    // ---- What the dial shows ----------------------------------------------
    readonly property bool isVolume: activeKind === "volume"
    // Volume and brightness are levels; everything else is a switch
    readonly property bool isLevel: activeKind === "volume" || activeKind === "brightness"
    readonly property bool switchOn: {
        switch (activeKind) {
        case "mic":
            return !micMuted;
        case "caps":
            return capsOn;
        case "num":
            return numOn;
        case "dnd":
            return dnd;
        }
        return true;
    }
    // Greyed out when the sound is muted, or a switch is off (the mic: muted)
    readonly property bool dimmed: isLevel ? (isVolume && isMuted) : !switchOn
    // The number is shown for a level that is not muted
    readonly property bool showNumber: isLevel && !dimmed
    // Whole percent, so the number never shows a fraction. Volume can go past
    // 100. A switch sits at one end of the ruler or the other.
    readonly property int pct: isLevel ? (isVolume ? Math.round(volumeLevel * 100) : brightnessPercent) : (switchOn ? 100 : 0)
    // Past 100% the ruler has run out; the colour says so
    readonly property bool over: isVolume && !isMuted && pct > 100
    // Where the number is right now: eased towards `pct`
    property real shownNum: 0
    // Where the disc is: the same, held to the end of the ruler
    readonly property real shownPct: Math.min(100, shownNum)
    // Muted greys out, over-amplified goes red, otherwise the accent
    property color tint: dimmed ? Colors.muted : (over ? Colors.critical : Colors.accent)
    readonly property string kindName: {
        switch (activeKind) {
        case "brightness":
            return "Brightness";
        case "mic":
            return "Microphone";
        case "caps":
            return "Caps Lock";
        case "num":
            return "Num Lock";
        case "dnd":
            return "Do not disturb";
        }
        return "Volume";
    }
    readonly property string detail: {
        switch (activeKind) {
        case "brightness":
            return "Display";
        case "mic":
            return micName;
        case "caps":
        case "num":
            return "";
        case "dnd":
            return dnd && NotificationServer.dndUntil > 0 ? "until " + Qt.formatTime(new Date(NotificationServer.dndUntil), "HH:mm") : "";
        }
        return sinkName;
    }
    // What the middle says when it is not a number
    readonly property string word: {
        if (activeKind === "mic")
            return switchOn ? "Live" : "Muted";
        if (isLevel)
            return "Muted";
        return switchOn ? "On" : "Off";
    }
    // The disc holds an icon (Nerd Font, Material Design codepoints) or, for
    // the lock keys, a letter: A for Caps Lock (a when it is off), 1 for Num Lock.
    readonly property bool glyphIsLetter: activeKind === "caps" || activeKind === "num"
    readonly property string glyphStr: {
        switch (activeKind) {
        case "brightness":
            return String.fromCodePoint(0xF00DF);
        case "mic":
            return String.fromCodePoint(micMuted ? 0xF036D : 0xF036C);
        case "caps":
            return capsOn ? "A" : "a";
        case "num":
            return "1";
        case "dnd":
            return dnd ? Icons.bellOff : Icons.bell;
        }
        if (isMuted)
            return String.fromCodePoint(0xF075F); // muted
        if (volumeLevel >= 0.66)
            return String.fromCodePoint(0xF057E); // volume high
        if (volumeLevel >= 0.05)
            return String.fromCodePoint(0xF0580); // volume medium
        return String.fromCodePoint(0xF057F); // volume low
    }

    onPctChanged: {
        shownNum = pct;
        if (!snapping) {
            kickAnim.restart();
            haloAnim.restart();
        }
    }

    Behavior on shownNum {
        enabled: !osd.snapping

        NumberAnimation {
            duration: Style.moveMs
            easing.type: Style.easeEnter
        }
    }

    Behavior on tint {
        ColorAnimation {
            duration: Style.baseMs
        }
    }

    // ---- Window ---------------------------------------------------------
    // Stay mapped while the stage is still leaving, otherwise it would vanish
    // instantly instead of sliding away.
    visible: shown || reveal > 0.001
    // Shows on whichever monitor has focus
    screen: Focus.screen
    color: "transparent"
    implicitWidth: stageW
    implicitHeight: stageH
    exclusiveZone: 0
    // An empty input region: the OSD is for looking at, clicks fall through
    mask: Region {}
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "qs-osd"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None // never steals typing

    // Only anchored to the bottom, so the compositor centres it horizontally
    anchors {
        bottom: true
    }

    // Rises and unfurls into the dial; settles with no bounce
    ParallelAnimation {
        id: openAnim

        NumberAnimation {
            target: osd
            property: "reveal"
            to: 1
            duration: Style.enterMs
            easing.type: Style.easeEnter
        }
        NumberAnimation {
            target: osd
            property: "fan"
            to: 0
            duration: Style.enterMs + Style.fadeMs
            easing.type: Style.easeMove
        }
    }

    // Leaving: quicker than arriving, the arc curls back into the dome
    ParallelAnimation {
        id: closeAnim

        NumberAnimation {
            target: osd
            property: "reveal"
            to: 0
            duration: Style.baseMs
            easing.type: Style.easeExit
        }
        NumberAnimation {
            target: osd
            property: "fan"
            to: 1
            duration: Style.baseMs
            easing.type: Style.easeExit
        }
    }

    // The icon changes (or the sound is muted): the disc swells back into place
    ParallelAnimation {
        id: pop

        NumberAnimation {
            target: glyphText
            property: "scale"
            from: 0.7
            to: 1
            duration: Style.baseMs
            easing.type: Style.easePop
            easing.overshoot: 1.6
        }
        NumberAnimation {
            targets: [glyphText, nameRow]
            property: "opacity"
            from: 0.3
            to: 1
            duration: Style.baseMs
            easing.type: Style.easeMove
        }
    }

    // Each step nudges the disc, like a detent
    SequentialAnimation {
        id: kickAnim

        NumberAnimation {
            target: osd
            property: "kick"
            to: 1
            duration: 60
            easing.type: Style.easePress
        }
        NumberAnimation {
            target: osd
            property: "kick"
            to: 0
            duration: Style.baseMs
            easing.type: Style.easeMove
        }
    }

    // ...and sends a ring off it
    NumberAnimation {
        id: haloAnim

        target: osd
        property: "halo"
        from: 0
        to: 1
        duration: Style.sweepMs
        easing.type: Style.easeMove
    }

    // ---- Stage ----------------------------------------------------------
    Item {
        id: stage

        readonly property real cx: width / 2

        anchors.fill: parent
        clip: true
        opacity: Math.min(1, osd.reveal * 3)
        transform: Translate {
            y: (1 - osd.reveal) * 70
        }

        // Feathered backing: a soft dark ellipse keeps the disc, the scale and
        // the number readable over any wallpaper without a visible panel edge.
        Shape {
            id: scrimShape

            readonly property real r: stage.width * 0.5

            x: stage.cx - r
            y: stage.height - r
            width: r * 2
            height: r * 2
            layer.enabled: true
            layer.samples: 4
            transform: Scale {
                origin.x: scrimShape.r
                origin.y: scrimShape.r
                yScale: 0.62
            }

            ShapePath {
                strokeColor: "transparent"
                startX: 0
                startY: scrimShape.r

                fillGradient: RadialGradient {
                    centerX: scrimShape.r
                    centerY: scrimShape.r
                    centerRadius: scrimShape.r
                    focalX: scrimShape.r
                    focalY: scrimShape.r

                    GradientStop {
                        position: 0
                        color: Qt.alpha(Colors.background, 0.97)
                    }
                    GradientStop {
                        position: 0.55
                        color: Qt.alpha(Colors.background, 0.82)
                    }
                    GradientStop {
                        position: 1
                        color: Qt.alpha(Colors.background, 0)
                    }
                }

                PathArc {
                    x: scrimShape.r * 2
                    y: scrimShape.r
                    radiusX: scrimShape.r
                    radiusY: scrimShape.r
                }
                PathArc {
                    x: 0
                    y: scrimShape.r
                    radiusX: scrimShape.r
                    radiusY: scrimShape.r
                }
            }
        }

        // Low light in the colour of the value; it swells a touch on every step.
        Shape {
            id: horizon

            readonly property real r: stage.width * 0.46

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
                        color: Qt.alpha(osd.tint, 0.2 * (1 + osd.kick * 0.8))
                    }
                    GradientStop {
                        position: 0.5
                        color: Qt.alpha(osd.tint, 0.08 * (1 + osd.kick * 0.8))
                    }
                    GradientStop {
                        position: 1
                        color: Qt.alpha(osd.tint, 0)
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

        // ---- The ruler: hairline ticks every 2.5%, the quarters longer -------
        // The ones up to the value are tinted; the ones near the disc rise,
        // like a magnifier.
        Repeater {
            model: osd.tickCount

            delegate: Rectangle {
                id: tick

                required property int index

                // 0 at the left end, 1 at the right
                readonly property real frac: index / (osd.tickCount - 1)
                readonly property bool major: index % 10 === 0
                readonly property bool lit: frac * 100 <= osd.shownPct + 0.001
                readonly property real a: osd.sFor(frac * 100) / osd.dialNow
                readonly property real rr: osd.dialNow - osd.ruleDrop
                // 1 right under the disc, fading to 0 a few ticks away
                readonly property real near: Math.exp(-Math.pow((frac * 100 - osd.shownPct) / 9, 2))
                // The ticks sweep in from the left as the stage opens
                readonly property real appear: osd.clamp(osd.reveal * 1.7 - frac * 0.7, 0, 1)

                x: stage.cx + rr * Math.sin(a) - width / 2
                y: osd.topY + osd.dialNow - rr * Math.cos(a)
                width: major ? 2 : 1.5
                height: (major ? 9 : 5) + 8 * near
                radius: width / 2
                antialiasing: true
                transformOrigin: Item.Top
                rotation: a * 180 / Math.PI
                opacity: appear
                color: lit ? Qt.alpha(osd.tint, major ? 0.95 : 0.65) : Qt.alpha(Colors.foreground, major ? 0.45 : 0.26)

                Behavior on color {
                    ColorAnimation {
                        duration: Style.fadeMs
                    }
                }
            }
        }

        // ---- The disc: what is being changed, riding the arc at the value ---
        Item {
            id: disc

            readonly property real a: osd.sFor(osd.shownPct) / osd.dialNow
            // Arrives with a small overshoot, then swells a touch on every step
            readonly property real appear: osd.clamp(osd.reveal * 1.6 - 0.2, 0, 1)

            width: osd.discSize
            height: osd.discSize
            x: stage.cx + osd.dialNow * Math.sin(a) - width / 2
            y: osd.topY + osd.dialNow * (1 - Math.cos(a)) - height / 2
            opacity: appear
            scale: (0.55 + 0.45 * osd.backOut(appear)) * (1 + 0.08 * osd.kick)

            // The ring that leaves it on every step
            Rectangle {
                anchors.centerIn: parent
                width: parent.width + 8 + 30 * osd.halo
                height: width
                radius: width / 2
                color: "transparent"
                antialiasing: true
                visible: osd.halo > 0.001 && osd.halo < 0.999
                border.width: 1.5
                border.color: Qt.alpha(osd.tint, 0.5 * (1 - osd.halo))
            }

            // Glass, like the bar: one flat surface with a hairline outline,
            // in the value's colour
            Rectangle {
                anchors.fill: parent
                radius: width / 2
                antialiasing: true
                color: Style.card
                border.width: 1
                border.color: Qt.alpha(osd.tint, 0.8)

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
                color: Qt.alpha(osd.tint, Style.tintAlpha)
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
                id: glyphText

                anchors.centerIn: parent
                text: osd.glyphStr
                color: osd.tint
                font.pixelSize: osd.glyphIsLetter ? 24 : 22
                font.bold: osd.glyphIsLetter
            }
        }

        // The accent underline below the disc; it widens with every step.
        Rectangle {
            width: 14 + 8 * osd.kick
            height: 2
            radius: 1
            color: osd.tint
            x: disc.x + disc.width / 2 - width / 2
            y: disc.y + disc.height + 5 * disc.scale
            rotation: disc.a * 180 / Math.PI
            opacity: osd.clamp(osd.reveal * 2 - 0.6, 0, 1)
        }

        // ---- The middle: the number, and what it is called -------------------
        Item {
            id: readout

            x: stage.cx - width / 2
            y: osd.ruleY + 22
            width: 320
            height: 66
            transform: Translate {
                y: (1 - osd.clamp((osd.reveal - 0.25) / 0.55, 0, 1)) * 12
            }

            // The number, with a soft shadow in the background colour so it reads on any wallpaper
            Txt {
                y: 1.5
                width: parent.width
                height: 38
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                text: osd.showNumber ? String(Math.round(osd.shownNum)) : osd.word
                color: Qt.alpha(Colors.background, 0.9)
                font.pixelSize: osd.showNumber ? 32 : (osd.dimmed ? 22 : 26)
                font.bold: !osd.dimmed
            }

            Txt {
                id: num

                width: parent.width
                height: 38
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                text: osd.showNumber ? String(Math.round(osd.shownNum)) : osd.word
                // Muted and Off are grey but kept readable over a bright wallpaper
                color: osd.dimmed ? Qt.alpha(Colors.foreground, 0.7) : (osd.over ? Colors.critical : Colors.foreground)
                font.pixelSize: osd.showNumber ? 32 : (osd.dimmed ? 22 : 26)
                font.bold: !osd.dimmed
                font.letterSpacing: -0.2

                Behavior on color {
                    ColorAnimation {
                        duration: Style.baseMs
                    }
                }
            }

            // The % hangs off the right of the number, which stays centred
            Txt {
                x: parent.width / 2 + numMetrics.width / 2 + 2
                y: 13
                visible: osd.showNumber
                text: "%"
                color: Qt.alpha(Colors.foreground, 0.75)
                font.pixelSize: Style.fontMd
            }

            TextMetrics {
                id: numMetrics

                font: num.font
                text: num.text
            }

            // What is being changed, and on which device
            Row {
                id: nameRow

                anchors.horizontalCenter: parent.horizontalCenter
                y: 42
                spacing: Style.spaceMd

                // A thin outline in the background colour: small text stays
                // readable over any wallpaper, bright or busy
                Txt {
                    id: kindText

                    text: osd.kindName
                    color: Colors.foreground
                    style: Text.Outline
                    styleColor: Qt.alpha(Colors.background, 0.85)
                    font.pixelSize: Style.fontLg
                    font.bold: true
                }

                Txt {
                    anchors.verticalCenter: kindText.verticalCenter
                    width: Math.min(implicitWidth, 190)
                    visible: text !== ""
                    text: osd.detail
                    color: Qt.alpha(Colors.foreground, 0.78)
                    style: Text.Outline
                    styleColor: Qt.alpha(Colors.background, 0.85)
                    elide: Text.ElideRight
                    font.pixelSize: Style.fontMd
                }
            }
        }
    }
}
