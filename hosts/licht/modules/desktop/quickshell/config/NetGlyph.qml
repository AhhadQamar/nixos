// The network, drawn. Wifi is three arcs over a dot, lit by signal strength
// (the arcs that are missing stay dim); ethernet is a small port; offline is
// the same dot and dim arcs with a slash through them. While the VPN tunnel is
// up (`vpn`), a small solid shield sits in the free lower right corner.
//
// What drives it: `kind` ("wifi", "ethernet" or "none") and `strength`
// (0..100, wifi only). The colour comes from StatItem's `iconColor` (muted
// when offline, SystemStats decides). On a 16-unit grid the dot sits at
// (8, 12) and the arcs are drawn round it.

import QtQuick
import QtQuick.Shapes

Glyph {
    id: root

    property string kind: "none"
    property int strength: 0
    property bool vpn: false

    // Lit arcs: 3 from 67%, 2 from 34%, otherwise 1. None unless on wifi.
    readonly property int bars: kind !== "wifi" ? 0 : strength >= 67 ? 3 : strength >= 34 ? 2 : 1

    // The arcs shown, as a real number that glides to `bars` (a plain
    // `property real` because it has a Behavior). Arc i is as lit as
    // `shownBars - i`, so a change in signal fades the arcs one at a time.
    property real shownBars: bars

    // How lit a missing arc still is
    readonly property real dim: 0.25

    Behavior on shownBars {
        NumberAnimation {
            duration: Style.moveMs
            easing.type: Style.easeMove
        }
    }

    // Wifi and offline share the dot and the arcs, ethernet fades in its place
    readonly property bool wired: kind === "ethernet"

    // The dot
    Rectangle {
        x: 6.8 * root.u
        y: 10.8 * root.u
        width: 2.4 * root.u
        height: width
        radius: width / 2
        antialiasing: true
        color: root.color
        opacity: root.wired ? 0 : 1
        visible: opacity > 0.01

        Behavior on opacity {
            NumberAnimation {
                duration: Style.fadeMs
            }
        }
    }

    // The arcs: round the dot, facing up. Angle -90 is straight up and positive
    // sweeps clockwise, so starting at -135 and sweeping 90 covers the upper
    // quarter of the circle. Written out one by one because a Repeater cannot
    // make ShapePaths.
    Shape {
        anchors.fill: parent
        opacity: root.wired ? 0 : 1
        visible: opacity > 0.01
        layer.enabled: visible
        layer.samples: 4

        Behavior on opacity {
            NumberAnimation {
                duration: Style.fadeMs
            }
        }

        Stroke {
            strokeColor: Qt.alpha(root.color, root.dim + (1 - root.dim) * Math.max(0, Math.min(1, root.shownBars)))

            PathAngleArc {
                centerX: 8 * root.u
                centerY: 12 * root.u
                radiusX: 3.2 * root.u
                radiusY: 3.2 * root.u
                startAngle: -135
                sweepAngle: 90
            }
        }

        Stroke {
            strokeColor: Qt.alpha(root.color, root.dim + (1 - root.dim) * Math.max(0, Math.min(1, root.shownBars - 1)))

            PathAngleArc {
                centerX: 8 * root.u
                centerY: 12 * root.u
                radiusX: 5.8 * root.u
                radiusY: 5.8 * root.u
                startAngle: -135
                sweepAngle: 90
            }
        }

        Stroke {
            strokeColor: Qt.alpha(root.color, root.dim + (1 - root.dim) * Math.max(0, Math.min(1, root.shownBars - 2)))

            PathAngleArc {
                centerX: 8 * root.u
                centerY: 12 * root.u
                radiusX: 8.4 * root.u
                radiusY: 8.4 * root.u
                startAngle: -135
                sweepAngle: 90
            }
        }
    }

    // The ethernet port: a box with a latch notch at the bottom (a closed
    // PathPolyline: the first point is repeated at the end), and three pins,
    // each a PathMove to the top of the pin and a PathLine down it.
    Shape {
        anchors.fill: parent
        opacity: root.wired ? 1 : 0
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

            PathPolyline {
                path: [Qt.point(2.5 * root.u, 3.5 * root.u), Qt.point(13.5 * root.u, 3.5 * root.u), Qt.point(13.5 * root.u, 10.5 * root.u), Qt.point(10.5 * root.u, 10.5 * root.u), Qt.point(10.5 * root.u, 12.5 * root.u), Qt.point(5.5 * root.u, 12.5 * root.u), Qt.point(5.5 * root.u, 10.5 * root.u), Qt.point(2.5 * root.u, 10.5 * root.u), Qt.point(2.5 * root.u, 3.5 * root.u)]
            }
        }

        Stroke {
            strokeColor: root.color

            PathMove {
                x: 5.5 * root.u
                y: 6 * root.u
            }
            PathLine {
                x: 5.5 * root.u
                y: 8.3 * root.u
            }
            PathMove {
                x: 8 * root.u
                y: 6 * root.u
            }
            PathLine {
                x: 8 * root.u
                y: 8.3 * root.u
            }
            PathMove {
                x: 10.5 * root.u
                y: 6 * root.u
            }
            PathLine {
                x: 10.5 * root.u
                y: 8.3 * root.u
            }
        }
    }

    // The VPN badge: a small solid shield in the empty lower right, under
    // where the arcs end. It pops in and out.
    ShieldGlyph {
        x: 8.8 * root.u
        y: 8.6 * root.u
        width: 7.4 * root.u
        height: width
        color: Colors.accent
        on: true
        opacity: root.vpn && root.kind !== "none" ? 1 : 0
        scale: root.vpn && root.kind !== "none" ? 1 : 0.5
        transformOrigin: Item.BottomRight
        visible: opacity > 0.01

        Behavior on opacity {
            NumberAnimation {
                duration: Style.fadeMs
            }
        }
        Behavior on scale {
            NumberAnimation {
                duration: Style.moveMs
                easing.type: Style.easeMove
            }
        }
    }

    Slash {
        anchors.fill: parent
        on: root.kind === "none"
        color: root.color
        u: root.u
    }
}
