// The volume, drawn: a speaker with sound waves coming out of it. The number
// of waves is the level (0 to 3), and a slash replaces them when muted. The
// exact volume is the ring StatItem draws round the icon, so this picture only
// has to say roughly how loud it is.
//
// What drives it: `level` (0..1, may go above 1) and `muted`. The colour comes
// from StatItem's `iconColor` (muted grey when muted, SystemStats decides).
// On a 16-unit grid the speaker is the box and cone on the left, and the waves
// are arcs round the cone's mouth at (7.5, 8).

import QtQuick
import QtQuick.Shapes

Glyph {
    id: root

    property real level: 0
    property bool muted: false

    // How many waves the level earns
    readonly property int waves: muted || level < 0.005 ? 0 : level < 0.34 ? 1 : level < 0.67 ? 2 : 3

    // The waves shown, as a real number: it glides to `waves`, and wave i is
    // as visible as `shownWaves - i` (clamped to 0..1). So going from 3 to 0
    // fades the outer wave first, then the next, one at a time, with no more
    // animation code than this one Behavior.
    property real shownWaves: waves

    Behavior on shownWaves {
        NumberAnimation {
            duration: Style.moveMs
            easing.type: Style.easeMove
        }
    }

    // One Shape holds the speaker and all three waves: one GPU layer.
    Shape {
        anchors.fill: parent
        layer.enabled: true
        layer.samples: 4

        // The speaker: a closed zig-zag (box, then cone). A PathPolyline lists
        // points; the first point is repeated at the end to close it.
        Stroke {
            strokeColor: root.color

            PathPolyline {
                path: [Qt.point(1.5 * root.u, 6 * root.u), Qt.point(4 * root.u, 6 * root.u), Qt.point(7.5 * root.u, 3 * root.u), Qt.point(7.5 * root.u, 13 * root.u), Qt.point(4 * root.u, 10 * root.u), Qt.point(1.5 * root.u, 10 * root.u), Qt.point(1.5 * root.u, 6 * root.u)]
            }
        }

        // The waves: three arcs round the same centre, each a little wider.
        // Angle 0 points right and positive sweeps clockwise, so -40 plus a
        // sweep of 80 is the arc facing right. Wave i is as visible as
        // `shownWaves - i`. They are written out one by one because a Repeater
        // cannot make ShapePaths (it only makes Items).
        Stroke {
            strokeColor: Qt.alpha(root.color, Math.max(0, Math.min(1, root.shownWaves)))

            PathAngleArc {
                centerX: 7.5 * root.u
                centerY: 8 * root.u
                radiusX: 2.6 * root.u
                radiusY: 2.6 * root.u
                startAngle: -40
                sweepAngle: 80
            }
        }

        Stroke {
            strokeColor: Qt.alpha(root.color, Math.max(0, Math.min(1, root.shownWaves - 1)))

            PathAngleArc {
                centerX: 7.5 * root.u
                centerY: 8 * root.u
                radiusX: 4.6 * root.u
                radiusY: 4.6 * root.u
                startAngle: -40
                sweepAngle: 80
            }
        }

        Stroke {
            strokeColor: Qt.alpha(root.color, Math.max(0, Math.min(1, root.shownWaves - 2)))

            PathAngleArc {
                centerX: 7.5 * root.u
                centerY: 8 * root.u
                radiusX: 6.6 * root.u
                radiusY: 6.6 * root.u
                startAngle: -40
                sweepAngle: 80
            }
        }
    }

    Slash {
        anchors.fill: parent
        on: root.muted
        color: root.color
        u: root.u
    }
}
