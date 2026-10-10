// NightLight.qml
// Colour-temperature panel in the clipboard manager's style: a compact card
// near the top of the screen, pill rows, and a standing accent marker on the
// selected row. Drives `hyprsunset`.
//   qs ipc call nightlight toggle | open | close | power | reapply
// Keys: ← → (h l) adjust   ↑ ↓ (k j) move   enter apply   space on/off   1-4 presets   esc close

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

PanelWindow {
    id: nightLight

    // ---- Settings -------------------------------------------------------
    readonly property int minTemp: 2000
    readonly property int maxTemp: 6500
    readonly property int step: 100
    // `tint` is only used for the little colour dot on each row
    readonly property var presets: [
        {
            "label": "Candle",
            "temp": 2500,
            "tint": "#ff9a3c"
        },
        {
            "label": "Warm",
            "temp": 3500,
            "tint": "#ffb56b"
        },
        {
            "label": "Evening",
            "temp": 4500,
            "tint": "#ffd2a1"
        },
        {
            "label": "Soft",
            "temp": 5500,
            "tint": "#ffe8d4"
        }
    ]

    // ---- State ----------------------------------------------------------
    // The panel can't read the filter's state back from hyprsunset, so it keeps
    // track itself. The daemon below is started with --identity (= "no
    // filter"), so this is always "off" right after Quickshell restarts.
    property bool filterOn: false
    property int temperature: 3500
    property int lastSent: -1
    property int crashCount: 0
    // The highlighted preset row (keyboard or mouse)
    property int selectedIndex: 0

    // ---- The hyprsunset daemon ------------------------------------------
    // A Process runs a command for as long as `running` is true. It inherits
    // Quickshell's environment, so it sees HYPRLAND_INSTANCE_SIGNATURE, which
    // `hyprctl hyprsunset ...` needs. `pkill` first so a stray old instance
    // can't hold the socket.
    Process {
        id: daemon

        command: ["sh", "-c", "pkill -x hyprsunset; exec hyprsunset --identity"]
        running: true
        onRunningChanged: if (running)
            stableTimer.restart()
        onExited: (exitCode, exitStatus) => {
            stableTimer.stop();
            nightLight.filterOn = false;
            nightLight.crashCount += 1;
            if (nightLight.crashCount <= 5)
                restartTimer.start();
            else
                console.warn("NightLight: hyprsunset keeps exiting (code " + exitCode + "), giving up. Run `hyprsunset --identity` in a terminal to see why.");
        }
    }

    Timer {
        id: restartTimer

        interval: 2000
        onTriggered: daemon.running = true
    }

    // If the daemon survives this long, forgive past crashes. Five failures
    // spread across weeks shouldn't count like five in a row.
    Timer {
        id: stableTimer

        interval: 30000
        running: true
        onTriggered: nightLight.crashCount = 0
    }

    // ---- Actions --------------------------------------------------------
    // Round to the nearest `step` and keep inside min..max
    function snap(v) {
        return Math.max(minTemp, Math.min(maxTemp, Math.round(v / step) * step));
    }

    // Send the current state to hyprsunset. execDetached starts a command and
    // forgets it.
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

    // Some drivers drop the colour matrix when a display is powered off and on
    // (hypridle calls this through IPC after waking the screen).
    function reapply() {
        if (filterOn)
            apply();
    }

    // Move the highlighted row, clamped to the list
    function move(delta) {
        selectedIndex = Math.max(0, Math.min(presets.length - 1, selectedIndex + delta));
    }

    // Row that matches the current temperature, or -1
    function activeIndex() {
        for (let i = 0; i < presets.length; i++) {
            if (presets[i].temp === temperature)
                return i;
        }
        return -1;
    }

    function open() {
        // Start on the active preset, if there is one
        selectedIndex = Math.max(0, activeIndex());
        visible = true;
        keys.forceActiveFocus();
        fadeIn.restart();
    }

    function close() {
        visible = false;
    }

    function toggle() {
        if (visible)
            close();
        else
            open();
    }

    // ---- Window ---------------------------------------------------------
    // Same placement as the clipboard manager: anchored to the top edge only,
    // so the compositor centres it horizontally. The window is exactly as big
    // as the card, so there is no fullscreen overlay and you can still click
    // other windows and watch the colour change while you adjust it.
    visible: false
    color: "transparent"
    margins.top: Screen.height / 5
    implicitWidth: 420
    implicitHeight: card.implicitHeight
    exclusiveZone: 0
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

    anchors {
        top: true
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

        function reapply() {
            nightLight.reapply();
        }

        target: "nightlight"
    }

    // Keyboard handling. An Item with `focus` receives key presses.
    Item {
        id: keys

        anchors.fill: parent
        focus: nightLight.visible
        Keys.onPressed: event => {
            const k = event.key;
            const ctrl = (event.modifiers & Qt.ControlModifier) !== 0;
            if (k === Qt.Key_Escape)
                nightLight.close();
            else if (k === Qt.Key_Left || k === Qt.Key_H)
                nightLight.setTemperature(nightLight.temperature - nightLight.step);
            else if (k === Qt.Key_Right || k === Qt.Key_L)
                nightLight.setTemperature(nightLight.temperature + nightLight.step);
            else if (k === Qt.Key_Down || k === Qt.Key_J || (ctrl && k === Qt.Key_N))
                nightLight.move(1);
            else if (k === Qt.Key_Up || k === Qt.Key_K || (ctrl && k === Qt.Key_P))
                nightLight.move(-1);
            else if (k === Qt.Key_Return || k === Qt.Key_Enter)
                nightLight.setTemperature(nightLight.presets[nightLight.selectedIndex].temp);
            else if (k === Qt.Key_Space)
                nightLight.togglePower();
            else if (k >= Qt.Key_1 && k <= Qt.Key_4)
                nightLight.setTemperature(nightLight.presets[k - Qt.Key_1].temp);
        }
    }

    ParallelAnimation {
        id: fadeIn

        NumberAnimation {
            target: card
            property: "opacity"
            from: 0
            to: 1
            duration: 140
            easing.type: Easing.OutCubic
        }

        NumberAnimation {
            target: card
            property: "scale"
            from: 0.97
            to: 1
            duration: 140
            easing.type: Easing.OutCubic
        }
    }

    // Round icon button, same as the notification centre's: transparent until
    // hovered, tinted accent while switched on.
    component IconButton: Rectangle {
        id: btn

        property string glyph: ""
        property bool on: false

        signal clicked

        implicitWidth: Style.itemHeight
        implicitHeight: Style.itemHeight
        radius: height / 2
        antialiasing: true
        color: on ? Qt.alpha(Colors.accent, 0.2) : (btnHover.hovered ? Style.hoverFill : "transparent")
        scale: btnTap.pressed ? 0.94 : 1

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

        Text {
            anchors.centerIn: parent
            textFormat: Text.PlainText
            text: btn.glyph
            color: btn.on ? Colors.accent : (btnHover.hovered ? Colors.foreground : Colors.muted)

            Behavior on color {
                ColorAnimation {
                    duration: 200
                }
            }

            font {
                family: Style.fontFamily
                pixelSize: 14
            }
        }

        HoverHandler {
            id: btnHover

            cursorShape: Qt.PointingHandCursor
        }

        TapHandler {
            id: btnTap

            onTapped: btn.clicked()
        }
    }

    // ---- The card -------------------------------------------------------
    Rectangle {
        id: card

        anchors.fill: parent
        implicitHeight: content.implicitHeight + 28
        radius: Style.barRadius
        antialiasing: true
        // More solid than the bar: this panel sits over other windows' text
        color: Qt.alpha(Colors.background, 0.97)
        border.width: 1
        border.color: Style.outline

        ColumnLayout {
            id: content

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 14
            spacing: 10

            // ---- Header ---------------------------------------------------
            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 6
                spacing: 8

                Text {
                    Layout.minimumWidth: implicitWidth
                    textFormat: Text.PlainText
                    text: "Night Light"
                    color: Colors.foreground

                    font {
                        family: Style.fontFamily
                        pixelSize: 14
                        bold: true
                    }
                }

                Rectangle {
                    width: 3
                    height: 3
                    radius: 1.5
                    color: Colors.muted
                }

                Text {
                    textFormat: Text.PlainText
                    text: nightLight.filterOn ? nightLight.temperature + " K" : "Off"
                    color: nightLight.filterOn ? Colors.accent : Colors.muted

                    Behavior on color {
                        ColorAnimation {
                            duration: 200
                        }
                    }

                    font {
                        family: Style.fontFamily
                        pixelSize: 13
                    }
                }

                Item {
                    Layout.fillWidth: true
                }

                // Power button: accent-tinted while the filter is on
                IconButton {
                    glyph: "\uf011"
                    on: nightLight.filterOn
                    onClicked: nightLight.togglePower()
                }
            }

            // ---- Slider ----------------------------------------------------
            // A track filled with a warm-to-cool gradient, and a round knob.
            // It is drawn by hand, so the MouseArea below does the dragging.
            Item {
                id: slider

                Layout.fillWidth: true
                Layout.leftMargin: 6
                Layout.rightMargin: 6
                implicitHeight: 28

                // 0 at minTemp, 1 at maxTemp
                readonly property real ratio: (nightLight.temperature - nightLight.minTemp) / (nightLight.maxTemp - nightLight.minTemp)

                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    height: 6
                    radius: 3
                    antialiasing: true
                    // Dimmed while the filter is off
                    opacity: nightLight.filterOn ? 1.0 : 0.4

                    Behavior on opacity {
                        NumberAnimation {
                            duration: 200
                        }
                    }

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

                // Knob. `width` here is the knob's own width, so the knob
                // stops exactly at the track's right end.
                Rectangle {
                    width: 16
                    height: 16
                    radius: 8
                    antialiasing: true
                    anchors.verticalCenter: parent.verticalCenter
                    x: slider.ratio * (slider.width - width)
                    color: Colors.foreground
                    border.width: 2
                    border.color: nightLight.filterOn ? Colors.accent : Colors.muted
                    scale: sliderArea.pressed ? 1.15 : 1

                    Behavior on border.color {
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
                }

                MouseArea {
                    id: sliderArea

                    // Turn a mouse x position into a temperature
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

                // While dragging, push updates about 10 times a second, and
                // only when the value actually changed.
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

            // ---- Presets ---------------------------------------------------
            // Same rows as the clipboard history: a pill that fills on the
            // selected row, with a 2px accent marker standing at its left.
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                Repeater {
                    model: nightLight.presets

                    delegate: Rectangle {
                        id: row

                        required property int index
                        required property var modelData

                        readonly property bool current: index === nightLight.selectedIndex
                        // This preset is what's applied right now
                        readonly property bool active: nightLight.filterOn && nightLight.temperature === modelData.temp

                        Layout.fillWidth: true
                        implicitHeight: 40
                        radius: height / 2
                        antialiasing: true
                        color: current ? Style.hoverFill : "transparent"
                        scale: rowArea.pressed ? 0.985 : 1

                        Behavior on color {
                            ColorAnimation {
                                duration: 120
                            }
                        }
                        Behavior on scale {
                            NumberAnimation {
                                duration: 100
                                easing.type: Easing.OutQuad
                            }
                        }

                        // Selection marker: the bar's 2px accent, standing up
                        Rectangle {
                            visible: row.current
                            anchors.left: parent.left
                            anchors.leftMargin: 9
                            anchors.verticalCenter: parent.verticalCenter
                            width: 2
                            height: 16
                            radius: 1
                            color: Colors.accent
                        }

                        MouseArea {
                            id: rowArea

                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            // Position, not enter, so nothing steals the keyboard
                            // selection when the panel opens under a still mouse
                            onPositionChanged: nightLight.selectedIndex = row.index
                            onClicked: nightLight.setTemperature(row.modelData.temp)
                        }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 22
                            anchors.rightMargin: 16
                            spacing: 12

                            // Dot in roughly this preset's colour
                            Rectangle {
                                Layout.preferredWidth: 10
                                Layout.preferredHeight: 10
                                radius: 5
                                antialiasing: true
                                color: row.modelData.tint
                            }

                            Text {
                                Layout.fillWidth: true
                                textFormat: Text.PlainText
                                text: row.modelData.label
                                color: row.active ? Colors.accent : Colors.foreground
                                opacity: row.current || rowArea.containsMouse || row.active ? 1 : 0.75

                                Behavior on color {
                                    ColorAnimation {
                                        duration: 200
                                    }
                                }

                                font {
                                    family: Style.fontFamily
                                    pixelSize: 13
                                }
                            }

                            Text {
                                textFormat: Text.PlainText
                                text: row.modelData.temp + " K"
                                color: Colors.muted

                                font {
                                    family: Style.fontFamily
                                    pixelSize: 12
                                }
                            }

                            // Tick on the preset that is applied right now
                            Text {
                                Layout.preferredWidth: 14
                                horizontalAlignment: Text.AlignHCenter
                                textFormat: Text.PlainText
                                text: row.active ? "\uf00c" : ""
                                color: Colors.accent

                                font {
                                    family: Style.fontFamily
                                    pixelSize: 12
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
