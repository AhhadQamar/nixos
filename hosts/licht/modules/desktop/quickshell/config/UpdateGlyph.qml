// The updater, drawn: four small pictures for the Updater's four states, laid
// on top of each other and cross-faded (fadeMs), so a change is never a jump.
//
//   busy       two curved arrows chasing in a circle, turning slowly
//   available  an arrow dropping into a tray
//   failed     an exclamation mark in a triangle
//   reboot     one open circle with an arrow head: restart
//
// What drives it: `mode` ("busy", "available", "failed" or "reboot"; the same
// order SystemStats checks them in). The colour comes from StatItem's
// `iconColor` (critical on failure, accent while busy or available), so the
// colour rules stay in SystemStats. The only loop is the turn, and it runs
// only while `mode` is "busy": a calm bar costs nothing.
//
// Drawn in the plain 16px box (this disc has no ring), so on the 16-unit grid
// the circle is centred on (8, 8) and has a radius of 5.2.

import QtQuick
import QtQuick.Shapes

Glyph {
    id: root

    property string mode: "reboot"

    // Degrees the busy arrows have turned. Plain `property real`; the
    // animation below drives it, nothing else touches it.
    property real spin: 0

    // One turn takes ambientMs * 3 (2.4s): slow, a breath rather than a
    // spinner. Easing.Linear is the one place a token is not used: any
    // other easing would make the arrows speed up and slow down every turn.
    // The value is left where it is when the loop stops; the arrows have
    // faded out by then.
    NumberAnimation {
        target: root
        property: "spin"
        running: root.mode === "busy"
        loops: Animation.Infinite
        from: 0
        to: 360
        duration: Style.ambientMs * 3
        easing.type: Easing.Linear
    }

    // An arrow head for a curved arrow that ends at angle `a` on the circle:
    // three points (one wing, the tip, the other wing) for a PathPolyline.
    // Angles work as in PathAngleArc: 0 points right, positive turns
    // clockwise on screen. The arrow travels clockwise, so at angle `a` it
    // heads in direction (-sin a, cos a); the wings are that direction turned
    // back by 40 degrees (0.7 rad) either way, 3 units long.
    function barbs(a) {
        const r = 5.2;
        const rad = a * Math.PI / 180;
        const px = 8 + r * Math.cos(rad);
        const py = 8 + r * Math.sin(rad);
        const tx = -Math.sin(rad);
        const ty = Math.cos(rad);
        const c = Math.cos(0.7);
        const s = Math.sin(0.7);
        const len = 3;
        return [Qt.point((px - len * (tx * c - ty * s)) * u, (py - len * (tx * s + ty * c)) * u), Qt.point(px * u, py * u), Qt.point((px - len * (tx * c + ty * s)) * u, (py - len * (-tx * s + ty * c)) * u)];
    }

    // One of the four pictures: a Shape that fades in when `on` and is not
    // drawn at all (no GPU layer) while it is faded out. A Shape's children
    // are ShapePaths, so each picture below is a Face holding Strokes.
    component Face: Shape {
        property bool on: false

        anchors.fill: parent
        opacity: on ? 1 : 0
        visible: opacity > 0.01
        layer.enabled: visible
        layer.samples: 4

        Behavior on opacity {
            NumberAnimation {
                duration: Style.fadeMs
            }
        }
    }

    // Busy: two arcs of 120 degrees on opposite sides of the circle, each
    // ending in an arrow head. Turning is not done by rotating the item (a
    // rotated GPU layer is a stretched, blurry texture) but by adding `spin`
    // to the arcs' angles, so the shape is redrawn sharp on every frame. The
    // first arc is 200 to 320 degrees, the second 20 to 140: 60 degrees of
    // gap between them, which is where each arrow is heading.
    Face {
        on: root.mode === "busy"

        Stroke {
            strokeColor: root.color

            PathAngleArc {
                centerX: 8 * root.u
                centerY: 8 * root.u
                radiusX: 5.2 * root.u
                radiusY: 5.2 * root.u
                startAngle: root.spin + 200
                sweepAngle: 120
            }
        }
        Stroke {
            strokeColor: root.color

            PathPolyline {
                path: root.barbs(root.spin + 320)
            }
        }
        Stroke {
            strokeColor: root.color

            PathAngleArc {
                centerX: 8 * root.u
                centerY: 8 * root.u
                radiusX: 5.2 * root.u
                radiusY: 5.2 * root.u
                startAngle: root.spin + 20
                sweepAngle: 120
            }
        }
        Stroke {
            strokeColor: root.color

            PathPolyline {
                path: root.barbs(root.spin + 140)
            }
        }
    }

    // Available: a tray (an open U) and an arrow falling into it. The arrow is
    // a stem and a V head; a Stroke starts where startX/startY say and each
    // PathMove lifts the pen to start another line in the same Stroke.
    Face {
        on: root.mode === "available"

        Stroke {
            strokeColor: root.color
            startX: 2.5 * root.u
            startY: 9.5 * root.u

            PathLine {
                x: 2.5 * root.u
                y: 13 * root.u
            }
            PathLine {
                x: 13.5 * root.u
                y: 13 * root.u
            }
            PathLine {
                x: 13.5 * root.u
                y: 9.5 * root.u
            }
            // The stem
            PathMove {
                x: 8 * root.u
                y: 2.5 * root.u
            }
            PathLine {
                x: 8 * root.u
                y: 10 * root.u
            }
            // The head
            PathMove {
                x: 4.8 * root.u
                y: 6.8 * root.u
            }
            PathLine {
                x: 8 * root.u
                y: 10 * root.u
            }
            PathLine {
                x: 11.2 * root.u
                y: 6.8 * root.u
            }
        }
    }

    // Failed: a triangle (the round joins soften its corners) with the stem
    // of an exclamation mark and, under it, a dot. The dot is a line almost
    // 0 long: with a round cap, that is a circle as wide as the stroke.
    Face {
        on: root.mode === "failed"

        Stroke {
            strokeColor: root.color

            PathPolyline {
                path: [Qt.point(8 * root.u, 2.4 * root.u), Qt.point(14.2 * root.u, 13.2 * root.u), Qt.point(1.8 * root.u, 13.2 * root.u), Qt.point(8 * root.u, 2.4 * root.u)]
            }
        }
        Stroke {
            strokeColor: root.color
            startX: 8 * root.u
            startY: 6.3 * root.u

            PathLine {
                x: 8 * root.u
                y: 9 * root.u
            }
            PathMove {
                x: 8 * root.u
                y: 11.3 * root.u
            }
            PathLine {
                x: 8 * root.u
                y: 11.4 * root.u
            }
        }
    }

    // Reboot: a circle left open at the top (290 degrees, from -70 round to
    // 220) that ends in an arrow head pointing into the gap.
    Face {
        on: root.mode === "reboot"

        Stroke {
            strokeColor: root.color

            PathAngleArc {
                centerX: 8 * root.u
                centerY: 8 * root.u
                radiusX: 5.2 * root.u
                radiusY: 5.2 * root.u
                startAngle: -70
                sweepAngle: 290
            }
        }
        Stroke {
            strokeColor: root.color

            PathPolyline {
                path: root.barbs(220)
            }
        }
    }
}
