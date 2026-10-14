// A short hairline ruler for the bar: the dial's ruler in miniature. It sits
// above a row of glass (the clock's capsule, the status discs).
//
// Ticks are a fixed distance apart, so a wider piece of glass just gets more
// of them. A 2px accent marker stands where `markX` says, and the ticks beside
// it rise like a magnifier. The curve is gentle on purpose: the bar is only
// 44px tall, so the ruler may sag a pixel or two and no more.
//
// When the bar appears the ticks swing in from the middle, washed in the
// wallpaper palette (Colors.color1..6), and the colour drains as they land.

import QtQuick

Item {
    id: root

    // Where the marker stands (this item's pixels) and how visible it is.
    // `glide` off makes the marker snap instead of sliding to a new markX.
    property real markX: 0
    property real markOpacity: 1
    property bool glide: true
    // Ticks left of this x (this item's pixels) take a soft accent, so the
    // ruler can show progress; -1 (the default) tints none
    property real fillX: -1

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
    Behavior on markX {
        enabled: root.glide

        NumberAnimation {
            duration: Style.moveMs
            easing.type: Style.easeEnter
        }
    }
    Behavior on markOpacity {
        NumberAnimation {
            duration: Style.fadeMs
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
            // Ticks near the marker rise (and only while the marker shows)
            readonly property real near: Math.max(0, 1 - Math.abs(tx - root.markX) / 34) * root.markOpacity
            readonly property bool filled: root.fillX >= 0 && tx <= root.fillX
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
            color: Qt.tint(root.spectral(Colors.foreground, tx / Math.max(1, root.width), major ? 0.5 : 0.3), Qt.alpha(Colors.accent, Math.max(0.8 * near, filled ? 0.55 : 0)))
        }
    }

    // The accent marker
    Rectangle {
        readonly property real a: (root.markX - root.width / 2) / root.arcR

        x: root.markX - 1
        y: root.dropAt(root.markX)
        width: 2
        height: 7
        radius: 1
        antialiasing: true
        transformOrigin: Item.Top
        rotation: a * 180 / Math.PI
        color: Colors.accent
        opacity: root.markOpacity * root.clamp(root.intro * 2 - 0.5, 0, 1)
    }
}
