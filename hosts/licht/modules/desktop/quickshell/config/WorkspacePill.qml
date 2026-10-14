// One workspace as a small glass disc: the app you were last in, or its
// number when nothing is open. The workspace you are on grows to show more
// apps.
//
// Workspaces.qml makes one of these for EVERY possible id on every monitor's
// row, and each pill works out for itself whether it should be visible:
// only if the workspace exists, lives on `monitorName`, and is worth drawing.
// Pills that do not qualify shrink to nothing. Because the pills are never
// thrown away and re-made, they can animate and keep their hover state.
//
// Everything a pill knows comes from Spaces, which reads the bar's one
// snapshot of Hyprland, so "exists", "active" and "has windows" are always
// about the same moment. Quickshell is only asked whether it is urgent.
//
// The pill itself is as tall as the bar, so the whole column is clickable;
// the glass (`face`) is the disc, Style.discSize tall, centred in it.
//
// The highlight of the ACTIVE workspace is NOT drawn here. One glider per
// monitor group (see Workspaces.qml) slides between pills, so a pill only
// has to tell its group where it is while it is the active one: that is the
// three Bindings below. The active pill hides its own glass so the glider
// shows through. A pill draws its own hover lift, and the red pulse for a
// workspace that wants attention. It reports `hovered` so the group's ruler
// marker can stand over it.

import QtQuick

