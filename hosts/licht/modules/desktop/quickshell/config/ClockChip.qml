// Time-left chip for the bar. Shows only while a countdown runs: the Pomodoro
// first, otherwise the timer. Click it to open the clock panel.
//
// The dial in miniature, like the rest of the bar: a glass capsule with a small
// clock glyph and the time left, and a short hairline ruler curving over it that
// IS the countdown. The ticks behind the accent marker are lit, and the marker
// stands where the time has got to. A Pomodoro break turns it green.
// Under the pointer the capsule takes the accent (outline, soft tint, a
// breathing ring and a 2px underline); the breath only runs while hovered.
//
// It folds away to nothing when nothing is running, so the bar takes back its
// room. The time itself comes from Clocks.badge, which only changes while a
// countdown runs, so a closed bar costs nothing.

import QtQuick

Item {
    id: root

    // 0..1..0 while hovered: the ring and underline breathe with it
    property real breath: 0

    readonly property bool shown: Clocks.badge !== ""
    readonly property bool onBreak: Clocks.pomRunning && Clocks.pomPhase !== "focus"
    readonly property color tint: onBreak ? Colors.success : Colors.accent
    // How much of the countdown has gone, 0..1
    readonly property real progress: {
        if (Clocks.pomRunning)
            return Clocks.pomTotal > 0 ? 1 - Clocks.pomLeft / Clocks.pomTotal : 0;
        return Clocks.tmrTotal > 0 ? 1 - Clocks.tmrLeft / Clocks.tmrTotal : 0;
    }

    signal clicked

    implicitHeight: Style.barHeight
    implicitWidth: shown ? glass.implicitWidth + Style.spaceMd : 0
    visible: opacity > 0.01
    opacity: shown ? 1 : 0

    Behavior on opacity {
        NumberAnimation {
            duration: Style.fadeMs
        }
    }
    Behavior on implicitWidth {
        NumberAnimation {
            duration: Style.baseMs
            easing.type: Style.easeMove
        }
    }

    // Breath, only while the pointer is on the chip
    SequentialAnimation {
        running: hover.hovered && root.visible
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

    // The countdown, as a ruler over the glass
    BarRuler {
        anchors.left: glass.left
        anchors.right: glass.right
        y: 2
        markX: inset + root.progress * (width - inset * 2)
        fillX: markX
    }

    // Ring round the capsule under the pointer; it breathes
    Rectangle {
        anchors.centerIn: glass
        width: glass.width + 4
        height: glass.height + 4
        radius: height / 2
        color: "transparent"
        antialiasing: true
        visible: hover.hovered
        border.width: 1
        border.color: Qt.alpha(root.tint, 0.2 + 0.2 * root.breath)
    }

    Rectangle {
        id: glass

        x: 0
        anchors.verticalCenter: parent.verticalCenter
        implicitHeight: Style.discSize
        implicitWidth: row.implicitWidth + Style.spaceLg * 2
        radius: height / 2
        antialiasing: true
        scale: tap.pressed ? 0.97 : 1
        color: hover.hovered ? Qt.alpha(root.tint, Style.tintAlpha) : Style.well
        border.width: 1
        border.color: hover.hovered ? Qt.alpha(root.tint, 0.6) : Style.outline

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
            id: row

            anchors.centerIn: parent
            spacing: Style.spaceSm

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: Icons.clock
                textFormat: Text.PlainText
                color: root.tint

                Behavior on color {
                    ColorAnimation {
                        duration: Style.baseMs
                    }
                }

                font {
                    family: Style.fontFamily
                    pixelSize: Style.fontLg
                }
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: Clocks.badge
                textFormat: Text.PlainText
                color: hover.hovered ? root.tint : Colors.foreground

                Behavior on color {
                    ColorAnimation {
                        duration: Style.baseMs
                    }
                }

                font {
                    family: Style.fontFamily
                    pixelSize: Style.fontMd
                    bold: true
                }
            }
        }
    }

    // Underline under the capsule while the pointer is on it
    Item {
        anchors.horizontalCenter: glass.horizontalCenter
        anchors.top: glass.bottom
        anchors.topMargin: Style.spaceXs
        width: 30
        height: 2
        opacity: hover.hovered ? 1 : 0
        visible: opacity > 0.01

        Behavior on opacity {
            NumberAnimation {
                duration: Style.fadeMs
            }
        }

        Rectangle {
            anchors.centerIn: parent
            width: 20 + 10 * root.breath
            height: 2
            radius: 1
            color: root.tint
            opacity: 0.55 + 0.4 * root.breath
        }
    }

    // The whole bar-high column is the target, not just the capsule
    TapHandler {
        id: tap

        onTapped: root.clicked()
    }
    HoverHandler {
        id: hover

        cursorShape: Qt.PointingHandCursor
    }
}
