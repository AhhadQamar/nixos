// PowerMenu.qml
// Session actions as a ring, in the launcher's style: one glass disc, the
// actions sitting on a thin ring, the centre naming the highlighted one.
// Reboot and Shutdown are red and need a second press.
//   qs ipc call powermenu toggle | open | close
// Keys: ← → ↑ ↓ (h j k l) or tab turn   enter run   1-5 jump   esc close
// Mouse: hover highlights, click runs, scroll wheel turns the ring

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

    readonly property real stepDeg: 360 / actions.length
    readonly property real ringRadius: 118
    readonly property int itemSize: 56
    readonly property int selectedSize: 68
    // The disc: ring + the selected item's overhang + a margin
    readonly property real discSize: (ringRadius + selectedSize / 2 + 18) * 2
    // The selection arc hugs the outside of the ring, like the bar's underline
    readonly property real arcRadius: ringRadius + selectedSize / 2 + 5

    // ---- State ----------------------------------------------------------
    property int selected: 0
    // Row waiting for its second press, or -1
    property int armed: -1
    // Degrees the highlight has travelled from the top slot. It keeps
    // counting past 360 so the arc always takes the short way round.
    property real turn: 0

    readonly property var current: actions[selected]
    readonly property bool isArmed: armed === selected

    // Moving the highlight cancels a pending confirmation
    onSelectedChanged: armed = -1

    // ---- Actions --------------------------------------------------------
    function open() {
        armed = -1;
        visible = true;
        keys.forceActiveFocus();
        fadeIn.restart();
    }

    function close() {
        visible = false;
        // Start from the top slot next time
        selected = 0;
        turn = 0;
    }

    function toggle() {
        if (visible)
            close();
        else
            open();
    }

    // Move the highlight to action i by the shortest way round the ring
    function select(i) {
        if (i === selected)
            return;
        const n = actions.length;
        let d = ((i - selected) % n + n) % n;
        if (d > n / 2)
            d -= n;
        turn += d * stepDeg;
        selected = i;
    }

    // dir: +1 = clockwise, -1 = anticlockwise
    function step(dir) {
        select((selected + dir + actions.length) % actions.length);
    }

    function activate(i) {
        const a = actions[i];
        // First press on a destructive action only arms it
        if (a.critical && armed !== i) {
            armed = i;
            return;
        }
        Quickshell.execDetached(["bash", "-c", a.cmd]);
        close();
    }

    // ---- Window ---------------------------------------------------------
    // Fullscreen and invisible, like the launcher: it only exists so a click
    // outside the disc can close the menu.
    visible: false
    color: "transparent"
    exclusiveZone: 0
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

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
        interval: 3000
        running: menu.armed >= 0
        onTriggered: menu.armed = -1
    }

    // Click-away-to-close
    MouseArea {
        anchors.fill: parent
        onClicked: menu.close()
    }

    Item {
        id: keys

        anchors.fill: parent
        focus: menu.visible
        Keys.onPressed: event => {
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

    ParallelAnimation {
        id: fadeIn

        NumberAnimation {
            target: disc
            property: "opacity"
            from: 0
            to: 1
            duration: 140
            easing.type: Easing.OutCubic
        }

        NumberAnimation {
            target: disc
            property: "scale"
            from: 0.96
            to: 1
            duration: 140
            easing.type: Easing.OutCubic
        }
    }

    // ---- The disc -------------------------------------------------------
    Item {
        id: disc

        readonly property real cx: width / 2
        readonly property real cy: height / 2

        anchors.centerIn: parent
        width: menu.discSize
        height: width

        Rectangle {
            anchors.fill: parent
            radius: width / 2
            antialiasing: true
            color: Style.surface
            border.width: 1
            border.color: Style.outline
        }

        // Swallows clicks inside the disc so they don't reach the click-away
        // area (clicks in the square's corners still close). The wheel turns
        // the ring.
        MouseArea {
            anchors.fill: parent
            onClicked: mouse => {
                const dx = mouse.x - disc.cx;
                const dy = mouse.y - disc.cy;
                if (dx * dx + dy * dy > disc.cx * disc.cx)
                    menu.close();
            }
            onWheel: wheel => menu.step(wheel.angleDelta.y < 0 ? 1 : -1)
        }

        // Thin guide ring
        Rectangle {
            x: disc.cx - menu.ringRadius
            y: disc.cy - menu.ringRadius
            width: menu.ringRadius * 2
            height: width
            radius: width / 2
            antialiasing: true
            color: "transparent"
            border.width: 1
            border.color: Style.outline
        }

        // Selection arc: the bar's 2px active underline, bent around the
        // outside of the highlighted action. `turn` moves it, and the
        // Behavior below makes it glide instead of jump.
        Shape {
            anchors.fill: parent
            layer.enabled: true
            layer.samples: 4

            ShapePath {
                strokeColor: menu.current.critical ? Colors.critical : Colors.accent
                strokeWidth: 2
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap

                Behavior on strokeColor {
                    ColorAnimation {
                        duration: 200
                    }
                }

                PathAngleArc {
                    centerX: disc.cx
                    centerY: disc.cy
                    radiusX: menu.arcRadius
                    radiusY: menu.arcRadius
                    startAngle: -90 + menu.turn - 18
                    sweepAngle: 36
                }
            }
        }

        // ---- The actions, evenly spaced on the ring, first one at the top
        Repeater {
            model: menu.actions

            delegate: Item {
                id: slot

                required property int index
                required property var modelData

                readonly property bool current: index === menu.selected
                readonly property bool armed: index === menu.armed
                readonly property real angle: (-90 + index * menu.stepDeg) * Math.PI / 180
                readonly property color tint: modelData.critical ? Colors.critical : Colors.accent
                // 0 at rest, 1 when highlighted. Animated, so the item swells.
                property real grow: current ? 1 : 0

                width: menu.itemSize + (menu.selectedSize - menu.itemSize) * grow
                height: width
                x: disc.cx + menu.ringRadius * Math.cos(angle) - width / 2
                y: disc.cy + menu.ringRadius * Math.sin(angle) - height / 2
                scale: area.pressed ? 0.94 : 1

                Behavior on grow {
                    NumberAnimation {
                        duration: 160
                        easing.type: Easing.OutCubic
                    }
                }
                Behavior on scale {
                    NumberAnimation {
                        duration: 100
                        easing.type: Easing.OutQuad
                    }
                }

                // Pill behind the icon: neutral when highlighted, red once armed
                Rectangle {
                    anchors.fill: parent
                    radius: width / 2
                    antialiasing: true
                    color: slot.armed ? Qt.alpha(Colors.critical, 0.18) : (slot.current ? Style.hoverFill : "transparent")

                    Behavior on color {
                        ColorAnimation {
                            duration: 200
                        }
                    }
                }

                Text {
                    anchors.centerIn: parent
                    textFormat: Text.PlainText
                    text: String.fromCodePoint(slot.modelData.icon)
                    // Destructive icons stay red at rest; the rest sit back
                    // like the bar's inactive workspaces.
                    color: slot.modelData.critical ? Colors.critical : (slot.current ? Colors.accent : Colors.foreground)
                    opacity: slot.current ? 1 : (slot.modelData.critical ? 0.8 : 0.65)

                    Behavior on color {
                        ColorAnimation {
                            duration: 200
                        }
                    }
                    Behavior on opacity {
                        NumberAnimation {
                            duration: 150
                        }
                    }

                    font {
                        family: Style.fontFamily
                        pixelSize: 22 + 6 * slot.grow
                    }
                }

                MouseArea {
                    id: area

                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    // Position, not enter, so a still mouse under the disc
                    // doesn't steal the keyboard selection when it opens
                    onPositionChanged: menu.select(slot.index)
                    onClicked: menu.activate(slot.index)
                }
            }
        }

        // ---- Centre: what is highlighted, and what Enter will do ----------
        Column {
            anchors.centerIn: parent
            width: 150
            spacing: 6

            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                textFormat: Text.PlainText
                text: menu.current.label
                color: menu.current.critical ? Colors.critical : Colors.accent

                Behavior on color {
                    ColorAnimation {
                        duration: 200
                    }
                }

                font {
                    family: Style.fontFamily
                    pixelSize: 17
                    bold: true
                }
            }

            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                textFormat: Text.PlainText
                text: menu.isArmed ? "Press enter again" : menu.current.hint
                color: menu.isArmed ? Colors.critical : Colors.muted

                Behavior on color {
                    ColorAnimation {
                        duration: 200
                    }
                }

                font {
                    family: Style.fontFamily
                    pixelSize: 12
                }
            }
        }
    }
}
