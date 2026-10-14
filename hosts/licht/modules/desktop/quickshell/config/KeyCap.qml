// Keyboard hint: a small key-shaped label.

import QtQuick

Rectangle {
    id: cap

    property string label: ""

    implicitWidth: Math.max(20, capText.implicitWidth + 12)
    implicitHeight: 20
    radius: Style.radiusXs
    color: Colors.raisedAlt

    Txt {
        id: capText

        anchors.centerIn: parent
        text: cap.label
        color: Colors.foreground
        opacity: 0.75
        font.pixelSize: Style.fontXs
        font.bold: true
    }
}
