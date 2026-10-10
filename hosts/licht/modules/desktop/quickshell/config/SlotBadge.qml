// A tiny slot number in the corner of a pill. It fades in on hover so the bar
// stays clean at rest. Put it directly inside the pill it belongs to.

import QtQuick

Text {
    property bool shown: false
    property color tint: Colors.muted

    anchors.top: parent.top
    anchors.right: parent.right
    anchors.topMargin: 3
    anchors.rightMargin: 9
    textFormat: Text.PlainText
    color: tint
    opacity: shown ? 0.9 : 0

    Behavior on opacity {
        NumberAnimation {
            duration: 150
        }
    }

    font {
        family: Style.fontFamily
        pixelSize: 8
        bold: true
    }
}
