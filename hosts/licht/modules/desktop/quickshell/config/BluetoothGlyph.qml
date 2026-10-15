// Bluetooth, drawn: the rune in hairline strokes. Off, a slash goes through
// it; while something is connected, a dot sits on each side of it (the way the
// usual Bluetooth icon shows a link).
//
// What drives it: `powered` (the adapter is on) and `linked` (at least one
// device is connected). The colour comes from StatItem's `iconColor` (muted
// when off, the accent while linked; SystemStats decides). On a 16-unit grid
// the rune's spine is the vertical line at x = 8, and the dots are at
// (2, 8) and (14, 8).

import QtQuick
import QtQuick.Shapes

Glyph {
    id: root

    property bool powered: true
    property bool linked: false

    // The rune: down the spine and out to both sides, as one unbroken line.
    // A PathPolyline lists points; round joins make the corners soft.
    Shape {
        anchors.fill: parent
        layer.enabled: true
        layer.samples: 4

        Stroke {
            strokeColor: root.color

            PathPolyline {
                path: [Qt.point(4.2 * root.u, 5 * root.u), Qt.point(11.8 * root.u, 11 * root.u), Qt.point(8 * root.u, 14.2 * root.u), Qt.point(8 * root.u, 1.8 * root.u), Qt.point(11.8 * root.u, 5 * root.u), Qt.point(4.2 * root.u, 11 * root.u)]
            }
        }
    }

    // The slash, only while the adapter is off
    Shape {
        anchors.fill: parent
        opacity: root.powered ? 0 : 1
        visible: opacity > 0.01
        layer.enabled: visible
        layer.samples: 4

        Behavior on opacity {
            NumberAnimation {
                duration: Style.fadeMs
            }
        }

        Stroke {
            strokeColor: root.color
            startX: 2 * root.u
            startY: 2 * root.u

            PathLine {
                x: 14 * root.u
                y: 14 * root.u
            }
        }
    }

    // The link dots, only while a device is connected
    Repeater {
        model: [2, 14]

        Rectangle {
            required property real modelData

            x: modelData * root.u - width / 2
            y: 8 * root.u - height / 2
            width: 2 * root.u
            height: width
            radius: width / 2
            antialiasing: true
            color: root.color
            opacity: root.linked && root.powered ? 1 : 0
            visible: opacity > 0.01

            Behavior on opacity {
                NumberAnimation {
                    duration: Style.fadeMs
                }
            }
        }
    }
}
