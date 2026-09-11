import QtQuick
import Quickshell.Services.Pipewire
import Quickshell.Services.UPower
import Quickshell.Networking

Rectangle {
    id: root
    implicitWidth: contentLayout.implicitWidth + 30
    implicitHeight: contentLayout.implicitHeight + 18
    color: Colors.background
    radius: 12
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    anchors {
        rightMargin: 10
    }
    readonly property var activeSink: Pipewire.defaultAudioSink
    readonly property bool isMute: activeSink?.audio?.muted ?? true
    readonly property real volumeLevel: activeSink?.audio?.volume ?? 0.0

    PwObjectTracker {
        objects: root.activeSink ? [root.activeSink] : []
    }
    Row {
        id: contentLayout
        anchors.centerIn: parent
        spacing: 16
        Row {
            id: volumeModule
            spacing: 8
            Text {
                id: volumeIcon
                anchors.verticalCenter: parent.verticalCenter
                font.pixelSize: {
                    return 18;
                }
                font.family: "JetBrainsMono Nerd Fonts Mono"
                color: {
                    if (dotMouseArea.hovered)
                        return Colors.accent;
                    if (isMute)
                        return Colors.muted;
                    return Colors.accentMuted;
                }
                text: {
                    if (!root.activeSink?.audio)
                        return "";
                    if (root.isMute)
                        return "";
                    if (root.volumeLevel >= 0.8)
                        return '';
                    if (root.volumeLevel >= 0.3)
                        return '';
                    return '';
                }
            }
            HoverHandler {
                id: dotMouseArea
                cursorShape: Qt.PointingHandCursor
            }
            TapHandler {
                onTapped: if (root.activeSink?.audio)
                    root.activeSink.audio.muted = !root.isMute
                cursorShape: Qt.PointingHandCursor
            }
        }
        Row {
            id: networkModule
            spacing: 8
            anchors.verticalCenter: parent.verticalCenter
            readonly property var wifiDevice: {
                for (const d of Networking.devices.values) {
                    if (d.type === DeviceType.Wifi)
                        return d;
                }
                return null;
            }
            readonly property bool isConnected: wifiDevice?.connected ?? false
            Text {
                id: networkIcon
                text: networkModule.isConnected ? '󰖩' : '󰤮'
                font {
                    family: "JetBrainsMono Nerd Font"
                    pixelSize: 16
                }
                color: networkModule.isConnected ? Colors.accentMuted : Colors.muted
            }
            HoverHandler {
                id: wifiMouseArea
                cursorShape: Qt.PointingHandCursor
            }
        }
        Row {
            id: batteryModule
            spacing: 8
            anchors.verticalCenter: parent.verticalCenter

            readonly property bool isVisible: UPower?.displayDevice?.isPresent ?? false
            readonly property real capacity: (UPower?.displayDevice?.percentage ?? 0) * 100
            readonly property bool isCharging: !UPower.onBattery

            visible: isVisible
            Text {
                id: batteryIcon
                font {
                    family: "JetBrainsMono Nerd Font"
                    pixelSize: 16
                }
                color: {
                    const isLow = !batteryModule.isCharging && batteryModule.capacity <= 20;
                    if (isLow)
                        return Colors.critical;
                    return powerMouseArea.hovered ? Colors.accent : Colors.accentMuted;
                }
                text: {
                    if (!batteryModule.isVisible)
                        return "";
                    if (batteryModule.isCharging && batteryModule.capacity < 100)
                        return "";

                    // Capacity breakpoints
                    if (batteryModule.capacity >= 90)
                        return "󰂂";
                    if (batteryModule.capacity >= 70)
                        return "󰂀";
                    if (batteryModule.capacity >= 50)
                        return "󰁾";
                    if (batteryModule.capacity >= 30)
                        return "󰁼";
                    if (batteryModule.capacity >= 10)
                        return "󰁺";
                    return "󰂃";
                }
                HoverHandler {
                    id: powerMouseArea
                    cursorShape: Qt.PointingHandCursor
                }
            }
        }
    }
}



