// VolumeBrightnessOSD.qml
// Auto-popping volume/brightness OSD, bottom-center, self-hiding.
// Fully reactive — no IPC, no keybind changes needed. It just watches
// the real volume (via Pipewire) and real screen brightness (via
// /sys/class/backlight) and pops up whenever either changes, so your
// existing wpctl / brightnessctl keybinds keep working exactly as-is.

import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Pipewire
import QtQuick
import QtQuick.Layouts

PanelWindow {
    id: osd

    color: "transparent"
    anchors { bottom: true }
    margins.bottom: 60

    implicitWidth: 300
    implicitHeight: 64

    exclusiveZone: 0
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    visible: false

    // "volume" | "brightness"
    property string activeKind: "volume"
    // Suppresses the popup firing once on startup when properties get
    // their initial values.
    property bool ready: false

    function showOsd(kind) {
        if (!ready) return
        activeKind = kind
        visible = true
        hideTimer.restart()
    }

    Timer {
        id: hideTimer
        interval: 1500
        repeat: false
        onTriggered: osd.visible = false
    }

    Timer {
        interval: 300
        running: true
        repeat: false
        onTriggered: osd.ready = true
    }

    // ---------------- Volume (Pipewire) ----------------
    readonly property var activeSink: Pipewire.defaultAudioSink
    readonly property real volumeLevel: activeSink?.audio?.volume ?? 0.0
    readonly property bool isMuted: activeSink?.audio?.muted ?? true

    PwObjectTracker {
        objects: osd.activeSink ? [osd.activeSink] : []
    }

    onVolumeLevelChanged: showOsd("volume")
    onIsMutedChanged: showOsd("volume")

    // ---------------- Brightness (sysfs backlight) ----------------
    property string backlightDevice: ""
    property int brightnessMax: 1
    property int brightnessCurrent: 0
    readonly property int brightnessPercent: brightnessMax > 0
        ? Math.round((brightnessCurrent / brightnessMax) * 100)
        : 0

    onBrightnessPercentChanged: showOsd("brightness")

    // One-time discovery of the backlight device name + max value.
    Process {
        id: backlightInit
        command: ["bash", "-c",
            "ls /sys/class/backlight | head -n1"]
        stdout: StdioCollector {
            onStreamFinished: {
                const dev = text.trim()
                if (dev.length > 0) {
                    osd.backlightDevice = dev
                    maxReader.running = true
                }
            }
        }
    }

    Process {
        id: maxReader
        command: ["bash", "-c",
            "cat /sys/class/backlight/" + osd.backlightDevice + "/max_brightness"]
        stdout: StdioCollector {
            onStreamFinished: {
                osd.brightnessMax = parseInt(text.trim()) || 1
            }
        }
    }

    // Live-watched current brightness — updates whenever anything
    // (brightnessctl, a keybind, another tool) changes it.
    FileView {
        id: brightnessFile
        path: osd.backlightDevice.length > 0
            ? "/sys/class/backlight/" + osd.backlightDevice + "/brightness"
            : ""
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            osd.brightnessCurrent = parseInt(brightnessFile.text().trim()) || 0
        }
    }

    Component.onCompleted: backlightInit.running = true

    // ---------------- UI ----------------
    Rectangle {
        anchors.fill: parent
        radius: 16
        color: Colors.background
        border.width: 2
        border.color: Colors.accent
        opacity: 0.97

        RowLayout {
            anchors.fill: parent
            anchors.margins: 14
            spacing: 14

            Text {
                text: {
                    if (osd.activeKind === "brightness")
                        return "󰃟"
                    if (osd.isMuted)
                        return "󰝟"
                    if (osd.volumeLevel >= 0.66)
                        return "󰕾"
                    if (osd.volumeLevel >= 0.05)
                        return "󰖀"
                    return "󰕿"
                }
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: 22
                color: (osd.activeKind === "volume" && osd.isMuted) ? Colors.muted : Colors.foreground
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 8
                    radius: 4
                    color: Colors.surfaceAlt

                    Rectangle {
                        readonly property real fraction: osd.activeKind === "brightness"
                            ? Math.min(1.0, osd.brightnessPercent / 100)
                            : Math.min(1.0, osd.volumeLevel)

                        width: parent.width * fraction
                        height: parent.height
                        radius: 4
                        color: (osd.activeKind === "volume" && osd.isMuted) ? Colors.muted : Colors.accent

                        Behavior on width {
                            NumberAnimation { duration: 120; easing.type: Easing.OutQuad }
                        }
                    }
                }
            }

            Text {
                text: {
                    if (osd.activeKind === "brightness")
                        return osd.brightnessPercent + "%"
                    return osd.isMuted ? "Muted" : Math.round(osd.volumeLevel * 100) + "%"
                }
                font.pixelSize: 13
                font.family: "monospace"
                color: Colors.muted
                Layout.preferredWidth: 46
                horizontalAlignment: Text.AlignRight
            }
        }
    }
}
