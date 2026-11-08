// The network, drawn. Wifi is three arcs over a dot, lit by signal strength
// (the arcs that are missing stay dim); ethernet is a small port; offline is
// the same dot and dim arcs with a slash through them. While the VPN tunnel is
// up (`vpn`), a small solid shield sits in the free lower right corner.
//
// It also moves, when there is something to show (all of it hairlines on the same
// grid, and none of it runs while the glyph is at rest):
//   downloading  downloads are running: accent ripples flow in along the arcs
//                (over the pins of the port), and the dot flashes as each one
//                arrives. `activity` (0..1) is how busy it is: busier, faster.
//   dropping     something is held over the disc: the arcs give way to a tray,
//                and an arrow drops into it, again and again
//   flash        what the drop did: "ok" draws a check, "none" shakes a cross
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

    property bool downloading: false
    property bool dropping: false
    property string flash: ""
    property real activity: 0

    // What it shows, strongest first. Everything but a plain network picture
    // gives way to the one that is on.
    readonly property string mode: flash === "ok" ? "ok" : flash === "none" ? "none" : dropping ? "drop" : downloading ? "load" : "idle"
    readonly property bool plain: mode === "idle" || mode === "load"

    // The loops and the one-shots, each driven by an animation below
    property real phase: 0
    property real bob: 0
    property real checkP: 0
    property real shake: 0

    // How lit a ripple is at this moment: a triangle that crosses `centre` (in
    // fifths of a loop, which leaves everything dark at both ends so the loop has
    // no seam) as the phase passes. Outer arc first, then the inner, then the
    // dot: the wave runs in towards the connection.
    function ripple(centre) {
        return Math.max(0, 1 - Math.abs(phase * 5 - 0.5 - centre));
    }

    // Where the check's two strokes reach at progress p (0..1): the short stroke
    // takes the first 40%, the long one the rest. Corners at (3.2, 8.6),
    // (6.6, 12) and (13, 4.6).
    function checkShort(p) {
        return Math.min(1, p / 0.4);
    }

    function checkLong(p) {
        return Math.max(0, (p - 0.4) / 0.6);
    }

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
        opacity: root.wired || !root.plain ? 0 : 1
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
        opacity: root.wired || !root.plain ? 0 : 1
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
        opacity: root.wired && root.plain ? 1 : 0
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
        opacity: root.vpn && root.kind !== "none" && root.plain ? 1 : 0
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
        on: root.kind === "none" && root.plain
        color: root.color
        u: root.u
    }

    // ---- Downloading: accent ripples flow in along the arcs ---------------------
    Item {
        anchors.fill: parent
        opacity: root.mode === "load" ? 1 : 0
        visible: opacity > 0.01

        Behavior on opacity {
            NumberAnimation {
                duration: Style.baseMs
            }
        }

        // The wifi arcs and the dot, lit one after the other, outermost first
        Shape {
            anchors.fill: parent
            visible: !root.wired
            layer.enabled: visible
            layer.samples: 4

            Stroke {
                strokeColor: Qt.alpha(Colors.accent, 0.95 * root.ripple(2.5))

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
                strokeColor: Qt.alpha(Colors.accent, 0.95 * root.ripple(1.5))

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
                strokeColor: Qt.alpha(Colors.accent, 0.95 * root.ripple(0.5))

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

        Rectangle {
            x: 6.8 * root.u
            y: 10.8 * root.u
            width: 2.4 * root.u
            height: width
            radius: width / 2
            antialiasing: true
            visible: !root.wired
            color: Colors.accent
            opacity: root.ripple(3.3)
            scale: 1 + 0.5 * root.ripple(3.3)
        }

        // The port: its three pins light in turn, the same wave
        Shape {
            anchors.fill: parent
            visible: root.wired
            layer.enabled: visible
            layer.samples: 4

            Stroke {
                strokeColor: Qt.alpha(Colors.accent, 0.95 * root.ripple(0.5))

                PathMove {
                    x: 10.5 * root.u
                    y: 6 * root.u
                }
                PathLine {
                    x: 10.5 * root.u
                    y: 8.3 * root.u
                }
            }

            Stroke {
                strokeColor: Qt.alpha(Colors.accent, 0.95 * root.ripple(1.5))

                PathMove {
                    x: 8 * root.u
                    y: 6 * root.u
                }
                PathLine {
                    x: 8 * root.u
                    y: 8.3 * root.u
                }
            }

            Stroke {
                strokeColor: Qt.alpha(Colors.accent, 0.95 * root.ripple(2.5))

                PathMove {
                    x: 5.5 * root.u
                    y: 6 * root.u
                }
                PathLine {
                    x: 5.5 * root.u
                    y: 8.3 * root.u
                }
            }
        }
    }

    // ---- Dropping: a tray, and an arrow that drops into it -----------------------
    Item {
        anchors.fill: parent
        opacity: root.mode === "drop" ? 1 : 0
        visible: opacity > 0.01
        scale: root.mode === "drop" ? 1 : 0.8

        Behavior on opacity {
            NumberAnimation {
                duration: Style.fadeMs
            }
        }
        Behavior on scale {
            NumberAnimation {
                duration: Style.baseMs
                easing.type: Style.easePop
            }
        }

        Shape {
            anchors.fill: parent
            layer.enabled: parent.visible
            layer.samples: 4

            Stroke {
                strokeColor: Colors.accent

                PathPolyline {
                    path: [Qt.point(2.8 * root.u, 9.6 * root.u), Qt.point(2.8 * root.u, 13.4 * root.u), Qt.point(13.2 * root.u, 13.4 * root.u), Qt.point(13.2 * root.u, 9.6 * root.u)]
                }
            }
        }

        // The arrow: it sinks a little way into the tray and rises again
        Shape {
            anchors.fill: parent
            layer.enabled: parent.visible
            layer.samples: 4
            opacity: 1 - 0.4 * root.bob
            transform: Translate {
                y: root.bob * 2.2 * root.u
            }

            Stroke {
                strokeColor: Colors.accent

                PathMove {
                    x: 8 * root.u
                    y: 1.8 * root.u
                }
                PathLine {
                    x: 8 * root.u
                    y: 9 * root.u
                }
            }

            Stroke {
                strokeColor: Colors.accent

                PathPolyline {
                    path: [Qt.point(4.8 * root.u, 5.8 * root.u), Qt.point(8 * root.u, 9.2 * root.u), Qt.point(11.2 * root.u, 5.8 * root.u)]
                }
            }
        }
    }

    // ---- It was added: a check that draws itself ---------------------------------
    Shape {
        anchors.fill: parent
        opacity: root.mode === "ok" ? 1 : 0
        visible: opacity > 0.01
        layer.enabled: visible
        layer.samples: 4

        Behavior on opacity {
            NumberAnimation {
                duration: Style.fadeMs
            }
        }

        Stroke {
            strokeColor: Colors.accent

            PathMove {
                x: 3.2 * root.u
                y: 8.6 * root.u
            }
            PathLine {
                x: (3.2 + (6.6 - 3.2) * root.checkShort(root.checkP)) * root.u
                y: (8.6 + (12 - 8.6) * root.checkShort(root.checkP)) * root.u
            }
        }

        // The long stroke only once the short one has arrived (a zero-length
        // round stroke would be a dot)
        Stroke {
            strokeColor: root.checkP > 0.4 ? Colors.accent : "transparent"

            PathMove {
                x: 6.6 * root.u
                y: 12 * root.u
            }
            PathLine {
                x: (6.6 + (13 - 6.6) * root.checkLong(root.checkP)) * root.u
                y: (12 + (4.6 - 12) * root.checkLong(root.checkP)) * root.u
            }
        }
    }

    // ---- There was nothing to add: a cross that shakes ----------------------------
    Shape {
        anchors.fill: parent
        opacity: root.mode === "none" ? 1 : 0
        visible: opacity > 0.01
        layer.enabled: visible
        layer.samples: 4
        rotation: root.shake * 14
        transformOrigin: Item.Center

        Behavior on opacity {
            NumberAnimation {
                duration: Style.fadeMs
            }
        }

        Stroke {
            strokeColor: Colors.critical

            PathMove {
                x: 4.5 * root.u
                y: 4.5 * root.u
            }
            PathLine {
                x: 11.5 * root.u
                y: 11.5 * root.u
            }
            PathMove {
                x: 11.5 * root.u
                y: 4.5 * root.u
            }
            PathLine {
                x: 4.5 * root.u
                y: 11.5 * root.u
            }
        }
    }

    // ---- The motion ------------------------------------------------------------------
    // The ripple loop: busier, faster (1.7 s down to 0.8 s a pass). It only runs
    // while it is shown.
    NumberAnimation on phase {
        running: root.mode === "load" && root.visible
        from: 0
        to: 1
        duration: 1700 - 900 * Math.max(0, Math.min(1, root.activity))
        loops: Animation.Infinite
    }

    // The arrow drops in and rises again
    SequentialAnimation on bob {
        running: root.mode === "drop" && root.visible
        loops: Animation.Infinite

        NumberAnimation {
            to: 1
            duration: 520
            easing.type: Easing.InOutSine
        }
        NumberAnimation {
            to: 0
            duration: 520
            easing.type: Easing.InOutSine
        }
    }

    onModeChanged: {
        if (mode === "ok")
            okAnim.restart();
        else if (mode === "none")
            noneAnim.restart();
    }

    NumberAnimation {
        id: okAnim

        target: root
        property: "checkP"
        from: 0
        to: 1
        duration: 420
        easing.type: Style.easeMove
    }

    // Three quick shakes, each smaller, then still
    SequentialAnimation {
        id: noneAnim

        NumberAnimation {
            target: root
            property: "shake"
            to: 1
            duration: 60
        }
        NumberAnimation {
            target: root
            property: "shake"
            to: -0.8
            duration: 110
        }
        NumberAnimation {
            target: root
            property: "shake"
            to: 0.55
            duration: 100
        }
        NumberAnimation {
            target: root
            property: "shake"
            to: -0.3
            duration: 90
        }
        NumberAnimation {
            target: root
            property: "shake"
            to: 0
            duration: 80
        }
    }
}
