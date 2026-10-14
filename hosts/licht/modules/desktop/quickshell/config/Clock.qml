// Time and date for the left of the bar. Click it to open the calendar;
// right-click it to open the clock panel (timer, Pomodoro, stopwatch, alarms).
//
// The dial in miniature: a glass capsule reads the time out (the date beside
// it as a small uppercase, letter-spaced head line), and a short ruler curves
// over it. The ruler is today: its accent marker stands where the day has got
// to, so it creeps along as the hours pass (it slides a little each minute).
// The ticks beside the marker rise like a magnifier.
//
// While the calendar is open the capsule takes the accent (outline, soft tint,
// the time and the dot) and a 2px underline breathes under it. The breath only
// runs while the calendar is open. Hover lifts the capsule from its resting
// glass. When the minute changes, the time slides up into place instead of
// just swapping.

import QtQuick
import Quickshell

Item {
    id: root

    // Lit while the calendar is showing
    property bool open: false
    // 0..1..0 while open: the underline breathes with it
    property real breath: 0
    // How far through the day it is, 0..1 (the ruler's marker follows it)
    readonly property real dayFraction: (clock.date.getHours() * 60 + clock.date.getMinutes()) / 1440

    signal clicked
    // Right-click: the bar uses it to open the clock panel (timer, Pomodoro ...)
    signal contextRequested

    implicitHeight: Style.barHeight
    // The capsule stands Style.spaceLg from the bar's left end, as the last
    // status disc does from the right; the rest is air before the workspaces
    implicitWidth: glass.implicitWidth + Style.spaceLg + Style.spaceMd

    SystemClock {
        id: clock

        precision: SystemClock.Minutes
    }

    // The minute changed: the time rises a few pixels and fades in
    ParallelAnimation {
        id: roll

        NumberAnimation {
            target: timeShift
            property: "y"
            from: 5
            to: 0
            duration: Style.moveMs
            easing.type: Style.easeMove
        }
        NumberAnimation {
            target: timeText
            property: "opacity"
            from: 0.2
            to: 1
            duration: Style.moveMs
            easing.type: Style.easeMove
        }
    }

    // Breath, only while the calendar is open
    SequentialAnimation {
        running: root.open
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

    // The day as a ruler, over the capsule
    BarRuler {
        anchors.left: glass.left
        anchors.right: glass.right
        y: 2
        markX: inset + root.dayFraction * (width - inset * 2)
    }

    Rectangle {
        id: glass

        x: Style.spaceLg
        anchors.verticalCenter: parent.verticalCenter
        implicitHeight: Style.discSize
        implicitWidth: row.implicitWidth + Style.spaceLg * 2
        radius: height / 2
        antialiasing: true
        scale: tap.pressed ? 0.97 : 1
        color: root.open ? Qt.alpha(Colors.accent, Style.tintAlpha) : (hover.hovered ? Style.hoverFill : Style.well)
        border.width: 1
        border.color: root.open ? Qt.alpha(Colors.accent, 0.6) : Style.outline

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
            spacing: Style.spaceMd

            Text {
                id: timeText

                anchors.verticalCenter: parent.verticalCenter
                text: Qt.formatDateTime(clock.date, "h:mm AP")
                textFormat: Text.PlainText
                color: root.open ? Colors.accent : Colors.foreground
                onTextChanged: roll.restart()

                transform: Translate {
                    id: timeShift
                }

                Behavior on color {
                    ColorAnimation {
                        duration: Style.baseMs
                    }
                }

                font {
                    family: Style.fontFamily
                    pixelSize: Style.fontLg
                    bold: true
                }
            }

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: 3
                height: 3
                radius: 1.5
                color: root.open ? Colors.accent : Colors.muted

                Behavior on color {
                    ColorAnimation {
                        duration: Style.baseMs
                    }
                }
            }

            // The head line: small, uppercase, letter-spaced. Hover brings it
            // up from its muted grey.
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: Qt.formatDateTime(clock.date, "ddd d MMM").toUpperCase()
                textFormat: Text.PlainText
                color: hover.hovered || root.open ? Colors.foreground : Colors.muted

                Behavior on color {
                    ColorAnimation {
                        duration: Style.baseMs
                    }
                }

                font {
                    family: Style.fontFamily
                    pixelSize: Style.fontSm
                    letterSpacing: 1
                }
            }
        }
    }

    // Underline under the capsule while the calendar is open
    Item {
        anchors.horizontalCenter: glass.horizontalCenter
        anchors.top: glass.bottom
        anchors.topMargin: Style.spaceXs
        width: 30
        height: 2
        opacity: root.open ? 1 : 0
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
            color: Colors.accent
            opacity: 0.55 + 0.4 * root.breath
        }
    }

    // The whole bar-high column is the target, not just the capsule
    TapHandler {
        id: tap

        onTapped: root.clicked()
    }
    TapHandler {
        acceptedButtons: Qt.RightButton
        onTapped: root.contextRequested()
    }
    HoverHandler {
        id: hover

        cursorShape: Qt.PointingHandCursor
    }
}
