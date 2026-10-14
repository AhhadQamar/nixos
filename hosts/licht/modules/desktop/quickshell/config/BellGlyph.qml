// The bell, drawn: a bell outline with a clapper. It swings once, a few
// degrees, when a new notification arrives; a slash replaces the swing when Do
// Not Disturb is on. The badge dot is StatItem's, not part of this picture.
//
// What drives it: `unread` (the count, which only goes up by one or resets to
// 0) and `dnd`. The colour comes from StatItem's `iconColor` (muted when
// silent). On a 16-unit grid the knob is at (8, 2) and the lip at y 11.8.

import QtQuick
import QtQuick.Shapes

Glyph {
    id: root

    property int unread: 0
    property bool dnd: false

    // The unread count the last time we looked, so only a rise swings the bell
    // (opening the centre resets it to 0, which must not)
    property int last: unread
    // Values set while the icon is being built are not arrivals
    property bool ready: false

    Component.onCompleted: {
        last = unread;
        ready = true;
    }

    // Degrees the bell is turned by. Plain `property real`; the animation
    // below drives it, nothing else touches it.
    property real swing: 0

    onUnreadChanged: {
        if (ready && unread > last && !dnd)
            ring.restart();
        last = unread;
    }

    // One swing that dies away: out, back past the middle, a little less each
    // time, home. It only runs when a notification arrives, so a calm bar
    // costs nothing.
    SequentialAnimation {
        id: ring

        NumberAnimation {
            target: root
            property: "swing"
            to: 8
            duration: Style.baseMs
            easing.type: Style.easeAmbient
        }
        NumberAnimation {
            target: root
            property: "swing"
            to: -6
            duration: Style.baseMs
            easing.type: Style.easeAmbient
        }
        NumberAnimation {
            target: root
            property: "swing"
            to: 3
            duration: Style.baseMs
            easing.type: Style.easeAmbient
        }
        NumberAnimation {
            target: root
            property: "swing"
            to: 0
            duration: Style.baseMs
            easing.type: Style.easeAmbient
        }
    }

    // The bell hangs from its knob, so it turns about (8, 2), not its centre
    Shape {
        anchors.fill: parent
        layer.enabled: true
        layer.samples: 4
        transform: Rotation {
            origin.x: 8 * root.u
            origin.y: 2 * root.u
            angle: root.swing
        }

        // The body: two cubic curves up to the dome and down again, then the
        // flared lip along the bottom (a PathCubic bends towards its control
        // points without touching them). The last line returns to the start.
        Stroke {
            strokeColor: root.color
            startX: 3.5 * root.u
            startY: 10.5 * root.u

            PathCubic {
                x: 8 * root.u
                y: 3 * root.u
                control1X: 3.5 * root.u
                control1Y: 7 * root.u
                control2X: 5 * root.u
                control2Y: 3 * root.u
            }
            PathCubic {
                x: 12.5 * root.u
                y: 10.5 * root.u
                control1X: 11 * root.u
                control1Y: 3 * root.u
                control2X: 12.5 * root.u
                control2Y: 7 * root.u
            }
            PathLine {
                x: 13.8 * root.u
                y: 11.8 * root.u
            }
            PathLine {
                x: 2.2 * root.u
                y: 11.8 * root.u
            }
            PathLine {
                x: 3.5 * root.u
                y: 10.5 * root.u
            }
        }

        // The knob on top
        Stroke {
            strokeColor: root.color
            startX: 8 * root.u
            startY: 1.8 * root.u

            PathLine {
                x: 8 * root.u
                y: 3 * root.u
            }
        }

        // The clapper: a small arc under the lip, angles 30 to 150 being the
        // bottom of the circle
        Stroke {
            strokeColor: root.color

            PathAngleArc {
                centerX: 8 * root.u
                centerY: 12 * root.u
                radiusX: 1.8 * root.u
                radiusY: 1.8 * root.u
                startAngle: 30
                sweepAngle: 120
            }
        }
    }

    Slash {
        anchors.fill: parent
        on: root.dnd
        color: root.color
        u: root.u
    }
}
