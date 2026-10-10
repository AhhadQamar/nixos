// Time and date for the left of the bar. Click it to open the calendar.

import QtQuick
import Quickshell

Item {
    id: root

    // Lit while the calendar is showing
    property bool open: false

    signal clicked

    implicitHeight: Style.barHeight
    implicitWidth: pill.implicitWidth + 16

    SystemClock {
        id: clock

        precision: SystemClock.Minutes
    }

    Rectangle {
        id: pill

        x: 8
        anchors.verticalCenter: parent.verticalCenter
        implicitHeight: Style.itemHeight + 4
        implicitWidth: row.implicitWidth + 28
        radius: height / 2
        antialiasing: true
        scale: tap.pressed ? 0.97 : 1
        color: root.open ? Qt.alpha(Colors.accent, 0.16) : (hover.hovered ? Style.hoverFill : "transparent")

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

        Row {
            id: row

            anchors.centerIn: parent
            spacing: 8

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: Qt.formatDateTime(clock.date, "h:mm AP")
                textFormat: Text.PlainText
                color: Colors.foreground

                font {
                    family: Style.fontFamily
                    pixelSize: 14
                    bold: true
                }
            }

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: 3
                height: 3
                radius: 1.5
                color: Colors.muted
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: Qt.formatDateTime(clock.date, "ddd d MMM")
                textFormat: Text.PlainText
                color: Colors.muted

                font {
                    family: Style.fontFamily
                    pixelSize: 13
                }
            }
        }

        TapHandler {
            id: tap

            onTapped: root.clicked()
        }
        HoverHandler {
            id: hover

            cursorShape: Qt.PointingHandCursor
        }
    }
}
