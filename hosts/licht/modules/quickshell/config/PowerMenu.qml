// PowerMenu.qml
// wlogout replacement — a centered grid of power actions.
// Toggle via IPC:
//   qs -p <your shell.qml path> ipc call powermenu toggle

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

PanelWindow {
    id: powerMenu

    // Actions — adjust the commands to match your actual lock screen
    // (currently hyprlock) and session setup if different.
    readonly property var actions: [
        {
            "label": "Lock",
            "icon": "󰌾",
            "cmd": "hyprlock",
            "critical": false
        },
        {
            "label": "Logout",
            "icon": "󰍃",
            "cmd": "uwsm logout",
            "critical": false
        },
        {
            "label": "Suspend",
            "icon": "󰤄",
            "cmd": "systemctl suspend",
            "critical": false
        },
        {
            "label": "Reboot",
            "icon": "󰜉",
            "cmd": "systemctl reboot",
            "critical": true
        },
        {
            "label": "Shutdown",
            "icon": "󰐥",
            "cmd": "systemctl poweroff",
            "critical": true
        }
    ]

    function open() {
        visible = true;
    }

    function close() {
        visible = false;
    }

    function toggle() {
        visible = !visible;
    }

    function run(cmd) {
        Quickshell.execDetached(["bash", "-c", cmd]);
        close();
    }

    visible: false
    color: "transparent"
    exclusiveZone: 0
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    IpcHandler {
        function toggle() {
            powerMenu.toggle();
        }

        function open() {
            powerMenu.open();
        }

        function close() {
            powerMenu.close();
        }

        target: "powermenu"
    }

    // Click-away-to-close backdrop
    MouseArea {
        anchors.fill: parent
        onClicked: powerMenu.close()
    }

    Rectangle {
        anchors.fill: parent
        color: Colors.background
        opacity: 0.55

        MouseArea {
            anchors.fill: parent
            onClicked: powerMenu.close()
        }
    }

    // Global Escape-to-close
    Item {
        anchors.fill: parent
        focus: powerMenu.visible
        Keys.onEscapePressed: powerMenu.close()
    }

    RowLayout {
        anchors.centerIn: parent
        spacing: 24

        Repeater {
            model: powerMenu.actions

            delegate: Rectangle {
                id: card

                property bool hovered: false

                implicitWidth: 140
                implicitHeight: 140
                radius: 18
                color: Colors.surface
                border.width: hovered ? 2 : 0
                border.color: modelData.critical ? Colors.critical : Colors.accent

                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: 10

                    Text {
                        text: modelData.icon
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 42
                        color: card.hovered ? (modelData.critical ? Colors.critical : Colors.accent) : Colors.foreground
                        Layout.alignment: Qt.AlignHCenter

                        Behavior on color {
                            ColorAnimation {
                                duration: 120
                            }
                        }
                    }

                    Text {
                        text: modelData.label
                        font.pixelSize: 13
                        color: Colors.muted
                        Layout.alignment: Qt.AlignHCenter
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onEntered: card.hovered = true
                    onExited: card.hovered = false
                    onClicked: powerMenu.run(modelData.cmd)
                }

                Behavior on border.width {
                    NumberAnimation {
                        duration: 120
                    }
                }
            }
        }
    }
}
