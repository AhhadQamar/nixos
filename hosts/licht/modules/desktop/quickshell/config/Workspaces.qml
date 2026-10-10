// Centre of the bar: every monitor's workspaces, in the order the screens sit.
//   - The same strip on every bar. This bar's own monitor is drawn bigger, in
//     a soft capsule; the others are smaller and dimmer.
//   - Click a pill to go there. Scroll over a monitor's group to step through
//     that monitor's workspaces.
//   - When the bar is tight, the other monitors fold to the workspace on
//     their screen plus a "+N" count (red if one of the N wants attention).
//   - Windows hidden on a special workspace (Super+S, the pypr terminal) show
//     as a dimmed chip on the focused monitor's bar; click to toggle.

import QtQuick

Island {
    id: root

    property string targetMonitor: ""
    // Width the bar can spare for this island
    property real maxWidth: 100000

    padding: 8
    spacing: 10

    // Rough width of everything if nothing were folded. Estimated from the
    // data rather than measured, so folding can never feed back into it.
    readonly property bool compactOthers: {
        let w = 16;
        for (let i = 0; i < Spaces.monitorNames.length; i++) {
            const name = Spaces.monitorNames[i];
            const shown = Spaces.summary[name]?.shown ?? 0;
            w += name === targetMonitor ? 44 * shown + 70 : 34 * shown + 16;
        }
        return w > maxWidth;
    }

    // Touchpads send many small deltas, so add them up and step once per
    // notch's worth (120). The running total belongs to one monitor and is
    // dropped after a pause, so half a scroll over one screen cannot tip a
    // later scroll, or another screen, into an extra step.
    property real wheelAcc: 0
    property string wheelOn: ""

    function wheel(name, dy) {
        if (name !== wheelOn) {
            wheelOn = name;
            wheelAcc = 0;
        }
        wheelAcc += dy;
        wheelIdle.restart();
        if (Math.abs(wheelAcc) >= 120) {
            Spaces.stepOn(name, wheelAcc < 0 ? 1 : -1);
            wheelAcc = 0;
        }
    }

    Timer {
        id: wheelIdle

        interval: 400
        onTriggered: root.wheelAcc = 0
    }

    // One group per monitor. The model is just the list of names, so the
    // groups stay put while workspaces come and go inside them.
    Repeater {
        model: Spaces.monitorNames

        delegate: Rectangle {
            id: group

            required property string modelData

            readonly property bool isLocal: modelData === root.targetMonitor
            readonly property bool folded: !isLocal && root.compactOthers
            readonly property var info: Spaces.summary[modelData] ?? ({
                    shown: 0,
                    rest: 0,
                    urgent: false
                })
            readonly property bool onFocusedScreen: Spaces.monitorByName(modelData)?.focused ?? false

            anchors.verticalCenter: parent.verticalCenter
            visible: info.shown > 0
            implicitHeight: Style.itemHeight
            implicitWidth: pills.implicitWidth + 8
            radius: height / 2
            antialiasing: true
            // The capsule only helps tell groups apart, so skip it with one screen
            color: isLocal && Spaces.monitorNames.length > 1 ? Qt.alpha(Colors.foreground, 0.05) : "transparent"

            Row {
                id: pills

                anchors.centerIn: parent
                spacing: 2

                // A pill for every possible id; each decides for itself
                // whether it belongs here (see WorkspacePill.qml)
                Repeater {
                    model: Spaces.idCount

                    delegate: WorkspacePill {
                        required property int index

                        anchors.verticalCenter: parent.verticalCenter
                        wsId: index + 1
                        monitorName: group.modelData
                        local: group.isLocal
                        compact: group.folded
                    }
                }

                // What the fold hides
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: group.folded && group.info.rest > 0
                    leftPadding: 4
                    rightPadding: 4
                    textFormat: Text.PlainText
                    text: "+" + group.info.rest
                    color: group.info.urgent ? Colors.critical : Colors.muted

                    font {
                        family: Style.fontFamily
                        pixelSize: 11
                    }
                }
            }

            WheelHandler {
                acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                onWheel: event => root.wheel(group.modelData, event.angleDelta.y)
            }
        }
    }

    // ---- Hidden on a special workspace ------------------------------------
    // Only on the focused monitor's bar; the scratchpad is not any one
    // screen's. Click to show or hide it.
    Rectangle {
        id: scratch

        readonly property var wins: Spaces.scratchWindows()
        readonly property bool onFocusedScreen: Spaces.monitorByName(root.targetMonitor)?.focused ?? false

        visible: wins.length > 0 && onFocusedScreen
        anchors.verticalCenter: parent.verticalCenter
        implicitHeight: Style.itemHeight - 6
        implicitWidth: scratchIcons.implicitWidth + 16
        radius: height / 2
        antialiasing: true
        scale: scratchTap.pressed ? 0.92 : 1
        color: scratchHover.hovered ? Style.hoverFill : "transparent"
        border.width: 1
        border.color: Qt.alpha(Colors.foreground, 0.18)

        Behavior on color {
            ColorAnimation {
                duration: 200
            }
        }
        Behavior on scale {
            NumberAnimation {
                duration: 100
                easing.type: Easing.OutQuad
            }
        }

        WindowIcons {
            id: scratchIcons

            anchors.centerIn: parent
            windows: scratch.wins
            maxIcons: 2
            iconSize: 14
            iconSpacing: 4
            opacity: scratchHover.hovered ? 1 : 0.6
            labelColor: Colors.foreground
        }

        TapHandler {
            id: scratchTap

            onTapped: Spaces.toggleScratch(scratch.wins[0])
        }
        HoverHandler {
            id: scratchHover

            cursorShape: Qt.PointingHandCursor
        }
    }
}
