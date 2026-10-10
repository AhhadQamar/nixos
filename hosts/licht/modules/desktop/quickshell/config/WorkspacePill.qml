// One workspace as a small capsule: the app you were last in, or its number
// when nothing is open. The workspace you are on grows to show more apps.
//
// Workspaces.qml makes one of these for EVERY possible id on every monitor's
// row, and each pill works out for itself whether it should be visible:
// only if the workspace exists, lives on `monitorName`, and is worth drawing.
// Pills that do not qualify shrink to nothing. Because the pills are never
// thrown away and re-made, they can animate and keep their hover state.

import QtQuick

Rectangle {
    id: root

    required property int wsId
    required property string monitorName

    // This bar's own monitor draws bigger pills than the ones it only mirrors.
    property bool local: true
    // Folded: draw only the workspace that is on screen.
    property bool compact: false

    readonly property var ws: Spaces.byId[wsId] ?? null
    readonly property bool mine: ws !== null && ws.monitor?.name === monitorName
    readonly property var windows: Spaces.windowsIn(wsId)

    readonly property bool isActive: mine && ws.active
    readonly property bool isFocused: mine && ws.focused
    readonly property bool isUrgent: mine && (ws.urgent ?? false) && !ws.active
    readonly property bool shown: mine && (compact ? isActive : (isActive || isUrgent || windows.length > 0))

    readonly property color ink: isUrgent ? Colors.critical : (isFocused ? Colors.accent : Colors.foreground)
    // Resting brightness: mirrored monitors sit back, hover or being on screen lifts it.
    readonly property real dim: hover.hovered ? 1 : (isActive ? (local ? 1 : 0.85) : (local ? 0.65 : 0.45))

    implicitHeight: local ? Style.itemHeight - 4 : Style.itemHeight - 8
    // A width of 0 hides the pill; the Behavior makes it grow and shrink
    // instead of popping. Row skips invisible children, so no gap is left.
    implicitWidth: shown ? Math.max(implicitHeight + 4, content.implicitWidth + 16) : 0
    visible: width > 0.5
    clip: true
    radius: height / 2
    antialiasing: true
    scale: tap.pressed ? 0.94 : 1

    color: hover.hovered ? Style.hoverFill : (isUrgent ? Qt.alpha(Colors.critical, 0.2) : (isActive ? Qt.alpha(isFocused ? Colors.accent : Colors.foreground, isFocused ? 0.18 : 0.08) : "transparent"))

    Behavior on color {
        ColorAnimation {
            duration: 200
        }
    }
    Behavior on implicitWidth {
        NumberAnimation {
            duration: 220
            easing.type: Easing.OutCubic
        }
    }
    Behavior on scale {
        NumberAnimation {
            duration: 100
            easing.type: Easing.OutQuad
        }
    }

    Row {
        id: content

        anchors.centerIn: parent
        spacing: 4
        opacity: root.dim

        Behavior on opacity {
            NumberAnimation {
                duration: 150
            }
        }

        // Nothing open: show the number instead of an icon
        Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.windows.length === 0
            textFormat: Text.PlainText
            text: Spaces.labelOn(root.monitorName, root.wsId)
            color: root.ink

            font {
                family: Style.fontFamily
                pixelSize: root.local ? 12 : 10
                bold: true
            }
        }

        // The window you were last in; the active pill shows up to three
        WindowIcons {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.windows.length > 0
            windows: root.windows
            maxIcons: root.local && root.isActive ? 3 : 1
            iconSize: root.local ? 16 : 13
            iconSpacing: 6
            labelColor: root.ink
        }
    }

    SlotBadge {
        text: Spaces.labelOn(root.monitorName, root.wsId)
        shown: root.local && hover.hovered && root.windows.length > 0
        tint: root.isUrgent ? Colors.critical : Colors.muted
        anchors.rightMargin: 4
        anchors.topMargin: 1
    }

    // Marks the workspace you are working in
    Rectangle {
        visible: root.isFocused
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 2
        width: 10
        height: 2
        radius: 1
        color: Colors.accent
    }

    TapHandler {
        id: tap

        // The workspace you are already on has nothing to switch to (and with
        // workspace_back_and_forth on, a click would bounce you away from it)
        onTapped: if (root.mine && !root.isFocused)
            root.ws.activate()
    }
    HoverHandler {
        id: hover

        cursorShape: Qt.PointingHandCursor
    }
}
