// One inset glass bar per screen:
//   clock left (the time opens the clock panel, the date the calendar),
//   workspaces centre,
//   music chip, tray and system stats right.
//
// The bar is one piece of glass, and everything on it speaks the dial's
// language in miniature: each group (the clock, every monitor's workspaces,
// the tray, the status icons) is a row of small glass discs 24px tall with
// its own short hairline ruler curving over it, all at the same height. The
// ruler segments, not a divider, tell the groups apart. The first and last
// disc stand the same distance from the bar's ends (Style.spaceLg), and the
// gaps between groups come from each group's own padding.
//
// The glass has a faint highlight along its top edge, where light would catch
// it, and the whole bar fades and settles into place when it appears (on
// login, on a reload, or when a screen is plugged in) instead of popping in.
// The rulers swing in with it, washed in the wallpaper's palette.

import QtQuick
import Quickshell
import Quickshell.Wayland

Variants {
    model: Quickshell.screens

    delegate: PanelWindow {
        id: bar

        required property var modelData

        // What the right cluster needs apart from the music chip. Workspaces
        // reserve room for a bare chip (the record); the chip then takes
        // whatever is left beside the centred workspaces.
        readonly property real rightFixed: tray.width + stats.width
        // Room the music chip needs beyond a bare record, and the air kept
        // between the centred workspaces and either side's cluster
        readonly property int chipExtra: Style.discSize + 2 * Style.spaceMd
        readonly property int centreGap: 48

        // 0 = just created, 1 = in place
        property real reveal: 0

        screen: modelData
        // Popups hanging from the bar can only take the keyboard if the bar
        // may. OnDemand, and only while one is open: the bar never holds
        // focus otherwise.
        WlrLayershell.keyboardFocus: Panels.barPopupOpen ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
        implicitHeight: Style.barHeight
        color: "transparent"

        margins {
            top: Style.barGap
            left: Style.barGap + 2
            right: Style.barGap + 2
        }

        anchors {
            top: true
            left: true
            right: true
        }

        Component.onCompleted: reveal = 1

        Behavior on reveal {
            NumberAnimation {
                duration: Style.enterMs
                easing.type: Style.easeEnter
            }
        }

        // Everything the bar draws lives in here, so one fade and one nudge
        // move all of it together. The window clips whatever leaves its edge.
        Item {
            id: face

            anchors.fill: parent
            opacity: bar.reveal
            transform: Translate {
                y: -(1 - bar.reveal) * 8
            }

            // The glass
            Rectangle {
                anchors.fill: parent
                radius: Style.barRadius
                antialiasing: true
                color: Style.surface
                border.width: 1
                border.color: Style.outline
            }

            // Light catching the top edge: a hairline that fades out towards
            // both ends, inside the outline
            EdgeLight {
                corner: Style.barRadius
            }

            Clock {
                id: clock

                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                clockOpen: clockPop.open
                calendarOpen: calendar.open
                onTimeClicked: clockPop.toggle()
                onDateClicked: calendar.toggle()
            }

            // Time left while a timer or the Pomodoro runs; nothing otherwise
            ClockChip {
                id: clockChip

                anchors.left: clock.right
                anchors.verticalCenter: parent.verticalCenter
                onClicked: clockPop.toggle()
            }

            Workspaces {
                id: workspaces

                anchors.centerIn: parent
                targetMonitor: bar.modelData.name
                // Keep clear of the clock and the right cluster, which may differ in width
                maxWidth: bar.width - 2 * Math.max(clock.width + clockChip.width, bar.rightFixed + (Music.hasTrack ? bar.chipExtra : 0)) - bar.centreGap
            }

            Row {
                id: right

                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter

                MusicChip {
                    id: musicChip

                    maxWidth: bar.width / 2 - workspaces.width / 2 - 16 - bar.rightFixed
                }

                Tray {
                    id: tray
                }

                SystemStats {
                    id: stats
                }
            }
        }

        CalendarPopup {
            id: calendar

            barWindow: bar
            target: clock
        }

        // Timer, Pomodoro, stopwatch and alarms: click the time, or the chip
        // beside it
        ClockPopup {
            id: clockPop

            barWindow: bar
            target: clock
        }
    }
}
