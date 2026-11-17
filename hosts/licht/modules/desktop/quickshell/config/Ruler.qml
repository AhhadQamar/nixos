// The shell's gauge: a hairline ruler for anything that has an amount (a
// download's progress, a volume, a seek position). BarRuler's idea as a
// control: ticks a fixed distance apart, a long one every few, a 2px accent
// marker where `value` stands, and the ticks beside it rising like a magnifier.
// Ticks behind the marker are lit, the ones ahead are dim.
//
// Use it sparingly: it belongs to the one thing being looked at (the control
// in use, the row under the cursor). Everything else stays a plain hairline.
//
//   Ruler { width: 300; height: 20; value: 0.4; reading: "40%" }
//
// `reading` floats above the marker; leave it empty for none. The ruler is as
// tall as its marker, and the reading sits above that, outside the item.

import QtQuick

Item {
    id: root

    // 0..1
    property real value: 0
    property string reading: ""

    // Pixels between ticks, how often one is long, and their heights
    property real step: 6
    property int majorEvery: 4
    property real tickH: 4
    property real majorH: 7
    // How far the ticks beside the marker rise, and how many ticks the lens spans
    property real lens: 10
    property real lensSpan: 7

    property color lit: Qt.alpha(Colors.accent, 0.85)
    property color dim: Qt.alpha(Colors.foreground, 0.16)
    property color markColor: Colors.accent

    // The marker glides to a new value
    property real shown: Math.max(0, Math.min(1, value))

    readonly property int count: Math.max(2, Math.floor(width / step) + 1)
    readonly property real at: shown * (count - 1)
    readonly property real markX: at * step

    Behavior on shown {
        NumberAnimation {
            duration: Style.moveMs
            easing.type: Style.easeMove
        }
    }

    Repeater {
        model: root.count

        delegate: Rectangle {
            required property int index
            readonly property real d: Math.abs(index - root.at)
            readonly property real rise: d < root.lensSpan ? Math.pow(Math.cos(d / root.lensSpan * Math.PI / 2), 2) * root.lens : 0

            x: index * root.step
            width: 1
            height: (index % root.majorEvery === 0 ? root.majorH : root.tickH) + rise
            anchors.bottom: parent.bottom
            color: index <= root.at ? root.lit : root.dim
        }
    }

    Rectangle {
        x: root.markX - 1
        width: 2
        height: root.height
        anchors.bottom: parent.bottom
        radius: 1
        color: root.markColor
    }

    Txt {
        visible: root.reading !== ""
        x: Math.max(0, Math.min(root.width - width, root.markX - width / 2))
        anchors.bottom: parent.top
        anchors.bottomMargin: 2
        text: root.reading
        color: root.markColor
        font.pixelSize: Style.fontXs
        font.bold: true
    }
}
