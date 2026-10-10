// System tray: the first few icons sit in the bar, the rest fold into a "+N"
// chip that opens a small list. Hides itself when nothing is in the tray.

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Services.SystemTray

Island {
    id: root

    // Icons shown in the bar itself
    readonly property int maxInline: 2
    // status 0 = Passive: the app asked to be hidden (udiskie does this when no drive is attached)
    readonly property var items: SystemTray.items.values.filter(i => i.status !== 0)
    readonly property int count: items.length
    readonly property int extra: Math.max(0, count - maxInline)

    padding: 8
    spacing: 2
    visible: count > 0

    Repeater {
        model: root.items.slice(0, root.maxInline)

        delegate: TrayIcon {
            required property var modelData

            anchors.verticalCenter: parent.verticalCenter
            item: modelData
        }
    }

    Rectangle {
        id: chip

        visible: root.extra > 0
        anchors.verticalCenter: parent.verticalCenter
        implicitHeight: Style.itemHeight - 4
        implicitWidth: label.implicitWidth + 18
        radius: height / 2
        antialiasing: true
        color: more.visible ? Qt.alpha(Colors.foreground, 0.12) : (hover.hovered ? Style.hoverFill : "transparent")

        Behavior on color {
            ColorAnimation {
                duration: 200
            }
        }

        Text {
            id: label

            anchors.centerIn: parent
            text: "+" + root.extra
            textFormat: Text.PlainText
            color: Colors.muted

            font {
                family: Style.fontFamily
                pixelSize: 11
            }
        }

        TapHandler {
            onTapped: more.toggle()
        }
        HoverHandler {
            id: hover

            cursorShape: Qt.PointingHandCursor
        }
    }

    // ---- The folded list ---------------------------------------------------
    PopupWindow {
        id: more

        property double closedAt: 0

        function toggle() {
            if (visible) {
                visible = false;
                return;
            }
            if (Date.now() - closedAt < 200)
                return;
            const win = root.QsWindow.window;
            anchor.rect = win.contentItem.mapFromItem(chip, 0, 0, chip.width, chip.height + 6);
            visible = true;
        }

        function close() {
            visible = false;
        }

        visible: false
        color: "transparent"
        implicitWidth: 214
        implicitHeight: list.implicitHeight + 12
        anchor.window: root.QsWindow.window
        anchor.edges: Edges.Bottom | Edges.Right
        anchor.gravity: Edges.Bottom | Edges.Left
        onVisibleChanged: if (visible)
            fadeIn.restart()

        HyprlandFocusGrab {
            windows: [more]
            active: more.visible
            onCleared: {
                more.visible = false;
                more.closedAt = Date.now();
            }
        }

        NumberAnimation {
            id: fadeIn

            target: card
            property: "opacity"
            from: 0
            to: 1
            duration: 140
            easing.type: Easing.OutCubic
        }

        Rectangle {
            id: card

            anchors.fill: parent
            radius: Style.barRadius - 2
            antialiasing: true
            color: Qt.alpha(Colors.background, 0.97)
            border.width: 1
            border.color: Style.outline

            Column {
                id: list

                x: 6
                y: 6
                spacing: 0

                Repeater {
                    model: root.items.slice(root.maxInline)

                    delegate: TrayIcon {
                        required property var modelData

                        item: modelData
                        showLabel: true
                        menuWindow: root.QsWindow.window
                        menuAnchor: chip
                        onTriggered: more.close()
                    }
                }
            }
        }
    }
}
