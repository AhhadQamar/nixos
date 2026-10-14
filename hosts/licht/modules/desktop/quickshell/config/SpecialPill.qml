// One special workspace (the Super+S scratchpad, ...) as a glass disc, drawn
// in the same language as WorkspacePill.qml: the windows parked on it as up to
// two icons, or its first letter while it is empty.
//
// Workspaces.qml keeps one of these for every special workspace it has seen,
// in the order of their names, and never throws one away. This one works out
// for itself whether it is `present`; when it is not, it fades and shrinks to
// nothing, and when it comes back it grows in again.
//
// Closed it rests dimmed. Open on THIS bar's monitor it takes the "selected"
// look of the dial: accent outline, soft tint and a 2px underline while that
// monitor has the focus, a quiet grey while it does not (the same as the
// glider in Workspaces.qml). A click shows or hides this workspace and no
// other. Everything it knows comes from Spaces, so it reads the same snapshot
// as the workspace discs.

import QtQuick

Item {
    id: root

    // The short name ("magic"), as toggle_special takes it
    required property string specName
    required property string monitorName

    readonly property var windows: Spaces.specialWindows(specName)
    readonly property bool present: Spaces.specialNames.indexOf(specName) >= 0
    readonly property bool isOpen: Spaces.openSpecial(monitorName) === specName
    readonly property bool monitorFocused: Spaces.monitors[monitorName]?.focused ?? false
    // Selected, and the monitor it is open on is the one you are working on
    readonly property bool accented: isOpen && monitorFocused

    readonly property color ink: accented ? Colors.accent : Colors.foreground
    // Resting brightness: hover or being open lifts it
    readonly property real dim: hover.hovered || isOpen ? 1 : 0.65

    // A disc made while its workspace is already there would appear at full
    // size, so it starts "not armed" and the timer below arms it a moment
    // later: then the width has a change to animate and the disc grows in.
    property bool armed: false
    readonly property bool shown: present && armed

    // What the disc shows. Once its workspace is gone `windows` is empty, so it
    // keeps the last list it had while it shrinks away.
    property var held: Spaces.none

    implicitHeight: Style.barHeight
    // A width of 0 hides the disc; the Behavior makes it grow and shrink.
    // Row skips invisible children, so no gap is left.
    implicitWidth: shown ? Math.max(Style.discSize + 4, content.implicitWidth + Style.spaceXl) : 0
    visible: width > 0.5
    clip: true
    opacity: shown ? 1 : 0
    scale: tap.pressed ? 0.94 : 1

    Behavior on implicitWidth {
        NumberAnimation {
            duration: Style.moveMs
            easing.type: Style.easeMove
        }
    }
    Behavior on opacity {
        NumberAnimation {
            duration: Style.fadeMs
        }
    }
    Behavior on scale {
        NumberAnimation {
            duration: Style.pressMs
            easing.type: Style.easePress
        }
    }

    Binding {
        target: root
        property: "held"
        value: root.windows
        when: root.present
        restoreMode: Binding.RestoreNone
    }

    // Not a duration of motion, just "after the first frame"
    Timer {
        running: true
        interval: 1
        onTriggered: root.armed = true
    }

    // ---- The disc -------------------------------------------------------------
    Rectangle {
        id: face

        anchors.verticalCenter: parent.verticalCenter
        width: parent.width
        height: Style.discSize
        radius: height / 2
        antialiasing: true
        color: root.isOpen ? (root.accented ? Qt.alpha(Colors.accent, Style.tintAlpha) : Style.hoverFill) : (hover.hovered ? Style.hoverFill : Style.well)
        border.width: 1
        border.color: root.isOpen ? (root.accented ? Qt.alpha(Colors.accent, 0.6) : Qt.alpha(Colors.foreground, 0.22)) : (hover.hovered ? Qt.alpha(Colors.foreground, 0.3) : Style.outline)

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

        EdgeLight {
            corner: face.height
        }

        // The accent underline, under the disc: only while it is open on the
        // monitor you are working on
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.bottom
            anchors.topMargin: Style.spaceXs
            width: 14
            height: 2
            radius: 1
            color: Colors.accent
            opacity: root.accented ? 1 : 0

            Behavior on opacity {
                NumberAnimation {
                    duration: Style.baseMs
                }
            }
        }
    }

    Row {
        id: content

        anchors.centerIn: parent
        spacing: Style.spaceXs
        opacity: root.dim

        Behavior on opacity {
            NumberAnimation {
                duration: Style.fadeMs
            }
        }

        // Nothing parked on it: its first letter instead of an icon
        Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.held.length === 0
            textFormat: Text.PlainText
            text: root.specName.charAt(0).toUpperCase()
            color: root.ink

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

        WindowIcons {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.held.length > 0
            windows: root.held
            maxIcons: 2
            iconSize: 14
            iconSpacing: Style.spaceXs
            labelColor: root.ink
        }
    }

    TapHandler {
        id: tap

        onTapped: Spaces.toggleSpecial(root.specName)
    }
    HoverHandler {
        id: hover

        cursorShape: Qt.PointingHandCursor
    }
}
