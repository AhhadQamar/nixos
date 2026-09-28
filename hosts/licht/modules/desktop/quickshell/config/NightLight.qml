// NightLight.qml
//
// IPC:
//   qs ipc call nightlight toggle   -> open/close the panel
//   qs ipc call nightlight power    -> flip the filter on/off, no panel
//
// Keys while open: h/l or arrows = +-100K, Space/Enter = on/off,
// 1-4 = presets, mouse wheel over the slider = +-100K, Esc = close.

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

PanelWindow {
    id: nightLight

    readonly property int minTemp: 2000
    readonly property int maxTemp: 6500
    readonly property int step: 100
    readonly property var presets: [
        {
            "label": "Candle",
            "temp": 2500
        },
        {
            "label": "Warm",
            "temp": 3500
        },
        {
            "label": "Evening",
            "temp": 4500
        },
        {
            "label": "Soft",
            "temp": 5500
        }
    ]

    // The panel can't read the filter's state back, so it tracks it itself.
    // After a Quickshell restart it starts "off" until you touch it again.
    property bool filterOn: false
    property int temperature: 3500
    property int lastSent: -1

    function snap(v) {
        return Math.max(minTemp, Math.min(maxTemp, Math.round(v / step) * step));
    }

    function apply() {
        if (filterOn)
            Quickshell.execDetached(["hyprctl", "hyprsunset", "temperature", String(temperature)]);
        else
            Quickshell.execDetached(["hyprctl", "hyprsunset", "identity"]);
    }

    // Any adjustment also switches the filter on.
    function setTemperature(t) {
        temperature = snap(t);
        filterOn = true;
        apply();
    }

    function togglePower() {
        filterOn = !filterOn;
        apply();
    }

    function open() {
        visible = true;
    }

    function close() {
        visible = false;
    }

    function toggle() {
        visible = !visible;
    }

    visible: false
    // Fully transparent on purpose: no dimmed backdrop, so you see the
    // colour change live while dragging.
    color: "transparent"
    exclusiveZone: 0
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    IpcHandler {
        function toggle() {
            nightLight.toggle();
        }

        function open() {
            nightLight.open();
        }

        function close() {
            nightLight.close();
        }

        function power() {
            nightLight.togglePower();
        }

        target: "nightlight"
    }

    // Click-away-to-close
    MouseArea {
        anchors.fill: parent
        onClicked: nightLight.close()
    }

    // Keyboard handling
    Item {
        anchors.fill: parent
        focus: nightLight.visible
        Keys.onPressed: event => {
            if (event.key === Qt.Key_Escape)
                nightLight.close();
            else if (event.key === Qt.Key_Left || event.key === Qt.Key_H)
                nightLight.setTemperature(nightLight.temperature - nightLight.step);
            else if (event.key === Qt.Key_Right || event.key === Qt.Key_L)
                nightLight.setTemperature(nightLight.temperature + nightLight.step);
            else if (event.key === Qt.Key_Space || event.key === Qt.Key_Return)
                nightLight.togglePower();
            else if (event.key >= Qt.Key_1 && event.key <= Qt.Key_4)
                nightLight.setTemperature(nightLight.presets[event.key - Qt.Key_1].temp);
        }
    }

    Rectangle {
        id: card

        anchors.centerIn: parent
        width: 380
        implicitHeight: content.implicitHeight + 48
        height: implicitHeight
        radius: 18
        color: Colors.surface
        border.width: 1
        border.color: Colors.surfaceAlt

        // Swallow clicks so they don't reach the click-away area
        MouseArea {
            anchors.fill: parent
        }

        ColumnLayout {
            id: content

            anchors.fill: parent
            anchors.margins: 24
            spacing: 18

            // Header: icon, title, on/off switch
            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                Text {
                    text: "\uDB81\uDD94"
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 24
                    color: nightLight.filterOn ? Colors.accent : Colors.muted

                    Behavior on color {
                        ColorAnimation {
                            duration: 120
                        }
                    }
                }

                Text {
                    text: "Night Light"
                    font.pixelSize: 16
                    font.bold: true
                    color: Colors.foreground
                    Layout.fillWidth: true
                }

                Rectangle {
                    id: sw

                    implicitWidth: 46
                    implicitHeight: 26
                    radius: 13
                    color: nightLight.filterOn ? Colors.accent : Colors.surfaceAlt

                    Behavior on color {
                        ColorAnimation {
                            duration: 120
                        }
                    }

                    Rectangle {
                        width: 20
                        height: 20
                        radius: 10
                        anchors.verticalCenter: parent.verticalCenter
                        x: nightLight.filterOn ? sw.width - width - 3 : 3
                        color: nightLight.filterOn ? Colors.background : Colors.foreground

                        Behavior on x {
                            NumberAnimation {
                                duration: 120
                            }
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: nightLight.togglePower()
                    }
                }
            }

            // Temperature readout
            RowLayout {
                Layout.fillWidth: true

                Text {
                    text: nightLight.temperature + " K"
                    font.pixelSize: 28
                    font.bold: true
                    color: nightLight.filterOn ? Colors.foreground : Colors.muted
                }

                Item {
                    Layout.fillWidth: true
                }

                Text {
                    text: nightLight.filterOn ? "warmer  \u2190  \u2192  cooler" : "off"
                    font.pixelSize: 12
                    color: Colors.muted
                }
            }

            // Slider
            Item {
                id: slider

                Layout.fillWidth: true
                implicitHeight: 34

                readonly property real ratio: (nightLight.temperature - nightLight.minTemp) / (nightLight.maxTemp - nightLight.minTemp)

                Rectangle {
                    id: track

                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    height: 10
                    radius: 5
                    opacity: nightLight.filterOn ? 1.0 : 0.45

                    gradient: Gradient {
                        orientation: Gradient.Horizontal

                        GradientStop {
                            position: 0.0
                            color: "#ff8b1f"
                        }
                        GradientStop {
                            position: 0.4
                            color: "#ffb56b"
                        }
                        GradientStop {
                            position: 0.75
                            color: "#ffe0c2"
                        }
                        GradientStop {
                            position: 1.0
                            color: "#fff6ee"
                        }
                    }
                }

                Rectangle {
                    width: 22
                    height: 22
                    radius: 11
                    anchors.verticalCenter: parent.verticalCenter
                    x: slider.ratio * (slider.width - width)
                    color: Colors.foreground
                    border.width: 3
                    border.color: nightLight.filterOn ? Colors.accent : Colors.muted
                }

                MouseArea {
                    id: sliderArea

                    function setFromX(mx) {
                        const r = Math.max(0, Math.min(1, mx / width));
                        nightLight.temperature = nightLight.snap(nightLight.minTemp + r * (nightLight.maxTemp - nightLight.minTemp));
                        nightLight.filterOn = true;
                    }

                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onPressed: mouse => {
                        nightLight.lastSent = -1;
                        setFromX(mouse.x);
                    }
                    onPositionChanged: mouse => {
                        if (pressed)
                            setFromX(mouse.x);
                    }
                    onReleased: nightLight.apply()
                    onWheel: wheel => nightLight.setTemperature(nightLight.temperature + (wheel.angleDelta.y > 0 ? nightLight.step : -nightLight.step))
                }

                // While dragging, push updates ~10x/s (only when the value changed)
                Timer {
                    interval: 100
                    repeat: true
                    running: sliderArea.pressed
                    onTriggered: {
                        if (nightLight.temperature !== nightLight.lastSent) {
                            nightLight.lastSent = nightLight.temperature;
                            nightLight.apply();
                        }
                    }
                }
            }

            // Presets
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Repeater {
                    model: nightLight.presets

                    delegate: Rectangle {
                        id: chip

                        readonly property bool active: nightLight.filterOn && nightLight.temperature === modelData.temp
                        property bool hovered: false

                        Layout.fillWidth: true
                        implicitHeight: 40
                        radius: 10
                        color: active ? Colors.accent : Colors.surfaceAlt
                        border.width: hovered && !active ? 1 : 0
                        border.color: Colors.accent

                        ColumnLayout {
                            anchors.centerIn: parent
                            spacing: 0

                            Text {
                                text: modelData.label
                                font.pixelSize: 12
                                font.bold: true
                                color: chip.active ? Colors.background : Colors.foreground
                                Layout.alignment: Qt.AlignHCenter
                            }

                            Text {
                                text: modelData.temp + "K"
                                font.pixelSize: 10
                                color: chip.active ? Colors.background : Colors.muted
                                Layout.alignment: Qt.AlignHCenter
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onEntered: chip.hovered = true
                            onExited: chip.hovered = false
                            onClicked: nightLight.setTemperature(modelData.temp)
                        }
                    }
                }
            }

            Text {
                text: "h/l adjust  \u00b7  space on/off  \u00b7  1-4 presets  \u00b7  esc close"
                font.pixelSize: 11
                color: Colors.muted
                Layout.alignment: Qt.AlignHCenter
            }
        }
    }
}
