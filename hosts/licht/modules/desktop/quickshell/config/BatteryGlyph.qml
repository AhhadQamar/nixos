// The battery, drawn: a cell outline with a small terminal, filled from the
// left up to the charge. Charging adds a small bolt. There is no number in it;
// the disc's label has that.
//
// What drives it: `level` (0..1) and `charging`. The colour comes from
// StatItem's `iconColor` (red when low, green when charging, SystemStats
// decides). On a 16-unit grid, the cell is 12.5 wide and 8 tall at y 4,
// the terminal pokes out on the right, and the whole picture is centred.

import QtQuick
import QtQuick.Shapes

Glyph {
    id: root

    property real level: 0
    property bool charging: false

    // What is drawn. It chases `level`, so the fill glides instead of jumping.
    // A plain `property real` (not readonly) because it has a Behavior.
    property real shown: Math.max(0, Math.min(1, level))

    Behavior on shown {
        NumberAnimation {
            duration: Style.moveMs
            easing.type: Style.easeMove
        }
    }

    // The outline: a Rectangle with a border and a transparent middle is the
    // quickest hairline box. A border is drawn inside the rectangle.
    Rectangle {
        x: 1 * root.u
        y: 4 * root.u
        width: 12.5 * root.u
        height: 8 * root.u
        radius: 2.5 * root.u
        color: "transparent"
        antialiasing: true
        border.width: root.sw
        border.color: Qt.alpha(root.color, 0.75)
    }

    // The terminal. It overlaps the outline's right edge, so it reads as one piece.
    Rectangle {
        x: 13 * root.u
        y: 6.5 * root.u
        width: 2 * root.u
        height: 3 * root.u
        radius: 0.75 * root.u
        color: Qt.alpha(root.color, 0.75)
        antialiasing: true
    }

    // The charge: the one place a fill is the data. It starts half a unit inside
    // the outline and is at most 8.5 wide; a sliver is kept at nearly empty so
    // "almost dead" still shows as something.
    Rectangle {
        x: 3 * root.u
        y: 6 * root.u
        width: Math.max(root.shown, 0.08) * 8.5 * root.u
        height: 4 * root.u
        radius: 1 * root.u
        color: root.color
        antialiasing: true
    }

    // The bolt: a closed zig-zag (a PathPolyline lists points; the first point
    // is repeated at the end to close it). Its middle is the background colour
    // and its edge the icon colour, so it shows over the green fill as a dark
    // bolt and over the empty part as a green outline. It fades with `charging`
    // and only gets a GPU layer while it is visible, so it costs nothing at rest.
    Shape {
        anchors.fill: parent
        opacity: root.charging ? 1 : 0
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
            // Thinner than the other strokes: the bolt is only 3 units wide
            strokeWidth: 1
            fillColor: Colors.background

            PathPolyline {
                path: [Qt.point(8.4 * root.u, 5.4 * root.u), Qt.point(5.8 * root.u, 8.5 * root.u), Qt.point(7.4 * root.u, 8.5 * root.u), Qt.point(6.4 * root.u, 10.6 * root.u), Qt.point(9 * root.u, 7.4 * root.u), Qt.point(7.4 * root.u, 7.4 * root.u), Qt.point(8.4 * root.u, 5.4 * root.u)]
            }
        }
    }
}
