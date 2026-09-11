// NotificationPopups.qml
// Auto-appearing/auto-expiring toast popups for new notifications.
// Always visible (no IPC toggle needed) — driven entirely by
// NotificationServer.active.

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets

PanelWindow {
    id: popups

    color: "transparent"
    margins.top: 12
    margins.right: 12
    implicitWidth: 360
    implicitHeight: column.implicitHeight
    exclusiveZone: 0
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    visible: NotificationServer.active.length > 0

    anchors {
        top: true
        right: true
    }

    ColumnLayout {
        id: column

        width: parent.width
        spacing: 8

        Repeater {
            model: NotificationServer.active

            delegate: Rectangle {
                id: toast

                property var notif: modelData

                Layout.fillWidth: true
                implicitHeight: content.implicitHeight + 24
                radius: 12
                color: Colors.background
                border.width: 2
                // Critical urgency always uses the fixed, palette-
                // independent "critical" color — an accent picked from
                // the wallpaper can't be trusted to read as urgent.
                border.color: notif.urgency === NotificationUrgency.Critical ? Colors.critical : Colors.accent
                opacity: 0.97

                RowLayout {
                    id: content

                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 10

                    Image {
                        visible: notif.image.length > 0 || notif.appIcon.length > 0
                        source: notif.image.length > 0 ? notif.image : Quickshell.iconPath(notif.appIcon, "dialog-information")
                        sourceSize.width: 40
                        sourceSize.height: 40
                        width: 40
                        height: 40
                        fillMode: Image.PreserveAspectFit
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2

                        Text {
                            text: notif.appName
                            color: Colors.muted
                            font.pixelSize: 11
                        }

                        Text {
                            text: notif.summary
                            color: Colors.foreground
                            font.pixelSize: 14
                            font.bold: true
                            wrapMode: Text.WordWrap
                            Layout.fillWidth: true
                        }

                        Text {
                            visible: notif.body.length > 0
                            text: notif.body
                            color: Colors.muted
                            font.pixelSize: 12
                            wrapMode: Text.WordWrap
                            Layout.fillWidth: true
                            maximumLineCount: 3
                            elide: Text.ElideRight
                        }

                        RowLayout {
                            visible: notif.actions.length > 0
                            spacing: 6

                            Repeater {
                                model: notif.actions

                                delegate: Rectangle {
                                    radius: 6
                                    color: Colors.accent
                                    implicitHeight: 26
                                    implicitWidth: actionLabel.implicitWidth + 16

                                    Text {
                                        id: actionLabel

                                        anchors.centerIn: parent
                                        text: modelData.text
                                        color: Colors.background
                                        font.pixelSize: 11
                                        font.bold: true
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        onClicked: NotificationServer.invokeAction(toast.notif, modelData.id)
                                    }
                                }
                            }
                        }
                    }

                    Text {
                        text: "✕"
                        color: Colors.muted
                        font.pixelSize: 14

                        MouseArea {
                            anchors.fill: parent
                            anchors.margins: -8
                            onClicked: NotificationServer.dismissActive(toast.notif.id)
                        }
                    }
                }
            }
        }
    }
}
