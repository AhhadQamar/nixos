// The light catching the top edge of a glass shape: a 1px hairline that fades
// out towards both ends. Put it inside the shape and give it the shape's
// radius as `corner`, so the line stays clear of the rounded ends.

import QtQuick

Rectangle {
    property real corner: Style.radiusXl

    anchors.top: parent.top
    anchors.topMargin: 1
    anchors.horizontalCenter: parent.horizontalCenter
    width: Math.max(0, parent.width - corner * 1.2)
    height: 1

    gradient: Gradient {
        orientation: Gradient.Horizontal

        GradientStop {
            position: 0
            color: Qt.alpha(Colors.foreground, 0)
        }
        GradientStop {
            position: 0.5
            color: Qt.alpha(Colors.foreground, 0.12)
        }
        GradientStop {
            position: 1
            color: Qt.alpha(Colors.foreground, 0)
        }
    }
}
