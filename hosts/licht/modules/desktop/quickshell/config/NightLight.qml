// NightLight.qml
// Colour temperature on the launcher's dial: the same borderless stage rising
// from the bottom edge, the same fine ruler, bar-style glass discs and accent
// underline.
// The ruler is the temperature scale itself, every tick in the colour the
// screen will actually take, warm on the left to cool on the right. A bead
// rides it where you are, the four presets sit above their temperatures, and
// the middle reads out the number (click it to switch the filter on or off).
// Drives `hyprsunset`.
//   qs ipc call nightlight toggle | open | close | power | reapply
// Keys: ← → (h l) adjust   ↑ ↓ (k j) move   enter apply   space on/off   1-4 presets   esc close
// Mouse: drag the ruler or scroll to adjust, click a preset, click the number for on/off
// Like the launcher it arrives as a rainbow: the scale and the presets swing in
// from the left over a tight dome and unfurl into the calm dial. Closing plays
// it in reverse; the bead glides, leaves a ripple, and the number rolls.
// The preset swatches and the scale's ticks are the one place raw colours are
// right: they show the colour the screen will actually take.
//
// Unlike the launcher this window is only as big as the stage, not the whole
// screen, so you can still use other windows and watch the colour change while
// you adjust it.

import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland

PanelWindow {
    id: nightLight

    // Opens on the monitor that has focus, and stays there while it is open so
    // it doesn't follow you when you click a window on another screen
    property var targetScreen: Focus.screen

    // ---- Settings -------------------------------------------------------
    readonly property int minTemp: 2000
    readonly property int maxTemp: 6500
    readonly property int step: 100
    // `tint` is the colour of each preset's swatch
    readonly property var presets: [
        {
            "label": "Candle",
            "temp": 2500,
            "tint": "#ff9a3c"
        },
        {
            "label": "Warm",
            "temp": 3500,
            "tint": "#ffb56b"
        },
        {
            "label": "Evening",
            "temp": 4500,
            "tint": "#ffd2a1"
        },
        {
            "label": "Soft",
            "temp": 5500,
            "tint": "#ffe8d4"
        }
    ]

    // The stage: same proportions as the launcher's, only as wide as it needs
    readonly property real screenW: targetScreen ? targetScreen.width : 1920
    readonly property int stageW: Math.min(780, Math.round(screenW * 0.9))
    readonly property int stageH: 236
    readonly property int topY: 62
    readonly property int ruleDrop: 46
    readonly property int ruleY: topY + ruleDrop
    readonly property real dialR: 900
    // The dome the dial starts as when it opens (and ends as when it closes)
    readonly property real rainbowR: 360
    // Pixels between slots while swinging in, and the length of the whole scale
    readonly property real stepPx: 100
    readonly property real spanW: Math.min(560, stageW - 160)

    // ---- State ----------------------------------------------------------
    // The panel can't read the filter's state back from hyprsunset, so it keeps
    // track itself. The daemon below is started with --identity (= "no
    // filter"), so this is always "off" right after Quickshell restarts.
    property bool filterOn: false
    property int temperature: 3500
    property int lastSent: -1
    property int crashCount: 0
    // The highlighted preset (keyboard or mouse)
    property int selectedIndex: 0
    property bool isOpen: false
    // 0 = hidden below the edge, 1 = in place
    property real reveal: 0
    // Slots the scale is swung to the left while arriving (and right when leaving)
    property real spinIn: 0
    // 1 = tight rainbow dome, 0 = the resting dial
    property real fan: 1
    // A slow pulse (0..1) for the bead's ring
    property real breath: 0

    // The colour the screen is taking; muted while the filter is off
    property color tint: filterOn ? kelvinColor(temperature) : Colors.muted
    // Where the bead is heading, in pixels along the scale (0 = the middle)
    readonly property real markerGoal: sFor(temperature)
    // Where the bead is: glides to the goal (follows the pointer exactly while dragging)
    property real markerS: markerGoal
    // The number in the middle rolls to the temperature instead of jumping
    property real shownTemp: temperature
    // A soft bloom of the glow when the filter is switched on or off, 0..1
    property real bloom: 0
    // A ripple off the bead when the temperature changes, 0..1
    property real ripple: 0
    // Radius of the dial right now: curvature eases from the dome to the dial
    readonly property real dialNow: 1 / (1 / dialR + (1 / rainbowR - 1 / dialR) * fan)

    Behavior on tint {
        ColorAnimation {
            duration: Style.moveMs
        }
    }

    Behavior on markerS {
        enabled: !dragArea.dragging
        // The bead glides to the new temperature and settles, with no bounce
        NumberAnimation {
            duration: Style.moveMs
            easing.type: Style.easeMove
        }
    }

    Behavior on shownTemp {
        enabled: !dragArea.dragging
        NumberAnimation {
            duration: Style.enterMs
            easing.type: Style.easeMove
        }
    }

    onFilterOnChanged: bloomAnim.restart()

    // ---- The hyprsunset daemon ------------------------------------------
    // A Process runs a command for as long as `running` is true. It inherits
    // Quickshell's environment, so it sees HYPRLAND_INSTANCE_SIGNATURE, which
    // `hyprctl hyprsunset ...` needs. `pkill` first so a stray old instance
    // can't hold the socket.
    Process {
        id: daemon

        command: ["sh", "-c", "pkill -x hyprsunset; exec hyprsunset --identity"]
        running: true
        onRunningChanged: if (running)
            stableTimer.restart()
        onExited: (exitCode, exitStatus) => {
            stableTimer.stop();
            nightLight.filterOn = false;
            nightLight.crashCount += 1;
            if (nightLight.crashCount <= 5)
                restartTimer.start();
            else
                console.warn("NightLight: hyprsunset keeps exiting (code " + exitCode + "), giving up. Run `hyprsunset --identity` in a terminal to see why.");
        }
    }

    Timer {
        id: restartTimer

        interval: 2000
        onTriggered: daemon.running = true
    }

    // If the daemon survives this long, forgive past crashes. Five failures
    // spread across weeks shouldn't count like five in a row.
    Timer {
        id: stableTimer

        interval: 30000
        running: true
        onTriggered: nightLight.crashCount = 0
    }

    // ---- Helpers --------------------------------------------------------
    function clamp(v, a, b) {
        return Math.max(a, Math.min(b, v));
    }

    // Round to the nearest `step` and keep inside min..max
    function snap(v) {
        return Math.max(minTemp, Math.min(maxTemp, Math.round(v / step) * step));
    }


    // Where a temperature sits along the scale, in pixels from the middle
    function sFor(t) {
        return (t - (minTemp + maxTemp) / 2) / (maxTemp - minTemp) * spanW;
    }

    // Ease-out with a small overshoot for the arrival of each item (0..1 in,
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

    // The colour a black-body of this temperature gives, as [r, g, b] 0..255
    // (Tanner Helland's approximation). Only used to draw the scale and tint
    // the dial; hyprsunset does the real work.
    function kelvinRgb(k) {
        const t = k / 100;
        let r, g, b;
        if (t <= 66) {
            r = 255;
            g = 99.4708025861 * Math.log(t) - 161.1195681661;
            b = t <= 19 ? 0 : 138.5177312231 * Math.log(t - 10) - 305.0447927307;
        } else {
            r = 329.698727446 * Math.pow(t - 60, -0.1332047592);
            g = 288.1221695283 * Math.pow(t - 60, -0.0755148492);
            b = 255;
        }
        const c = v => Math.max(0, Math.min(255, Math.round(v)));
        return [c(r), c(g), c(b)];
    }

    function kelvinColor(k) {
        const c = kelvinRgb(k);
        return Qt.rgba(c[0] / 255, c[1] / 255, c[2] / 255, 1);
    }

    // Name for the readout: the preset you are on, or "Custom"
    function nameFor(t) {
        for (let i = 0; i < presets.length; i++) {
            if (presets[i].temp === t)
                return presets[i].label;
        }
        return "Custom";
    }


    // ---- Actions --------------------------------------------------------
    // Send the current state to hyprsunset. execDetached starts a command and
    // forgets it.
    function apply() {
        if (filterOn)
            Quickshell.execDetached(["hyprctl", "hyprsunset", "temperature", String(temperature)]);
        else
            Quickshell.execDetached(["hyprctl", "hyprsunset", "identity"]);
    }

    // Any adjustment also switches the filter on.
    function setTemperature(t) {
        temperature = snap(t);
        filterOn = true;
        apply();
    }

    function togglePower() {
        filterOn = !filterOn;
        apply();
    }

    // Some drivers drop the colour matrix when a display is powered off and on
    // (hypridle calls this through IPC after waking the screen).
    function reapply() {
        if (filterOn)
            apply();
    }

    // Move the highlighted preset, clamped to the list
    function move(delta) {
        selectedIndex = Math.max(0, Math.min(presets.length - 1, selectedIndex + delta));
    }

    // Preset that matches the current temperature, or -1
    function activeIndex() {
        for (let i = 0; i < presets.length; i++) {
            if (presets[i].temp === temperature)
                return i;
        }
        return -1;
    }

    function open() {
        if (isOpen)
            return;
        // Start on the active preset, if there is one
        selectedIndex = Math.max(0, activeIndex());
        targetScreen = Focus.screen;
        isOpen = true;
        closeAnim.stop();
        reveal = 0;
        spinIn = 3.2;
        fan = 1;
        openAnim.restart();
        keys.forceActiveFocus();
    }

    function close() {
        if (!isOpen)
            return;
        isOpen = false;
        openAnim.stop();
        closeAnim.restart();
    }

    // When the last click outside the panel closed it. The same click can
    // land on the bar item that toggles it, which must not open it again.
    property double closedAt: 0

    function toggle() {
        if (!isOpen && Date.now() - closedAt < 250)
            return;
        if (isOpen)
            close();
        else
            open();
    }

    // Click outside the panel to close it. The window only covers the panel
    // (clicks beside it reach what is underneath), so the compositor's focus
    // grab tells us about a click anywhere else.
    HyprlandFocusGrab {
        windows: [nightLight]
        active: nightLight.isOpen && nightLight.visible
        onCleared: {
            nightLight.closedAt = Date.now();
            nightLight.close();
        }
    }

    // ---- Window ---------------------------------------------------------
    // Full screen, like the launcher: the shared dim goes over the whole screen and
    // the stage rises from the bottom edge, centred. A click on the dim closes.
    visible: isOpen || reveal > 0.001
    color: "transparent"
    screen: targetScreen
    exclusiveZone: 0
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "qs-nightlight"
    WlrLayershell.keyboardFocus: isOpen ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    IpcHandler {
        function toggle() {
            nightLight.toggle();
        }

        function open() {
            nightLight.open();
        }

        function close() {
            nightLight.close();
        }

        function power() {
            nightLight.togglePower();
        }

        function reapply() {
            nightLight.reapply();
        }

        target: "nightlight"
    }

    // Rises smoothly. The scale and presets swing in from the left over a tight
    // dome and unfurl into the dial.
    ParallelAnimation {
        id: openAnim

        NumberAnimation {
            target: nightLight
            property: "reveal"
            from: 0
            to: 1
            duration: Style.sweepMs
            easing.type: Style.easeEnter
        }
        NumberAnimation {
            target: nightLight
            property: "spinIn"
            from: 3.2
            to: 0
            duration: Style.sweepMs + Style.moveMs
            easing.type: Style.easeEnter
        }
        NumberAnimation {
            target: nightLight
            property: "fan"
            from: 1
            to: 0
            duration: Style.sweepMs + Style.ambientMs / 2
            easing.type: Style.easeMove
        }
    }

    // Leaving: the dial curls back into the dome and the scale sweeps off right.
    ParallelAnimation {
        id: closeAnim

        NumberAnimation {
            target: nightLight
            property: "reveal"
            to: 0
            duration: Style.moveMs + Style.fadeMs
            easing.type: Style.easeExit
        }
        NumberAnimation {
            target: nightLight
            property: "spinIn"
            to: -3.2
            duration: Style.moveMs + Style.fadeMs
            easing.type: Style.easeExit
        }
        NumberAnimation {
            target: nightLight
            property: "fan"
            to: 1
            duration: Style.moveMs + Style.fadeMs
            easing.type: Style.easeExit
        }
    }

    // Slow breath for the ring around the bead.
    SequentialAnimation {
        running: nightLight.isOpen
        loops: Animation.Infinite

        NumberAnimation {
            target: nightLight
            property: "breath"
            from: 0
            to: 1
            duration: Style.ambientMs * 2
            easing.type: Style.easeAmbient
        }
        NumberAnimation {
            target: nightLight
            property: "breath"
            from: 1
            to: 0
            duration: Style.ambientMs * 2
            easing.type: Style.easeAmbient
        }
    }

    // The temperature changes by key, wheel or preset: a ripple off the bead.
    // (While dragging it would fire constantly, so it only marks the grab.)
    Connections {
        target: nightLight

        function onTemperatureChanged() {
            if (!dragArea.dragging)
                rippleAnim.restart();
        }
    }

    NumberAnimation {
        id: rippleAnim

        target: nightLight
        property: "ripple"
        from: 0
        to: 1
        duration: Style.sweepMs
        easing.type: Style.easeMove
    }

    // On or off: the glow swells quickly and settles back
    SequentialAnimation {
        id: bloomAnim

        NumberAnimation {
            target: nightLight
            property: "bloom"
            to: 1
            duration: Style.pressMs
            easing.type: Style.easeMove
        }
        NumberAnimation {
            target: nightLight
            property: "bloom"
            to: 0
            duration: Style.sweepMs
            easing.type: Style.easeMove
        }
    }

    // The name under the number changes (preset, Custom, Off): a quick fade
    NumberAnimation {
        id: nameFade

        target: nameText
        property: "opacity"
        from: 0.2
        to: 1
        duration: Style.baseMs
        easing.type: Style.easeMove
    }

    PanelLink {
        win: nightLight
        name: "nightlight"
    }

    // Keyboard handling. An Item with `focus` receives key presses.
    Item {
        id: keys

        anchors.fill: parent
        focus: nightLight.isOpen
        Keys.onPressed: event => {
            const k = event.key;
            const ctrl = (event.modifiers & Qt.ControlModifier) !== 0;
            if (k === Qt.Key_Escape)
                nightLight.close();
            else if (k === Qt.Key_Left || k === Qt.Key_H)
                nightLight.setTemperature(nightLight.temperature - nightLight.step);
            else if (k === Qt.Key_Right || k === Qt.Key_L)
                nightLight.setTemperature(nightLight.temperature + nightLight.step);
            else if (k === Qt.Key_Down || k === Qt.Key_J || (ctrl && k === Qt.Key_N))
                nightLight.move(1);
            else if (k === Qt.Key_Up || k === Qt.Key_K || (ctrl && k === Qt.Key_P))
                nightLight.move(-1);
            else if (k === Qt.Key_Return || k === Qt.Key_Enter)
                nightLight.setTemperature(nightLight.presets[nightLight.selectedIndex].temp);
            else if (k === Qt.Key_Space)
                nightLight.togglePower();
            else if (k >= Qt.Key_1 && k < Qt.Key_1 + nightLight.presets.length)
                nightLight.setTemperature(nightLight.presets[k - Qt.Key_1].temp);
        }
    }

    // While dragging, push updates about 10 times a second, and only when the
    // value actually changed.
    Timer {
        interval: 100
        repeat: true
        running: dragArea.dragging
        onTriggered: {
            if (nightLight.temperature !== nightLight.lastSent) {
                nightLight.lastSent = nightLight.temperature;
                nightLight.apply();
            }
        }
    }

    // The shared dim (Dim.qml): the same wash as the screenshot tool
    Dim {
        reveal: nightLight.reveal
        closes: true
        onClicked: nightLight.close()
    }

    // ---- Stage ----------------------------------------------------------
    Item {
        id: stage

        readonly property real cx: width / 2

        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        width: nightLight.stageW
        height: nightLight.stageH
        clip: true
        opacity: Math.min(1, nightLight.reveal * 3)
        transform: Translate {
            y: (1 - nightLight.reveal) * (nightLight.stageH + 40)
        }

        // Drag the ruler to set the temperature; the wheel steps it.
        MouseArea {
            id: dragArea

            property bool dragging: false

            // On the ruler band, near the scale
            function onRuler(x, y) {
                return y > nightLight.ruleY - 26 && y < nightLight.ruleY + 24 && Math.abs(x - stage.cx) < nightLight.spanW / 2 + 36;
            }

            function tempAt(x) {
                const rr = nightLight.dialNow - nightLight.ruleDrop;
                const a = Math.asin(nightLight.clamp((x - stage.cx) / rr, -1, 1));
                const s = a * nightLight.dialNow;
                const f = nightLight.clamp(s / nightLight.spanW + 0.5, 0, 1);
                return nightLight.snap(nightLight.minTemp + f * (nightLight.maxTemp - nightLight.minTemp));
            }

            function setFrom(x) {
                nightLight.temperature = tempAt(x);
                nightLight.filterOn = true;
            }

            anchors.fill: parent
            cursorShape: containsMouse && onRuler(mouseX, mouseY) ? Qt.PointingHandCursor : Qt.ArrowCursor
            hoverEnabled: true
            onPressed: mouse => {
                if (onRuler(mouse.x, mouse.y)) {
                    dragging = true;
                    rippleAnim.restart();
                    nightLight.lastSent = -1;
                    setFrom(mouse.x);
                } else {
                    mouse.accepted = false;
                }
            }
            onPositionChanged: mouse => {
                if (dragging)
                    setFrom(mouse.x);
            }
            onReleased: {
                if (dragging) {
                    dragging = false;
                    nightLight.apply();
                }
            }
            onWheel: wheel => nightLight.setTemperature(nightLight.temperature + (wheel.angleDelta.y > 0 ? nightLight.step : -nightLight.step))
        }

        // Feathered backing: a soft dark ellipse keeps the number and scale
        // readable over any wallpaper without a visible panel edge.
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
                        color: Qt.alpha(Colors.background, 0.88)
                    }
                    GradientStop {
                        position: 0.55
                        color: Qt.alpha(Colors.background, 0.6)
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

        // Low light in the colour of the screen; it blooms when switched on or off.
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
                        color: Qt.alpha(nightLight.tint, 0.14 * (1 + nightLight.bloom * 1.4))
                    }
                    GradientStop {
                        position: 0.5
                        color: Qt.alpha(nightLight.tint, 0.05 * (1 + nightLight.bloom * 1.4))
                    }
                    GradientStop {
                        position: 1
                        color: Qt.alpha(nightLight.tint, 0)
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

        // ---- The scale: one tick per step, in the colour the screen takes -----
        Repeater {
            model: Math.round((nightLight.maxTemp - nightLight.minTemp) / nightLight.step) + 1

            delegate: Rectangle {
                id: tick

                required property int index

                readonly property real t: nightLight.minTemp + index * nightLight.step
                readonly property real s: nightLight.sFor(t) - nightLight.spinIn * nightLight.stepPx * 0.5
                readonly property real a: s / nightLight.dialNow
                readonly property real rr: nightLight.dialNow - nightLight.ruleDrop
                readonly property bool major: t % 500 === 0
                // Ticks near the bead rise a little, like a magnifier
                readonly property real near: Math.max(0, 1 - Math.abs(t - nightLight.shownTemp) / 450)

                x: stage.cx + rr * Math.sin(a) - 0.75
                y: nightLight.topY + nightLight.dialNow - rr * Math.cos(a)
                width: 1.5
                height: (major ? 9 : 5) + 7 * near
                radius: 0.75
                antialiasing: true
                visible: Math.abs(a) < 1.2 && y < stage.height - 30
                transformOrigin: Item.Top
                rotation: a * 180 / Math.PI
                color: nightLight.kelvinColor(t)
                opacity: (nightLight.filterOn ? (0.7 + 0.3 * near) : 0.4)
                         * nightLight.clamp((stage.cx - Math.abs(x - stage.cx)) / 90, 0, 1)
                         * nightLight.clamp(nightLight.reveal * 2 - Math.abs(x - stage.cx) / stage.cx * 0.9, 0, 1)

                Behavior on opacity {
                    NumberAnimation {
                        duration: Style.moveMs
                    }
                }
            }
        }

        // ---- The bead: where the screen is now. It rides the scale, swells
        // under the pointer, and ripples when the temperature changes. --------
        Item {
            id: knob

            readonly property real a: (nightLight.markerS - nightLight.spinIn * nightLight.stepPx * 0.5) / nightLight.dialNow
            readonly property real rr: nightLight.dialNow - nightLight.ruleDrop

            x: stage.cx + rr * Math.sin(a) - width / 2
            y: nightLight.topY + nightLight.dialNow - rr * Math.cos(a) - height / 2
            width: 16
            height: 16
            opacity: Math.min(1, nightLight.reveal * 2)
            scale: 0.4 + 0.6 * nightLight.clamp(nightLight.reveal * 2 - 0.5, 0, 1)

            // Breathing ring
            Rectangle {
                anchors.centerIn: parent
                width: parent.width + 12
                height: width
                radius: width / 2
                color: "transparent"
                border.width: 1
                border.color: Qt.alpha(nightLight.tint, 0.25 + 0.25 * nightLight.breath)
            }

            // Ripple off the bead
            Rectangle {
                anchors.fill: parent
                radius: width / 2
                antialiasing: true
                color: nightLight.tint
                opacity: 0.4 * (1 - nightLight.ripple)
                scale: 1 + 1.9 * nightLight.ripple
                visible: nightLight.ripple > 0.001 && nightLight.ripple < 0.999
            }

            Rectangle {
                anchors.fill: parent
                radius: width / 2
                antialiasing: true
                color: nightLight.tint
                border.width: 3
                border.color: Qt.alpha(Colors.background, 0.9)
                scale: dragArea.dragging ? 1.25 : 1

                Behavior on scale {
                    NumberAnimation {
                        duration: Style.fadeMs
                        easing.type: Style.easePop
                        easing.overshoot: 1.8
                    }
                }
            }
        }

        // ---- The presets, above their temperatures --------------------------
        Repeater {
            model: nightLight.presets

            delegate: Item {
                id: slot

                required property int index
                required property var modelData

                readonly property bool current: index === nightLight.selectedIndex
                readonly property bool active: nightLight.filterOn && nightLight.temperature === modelData.temp
                // Swung left while arriving, right while leaving
                readonly property real s: nightLight.sFor(modelData.temp) - nightLight.spinIn * nightLight.stepPx
                readonly property real a: s / nightLight.dialNow
                // 0 at rest, 1 when highlighted. Animated, so the disc swells.
                property real grow: current ? 1 : 0
                readonly property real sz: 44 + 12 * grow
                readonly property real px: stage.cx + nightLight.dialNow * Math.sin(a)
                // The highlighted one also lifts a little off the dial
                readonly property real py: nightLight.topY + nightLight.dialNow * (1 - Math.cos(a)) - 6 * grow
                // The presets arrive in a left-to-right wave, each with a small
                // overshoot, and leave the same way.
                readonly property real k: index - (nightLight.presets.length - 1) / 2
                readonly property real appear: nightLight.clamp((nightLight.reveal - index * 0.06) / 0.42, 0, 1)
                readonly property real pop_: nightLight.backOut(appear)
                // 0 under the pointer: a gentle lift
                property real hover: area.containsMouse && !current ? 1 : 0
                // 0..1 while the ring around a newly highlighted preset expands
                property real ping: 0
                // Shape: a squircle that rounds a little more as it is highlighted
                readonly property real corner: sz * (0.36 + 0.06 * grow)
                readonly property real edge: nightLight.clamp((stage.cx - Math.abs(px - stage.cx)) / 90, 0, 1)
                readonly property real horizon: nightLight.clamp((stage.height - py + sz * 0.3) / (sz * 0.6), 0, 1)

                visible: py - sz / 2 < stage.height
                width: sz
                height: sz
                x: px - sz / 2
                y: py - sz / 2
                z: current ? 20 : 10
                opacity: appear * edge * horizon
                scale: 0.55 + 0.45 * pop_
                // Tilts along the dial, and rises from below as it arrives
                rotation: a * 180 / Math.PI * 0.6
                transform: Translate {
                    y: (1 - slot.appear) * 30 - 3 * slot.hover
                }

                Behavior on hover {
                    NumberAnimation {
                        duration: Style.baseMs
                        easing.type: Style.easeMove
                    }
                }

                // The highlight moved to this one: a ring leaves it.
                onCurrentChanged: if (current && nightLight.isOpen && nightLight.reveal > 0.8)
                    pingAnim.restart()

                NumberAnimation {
                    id: pingAnim
                    target: slot
                    property: "ping"
                    from: 0
                    to: 1
                    duration: Style.sweepMs
                    easing.type: Style.easeMove
                }

                // Ring that leaves a newly highlighted item.
                Rectangle {
                    anchors.centerIn: parent
                    width: parent.width + 14 + 34 * slot.ping
                    height: width
                    radius: slot.corner + 7 + 17 * slot.ping
                    color: "transparent"
                    antialiasing: true
                    visible: slot.ping > 0.001 && slot.ping < 0.999
                    border.width: 1.5
                    border.color: Qt.alpha(slot.modelData.tint, 0.5 * (1 - slot.ping))
                }

                // Swells with a little overshoot, settles back without one
                Behavior on grow {
                    NumberAnimation {
                        duration: Style.moveMs
                        easing.type: slot.current ? Style.easePop : Style.easeMove
                        easing.overshoot: 1.2
                    }
                }

                // Breathing ring around the highlighted preset.
                Rectangle {
                    anchors.centerIn: parent
                    width: parent.width + 14
                    height: width
                    radius: slot.corner + 7
                    color: "transparent"
                    antialiasing: true
                    visible: slot.grow > 0.05
                    border.width: 1
                    border.color: Qt.alpha(slot.modelData.tint, slot.grow * (0.25 + 0.25 * nightLight.breath))
                }

                // Everything that can be pressed sits in here, so the press
                // shrink never changes the area the mouse reacts to
                Item {
                    anchors.fill: parent
                    scale: area.pressed ? 0.94 : 1

                    Behavior on scale {
                        NumberAnimation {
                            duration: Style.pressMs
                            easing.type: Style.easePress
                        }
                    }

                    // Glass, like the bar: one flat surface with a hairline outline,
                    // in the preset's colour once highlighted
                    Rectangle {
                        anchors.fill: parent
                        radius: slot.corner
                        antialiasing: true
                        color: Style.card
                        border.width: 1
                        border.color: slot.current ? Qt.alpha(slot.modelData.tint, 0.8) : Qt.alpha(Colors.foreground, 0.2)

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
                        width: parent.width - slot.corner * 1.2
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

                    // The swatch: the colour this preset gives the screen
                    Rectangle {
                        anchors.centerIn: parent
                        width: parent.width * 0.5
                        height: width
                        radius: width * 0.34
                        // Stays upright while the squircle tilts with the dial
                        rotation: -slot.rotation
                        antialiasing: true
                        color: slot.modelData.tint
                        opacity: slot.active ? 1 : (slot.current ? 1 : 0.88)
                        // The one the screen is on fills out; the others sit a little smaller
                        scale: slot.active ? 1.12 : 0.94

                        Behavior on opacity {
                            NumberAnimation {
                                duration: Style.fadeMs
                            }
                        }
                        Behavior on scale {
                            NumberAnimation {
                                duration: Style.moveMs
                                easing.type: Style.easePop
                                easing.overshoot: 1.6
                            }
                        }
                    }
                }

                MouseArea {
                    id: area

                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    // Position, not enter, so a still mouse under the dial
                    // doesn't steal the keyboard selection when it opens
                    onPositionChanged: nightLight.selectedIndex = slot.index
                    onClicked: nightLight.setTemperature(slot.modelData.temp)
                }
            }
        }

        // Accent underline above the highlighted preset; it breathes with the ring.
        Rectangle {
            readonly property real s: nightLight.sFor(nightLight.presets[nightLight.selectedIndex].temp) - nightLight.spinIn * nightLight.stepPx
            readonly property real a: s / nightLight.dialNow

            width: 20 + 10 * nightLight.breath
            height: 2
            radius: 1
            color: nightLight.presets[nightLight.selectedIndex].tint
            x: stage.cx + nightLight.dialNow * Math.sin(a) - width / 2
            y: nightLight.topY + nightLight.dialNow * (1 - Math.cos(a)) - 34 - 6
            rotation: a * 180 / Math.PI
            opacity: nightLight.clamp(nightLight.reveal * 2 - 0.6, 0, 1)
        }

        // ---- The middle: the number, and what it is called --------------------
        // Click it to switch the filter on or off.
        Rectangle {
            x: stage.cx - width / 2
            y: readout.y - 4
            width: 150
            height: readout.height + 8
            radius: Style.radiusLg
            color: Qt.alpha(nightLight.tint, Style.tintAlpha)
            opacity: coreArea.pressed ? 1 : (coreArea.containsMouse ? 0.6 : 0)

            Behavior on opacity {
                NumberAnimation {
                    duration: Style.fadeMs
                }
            }
        }

        MouseArea {
            id: coreArea

            hoverEnabled: true
            x: stage.cx - 75
            y: readout.y - 4
            width: 150
            height: readout.height + 8
            cursorShape: Qt.PointingHandCursor
            onClicked: nightLight.togglePower()
        }

        Item {
            id: readout

            x: stage.cx - width / 2
            y: nightLight.ruleY + 32
            width: 220
            height: 52
            // Clicks pass through to the middle
            enabled: false
            transform: Translate {
                y: (1 - nightLight.stage_(0.25, 0.8)) * 12
            }

            // The number, with a soft shadow in the background colour so it reads on any wallpaper
            Txt {
                y: 1.5
                width: parent.width
                height: 32
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                text: Math.round(nightLight.shownTemp) + "K"
                color: Qt.alpha(Colors.background, 0.9)
                font.pixelSize: 26
                font.bold: true
            }

            Txt {
                width: parent.width
                height: 32
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                text: Math.round(nightLight.shownTemp) + "K"
                color: nightLight.filterOn ? nightLight.tint : Colors.foreground
                font.pixelSize: 26
                font.bold: true
                font.letterSpacing: -0.2
            }

            Txt {
                id: nameText

                y: 34
                width: parent.width
                height: 16
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                text: nightLight.filterOn ? nightLight.nameFor(nightLight.temperature) : "Off"
                color: Colors.muted
                font.pixelSize: Style.fontXs
                font.letterSpacing: 1.4
                font.capitalization: Font.AllUppercase
                onTextChanged: nameFade.restart()
            }
        }
    }
}
