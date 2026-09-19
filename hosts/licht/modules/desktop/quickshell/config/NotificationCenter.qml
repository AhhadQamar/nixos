import QtQuick
import QtQuick.Layouts
// NotificationCenter.qml
// The full notification history/inbox. Toggle via IPC, e.g.:
//   qs -p <your shell.qml path> ipc call notifications toggle
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets

PanelWindow {
    id: center

    function toggle() {
        visible = !visible;
    }

    function open() {
        visible = true;
    }

    function close() {
        visible = false;
    }

    visible: false
    color: "transparent"
    margins.top: 50
    margins.right: 12
    implicitWidth: 380
    implicitHeight: 520
    exclusiveZone: 0
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    anchors {
        top: true
        right: true
    }

    IpcHandler {
        function toggle() {
            center.toggle();
        }

        function open() {
            center.open();
        }

        function close() {
            center.close();
        }

        function clear() {
            NotificationServer.clearHistory();
        }

        target: "notifications"
    }

    Rectangle {
        anchors.fill: parent
        radius: 14
        color: Colors.background
        border.width: 2
        border.color: Colors.accent
        opacity: 0.97

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 8

            RowLayout {
                Layout.fillWidth: true

                Text {
                    text: "Notifications"
                    color: Colors.foreground
                    font.pixelSize: 16
                    font.bold: true
                    Layout.fillWidth: true
                }

                Rectangle {
                    radius: 6
                    implicitWidth: dndLabel.implicitWidth + 16
                    implicitHeight: 26
                    color: NotificationServer.doNotDisturb ? Colors.accent : Colors.surface

                    Text {
                        id: dndLabel

                        anchors.centerIn: parent
                        text: "DND"
                        font.pixelSize: 11
                        font.bold: true
                        color: NotificationServer.doNotDisturb ? Colors.background : Colors.muted
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: NotificationServer.toggleDnd()
                    }
                }

                Rectangle {
                    radius: 6
                    implicitWidth: clearLabel.implicitWidth + 16
                    implicitHeight: 26
                    color: Colors.surface

                    Text {
                        id: clearLabel

                        anchors.centerIn: parent
                        text: "Clear"
                        font.pixelSize: 11
                        color: Colors.muted
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: NotificationServer.clearHistory()
                    }
                }
            }

            ListView {
                id: historyList

                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: 8
                model: NotificationServer.history

                Text {
                    anchors.centerIn: parent
                    visible: NotificationServer.history.length === 0
                    text: "No notifications"
                    color: Colors.muted
                    font.pixelSize: 14
                }

                delegate: Rectangle {
                    width: historyList.width
                    implicitHeight: histContent.implicitHeight + 20
                    radius: 10
                    color: Colors.surfaceAlt

                    RowLayout {
                        id: histContent

                        anchors.fill: parent
                        anchors.margins: 10
                        spacing: 10

                        Image {
                            visible: modelData.appIcon.length > 0
                            source: Quickshell.iconPath(modelData.appIcon, "dialog-information")
                            width: 32
                            height: 32
                            sourceSize.width: 32
                            sourceSize.height: 32
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2

                            Text {
                                text: modelData.appName
                                color: Colors.muted
                                font.pixelSize: 10
                            }

                            Text {
                                text: modelData.summary
                                color: Colors.foreground
                                font.pixelSize: 13
                                font.bold: true
                                wrapMode: Text.WordWrap
                                Layout.fillWidth: true
                            }

                            Text {
                                visible: modelData.body.length > 0
                                text: modelData.body
                                color: Colors.muted
                                font.pixelSize: 11
                                wrapMode: Text.WordWrap
                                Layout.fillWidth: true
                                maximumLineCount: 2
                                elide: Text.ElideRight
                            }
                        }

                        Text {
                            text: "✕"
                            color: Colors.muted
                            font.pixelSize: 12

                            MouseArea {
                                anchors.fill: parent
                                anchors.margins: -8
                                onClicked: NotificationServer.dismissHistory(modelData.id)
                            }
                        }
                    }
                }
            }
        }
    }
}
