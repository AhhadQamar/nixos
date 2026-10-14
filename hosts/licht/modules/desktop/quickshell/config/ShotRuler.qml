// One edge of the screenshot selection, drawn as a piece of the dial's ruler:
// fine ticks every 10px (a taller one every 50), and the ticks beside the
// pointer rise and turn accent, like the ticks by the middle of the dial. A
// 2px accent marker stands where the pointer is along the edge. The ruler
// wakes up as the pointer comes near its edge and sleeps when it is far, so
// while you drag a corner the two edges that meet there are the ones alive.
//
// Put it at the start of the edge (top left for the top and left edges, the
// bottom left for the bottom edge, the top right for the right edge):
//
//   horizontal  a top or bottom edge (false: a left or right edge)
//   flip        ticks point back the other way (bottom and right edges), so
//               they always point into the selection
//   length      the edge's length in pixels
//   along       where the pointer is, in pixels from the start of the edge
//   away        how far the pointer is from the edge
//   lit         the edge is being pulled or hovered: fully awake

import QtQuick

Item {
    id: root

    property bool horizontal: true
    property bool flip: false
    property real length: 0
    property real along: 0
    property real away: 9999
    property bool lit: false

    // Ticks on each side of the pointer, and the gap between them
    readonly property int half: 10
    readonly property real step: 10
    // 0.28 asleep .. 1 awake
    property real wake: lit ? 1 : Math.max(0.28, Math.min(1, 1 - away / 220))
    // The tick the pointer is nearest to; the others are laid out from it
    readonly property real base: Math.round(along / step) * step

    Behavior on wake {
        NumberAnimation {
            duration: Style.fadeMs
        }
    }

    Repeater {
        model: root.length > 0 ? root.half * 2 + 1 : 0

        delegate: Rectangle {
            id: tick

            required property int index

            readonly property real pos: root.base + (index - root.half) * root.step
            readonly property real dist: Math.abs(pos - root.along)
            readonly property real near: Math.max(0, 1 - dist / 80)
            readonly property bool major: Math.round(pos / root.step) % 5 === 0
            readonly property real len: (major ? 9 : 5) + 6 * near

            visible: pos >= 0 && pos <= root.length
            x: root.horizontal ? pos - 0.75 : (root.flip ? -len : 0)
            y: root.horizontal ? (root.flip ? -len : 0) : pos - 0.75
            width: root.horizontal ? 1.5 : len
            height: root.horizontal ? len : 1.5
            radius: 0.75
            antialiasing: true
            color: Qt.tint(Qt.alpha(Colors.foreground, major ? 0.5 : 0.3), Qt.alpha(Colors.accent, 0.8 * near))
            opacity: root.wake * Math.max(0, 1 - dist / (root.half * root.step + 5))
        }
    }

    // The pointer's place along the edge
    Rectangle {
        readonly property real at: Math.max(0, Math.min(root.length, root.along))

        visible: root.length > 0
        x: root.horizontal ? at - 1 : (root.flip ? -14 : 0)
        y: root.horizontal ? (root.flip ? -14 : 0) : at - 1
        width: root.horizontal ? 2 : 14
        height: root.horizontal ? 14 : 2
        radius: 1
        color: Colors.accent
        opacity: Math.max(0, (root.wake - 0.5) * 2)
    }
}
