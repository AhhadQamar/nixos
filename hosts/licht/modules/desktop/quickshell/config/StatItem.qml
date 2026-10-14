// One disc in the bar's status cluster (SystemStats.qml): a small glass disc
// holding a drawn icon, which opens into a pill with a label on hover.
//
//   glyph     what is drawn inside the disc: a Component holding one of the
//             *Glyph.qml icons (hairline strokes on a 16px box, 14px when the
//             disc also draws its ring). While it is null the disc shows the
//             font glyph in `icon` instead, so icons can be converted one at a
//             time without breaking the bar
//   glyphKey  anything that changes when the picture should swell back into
//             place (mute on or off, charging...). Levels that glide by
//             themselves should not be part of it
//   present   false shrinks the item away instead of making it vanish, and
//             true grows it in, so the cluster never jumps when an indicator
//             comes and goes (use this instead of `visible`)
//   ring      0..1 draws a hairline ring round the icon, filled that far, the
//             same ring the volume OSD draws; -1 (the default) draws none
//   badge     a small dot in the corner for "something new"; it pops in with
//             one ripple
//   labelSizer  optional: a sample of the widest text the label will show. The
//             pill keeps that much room, so a label whose digits change every
//             second does not make it twitch. Leave it empty for a label that
//             sizes itself
//   doubleClicked  two quick taps; an item can use it to lock its label open
//             (alwaysShowLabel) until the next double tap
//
// Hovered, the disc is the "selected" one, as in the launcher: accent outline
// and soft tint, a breathing ring round it and a 2px underline. The breath
// only runs while the pointer is on it. The picture swells back into place
// whenever `icon` or `glyphKey` changes.
//
// The item itself is as tall as the bar so the whole column is clickable; the
// glass is `disc`, which SystemStats uses to place the ruler marker and the
// output menu.

import QtQuick
import QtQuick.Shapes

