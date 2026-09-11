import QtQuick
import Quickshell

Variants {
    id: root

    model: Quickshell.screens

    delegate: PanelWindow {
        id: mainBar

        required property var modelData

        screen: modelData
        implicitHeight: 36
        color: 'transparent'

        margins {
            top: 5
            left: 10
            right: 10
        }

        anchors {
            top: true
            left: true
            right: true
        }

        Rectangle {
            color: Colors.background
            anchors.fill: parent
            radius: 20

            Clock {}

            Workspaces {
                id: workspaceModule

                targetMonitor: modelData.name
            }

            SystemStats {
                id: systemStats
            }
        }
    }
}