Item {
    id: root

    required property int wsId
    required property string monitorName

    // This bar's own monitor draws bigger pills than the ones it only mirrors.
    property bool local: true
    // Folded: draw only the workspace that is on screen.
    property bool compact: false
    // Height of the disc in this group; the group's glider is the same height
    property real pillH: Style.discSize
    // The group this pill sits in. It owns the glider (markX, markW and
    // markFocused are properties of the group, see Workspaces.qml).
    property var tracker: null

    // This workspace as the snapshot sees it (null if it does not exist)
    readonly property var place: Spaces.places[wsId] ?? null
    readonly property bool mine: place !== null && place.monitor === monitorName
    readonly property var windows: Spaces.windowsIn(wsId)
    readonly property bool monitorFocused: Spaces.monitors[monitorName]?.focused ?? false

    readonly property bool hovered: hover.hovered
    // `isActive` is the workspace on screen on its monitor, and it stays so
    // while a special workspace is open over it. There is exactly one per
    // monitor, which is what keeps the glider from losing or doubling it.
    readonly property bool isActive: mine && place.active
    readonly property bool isFocused: mine && place.focused
    // Already where a click would take you
    readonly property bool here: isActive && monitorFocused
    readonly property bool isUrgent: mine && Spaces.urgentIds[wsId] === true && !isActive
    // The active pill is always shown, so it can never shrink under the glider
    readonly property bool shown: mine && (compact ? isActive : (isActive || isUrgent || windows.length > 0))

    // What the disc shows. While it shrinks away `windows` is already empty,
    // so it keeps the last list it had instead of flipping to its number.
    property var held: Spaces.none

    readonly property color ink: isUrgent ? Colors.critical : (isFocused ? Colors.accent : Colors.foreground)
    // Resting brightness: mirrored monitors sit back, hover or being on screen lifts it.
    readonly property real dim: hover.hovered ? 1 : (isActive ? (local ? 1 : 0.85) : (local ? 0.65 : 0.45))

    implicitHeight: Style.barHeight
    // A width of 0 hides the pill; the Behavior makes it grow and shrink
    // instead of popping. Row skips invisible children, so no gap is left.
    implicitWidth: shown ? Math.max(pillH + 4, content.implicitWidth + Style.spaceXl) : 0
    visible: width > 0.5
    clip: true
    scale: tap.pressed ? 0.94 : 1

    Behavior on implicitWidth {
        NumberAnimation {
            duration: Style.moveMs
            easing.type: Style.easeMove
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
        when: root.shown
        restoreMode: Binding.RestoreNone
    }

    // ---- Telling the glider where we are ------------------------------------
    // While this is the active pill, the group's glider follows our position
    // (in the group's row) and width, including while we grow or shrink.
    // RestoreNone keeps the glider where it was once we stop being active;
    // otherwise it would snap back to zero in the instant before the next
    // pill takes over. That instant is one and the same snapshot for both
    // pills, so the glider is never left on a pill that is not active.
    Binding {
        target: root.tracker
        property: "markX"
        value: root.parent ? root.parent.x + root.x : root.x
        when: root.tracker !== null && root.isActive
        restoreMode: Binding.RestoreNone
    }

    Binding {
        target: root.tracker
        property: "markW"
        value: root.width
        when: root.tracker !== null && root.isActive
        restoreMode: Binding.RestoreNone
    }

    Binding {
        target: root.tracker
        property: "markFocused"
        value: root.isFocused
        when: root.tracker !== null && root.isActive
        restoreMode: Binding.RestoreNone
    }

    // ---- The disc -------------------------------------------------------------
    Item {
        id: face

        anchors.verticalCenter: parent.verticalCenter
        width: parent.width
        height: root.pillH

        // Resting glass. It fades out under the glider (the active one) and
        // back in when the glider leaves, but not while the disc itself is
        // shrinking away: then it would show up under a glider that is leaving.
        Rectangle {
            id: glass

            anchors.fill: parent
            radius: height / 2
            antialiasing: true
            opacity: root.isActive || !root.shown ? 0 : 1
            color: hover.hovered ? Style.hoverFill : Style.well
            border.width: 1
            border.color: root.isUrgent ? Qt.alpha(Colors.critical, 0.6) : (hover.hovered ? Qt.alpha(Colors.foreground, 0.3) : Style.outline)

            Behavior on opacity {
                NumberAnimation {
                    duration: Style.baseMs
                }
            }
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
                corner: glass.height
            }
        }

        // Wants attention: a slow red breath. It only runs while the
        // workspace is urgent, so a calm bar costs nothing.
        Rectangle {
            id: urgentGlow

            anchors.fill: parent
            visible: root.isUrgent
            radius: height / 2
            color: Qt.alpha(Colors.critical, Style.selectedAlpha)

            SequentialAnimation on opacity {
                running: root.isUrgent
                loops: Animation.Infinite

                NumberAnimation {
                    from: 0.35
                    to: 1
                    duration: Style.ambientMs
                    easing.type: Style.easeAmbient
                }
                NumberAnimation {
                    from: 1
                    to: 0.35
                    duration: Style.ambientMs
                    easing.type: Style.easeAmbient
                }
            }
        }

        SlotBadge {
            text: Spaces.labelOn(root.monitorName, root.wsId)
            shown: root.local && hover.hovered && root.held.length > 0
            tint: root.isUrgent ? Colors.critical : Colors.muted
            anchors.rightMargin: 4
            anchors.topMargin: 1
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

        // Nothing open: show the number instead of an icon
        Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.held.length === 0
            textFormat: Text.PlainText
            text: Spaces.labelOn(root.monitorName, root.wsId)
            color: root.ink

            Behavior on color {
                ColorAnimation {
                    duration: Style.baseMs
                }
            }

            font {
                family: Style.fontFamily
                pixelSize: root.local ? Style.fontMd : Style.fontXs
                bold: true
            }
        }

        // The window you were last in; the active pill shows up to three
        WindowIcons {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.held.length > 0
            windows: root.held
            maxIcons: root.local && root.isActive ? 3 : 1
            iconSize: root.local ? 14 : 12
            iconSpacing: Style.spaceSm
            labelColor: root.ink
        }
    }

    TapHandler {
        id: tap

        // The workspace you are already on has nothing to switch to (and with
        // workspace_back_and_forth on, a click would bounce you away from it)
        onTapped: if (root.mine && !root.here)
            Spaces.activate(root.wsId)
    }
    HoverHandler {
        id: hover

        cursorShape: Qt.PointingHandCursor
    }
}
