// CavaVisualizer.qml
// Floating audio-reactive bar visualizer, powered by `cava`.
// Always-on, decorative — sits low-opacity at the bottom of the screen
// and comes alive whenever audio is playing. No IPC/toggle; it's meant
// to just be part of the desktop.
// Requires cava: sudo pacman -S cava
// Config used: ~/.config/cava/quickshell.conf (raw ASCII output, one
// space-separated frame per line — see the file provided alongside
// this component).
// Note: this window has no MouseArea and isn't meant to accept clicks,
// but I can't fully verify click-through behavior for a borderless
// layer-shell overlay in your exact Quickshell build without seeing it
// run — if it ends up blocking clicks to windows behind it, tell me
// and I'll adjust the layer/exclusiveZone setup.

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

PanelWindow {
    id: viz

    readonly property int barCount: 24
    property var bars: []

    color: "transparent"
    margins.bottom: 4
    implicitHeight: 48
    exclusiveZone: 0
    WlrLayershell.layer: WlrLayer.Background
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    Component.onCompleted: {
        // idle baseline so it doesn't render as a blank row before the
        // first frame arrives
        const initial = [];
        for (let i = 0; i < barCount; i++)
            initial.push(0);
        bars = initial;
    }

    anchors {
        bottom: true
        left: true
        right: true
    }

    Process {
        id: cavaProcess

        command: ["cava", "-p", Quickshell.env("HOME") + "/.config/cava/quickshell.conf"]
        running: true

        stdout: SplitParser {
            splitMarker: "\n"
            onRead: line => {
                const parsed = line.trim().split(" ").filter(s => {
                    return s.length > 0;
                }).map(Number);
                if (parsed.length > 0)
                    viz.bars = parsed;
            }
        }
    }

    RowLayout {
        anchors.centerIn: parent
        width: Math.min(parent.width * 0.5, 480)
        height: parent.height
        spacing: 3

        Repeater {
            model: viz.barCount

            delegate: Rectangle {
                required property int index
                readonly property real value: (viz.bars[index] ?? 0) / 100

                Layout.fillWidth: true
                Layout.alignment: Qt.AlignBottom
                Layout.preferredHeight: Math.max(3, value * 40)
                radius: 2
                // Gradient feel without a real Gradient element — mixes
                // accent and muted based on how "loud" this bar is, so
                // quiet bars fade toward the background instead of all
                // bars being a flat, uniform block of color.
                color: Qt.tint(Colors.muted, Qt.rgba(Colors.accent.r, Colors.accent.g, Colors.accent.b, value))

                Behavior on Layout.preferredHeight {
                    NumberAnimation {
                        duration: 60
                        easing.type: Easing.OutQuad
                    }
                }
            }
        }
    }
}
