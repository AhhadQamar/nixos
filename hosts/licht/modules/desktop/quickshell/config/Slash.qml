// The "off" slash shared by the drawn icons (muted speaker, Do Not Disturb
// bell, offline network): a hairline from the top left to the bottom right of
// the 16-unit grid that draws itself in when `on` turns true and draws itself
// away when it turns false. Where it crosses the picture, a slightly wider
// stroke in the background colour cuts a small gap, so the two lines do not
// run together.
//
// Put it over the icon with anchors.fill: parent and hand it the icon's `u`
// and colour. It only gets a GPU layer while it is on screen.

import QtQuick
import QtQuick.Shapes

Shape {
    id: root

    property bool on: false
    property color color: Colors.foreground
    // Pixels per grid unit, from the icon (see Glyph.qml)
    property real u: 1

    // 0..1, how much of the line exists. Plain `property real` because it has
    // a Behavior.
    property real drawn: on ? 1 : 0

    // The line, on the grid
    readonly property real x0: 2.5 * u
    readonly property real y0: 2.5 * u
    readonly property real x1: 13.5 * u
    readonly property real y1: 13.5 * u

    visible: drawn > 0.01
    layer.enabled: visible
    layer.samples: 4

    Behavior on drawn {
        NumberAnimation {
            duration: Style.moveMs
            easing.type: Style.easeMove
        }
    }

    // The gap: drawn first, so the line sits on top of it
    Stroke {
        strokeColor: Qt.alpha(Colors.background, 0.9)
        strokeWidth: 4
        startX: root.x0
        startY: root.y0

        PathLine {
            x: root.x0 + (root.x1 - root.x0) * root.drawn
            y: root.y0 + (root.y1 - root.y0) * root.drawn
        }
    }

    Stroke {
        strokeColor: root.color
        startX: root.x0
        startY: root.y0

        PathLine {
            x: root.x0 + (root.x1 - root.x0) * root.drawn
            y: root.y0 + (root.y1 - root.y0) * root.drawn
        }
    }
}
