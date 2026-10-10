// Radial launcher in the bar's style: one inset glass disc, ring of apps, selection on top.
//   qs ipc call launcher toggle | open | close

import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets

PanelWindow {
    id: launcher

    // ---- Settings -------------------------------------------------------
    readonly property int slots: 6
    readonly property real stepDeg: 360 / slots
    readonly property real ringRadius: 148
    readonly property int itemSize: 52
    readonly property int selectedSize: 66
    // The disc behind the ring: ring + the selected icon's overhang + a margin.
    readonly property real discSize: (ringRadius + selectedSize / 2 + 14) * 2
    // Used for apps with Terminal=true in their .desktop file.
    readonly property string terminal: "kitty"
    readonly property string countsPath: Quickshell.env("HOME") + "/.cache/quickshell/launcher-counts.json"

    // ---- State ----------------------------------------------------------
    property var allApps: []
    property var filtered: []
    property int selectedIndex: 0
    property var counts: ({})
    // Degrees the ring is still turning. Set on each step, eased back to 0.
    property real spin: 0
    // App under the mouse; shown in the middle instead of the selection.
    property var peek: null

    readonly property int visibleCount: Math.min(slots, filtered.length)
    readonly property var current: filtered.length > 0 ? filtered[selectedIndex] : null
    readonly property var shown: peek ? peek : current

    // ---- Search ---------------------------------------------------------
    function scanApps() {
        const seen = {};
        const out = [];
        const all = DesktopEntries.applications.values;
        for (let i = 0; i < all.length; i++) {
            const a = all[i];
            if (a.noDisplay)
                continue;
            const key = (a.name || "").toLowerCase();
            if (key === "" || seen[key])
                continue;
            seen[key] = true;
            out.push(a);
        }
        allApps = out;
    }

    // Lower is better; -1 means no match.
    function score(a, q) {
        const name = (a.name || "").toLowerCase();
        if (name === q)
            return 0;
        if (name.indexOf(q) === 0)
            return 1;
        if (name.indexOf(" " + q) >= 0)
            return 2;
        if (name.indexOf(q) >= 0)
            return 3;
        if ((a.genericName || "").toLowerCase().indexOf(q) >= 0)
            return 4;
        let kw = "";
        try {
            kw = Array.prototype.join.call(a.keywords || [], " ").toLowerCase();
        } catch (e) {}
        if (kw.indexOf(q) >= 0)
            return 5;
        if ((a.id || "").toLowerCase().indexOf(q) >= 0)
            return 6;
        return -1;
    }

    function refilter() {
        const q = input.text.toLowerCase().trim();
        const list = [];
        for (let i = 0; i < allApps.length; i++) {
            const a = allApps[i];
            const s = q === "" ? 0 : score(a, q);
            if (s >= 0)
                list.push({
                    "a": a,
                    "s": s,
                    "n": counts[a.id] || 0
                });
        }
        list.sort((x, y) => (x.s - y.s) || (y.n - x.n) || x.a.name.localeCompare(y.a.name));
        filtered = list.map(x => x.a);
        selectedIndex = 0;
        peek = null;
        spinAnim.stop();
        spin = 0;
    }

    // ---- Actions --------------------------------------------------------
    // dir: +1 = next app (ring turns anticlockwise), -1 = previous
    function step(dir) {
        const n = filtered.length;
        if (n < 2)
            return;
        selectedIndex = (selectedIndex + dir + n) % n;
        peek = null;
        spinAnim.stop();
        spin = Math.max(-stepDeg * 2, Math.min(stepDeg * 2, spin + dir * stepDeg));
        spinAnim.start();
    }

    function saveCounts() {
        Quickshell.execDetached(["sh", "-c", 'mkdir -p "$(dirname "$2")" && printf %s "$1" > "$2"', "sh", JSON.stringify(counts), countsPath]);
    }

    function launch(entry) {
        if (!entry)
            return;
        const c = Object.assign({}, counts);
        c[entry.id] = (c[entry.id] || 0) + 1;
        counts = c;
        saveCounts();

        if (entry.runInTerminal)
            Quickshell.execDetached([terminal, "-e"].concat(Array.prototype.slice.call(entry.command)));
        else
            entry.execute();
        close();
    }

    function iconFor(entry) {
        const i = entry ? entry.icon : "";
        if (!i)
            return Quickshell.iconPath("application-x-executable");
        if (i.charAt(0) === "/")
            return "file://" + i;
        return Quickshell.iconPath(i, "application-x-executable");
    }

    function open() {
        visible = true;
        scanApps();
        input.text = "";
        refilter();
        input.forceActiveFocus();
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
    visible: false
    color: "transparent"
    exclusiveZone: 0
    WlrLayershell.layer: WlrLayer.Overlay
    // Exclusive so typing works the moment the ring appears.
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    IpcHandler {
        function toggle() {
            launcher.toggle();
        }

        function open() {
            launcher.open();
        }

        function close() {
            launcher.close();
        }

        target: "launcher"
    }

    FileView {
        id: countsFile

        path: launcher.countsPath
        onLoaded: {
            try {
                launcher.counts = JSON.parse(countsFile.text());
            } catch (e) {
                launcher.counts = ({});
            }
        }
    }

    SystemClock {
        id: clock

        precision: SystemClock.Minutes
    }

    NumberAnimation {
        id: spinAnim

        target: launcher
        property: "spin"
        to: 0
        duration: 170
        easing.type: Easing.OutCubic
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
            from: 0.96
            to: 1
            duration: 140
            easing.type: Easing.OutCubic
        }
    }

    // Click-away-to-close (no dimming; the desktop stays as it is)
    MouseArea {
        anchors.fill: parent
        onClicked: launcher.close()
    }

    // ---- The ring -------------------------------------------------------
    // One circle with the bar's surface and outline, sized to the ring.
    Item {
        id: card

        readonly property real cx: width / 2
        readonly property real cy: height / 2

        anchors.centerIn: parent
        width: launcher.discSize
        height: width

        Rectangle {
            anchors.fill: parent
            radius: width / 2
            antialiasing: true
            color: Style.surface
            border.width: 1
            border.color: Style.outline
        }

        // Swallows clicks inside the disc so they don't reach the click-away
        // area (clicks in the square's corners still close); the wheel turns
        // the ring.
        MouseArea {
            anchors.fill: parent
            onClicked: mouse => {
                const dx = mouse.x - card.cx;
                const dy = mouse.y - card.cy;
                if (dx * dx + dy * dy > card.cx * card.cx)
                    launcher.close();
            }
            onWheel: wheel => launcher.step(wheel.angleDelta.y < 0 ? 1 : -1)
        }

        // Thin guide ring
        Rectangle {
            x: card.cx - launcher.ringRadius
            y: card.cy - launcher.ringRadius
            width: launcher.ringRadius * 2
            height: width
            radius: width / 2
            antialiasing: true
            color: "transparent"
            border.width: 1
            border.color: Style.outline
        }

        // Selection arc: the bar's 2px active underline, bent along the ring
        Shape {
            anchors.fill: parent
            layer.enabled: true
            layer.samples: 4

            ShapePath {
                strokeColor: Colors.accent
                strokeWidth: 2
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap

                PathAngleArc {
                    centerX: card.cx
                    centerY: card.cy
                    radiusX: launcher.ringRadius
                    radiusY: launcher.ringRadius
                    startAngle: -90 - 30
                    sweepAngle: 60
                }
            }
        }

        // Empty slots stay visible as faint dots so the ring keeps its shape
        Repeater {
            model: launcher.slots

            delegate: Rectangle {
                required property int index

                readonly property real angle: (-90 + index * launcher.stepDeg) * Math.PI / 180

                visible: index >= launcher.visibleCount
                x: card.cx + launcher.ringRadius * Math.cos(angle) - width / 2
                y: card.cy + launcher.ringRadius * Math.sin(angle) - height / 2
                width: 6
                height: 6
                radius: 3
                color: Qt.alpha(Colors.foreground, 0.12)
            }
        }

        // Apps. Slots run from -1 to `slots`: the two outer ones are invisible at
        // rest and only exist so an app can glide in or out while the ring turns.
        Repeater {
            model: launcher.slots + 2

            delegate: Item {
                id: slot

                required property int index

                readonly property int k: index - 1
                readonly property int total: launcher.filtered.length
                readonly property var entry: total > 0 && k <= launcher.visibleCount ? launcher.filtered[(((launcher.selectedIndex + k) % total) + total) % total] : null
                // Slot position including the turn in progress (0 = top)
                readonly property real pos: k + launcher.spin / launcher.stepDeg
                readonly property real angle: (-90 + pos * launcher.stepDeg) * Math.PI / 180
                // 1 when sitting on the top slot, 0 one slot away
                readonly property real weight: Math.max(0, 1 - Math.abs(pos))
                readonly property int lastSlot: Math.max(0, launcher.visibleCount - 1)

                // Hidden ghosts must not take hover or clicks
                visible: entry !== null && opacity > 0.01
                width: launcher.itemSize + (launcher.selectedSize - launcher.itemSize) * weight
                height: width
                x: card.cx + launcher.ringRadius * Math.cos(angle) - width / 2
                y: card.cy + launcher.ringRadius * Math.sin(angle) - height / 2
                scale: area.pressed ? 0.94 : 1
                // Apps entering or leaving the window fade instead of popping
                opacity: pos < 0 ? Math.max(0, 1 + pos) : (pos > lastSlot ? Math.max(0, 1 - (pos - lastSlot)) : 1)

                Behavior on scale {
                    NumberAnimation {
                        duration: 100
                        easing.type: Easing.OutQuad
                    }
                }

                // Resting pill: the bar's hover fill, strongest on the top slot
                Rectangle {
                    anchors.fill: parent
                    radius: width / 2
                    antialiasing: true
                    color: Qt.alpha(Colors.foreground, 0.09 * slot.weight)
                }

                // Hover pill, faded like the bar's items
                Rectangle {
                    anchors.fill: parent
                    radius: width / 2
                    antialiasing: true
                    color: area.containsMouse ? Style.hoverFill : "transparent"

                    Behavior on color {
                        ColorAnimation {
                            duration: 200
                        }
                    }
                }

                IconImage {
                    anchors.centerIn: parent
                    width: Math.round(parent.width * 0.52)
                    height: width
                    source: launcher.iconFor(slot.entry)
                    // Resting icons sit back, like the bar's inactive workspaces
                    opacity: area.containsMouse ? 1 : 0.65 + 0.35 * slot.weight
                }

                MouseArea {
                    id: area

                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onEntered: launcher.peek = slot.entry
                    onExited: if (launcher.peek === slot.entry)
                        launcher.peek = null
                    onClicked: launcher.launch(slot.entry)
                }
            }
        }

        // Centre: time and date like the bar clock, app name, search pill
        Column {
            anchors.centerIn: parent
            width: 200
            spacing: 6

            Item {
                width: parent.width
                height: 18

                Row {
                    anchors.centerIn: parent
                    spacing: 8

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: Qt.formatDateTime(clock.date, "h:mm AP")
                        textFormat: Text.PlainText
                        color: Colors.foreground

                        font {
                            family: Style.fontFamily
                            pixelSize: 14
                            bold: true
                        }
                    }

                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 3
                        height: 3
                        radius: 1.5
                        color: Colors.muted
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: Qt.formatDateTime(clock.date, "ddd d MMM")
                        textFormat: Text.PlainText
                        color: Colors.muted

                        font {
                            family: Style.fontFamily
                            pixelSize: 13
                        }
                    }
                }
            }

            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                textFormat: Text.PlainText
                text: launcher.shown ? launcher.shown.name : (launcher.allApps.length === 0 ? "Loading…" : "No matches")
                color: launcher.shown ? Colors.accent : Colors.muted

                Behavior on color {
                    ColorAnimation {
                        duration: 200
                    }
                }

                font {
                    family: Style.fontFamily
                    pixelSize: 17
                    bold: true
                }
            }
        }

        // No box: the field is invisible until you type, then the text shows
        // under the app name. It still holds focus, so typing always searches.
        TextInput {
            id: input

            anchors.horizontalCenter: parent.horizontalCenter
            y: card.cy + 30
            width: 176
            height: 20
            horizontalAlignment: TextInput.AlignHCenter
            verticalAlignment: TextInput.AlignVCenter
            clip: true
            color: Colors.foreground
            selectionColor: Colors.accent
            selectedTextColor: Colors.background

            // Only draw a caret once there is something typed
            cursorDelegate: Rectangle {
                width: 1
                color: Colors.accent
                visible: input.text.length > 0
            }

            font {
                family: Style.fontFamily
                pixelSize: 13
            }

            onTextChanged: launcher.refilter()
            Keys.onEscapePressed: launcher.close()
            Keys.onReturnPressed: launcher.launch(launcher.current)
            Keys.onEnterPressed: launcher.launch(launcher.current)
            Keys.onLeftPressed: launcher.step(-1)
            Keys.onUpPressed: launcher.step(-1)
            Keys.onBacktabPressed: launcher.step(-1)
            Keys.onRightPressed: launcher.step(1)
            Keys.onDownPressed: launcher.step(1)
            Keys.onTabPressed: launcher.step(1)
            Keys.onPressed: event => {
                if (!(event.modifiers & Qt.ControlModifier))
                    return;
                if (event.key === Qt.Key_N) {
                    launcher.step(1);
                    event.accepted = true;
                } else if (event.key === Qt.Key_P) {
                    launcher.step(-1);
                    event.accepted = true;
                }
            }
        }
    }
}
