// VolumeBrightnessOSD.qml
// Small pill that pops up above the bottom edge when the volume, mute state or
// screen brightness changes, then fades out after a moment. It shows by itself:
// there is no IPC command and no keybind.

import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Pipewire
import QtQuick
import QtQuick.Layouts

PanelWindow {
    id: osd

    // ---- Settings -------------------------------------------------------
    readonly property int hideAfterMs: 1500

    // ---- State ----------------------------------------------------------
    // Which of the two the pill is currently showing: "volume" or "brightness"
    property string activeKind: "volume"
    // True while the pill should be on screen. The window itself stays alive a
    // little longer (see `visible` below) so the fade-out can finish.
    property bool shown: false
    // Stops the pill popping up once at startup, when the properties below
    // get their first values.
    property bool ready: false

    function showOsd(kind) {
        if (!ready)
            return;
        activeKind = kind;
        shown = true;
        hideTimer.restart(); // restart = push the hide back if you keep adjusting
    }

    Timer {
        id: hideTimer

        interval: osd.hideAfterMs
        onTriggered: osd.shown = false
    }

    Timer {
        interval: 300
        running: true
        onTriggered: osd.ready = true
    }

    // ---- Volume (Pipewire) ----------------------------------------------
    // `?.` stops quietly if the thing on the left is null, and `??` supplies a
    // fallback, so these are safe while no audio device exists yet.
    readonly property var activeSink: Pipewire.defaultAudioSink
    readonly property real volumeLevel: activeSink?.audio?.volume ?? 0.0
    readonly property bool isMuted: activeSink?.audio?.muted ?? true

    // Pipewire only reports an object's volume while something is tracking it.
    PwObjectTracker {
        objects: osd.activeSink ? [osd.activeSink] : []
    }

    // These run whenever the value changes, whoever changed it (keybind,
    // the bar's scroll wheel, another app...).
    onVolumeLevelChanged: showOsd("volume")
    onIsMutedChanged: showOsd("volume")

    // ---- Brightness (sysfs backlight) -------------------------------------
    property string backlightDevice: ""
    property int brightnessMax: 1
    property int brightnessCurrent: 0
    readonly property int brightnessPercent: brightnessMax > 0 ? Math.round((brightnessCurrent / brightnessMax) * 100) : 0

    onBrightnessPercentChanged: showOsd("brightness")

    // Step 1: find the backlight device's name, e.g. "intel_backlight".
    Process {
        id: backlightInit

        command: ["bash", "-c", "ls /sys/class/backlight | head -n1"]

        stdout: StdioCollector {
            onStreamFinished: {
                const dev = text.trim();
                if (dev.length > 0) {
                    osd.backlightDevice = dev;
                    maxReader.running = true;
                }
            }
        }
    }

    // Step 2: read its maximum value, so we can turn "current" into a percentage.
    Process {
        id: maxReader

        command: ["bash", "-c", "cat /sys/class/backlight/" + osd.backlightDevice + "/max_brightness"]

        stdout: StdioCollector {
            onStreamFinished: osd.brightnessMax = parseInt(text.trim()) || 1
        }
    }

    // Step 3: watch the "current brightness" file. The kernel updates it
    // whenever anything changes the brightness.
    FileView {
        id: brightnessFile

        path: osd.backlightDevice.length > 0 ? "/sys/class/backlight/" + osd.backlightDevice + "/brightness" : ""
        watchChanges: true
        onFileChanged: reload()
        onLoaded: osd.brightnessCurrent = parseInt(brightnessFile.text().trim()) || 0
    }

    Component.onCompleted: backlightInit.running = true

    // ---- What the pill shows ----------------------------------------------
    readonly property bool isVolume: activeKind === "volume"
    // Greyed out when the sound is muted
    readonly property bool dimmed: isVolume && isMuted
    readonly property real fraction: isVolume ? Math.min(1.0, volumeLevel) : Math.min(1.0, brightnessPercent / 100)
    readonly property string readout: isVolume ? (isMuted ? "Muted" : Math.round(volumeLevel * 100) + "%") : brightnessPercent + "%"
    // Nerd Font codepoints; String.fromCodePoint() turns one into its icon.
    readonly property int glyph: {
        if (!isVolume)
            return 0xF00DF; // brightness
        if (isMuted)
            return 0xF075F; // muted
        if (volumeLevel >= 0.66)
            return 0xF057E; // volume high
        if (volumeLevel >= 0.05)
            return 0xF0580; // volume medium
        return 0xF057F; // volume low
    }

    // ---- Window ---------------------------------------------------------
    // Stay mapped while the card is still fading out, otherwise it would vanish
    // instantly instead of fading.
    visible: shown || card.opacity > 0.01
    color: "transparent"
    implicitWidth: 320
    implicitHeight: 60
    margins.bottom: 60
    exclusiveZone: 0
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None // never steals typing

    // Only anchored to the bottom, so the compositor centres it horizontally.
    anchors {
        bottom: true
    }

    // ---- The pill ---------------------------------------------------------
    Rectangle {
        id: card

        anchors.fill: parent
        radius: height / 2
        antialiasing: true
        // More solid than the bar: this pill sits over other windows' text
        color: Qt.alpha(Colors.background, 0.97)
        border.width: 1
        border.color: Style.outline

        // A Behavior animates a property whenever its value changes, so setting
        // `shown` is all it takes to fade in or out.
        opacity: osd.shown ? 1 : 0
        scale: osd.shown ? 1 : 0.97

        Behavior on opacity {
            NumberAnimation {
                duration: 160
                easing.type: Easing.OutCubic
            }
        }
        Behavior on scale {
            NumberAnimation {
                duration: 160
                easing.type: Easing.OutCubic
            }
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 22
            anchors.rightMargin: 22
            spacing: 14

            // Icon
            Text {
                Layout.preferredWidth: 28
                horizontalAlignment: Text.AlignHCenter
                text: String.fromCodePoint(osd.glyph)
                textFormat: Text.PlainText
                color: osd.dimmed ? Colors.muted : Colors.foreground

                Behavior on color {
                    ColorAnimation {
                        duration: 200
                    }
                }

                font {
                    family: Style.fontFamily
                    pixelSize: 22
                }
            }

            // Track with the filled part on top
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 6
                radius: 3
                antialiasing: true
                color: Style.hoverFill

                Rectangle {
                    width: parent.width * osd.fraction
                    height: parent.height
                    radius: 3
                    antialiasing: true
                    color: osd.dimmed ? Colors.muted : Colors.accent

                    Behavior on width {
                        NumberAnimation {
                            duration: 120
                            easing.type: Easing.OutQuad
                        }
                    }
                    Behavior on color {
                        ColorAnimation {
                            duration: 200
                        }
                    }
                }
            }

            // Percentage, or "Muted"
            Text {
                Layout.preferredWidth: 48
                horizontalAlignment: Text.AlignRight
                text: osd.readout
                textFormat: Text.PlainText
                color: osd.dimmed ? Colors.muted : Colors.foreground

                font {
                    family: Style.fontFamily
                    pixelSize: 13
                    weight: Font.Medium
                }
            }
        }
    }
}
