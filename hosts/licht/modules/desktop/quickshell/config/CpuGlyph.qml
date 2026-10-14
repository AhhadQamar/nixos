// The CPU, drawn: a chip, which is a rounded square with pins on every side.
// The ring StatItem draws round it is the load, so the chip itself only has
// one thing to say: it turns critical when the machine runs hot.
//
// Nothing drives it but its colour, which comes from StatItem's `iconColor`
// (critical when SystemStats says `hot`). It is drawn in the 14px box, so on
// the 16-unit grid the body is 8 units wide at (4, 4) and the pins reach out
// to 1.6 and 14.4, which stays inside the ring. Two pins a side, spaced wide
// enough that they stay separate at this size (closer, they merge into teeth).

import QtQuick

Glyph {
    id: root

    // The body: a Rectangle with a border and a transparent middle
    Rectangle {
        x: 3.5 * root.u
        y: 3.5 * root.u
        width: 9 * root.u
        height: 9 * root.u
        radius: 2.5 * root.u
        color: "transparent"
        antialiasing: true
        border.width: root.sw
        border.color: root.color
    }

    // The pins. A Repeater makes one delegate per position along a side; each
    // delegate places the four pins at that position (top, bottom, left,
    // right). A pin is a thin rounded Rectangle as wide as the stroke, and its
    // inner end tucks under the body's border so the two read as one piece.
    Repeater {
        model: [5.6, 10.4]

        delegate: Item {
            id: pin

            required property real modelData

            Rectangle {
                x: pin.modelData * root.u - root.sw / 2
                y: 1.6 * root.u
                width: root.sw
                height: 2.5 * root.u
                radius: root.sw / 2
                color: root.color
                antialiasing: true
            }
            Rectangle {
                x: pin.modelData * root.u - root.sw / 2
                y: 11.9 * root.u
                width: root.sw
                height: 2.5 * root.u
                radius: root.sw / 2
                color: root.color
                antialiasing: true
            }
            Rectangle {
                x: 1.6 * root.u
                y: pin.modelData * root.u - root.sw / 2
                width: 2.5 * root.u
                height: root.sw
                radius: root.sw / 2
                color: root.color
                antialiasing: true
            }
            Rectangle {
                x: 11.9 * root.u
                y: pin.modelData * root.u - root.sw / 2
                width: 2.5 * root.u
                height: root.sw
                radius: root.sw / 2
                color: root.color
                antialiasing: true
            }
        }
    }
}
