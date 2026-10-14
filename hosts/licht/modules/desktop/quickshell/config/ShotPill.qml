// A small glass pill with one line of text: the labels of the screenshot
// selection (its width and height on the rulers, the name of a window).
// Glass like the bar and the dial discs: the card fill, a hairline outline and
// the light on the top edge.

import QtQuick

Rectangle {
    id: root

    property string text: ""
    property color textColor: Colors.foreground

    implicitWidth: label.implicitWidth + 16
    implicitHeight: 20
    radius: height / 2
    antialiasing: true
    color: Style.card
    border.width: 1
    border.color: Style.outline

    EdgeLight {
        corner: root.height / 2
    }

    Txt {
        id: label

        anchors.centerIn: parent
        text: root.text
        color: root.textColor
        font.pixelSize: Style.fontSm
        font.bold: true
    }
}
