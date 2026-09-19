import Quickshell.Hyprland
import QtQuick

Rectangle {
    id: root
    property string targetMonitor: ""
    readonly property int dotSize: 28
    readonly property int hoverSize: 46
    readonly property int expandedSize: 60
    readonly property int paddingV: 7
    readonly property int paddingH: 10

    implicitHeight: mainLayout.implicitHeight + paddingV * 2
    implicitWidth: mainLayout.implicitWidth + paddingH * 2
    color: Colors.background
    radius: 12
    antialiasing: true
    anchors.centerIn: parent

    Row {
        id: mainLayout
        spacing: 10
        anchors.centerIn: parent

        Repeater {
            model: Hyprland.workspaces

            delegate: Rectangle {
                id: workspaceDot

                readonly property bool isFocused: modelData.focused
                readonly property bool isActive: modelData.active && !isFocused
                readonly property bool isHovered: dotHoverHandler.hovered

                visible: modelData.id >= 1 && modelData.monitor?.name === root.targetMonitor
                antialiasing: true

                implicitHeight: root.dotSize
                radius: implicitHeight / 2

                implicitWidth: {
                    if (!visible)
                        return 0;
                    if (isFocused || isActive)
                        return root.expandedSize;
                    if (isHovered)
                        return root.hoverSize;
                    return root.dotSize;
                }

                color: {
                    if (isFocused)
                        return Colors.accent;
                    if (isActive)
                        return Qt.lighter(Colors.muted, 1.6);
                    return isHovered ? Qt.lighter(Colors.muted, 1.3) : Colors.muted;
                }

                scale: tapHandler.pressed ? 0.92 : 1

                Behavior on color {
                    ColorAnimation {
                        duration: 200
                    }
                }
                Behavior on implicitWidth {
                    NumberAnimation {
                        duration: 200
                        easing.type: Easing.OutCubic
                    }
                }
                Behavior on scale {
                    NumberAnimation {
                        duration: 100
                        easing.type: Easing.OutQuad
                    }
                }

                TapHandler {
                    id: tapHandler
                    onTapped: modelData.activate()
                }
                HoverHandler {
                    id: dotHoverHandler
                    cursorShape: Qt.PointingHandCursor
                }
            }
        }
    }
}
