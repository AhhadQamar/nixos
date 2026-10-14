// The workspaces' ruler for the bar: one continuous scale, the dial's ruler in
// miniature, running over the whole of the workspace island (every monitor's
// workspaces and the special discs). It is BarRuler's twin (same ticks, same
// gentle arc, same swing-in washed in the wallpaper's palette) with one
// difference: it does not follow the pointer. Only the active workspace of each
// monitor has the effect. A 2px accent marker stands over it, the ticks beside
// it rise like a magnifier, and both glide along with it when you change
// workspace. The marker on the monitor you are not working on is quieter.
//
// The marks come from Workspaces.qml as a list, one entry per monitor and in
// the same order, `{ x, o }`: where the marker stands (this item's pixels) and
// how visible it is (0 hides it).

import QtQuick

Item {
    id: root

    // One { x, o } per monitor's group; o = 0 for a group with no marker
    property var marks: []

    // Pixels between ticks, how often a tick is a long one, and the room left
    // clear at each end (so ticks stay off the glass's rounded ends)
    property real step: 6
    property int majorEvery: 4
    property real inset: Style.spaceLg

    // 0 = just created, 1 = calm. Plain `property real` because it has a Behavior.
    property real intro: 0

    // Radius of the arc the ticks sit on: big, so the curve is slight
    readonly property real arcR: 5000
    readonly property int count: Math.max(0, Math.floor((width - inset * 2) / step) + 1)

    function clamp(v, a, b) {
        return Math.max(a, Math.min(b, v));
    }

    function xOf(i) {
        return inset + i * step;
    }

    // How far a point at x sits below the top of the arc
    function dropAt(x) {
        return arcR - Math.sqrt(Math.max(0, arcR * arcR - (x - width / 2) * (x - width / 2)));
    }

    // How strongly the markers lift the tick at x: 1 right under one, fading
    // to 0 thirty-four pixels away, the strongest of them
    function lift(x) {
        let best = 0;
        for (let i = 0; i < marks.length; i++) {
            const m = marks[i];
            if (m.o > 0)
                best = Math.max(best, Math.max(0, 1 - Math.abs(x - m.x) / 34) * m.o);
        }
        return best;
    }

    // `base` washed with one of the palette's colours, chosen by position f
    // across the ruler. The wash fades out as `intro` reaches 1.
    function spectral(base, f, a) {
        const ramp = [Colors.color1, Colors.color2, Colors.color3, Colors.color4, Colors.color5, Colors.color6];
        const t = clamp(f, 0, 1) * (ramp.length - 1);
        const i = Math.min(ramp.length - 2, Math.floor(t));
        const c = Qt.tint(ramp[i], Qt.alpha(ramp[i + 1], t - i));
        return Qt.alpha(Qt.tint(base, Qt.alpha(c, 0.9 * (1 - intro))), a);
    }

    implicitHeight: 10
    Component.onCompleted: intro = 1

    Behavior on intro {
        NumberAnimation {
            duration: Style.sweepMs
            easing.type: Style.easeEnter
        }
    }

    Repeater {
        model: root.count

        delegate: Rectangle {
            id: tick

            required property int index

            readonly property real tx: root.xOf(index)
            readonly property real a: (tx - root.width / 2) / root.arcR
            readonly property bool major: index % root.majorEvery === 0
            // Ticks near a marker rise
            readonly property real near: root.lift(tx)
            // Swing in from the middle outwards
            readonly property real arrive: root.clamp(root.intro * 2 - 0.3 - Math.abs(tx - root.width / 2) / Math.max(1, root.width) * 0.6, 0, 1)

            x: tx - 0.75
            y: 1 + root.dropAt(tx)
            width: 1.5
            height: (major ? 4 : 3) + 2.5 * near
            radius: 0.75
            antialiasing: true
            transformOrigin: Item.Top
            rotation: a * 180 / Math.PI
            opacity: arrive
            color: Qt.tint(root.spectral(Colors.foreground, tx / Math.max(1, root.width), major ? 0.5 : 0.3), Qt.alpha(Colors.accent, 0.8 * near))
        }
    }

    // The accent markers: one for each monitor's active workspace. The count
    // is a plain number, so the markers are only added or removed when a
    // screen is plugged in or out.
    Repeater {
        model: root.marks.length

        delegate: Rectangle {
            id: marker

            required property int index

            readonly property real mx: root.marks[index] ? root.marks[index].x : 0
            property real mo: root.marks[index] ? root.marks[index].o : 0
            readonly property real a: (mx - root.width / 2) / root.arcR

            x: mx - 1
            y: root.dropAt(mx)
            width: 2
            height: 7
            radius: 1
            antialiasing: true
            transformOrigin: Item.Top
            rotation: a * 180 / Math.PI
            color: Colors.accent
            opacity: mo * root.clamp(root.intro * 2 - 0.5, 0, 1)

            Behavior on mo {
                NumberAnimation {
                    duration: Style.fadeMs
                }
            }
        }
    }
}
