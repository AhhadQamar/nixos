// Toasts for new notifications, stacked under the bar at its right edge.
// Driven entirely by NotificationServer.active. Click a toast to dismiss it
// (it stays in the notification centre).

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland

PanelWindow {
    id: popups

    color: "transparent"
    // Sits just under the bar, lined up with its right edge
    margins.top: Style.barGap + Style.barHeight + 8
    margins.right: Style.barGap + 2
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

                required property var modelData

                readonly property var notif: modelData
                readonly property bool critical: notif.critical
                readonly property string icon: NotificationServer.iconSource(notif)
                // The list is rebuilt on every change, so only a toast that
                // has just arrived animates in; the rest are already there.
                readonly property bool fresh: Date.now() - notif.time < 400
                property bool shown: !fresh

                Layout.fillWidth: true
                implicitHeight: content.implicitHeight + 28
                radius: Style.barRadius
                antialiasing: true
                // More solid than the bar: toasts sit over other windows' text
                color: Qt.alpha(Colors.background, 0.97)
                border.width: 1
                border.color: Style.outline
                opacity: shown ? 1 : 0
                scale: dismissTap.pressed ? 0.985 : 1
                Component.onCompleted: shown = true

                Behavior on opacity {
                    NumberAnimation {
                        duration: 160
                    }
                }
                Behavior on scale {
                    NumberAnimation {
                        duration: 100
                        easing.type: Easing.OutQuad
                    }
                }

                transform: Translate {
                    x: toast.shown ? 0 : 18

                    Behavior on x {
                        NumberAnimation {
                            duration: 200
                            easing.type: Easing.OutCubic
                        }
                    }
                }

                // Urgent notifications carry the one fixed alert colour; an
                // accent picked from the wallpaper can't be trusted to read
                // as urgent.
                Rectangle {
                    visible: toast.critical
                    anchors.left: parent.left
                    anchors.leftMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    width: 2
                    height: parent.height - 28
                    radius: 1
                    color: Colors.critical
                }

                HoverHandler {
                    id: hover

                    cursorShape: Qt.PointingHandCursor
                }

                TapHandler {
                    id: dismissTap

                    onTapped: NotificationServer.dismissActive(toast.notif.id)
                }

                RowLayout {
                    id: content

                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.leftMargin: 18
                    anchors.rightMargin: 14
                    anchors.topMargin: 14
                    spacing: 12

                    // Picture, app icon, or the app's first letter
                    Rectangle {
                        Layout.alignment: Qt.AlignTop
                        implicitWidth: 36
                        implicitHeight: 36
                        radius: 10
                        antialiasing: true
                        color: Style.hoverFill

                        Image {
                            anchors.fill: parent
                            anchors.margins: toast.notif.image !== "" ? 0 : 7
                            visible: toast.icon !== ""
                            source: toast.icon
                            sourceSize.width: 72
                            sourceSize.height: 72
                            fillMode: Image.PreserveAspectFit
                            asynchronous: true
                        }

                        Text {
                            anchors.centerIn: parent
                            visible: toast.icon === ""
                            textFormat: Text.PlainText
                            text: toast.notif.appName.charAt(0).toUpperCase()
                            color: Colors.foreground

                            font {
                                family: Style.fontFamily
                                pixelSize: 15
                                bold: true
                            }
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 3

                        Text {
                            Layout.fillWidth: true
                            textFormat: Text.PlainText
                            elide: Text.ElideRight
                            text: toast.notif.appName
                            color: Colors.muted

                            font {
                                family: Style.fontFamily
                                pixelSize: 11
                            }
                        }

                        Text {
                            Layout.fillWidth: true
                            visible: text !== ""
                            textFormat: Text.PlainText
                            wrapMode: Text.Wrap
                            maximumLineCount: 2
                            elide: Text.ElideRight
                            text: toast.notif.summary
                            color: Colors.foreground

                            font {
                                family: Style.fontFamily
                                pixelSize: 13
                                bold: true
                            }
                        }

                        Text {
                            Layout.fillWidth: true
                            visible: text !== ""
                            textFormat: Text.PlainText
                            wrapMode: Text.Wrap
                            maximumLineCount: 3
                            elide: Text.ElideRight
                            text: toast.notif.body
                            color: Colors.muted

                            font {
                                family: Style.fontFamily
                                pixelSize: 12
                            }
                        }

                        RowLayout {
                            visible: toast.notif.actions.length > 0
                            Layout.topMargin: 6
                            spacing: 6

                            Repeater {
                                model: toast.notif.actions

                                delegate: Rectangle {
                                    id: action

                                    required property var modelData

                                    implicitWidth: actionLabel.implicitWidth + 24
                                    implicitHeight: 26
                                    radius: height / 2
                                    antialiasing: true
                                    color: actionArea.containsMouse ? Colors.accent : Style.hoverFill
                                    scale: actionArea.pressed ? 0.94 : 1

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

                                    Text {
                                        id: actionLabel

                                        anchors.centerIn: parent
                                        textFormat: Text.PlainText
                                        text: action.modelData.text
                                        color: actionArea.containsMouse ? Colors.background : Colors.foreground

                                        font {
                                            family: Style.fontFamily
                                            pixelSize: 12
                                            weight: Font.Medium
                                        }
                                    }

                                    MouseArea {
                                        id: actionArea

                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: NotificationServer.invokeAction(toast.notif, action.modelData.id)
                                    }
                                }
                            }
                        }
                    }

                    // Close mark: always takes its space so nothing shifts on hover
                    Text {
                        Layout.alignment: Qt.AlignTop
                        textFormat: Text.PlainText
                        text: "\uf00d"
                        opacity: hover.hovered ? 1 : 0
                        color: closeArea.containsMouse ? Colors.critical : Colors.muted

                        Behavior on opacity {
                            NumberAnimation {
                                duration: 150
                            }
                        }
                        Behavior on color {
                            ColorAnimation {
                                duration: 200
                            }
                        }

                        font {
                            family: Style.fontFamily
                            pixelSize: 13
                        }

                        MouseArea {
                            id: closeArea

                            anchors.fill: parent
                            anchors.margins: -8
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: NotificationServer.dismissActive(toast.notif.id)
                        }
                    }
                }
            }
        }
    }
}
