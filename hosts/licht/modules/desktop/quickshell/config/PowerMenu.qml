// PowerMenu.qml
// Session actions on the launcher's dial: the same borderless stage rising
// from the bottom edge, the same fine ruler, bar-style glass discs and accent
// underline.
// The five actions sit side by side along the dial; the underline glides to the
// highlighted one and its name appears in the middle, and nothing else.
// Reboot and Shutdown are red and need a second press, with a red line running
// down the time left to confirm.
// Like the launcher it arrives as a rainbow: the actions swing in from the left
// over a tight dome, washed with the wallpaper's palette colours, then unfurl
// into the calm dial as the colour drains. Closing plays it in reverse, and the
// chosen action pulses before the dial goes.
//   qs ipc call powermenu toggle | open | close
// Keys: ← → ↑ ↓ (h j k l) or tab move   enter run   1-5 jump   esc close
// Mouse: hover highlights, click runs, scroll wheel moves

import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

PanelWindow {
    id: menu

    // ---- Settings -------------------------------------------------------
    // Each action: label, one-line hint, Nerd Font codepoint, shell command,
    // and whether it is destructive (red, asks for a second press).
    readonly property var actions: [
        {
            "label": "Lock",
            "hint": "Lock the screen",
            "icon": 0xF033E,
            "cmd": "hyprlock",
            "critical": false
        },
        {
            "label": "Logout",
            "hint": "End this session",
            "icon": 0xF0343,
            "cmd": "uwsm stop",
            "critical": false
        },
        {
            "label": "Suspend",
            "hint": "Sleep, keep everything open",
            "icon": 0xF0904,
            "cmd": "systemctl suspend",
            "critical": false
        },
        {
            "label": "Reboot",
            "hint": "Restart the machine",
            "icon": 0xF0709,
            "cmd": "systemctl reboot",
            "critical": true
        },
        {
            "label": "Shutdown",
            "hint": "Power off",
            "icon": 0xF0425,
            "cmd": "systemctl poweroff",
            "critical": true
        }
    ]

    // Same stage and dial as the launcher
    readonly property int stageH: 280
    readonly property int topY: 70
    readonly property real stepPx: 100
    readonly property real dialR: Math.max(900, width * 0.92)
    // The dome the dial starts as when it opens (and ends as when it closes)
    readonly property real rainbowR: Math.min(380, Math.max(280, width * 0.2))

    readonly property int itemSize: 54
    readonly property int selectedSize: 78

    readonly property int ruleDrop: 52
    readonly property int ruleY: topY + ruleDrop
    readonly property int tickGap: 12
    readonly property int tickCount: Math.ceil(width / tickGap / 10) * 10 + 20

    // Strength of the lower-edge shade (0 = none, 1 = solid)
    readonly property real scrim: 0.95
    // How long a pending confirmation stays armed, in ms
    readonly property int confirmMs: 3000

    // ---- State ----------------------------------------------------------
    property bool isOpen: false
    // 0 = hidden below the edge, 1 = in place
    property real reveal: 0
    // Slots the actions are swung to the left while arriving (and right when leaving)
    property real spinIn: 0
    // 1 = tight rainbow dome with spectral tint, 0 = the resting dial
    property real fan: 1
    // A slow pulse (0..1) for the highlighted action's ring
    property real breath: 0
    property int selected: 0
    // Action waiting for its second press, or -1
    property int armed: -1
    // 1 right after arming, running down to 0 as the confirmation lapses
    property real armLeft: 0
    // An action has been chosen and the dial is pulsing before it closes
    property bool launching: false
    // 0..1 while it pulses
    property real launchPulse: 0
    // Sideways nudge of the name when the highlight moves (it slides in from
    // the side the highlight came from)
    property real readShift: 0
    property int lastSelected: 0
    // Opens on the monitor that has focus (set in open())
    property var targetScreen: Focus.screen

    readonly property var current: actions[selected]
    readonly property bool isArmed: armed === selected
    // Red for the destructive actions, the accent for the rest; eases between
    property color tint: current.critical ? Colors.critical : Colors.accent
    // Where the highlighted action is, in slots from the middle one
    readonly property real markerGoal: selected - (actions.length - 1) / 2
    // Where the underline is: it glides to the goal, and stretches while it
    // travels
    property real markerK: markerGoal
    // Radius of the dial right now: curvature eases from the dome to the dial
    readonly property real dialNow: 1 / (1 / dialR + (1 / rainbowR - 1 / dialR) * fan)

    Behavior on tint {
        ColorAnimation {
            duration: Style.baseMs
        }
    }

    Behavior on markerK {
        // The underline glides to the next action and settles, with no bounce
        NumberAnimation {
            duration: Style.moveMs
            easing.type: Style.easeMove
        }
    }

    // Moving the highlight cancels a pending confirmation
    onSelectedChanged: armed = -1

    onArmedChanged: {
        if (armed >= 0) {
            armAnim.restart();
        } else {
            armAnim.stop();
            armLeft = 0;
        }
    }

    function clamp(v, a, b) {
        return Math.max(a, Math.min(b, v));
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

    // `base` washed with one of the palette's colours, chosen by screen
    // position x (colour1 on the left through colour6 on the right). The wash
    // is `fan` strong, so it only shows while the dial is arriving or leaving,
    // and it follows the wallpaper like everything else in the shell.
    function spectral(base, x, a) {
        const ramp = [Colors.color1, Colors.color2, Colors.color3, Colors.color4, Colors.color5, Colors.color6];
        const t = (clamp((x - width / 2) / (width * 0.34), -1, 1) * 0.5 + 0.5) * (ramp.length - 1);
        const i = Math.min(ramp.length - 2, Math.floor(t));
        const c = Qt.tint(ramp[i], Qt.alpha(ramp[i + 1], t - i));
        return Qt.alpha(Qt.tint(base, Qt.alpha(c, 0.9 * fan)), a);
    }

    // Where slot k (in slots from the middle, swing included) sits on the dial
    function slotAngle(k) {
        return k * stepPx / dialNow;
    }

    // ---- Actions --------------------------------------------------------
    function open() {
        if (isOpen)
            return;
        armed = -1;
        selected = 0;
        lastSelected = 0;
        readShift = 0;
        launching = false;
        launchPulse = 0;
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
        armed = -1;
        openAnim.stop();
        closeAnim.restart();
    }

    function toggle() {
        if (isOpen)
            close();
        else
            open();
    }

    function select(i) {
        // Hovering over another action while the chosen one pulses must not
        // move the highlight
        if (launching)
            return;
        selected = i;
    }

    // dir: +1 = right, -1 = left, wrapping round
    function step(dir) {
        select((selected + dir + actions.length) % actions.length);
    }

    function activate(i) {
        if (launching)
            return;
        const a = actions[i];
        // First press on a destructive action only arms it
        if (a.critical && armed !== i) {
            armed = i;
            return;
        }
        // Run it now; the dial pulses and then closes while it takes effect
        launching = true;
        armed = -1;
        Quickshell.execDetached(["bash", "-c", a.cmd]);
        launchAnim.restart();
    }

    // ---- Window ---------------------------------------------------------
    // Fullscreen and invisible, like the launcher: it only exists so a click
    // outside the dial can close the menu.
    visible: isOpen || reveal > 0.001
    screen: targetScreen
    color: "transparent"
    exclusiveZone: 0
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "qs-powermenu"
    WlrLayershell.keyboardFocus: isOpen ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    IpcHandler {
        function toggle() {
            menu.toggle();
        }

        function open() {
            menu.open();
        }

        function close() {
            menu.close();
        }

        target: "powermenu"
    }

    // A pending confirmation lapses after a few seconds
    Timer {
        interval: menu.confirmMs
        running: menu.armed >= 0
        onTriggered: menu.armed = -1
    }

    // The red line under the name shrinks while the confirmation runs out
    NumberAnimation {
        id: armAnim

        target: menu
        property: "armLeft"
        from: 1
        to: 0
        duration: menu.confirmMs
        easing.type: Easing.Linear
    }

    // Rises smoothly. The actions swing in from the left over a tight dome and
    // unfurl into the dial while the spectrum drains out of them.
    ParallelAnimation {
        id: openAnim

        NumberAnimation {
            target: menu
            property: "reveal"
            from: 0
            to: 1
            duration: Style.sweepMs
            easing.type: Style.easeEnter
        }
        NumberAnimation {
            target: menu
            property: "spinIn"
            from: 3.2
            to: 0
            duration: Style.sweepMs + Style.moveMs
            easing.type: Style.easeEnter
        }
        NumberAnimation {
            target: menu
            property: "fan"
            from: 1
            to: 0
            duration: Style.sweepMs + Style.ambientMs / 2
            easing.type: Style.easeMove
        }
    }

    // Leaving: the dial curls back into the dome and the actions sweep off right.
    ParallelAnimation {
        id: closeAnim

        NumberAnimation {
            target: menu
            property: "reveal"
            to: 0
            duration: Style.moveMs + Style.fadeMs
            easing.type: Style.easeExit
        }
        NumberAnimation {
            target: menu
            property: "spinIn"
            to: -3.2
            duration: Style.moveMs + Style.fadeMs
            easing.type: Style.easeExit
        }
        NumberAnimation {
            target: menu
            property: "fan"
            to: 1
            duration: Style.moveMs + Style.fadeMs
            easing.type: Style.easeExit
        }
    }

    // Slow breath for the ring around the highlighted action.
    SequentialAnimation {
        running: menu.isOpen
        loops: Animation.Infinite

        NumberAnimation {
            target: menu
            property: "breath"
            from: 0
            to: 1
            duration: Style.ambientMs * 2
            easing.type: Style.easeAmbient
        }
        NumberAnimation {
            target: menu
            property: "breath"
            from: 1
            to: 0
            duration: Style.ambientMs * 2
            easing.type: Style.easeAmbient
        }
    }

    // The chosen action swells while the others fall back, then the dial closes
    SequentialAnimation {
        id: launchAnim

        NumberAnimation {
            target: menu
            property: "launchPulse"
            from: 0
            to: 1
            duration: Style.fadeMs
            easing.type: Style.easeMove
        }
        ScriptAction {
            script: menu.close()
        }
    }

    // The highlighted action changes: the name slides in from the side the
    // highlight came from, fading and settling
    Connections {
        target: menu

        function onSelectedChanged() {
            const n = menu.actions.length;
            let d = menu.selected - menu.lastSelected;
            if (d > n / 2)
                d -= n;
            if (d < -n / 2)
                d += n;
            menu.lastSelected = menu.selected;
            menu.readShift = d > 0 ? 16 : -16;
            pop.restart();
        }
    }

    ParallelAnimation {
        id: pop

        NumberAnimation {
            target: readout
            property: "opacity"
            from: 0.25
            to: 1
            duration: Style.baseMs
            easing.type: Style.easeMove
        }
        NumberAnimation {
            target: readout
            property: "scale"
            from: 0.94
            to: 1
            duration: Style.baseMs
            easing.type: Style.easeMove
        }
        NumberAnimation {
            target: menu
            property: "readShift"
            to: 0
            duration: Style.moveMs
            easing.type: Style.easeMove
        }
    }

    PanelLink {
        win: menu
        name: "powermenu"
    }

    // The shared dim (Dim.qml): the same wash as the screenshot tool
    Dim {
        reveal: menu.reveal
    }

    // Click anywhere outside the dial to close. The wheel moves the highlight.
    MouseArea {
        anchors.fill: parent
        onClicked: menu.close()
        onWheel: wheel => menu.step(wheel.angleDelta.y < 0 ? 1 : -1)
    }

    Item {
        id: keys

        anchors.fill: parent
        focus: menu.isOpen
        Keys.onPressed: event => {
            if (menu.launching)
                return;
            const k = event.key;
            const ctrl = (event.modifiers & Qt.ControlModifier) !== 0;
            if (k === Qt.Key_Escape)
                menu.close();
            else if (k === Qt.Key_Right || k === Qt.Key_Down || k === Qt.Key_L || k === Qt.Key_J || k === Qt.Key_Tab || (ctrl && k === Qt.Key_N))
                menu.step(1);
            else if (k === Qt.Key_Left || k === Qt.Key_Up || k === Qt.Key_H || k === Qt.Key_K || k === Qt.Key_Backtab || (ctrl && k === Qt.Key_P))
                menu.step(-1);
            else if (k === Qt.Key_Return || k === Qt.Key_Enter)
                menu.activate(menu.selected);
            else if (k >= Qt.Key_1 && k < Qt.Key_1 + menu.actions.length) {
                menu.select(k - Qt.Key_1);
                menu.activate(menu.selected);
            }
        }
    }

    // ---- Stage ----------------------------------------------------------
    Item {
        id: stage
        readonly property real cx: width / 2

        anchors.bottom: parent.bottom
        width: parent.width
        height: menu.stageH
        opacity: Math.min(1, menu.reveal * 3)
        transform: Translate {
            y: (1 - menu.reveal) * (menu.stageH + 40)
        }

        // Screenshot's feathered backing (StageShade.qml): a soft dark ellipse,
        // no visible panel boundary, over the shared dim under it.
        StageShade {}

        // Wide, low light on the horizon, in the colour of the highlight
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
                        color: Qt.alpha(menu.tint, 0.09)
                    }
                    GradientStop {
                        position: 0.5
                        color: Qt.alpha(menu.tint, 0.03)
                    }
                    GradientStop {
                        position: 1
                        color: Qt.alpha(menu.tint, 0)
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

        // Fine dial ruler. It drifts against the highlight at half speed.
        Repeater {
            model: menu.tickCount

            delegate: Rectangle {
                id: tick
                required property int index

                readonly property real span: menu.tickCount * menu.tickGap
                readonly property real dx: ((index * menu.tickGap + (menu.markerK - menu.spinIn) * menu.stepPx * 0.5) % span + span) % span - span / 2
                readonly property real a: dx / menu.dialNow
                readonly property real rr: menu.dialNow - menu.ruleDrop
                readonly property bool major: index % 10 === 0
                readonly property bool mid: index % 5 === 0

                x: stage.cx + rr * Math.sin(a) - 0.5
                y: menu.topY + menu.dialNow - rr * Math.cos(a)
                width: 1
                height: major ? 9 : (mid ? 6 : 3)
                radius: 0.5
                antialiasing: true
                visible: Math.abs(a) < 1.2 && y < stage.height - 70
                transformOrigin: Item.Top
                rotation: a * 180 / Math.PI
                color: menu.spectral(Colors.foreground, x, major ? 0.95 : (mid ? 0.7 : 0.5))
                opacity: menu.clamp((stage.cx - Math.abs(x - stage.cx)) / 230, 0, 1)
                         * menu.clamp((stage.height - y) / 82, 0, 1)
                         * menu.clamp(menu.reveal * 2 - Math.abs(x - stage.cx) / stage.cx * 0.9, 0, 1)
            }
        }

        // Fine center marker on the ruler, with a soft bead at its foot.
        Rectangle {
            x: stage.cx - 0.75
            y: menu.ruleY - 1
            width: 1.5
            height: 12
            radius: 0.5
            color: menu.tint
        }
        Rectangle {
            x: stage.cx - width / 2
            y: menu.ruleY + 14
            width: 5
            height: 5
            radius: 2.5
            color: menu.tint
            opacity: 0.55 + 0.4 * menu.breath
        }

        // Underline above the highlighted action. It glides between actions
        // and stretches from where it was to where it is going, then settles.
        Rectangle {
            id: marker

            readonly property real k: menu.markerK - menu.spinIn
            readonly property real a: menu.slotAngle(k)

            width: 20 + 10 * menu.breath + 46 * Math.min(1, Math.abs(menu.markerK - menu.markerGoal))
            height: 2
            radius: 1
            color: menu.tint
            x: stage.cx + menu.dialNow * Math.sin(a) - width / 2
            y: menu.topY + menu.dialNow * (1 - Math.cos(a)) - menu.selectedSize * 0.62 - 8
            rotation: a * 180 / Math.PI
            opacity: menu.clamp(menu.reveal * 2 - 0.6, 0, 1)
        }

        // ---- The actions ------------------------------------------------
        Repeater {
            model: menu.actions

            delegate: Item {
                id: slot

                required property int index
                required property var modelData

                readonly property bool current: index === menu.selected
                readonly property bool armed: index === menu.armed
                // Slots from the middle one: -2 .. 2 for five actions
                readonly property real k0: index - (menu.actions.length - 1) / 2
                // Swung left while arriving, right while leaving
                readonly property real k: k0 - menu.spinIn
                readonly property real a: menu.slotAngle(k)
                readonly property color tint: modelData.critical ? Colors.critical : Colors.accent
                // 0 at rest, 1 when highlighted. Animated, so the item swells.
                property real grow: current ? 1 : 0
                readonly property real sz: menu.itemSize + (menu.selectedSize - menu.itemSize) * grow
                readonly property real px: stage.cx + menu.dialNow * Math.sin(a)
                // The highlighted one also lifts a little off the dial
                readonly property real py: menu.topY + menu.dialNow * (1 - Math.cos(a)) - 8 * grow
                // The actions arrive in a left-to-right wave, each with a small
                // overshoot, and leave the same way.
                readonly property real appear: menu.clamp((menu.reveal - (k0 + 2) * 0.05) / 0.42, 0, 1)
                readonly property real pop_: menu.backOut(appear)
                // 0 under the pointer: a gentle lift
                property real hover: area.containsMouse && !current ? 1 : 0
                // 0..1 while the ring around a newly highlighted action expands
                property real ping: 0
                // Shape: a squircle that rounds a little more as it is highlighted
                readonly property real corner: sz * (0.36 + 0.06 * grow)
                readonly property real edge: menu.clamp((stage.cx - Math.abs(px - stage.cx)) / 105, 0, 1)
                readonly property real horizon: menu.clamp((stage.height - py + sz * 0.3) / (sz * 0.6), 0, 1)

                visible: py - sz / 2 < stage.height
                width: sz
                height: sz
                x: px - sz / 2
                y: py - sz / 2
                z: current ? 20 : 10 - Math.abs(k0)
                // On choosing, this one swells and the others fall back
                opacity: appear * edge * horizon * (current ? 1 : 1 - 0.65 * menu.launchPulse)
                scale: (0.55 + 0.45 * pop_) * (current ? 1 + 0.14 * menu.launchPulse : 1)
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

                // The highlight moved to this one: a ring leaves it.
                onCurrentChanged: if (current && menu.isOpen && menu.reveal > 0.8)
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
                    border.color: Qt.alpha(slot.armed ? Colors.critical : slot.tint, 0.5 * (1 - slot.ping))
                }

                // Swells with a little overshoot, settles back without one
                Behavior on grow {
                    NumberAnimation {
                        duration: Style.moveMs
                        easing.type: slot.current ? Style.easePop : Style.easeMove
                        easing.overshoot: 1.2
                    }
                }

                // A small shake when it arms, so the second press is noticed
                onArmedChanged: if (armed)
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

                // Breathing ring around the highlighted action; red while armed
                Rectangle {
                    anchors.centerIn: parent
                    width: parent.width + 14
                    height: width
                    radius: slot.corner + 7
                    color: "transparent"
                    antialiasing: true
                    visible: slot.grow > 0.05
                    border.width: 1
                    border.color: slot.armed
                                  ? Qt.alpha(Colors.critical, 0.35 + 0.45 * menu.breath)
                                  : Qt.alpha(slot.tint, slot.grow * (0.2 + 0.2 * menu.breath))
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

                    // Glass, like the bar: one flat surface with a hairline outline.
                    // The outline takes the palette wash while the dial is
                    // arriving, and the tint once highlighted. Armed, it reddens.
                    Rectangle {
                        anchors.fill: parent
                        radius: slot.corner
                        antialiasing: true
                        color: slot.armed ? Qt.tint(Style.card, Qt.alpha(Colors.critical, 0.3)) : Style.card
                        border.width: 1
                        border.color: slot.grow > 0.45
                                      ? menu.spectral(slot.tint, slot.px, 0.6 + 0.4 * slot.grow)
                                      : menu.spectral(slot.modelData.critical ? Colors.critical : Colors.foreground, slot.px, slot.modelData.critical ? 0.45 : 0.2)
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

                    Txt {
                        anchors.centerIn: parent
                        // The glyph stays upright while the disc tilts with the dial
                        rotation: -slot.rotation
                        text: String.fromCodePoint(slot.modelData.icon)
                        // Destructive icons stay red at rest; the rest sit back.
                        color: slot.modelData.critical ? Colors.critical : (slot.current ? Colors.accent : Colors.foreground)
                        opacity: slot.current || slot.modelData.critical ? 1 : 0.9
                        font.pixelSize: 22 + 8 * slot.grow

                        Behavior on color {
                            ColorAnimation {
                                duration: Style.baseMs
                            }
                        }
                        Behavior on opacity {
                            NumberAnimation {
                                duration: Style.fadeMs
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
                    onPositionChanged: menu.select(slot.index)
                    onClicked: menu.activate(slot.index)
                }
            }
        }

        // ---- Central readout --------------------------------------------
        // Just the name, with a soft shadow in the background colour so it reads on any wallpaper.
        Item {
            id: readout

            x: stage.cx - width / 2
            y: menu.ruleY + 30
            width: 460
            height: 30
            transform: Translate {
                x: menu.readShift
                y: (1 - menu.stage_(0.25, 0.8)) * 12
            }

            Item {
                anchors.horizontalCenter: parent.horizontalCenter
                width: Math.min(nameText.implicitWidth, readout.width)
                height: nameText.implicitHeight

                Txt {
                    y: 1.5
                    width: parent.width
                    text: nameText.text
                    color: Qt.alpha(Colors.background, 0.9)
                    font: nameText.font
                }

                Txt {
                    id: nameText
                    width: parent.width
                    text: menu.current.label
                    color: menu.current.critical ? Colors.critical : Colors.foreground
                    font.pixelSize: 22
                    font.bold: true
                    font.letterSpacing: -0.2

                    Behavior on color {
                        ColorAnimation {
                            duration: Style.baseMs
                        }
                    }
                }
            }
        }

        // Only while a destructive action waits for its second press: what to do,
        // and a line running out.
        Item {
            x: stage.cx - width / 2
            y: readout.y + readout.height + 6
            width: 220
            height: 22
            opacity: menu.isArmed ? 1 : 0
            visible: opacity > 0.01

            Behavior on opacity {
                NumberAnimation {
                    duration: Style.baseMs
                }
            }

            Txt {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: "Press again to confirm"
                color: Colors.critical
                font.pixelSize: Style.fontSm
            }

            Rectangle {
                x: (parent.width - 120) / 2
                y: 18
                width: 120
                height: 2
                radius: 1
                color: Style.outline

                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: parent.width * menu.armLeft
                    height: parent.height
                    radius: 1
                    color: Colors.critical
                }
            }
        }
    }
}
