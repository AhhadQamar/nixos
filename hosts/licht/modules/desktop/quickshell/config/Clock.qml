import QtQuick
import Quickshell

Rectangle {
    implicitWidth: root.implicitWidth + 50
    color: 'transparent'
    anchors.left: parent.left
    anchors.verticalCenter: parent.verticalCenter

    Text {
        id: root

        text: Time.time
        anchors.centerIn: parent
        color: Colors.foreground

        font {
            family: "JetBrainsMono Nerd Fonts Propo"
            pixelSize: 16
            bold: true
        }
    }
}
