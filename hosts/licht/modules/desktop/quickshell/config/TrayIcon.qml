// One system tray item. Left click activates it (or opens its menu when it
// only has a menu), right click opens its menu, middle click is the secondary
// action. With showLabel it becomes a row for the folded list.

import QtQuick
import Quickshell
import Quickshell.Widgets

Rectangle {
    id: root

    required property var item
    property bool showLabel: false
    // Where a menu is drawn. The folded list points these at the bar so the
    // menu outlives the list closing.
    property var menuWindow: root.QsWindow.window
    property Item menuAnchor: root

    // Fired after a plain activate, so the folded list can close itself
    signal triggered

    // status 2 = NeedsAttention
    readonly property bool attention: item.status === 2

    implicitHeight: showLabel ? 34 : Style.itemHeight
    implicitWidth: showLabel ? 198 : Style.itemHeight
    radius: showLabel ? 10 : height / 2
    antialiasing: true
    color: hover.hovered ? Style.hoverFill : "transparent"
    scale: tap.pressed ? 0.94 : 1

    Behavior on color {
        ColorAnimation {
            duration: 200
        }
    }
    Behavior on scale {
        NumberAnimation {
            duration: 100
            easing.type: Easing.OutQuad
        }
    }

    function showMenu() {
        if (!item.hasMenu || !menuWindow)
            return;
        const p = menuAnchor.mapToItem(null, 0, menuAnchor.height + 6);
        item.display(menuWindow, p.x, p.y);
    }

    Row {
        anchors.verticalCenter: parent.verticalCenter
        anchors.horizontalCenter: root.showLabel ? undefined : parent.horizontalCenter
        x: root.showLabel ? 10 : 0
        spacing: 12

        Item {
            width: root.showLabel ? 18 : 16
            height: width
            anchors.verticalCenter: parent.verticalCenter

            IconImage {
                anchors.fill: parent
                source: root.item.icon
                opacity: hover.hovered ? 1 : 0.85
            }

            // Attention dot
            Rectangle {
                visible: root.attention
                anchors.top: parent.top
                anchors.right: parent.right
                width: 6
                height: 6
                radius: 3
                color: Colors.critical
            }
        }

        Text {
            visible: root.showLabel
            anchors.verticalCenter: parent.verticalCenter
            width: root.implicitWidth - 54
            text: root.item.title || root.item.id
            textFormat: Text.PlainText
            elide: Text.ElideRight
            color: Colors.foreground

            font {
                family: Style.fontFamily
                pixelSize: 13
            }
        }
    }

    TapHandler {
        id: tap

        onTapped: {
            // udiskie has a menu but no "activate" action, so open the menu
            const menuOnly = root.item.onlyMenu || /udiskie/i.test(root.item.id + " " + root.item.title);
            if (menuOnly && root.item.hasMenu) {
                root.showMenu();
            } else {
                root.item.activate();
                root.triggered();
            }
        }
    }
    TapHandler {
        acceptedButtons: Qt.RightButton
        onTapped: root.showMenu()
    }
    TapHandler {
        acceptedButtons: Qt.MiddleButton
        onTapped: root.item.secondaryActivate()
    }
    HoverHandler {
        id: hover

        cursorShape: Qt.PointingHandCursor
    }
}
