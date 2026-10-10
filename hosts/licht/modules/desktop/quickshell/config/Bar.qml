// One inset glass bar per screen:
//   clock (opens the calendar) left, workspaces centre,
//   tray, bell and system stats right.

import QtQuick
import Quickshell

Variants {
    model: Quickshell.screens

    delegate: PanelWindow {
        id: bar

        required property var modelData

        screen: modelData
        implicitHeight: Style.barHeight
        color: "transparent"

        margins {
            top: Style.barGap
            left: Style.barGap + 2
            right: Style.barGap + 2
        }

        anchors {
            top: true
            left: true
            right: true
        }

        Rectangle {
            anchors.fill: parent
            radius: Style.barRadius
            antialiasing: true
            color: Style.surface
            border.width: 1
            border.color: Style.outline
        }

        Clock {
            id: clock

            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            open: calendar.open
            onClicked: calendar.toggle()
        }

        Workspaces {
            anchors.centerIn: parent
            targetMonitor: bar.modelData.name
            // Keep clear of the clock and the right cluster, which may differ in width
            maxWidth: bar.width - 2 * Math.max(clock.width, right.width) - 48
        }

        Row {
            id: right

            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter

            MusicChip {}

            Tray {
                id: tray
            }

            // Divider between the tray and the status icons
            Item {
                visible: tray.visible
                anchors.verticalCenter: parent.verticalCenter
                width: 9
                height: Style.itemHeight

                Rectangle {
                    anchors.centerIn: parent
                    width: 1
                    height: 16
                    color: Style.outline
                }
            }

            SystemStats {
                id: stats
            }
        }

        CalendarPopup {
            id: calendar

            barWindow: bar
            target: clock
        }
    }
}