Item {
    id: root

    // Fallback picture (a font glyph), used while `glyph` is null
    property string icon: ""
    property Component glyph: null
    property var glyphKey: null
    property string label: ""
    property string labelSizer: ""
    property color iconColor: Colors.foreground
    property color labelColor: Colors.foreground
    property bool alwaysShowLabel: false

    property bool present: true
    property real ring: -1
    property color ringColor: Colors.accent

    // A small dot in the corner, for "something new"
    property bool badge: false

    signal clicked
    signal rightClicked
    signal doubleClicked
    signal scrolled(real delta)

    readonly property bool hovered: hover.hovered
    readonly property bool open: alwaysShowLabel || hover.hovered
    readonly property bool hasRing: ring >= 0
    readonly property bool drawn: glyph !== null
    readonly property Item disc: glass
    // 0 = gone, 1 = in place; the width follows it
    property real presence: present ? 1 : 0
    // Where the ring is drawn up to, eased
    property real shownRing: Math.max(0, Math.min(1, ring))
    // 0..1..0 while hovered: the ring and underline breathe with it
    property real breath: 0
    // The first values arrive while the bar is being built; do not animate those
    property bool ready: false

    Component.onCompleted: ready = true

    onIconChanged: if (ready)
        pop.restart()
    onGlyphKeyChanged: if (ready)
        pop.restart()
    onBadgeChanged: if (ready && badge)
        ripple.restart()

    implicitHeight: Style.barHeight
    implicitWidth: glass.implicitWidth * presence
    // Row skips invisible children, so a gone item leaves no gap
    visible: width > 0.5
    // Only clip while growing or shrinking; at rest the breathing ring may
    // reach past the disc
    clip: presence < 0.999

    Behavior on presence {
        NumberAnimation {
            duration: Style.moveMs
            easing.type: Style.easeMove
        }
    }
    Behavior on shownRing {
        NumberAnimation {
            duration: Style.moveMs
            easing.type: Style.easeMove
        }
    }

    // Breath, only while the pointer is on the disc
    SequentialAnimation {
        running: root.hovered
        loops: Animation.Infinite

        NumberAnimation {
            target: root
            property: "breath"
            from: 0
            to: 1
            duration: Style.ambientMs * 2
            easing.type: Style.easeAmbient
        }
        NumberAnimation {
            target: root
            property: "breath"
            from: 1
            to: 0
            duration: Style.ambientMs * 2
            easing.type: Style.easeAmbient
        }
    }

    // The picture changed: it swells back into place
    ParallelAnimation {
        id: pop

        NumberAnimation {
            target: iconBox
            property: "scale"
            from: 0.78
            to: 1
            duration: Style.baseMs
            easing.type: Style.easeMove
        }
        NumberAnimation {
            target: art
            property: "opacity"
            from: 0.35
            to: 1
            duration: Style.baseMs
            easing.type: Style.easeMove
        }
    }

    // A ring off the badge dot, once, when it appears
    NumberAnimation {
        id: ripple

        target: badgeDot
        property: "wave"
        from: 0
        to: 1
        duration: Style.enterMs
        easing.type: Style.easeMove
    }

    // Breathing accent ring round the hovered disc
    Rectangle {
        anchors.centerIn: glass
        width: glass.width + 4
        height: glass.height + 4
        radius: height / 2
        color: "transparent"
        antialiasing: true
        visible: root.hovered
        border.width: 1
        border.color: Qt.alpha(Colors.accent, 0.2 + 0.2 * root.breath)
    }

    // The glass
    Rectangle {
        id: glass

        anchors.verticalCenter: parent.verticalCenter
        implicitWidth: Math.max(Style.discSize, content.implicitWidth + 2)
        width: implicitWidth
        height: Style.discSize
        radius: height / 2
        antialiasing: true
        scale: tap.pressed ? 0.94 : 1
        color: root.hovered ? Qt.alpha(Colors.accent, Style.tintAlpha) : Style.well
        border.width: 1
        border.color: root.hovered ? Qt.alpha(Colors.accent, 0.6) : Style.outline

        Behavior on color {
            ColorAnimation {
                duration: Style.baseMs
            }
        }
        Behavior on border.color {
            ColorAnimation {
                duration: Style.baseMs
            }
        }
        Behavior on scale {
            NumberAnimation {
                duration: Style.pressMs
                easing.type: Style.easePress
            }
        }
        EdgeLight {
            corner: glass.height
        }

        Row {
            id: content

            anchors.centerIn: parent

            Item {
                id: iconBox

                anchors.verticalCenter: parent.verticalCenter
                width: Style.discSize - 2
                height: Style.discSize - 2

                // The ring: an empty track and the filled part from the top
                Shape {
                    anchors.fill: parent
                    visible: root.hasRing
                    layer.enabled: root.hasRing
                    layer.samples: 4

                    ShapePath {
                        strokeColor: Qt.alpha(Colors.foreground, 0.12)
                        strokeWidth: 1.5
                        fillColor: "transparent"

                        PathAngleArc {
                            centerX: iconBox.width / 2
                            centerY: iconBox.height / 2
                            radiusX: 9
                            radiusY: 9
                            startAngle: -90
                            sweepAngle: 359.9
                        }
                    }

                    ShapePath {
                        // A round cap would leave a dot at 0%
                        strokeColor: root.shownRing > 0.01 ? root.ringColor : "transparent"
                        strokeWidth: 1.5
                        fillColor: "transparent"
                        capStyle: ShapePath.RoundCap

                        Behavior on strokeColor {
                            ColorAnimation {
                                duration: Style.baseMs
                            }
                        }

                        PathAngleArc {
                            centerX: iconBox.width / 2
                            centerY: iconBox.height / 2
                            radiusX: 9
                            radiusY: 9
                            startAngle: -90
                            sweepAngle: 359.9 * root.shownRing
                        }
                    }
                }

                // The picture, drawn or typed. `art` is what the pop fades.
                Item {
                    id: art

                    anchors.fill: parent

                    // A drawn icon. The Loader's size is the icon's box, and
                    // the loaded item is resized to match it.
                    Loader {
                        anchors.centerIn: parent
                        width: root.hasRing ? 14 : 16
                        height: width
                        sourceComponent: root.glyph
                    }

                    Text {
                        anchors.centerIn: parent
                        visible: !root.drawn
                        text: root.icon
                        color: root.iconColor

                        Behavior on color {
                            ColorAnimation {
                                duration: Style.baseMs
                            }
                        }

                        font {
                            family: Style.fontFamily
                            // A little smaller inside a ring, so the glyph clears it
                            pixelSize: root.hasRing ? Style.fontBase : Style.fontXl
                        }
                    }
                }
            }

            Item {
                anchors.verticalCenter: parent.verticalCenter
                height: labelText.implicitHeight
                // The text (or the sample, if that is wider), a small gap
                // before it and room after it
                width: root.open && root.label !== "" ? Math.max(labelText.implicitWidth, sizer.width) + 2 + Style.spaceMd : 0
                visible: width > 0.5
                clip: true

                // Opening and closing is a glide (moveMs), as for every other
                // growing thing in the bar
                Behavior on width {
                    NumberAnimation {
                        duration: Style.moveMs
                        easing.type: Style.easeMove
                    }
                }

                // Measures `labelSizer` in the label's own font (0 when empty)
                TextMetrics {
                    id: sizer

                    text: root.labelSizer
                    font: labelText.font
                }

                Text {
                    id: labelText

                    x: 2
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.label
                    textFormat: Text.PlainText
                    color: root.labelColor
                    opacity: root.open ? 1 : 0

                    // Opening, the text fades in slowly (easeAmbient starts
                    // gently), so it arrives as the pill gets room for it
                    // instead of before it. Closing, it is gone quickly.
                    Behavior on opacity {
                        NumberAnimation {
                            duration: root.open ? Style.moveMs : Style.fadeMs
                            easing.type: Style.easeAmbient
                        }
                    }

                    font {
                        family: Style.fontFamily
                        pixelSize: Style.fontMd
                        weight: Font.Medium
                    }
                }
            }
        }
    }

    // Underline under the hovered disc; it breathes with the ring
    Item {
        anchors.horizontalCenter: glass.horizontalCenter
        anchors.top: glass.bottom
        anchors.topMargin: Style.spaceXs
        width: 20
        height: 2
        opacity: root.hovered ? 1 : 0
        visible: opacity > 0.01

        Behavior on opacity {
            NumberAnimation {
                duration: Style.fadeMs
            }
        }

        Rectangle {
            anchors.centerIn: parent
            width: 12 + 8 * root.breath
            height: 2
            radius: 1
            color: Colors.accent
            opacity: 0.55 + 0.4 * root.breath
        }
    }

    // The badge: pops in, with one ripple
    Item {
        id: badgeDot

        // 0..1, the ripple's progress
        property real wave: 1

        anchors.top: glass.top
        anchors.right: glass.right
        anchors.topMargin: 3
        anchors.rightMargin: 3
        width: 0
        height: 0
        visible: scale > 0.01
        scale: root.badge ? 1 : 0

        Behavior on scale {
            NumberAnimation {
                duration: Style.baseMs
                easing.type: Style.easePop
            }
        }

        Rectangle {
            anchors.centerIn: parent
            visible: badgeDot.wave < 1
            width: 8 + 14 * badgeDot.wave
            height: width
            radius: width / 2
            color: "transparent"
            border.width: 1.5
            border.color: Qt.alpha(Colors.accent, 0.6 * (1 - badgeDot.wave))
        }

        Rectangle {
            anchors.centerIn: parent
            width: 8
            height: 8
            radius: 4
            color: Colors.accent
            border.width: 1.5
            border.color: Qt.alpha(Colors.background, 1)
        }
    }

    TapHandler {
        id: tap

        // tapCount is how many quick taps in a row this is: 2 is the double tap
        onTapped: {
            root.clicked();
            if (tap.tapCount === 2)
                root.doubleClicked();
        }
    }
    TapHandler {
        acceptedButtons: Qt.RightButton
        onTapped: root.rightClicked()
    }
    HoverHandler {
        id: hover

        cursorShape: Qt.PointingHandCursor
    }
    WheelHandler {
        onWheel: event => root.scrolled(event.angleDelta.y)
    }
}
