// Launcher: a dial rising from the bottom edge of the screen, in the shell's
// language: glass discs with a hairline outline, the accent only where it means
// something, and every colour from the palette. A fine ruler turns against the
// apps, and the middle reads out the name of the one on top.
// The apps and the ruler arrive like a rainbow: they swing in over a tight
// dome from the left, washed with the wallpaper's palette colours, then unfurl
// into the calm dial as the colour drains. Closing plays it in reverse.
//
//   qs ipc call launcher toggle | open | close
// Type to search (or type a sum). Left / Right, Tab or the wheel turn the dial,
// Enter launches (or copies the answer), Esc clears the search, then closes.
// Click an app to bring it to the top; click it again to launch.

import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets

PanelWindow {
    id: launcher

    // ---- Settings -------------------------------------------------------
    // Compact stage and tighter dial proportions.
    readonly property int stageH: 290
    readonly property int topY: 76
    readonly property real stepPx: 80
    readonly property real dialR: Math.max(900, width * 0.92)

    readonly property int itemSize: 46
    readonly property int selectedSize: 76

    // The dome the dial starts as when it opens (and ends as when it closes).
    readonly property real rainbowR: Math.min(380, Math.max(280, width * 0.2))

    readonly property int ruleDrop: 48
    readonly property int ruleY: topY + ruleDrop
    readonly property int tickGap: 12
    readonly property int tickCount: Math.ceil(width / tickGap / 10) * 10 + 20
    readonly property int slotHalf: Math.min(22, Math.ceil(width * 0.52 / stepPx) + 1)

    // Strength of the lower-edge shade (0 = none, 1 = solid).
    readonly property real scrim: 0.95
    readonly property string terminal: Config.terminal
    readonly property string countsPath: Config.home + "/.cache/quickshell/launcher-counts.json"

    // Opens on the monitor that has focus (set in open()).
    property var targetScreen: Focus.screen

    // ---- State ----------------------------------------------------------
    property bool isOpen: false
    property var allApps: []
    property var filtered: []
    property var counts: ({})
    property int ringTarget: 0
    property real ringPos: 0
    property real spinIn: 0
    property real reveal: 0
    property bool animateRing: true
    property var peek: null

    // 1 = tight rainbow dome with spectral tint, 0 = the resting dial
    property real fan: 1
    // A slow pulse (0..1) for the selected app's ring
    property real breath: 0
    // Sideways nudge of the name when the dial turns: it slides in from the
    // side the new app came from.
    property real readShift: 0
    // Radius of the dial right now: curvature eases from the dome to the dial
    readonly property real dialNow: 1 / (1 / dialR + (1 / rainbowR - 1 / dialR) * fan)

    readonly property real viewPos: ringPos + spinIn
    readonly property int count: filtered.length
    readonly property int selectedIndex: count > 0 ? ((ringTarget % count) + count) % count : 0
    readonly property var current: count > 0 ? filtered[selectedIndex] : null
    readonly property var display: peek ? peek : current
    property real progress: count > 1 ? (selectedIndex + 1) / count : 0

    // Typing a sum ("2*(3+4)") shows the answer in the middle; Enter copies it.
    readonly property string calcResult: {
        const v = Calc.evaluate(input.text);
        return isNaN(v) ? "" : Calc.format(v);
    }

    Behavior on ringPos {
        enabled: launcher.animateRing

        // The dial glides into place and settles, with no bounce
        NumberAnimation {
            duration: Style.enterMs
            easing.type: Style.easeEnter
        }
    }

    Behavior on progress {
        NumberAnimation {
            duration: Style.moveMs
            easing.type: Style.easeMove
        }
    }

    function clamp(v, a, b) {
        return Math.max(a, Math.min(b, v));
    }

    // Ease-out with a small overshoot for the arrival of each app (0..1 in,
    // about 1.04 at the peak): the shell's `pop`, kept gentle.
    function backOut(t) {
        const c1 = 0.8;
        const u = t - 1;
        return 1 + (c1 + 1) * u * u * u + c1 * u * u;
    }

    // Staggered arrival: 0 until `from`, 1 at `to` (in reveal units).
    function stage_(from, to) {
        return clamp((reveal - from) / (to - from), 0, 1);
    }

    // `base` washed with one of the palette's colours, chosen by screen
    // position x (colour1 on the left through colour6 on the right). The wash
    // is `fan` strong, so it only shows while the dial is arriving or leaving,
    // and it follows the wallpaper like everything else in the shell.
    function spectral(base, x, a) {
        const ramp = [Colors.color1, Colors.color2, Colors.color3, Colors.color4, Colors.color5, Colors.color6];
        const t = (clamp((x - width / 2) / (width * 0.34), -1, 1) * 0.5 + 0.5) * (ramp.length - 1);
        const i = Math.min(ramp.length - 2, Math.floor(t));
        const c = Qt.tint(ramp[i], Qt.alpha(ramp[i + 1], t - i));
        return Qt.alpha(Qt.tint(base, Qt.alpha(c, 0.9 * fan)), a);
    }

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

    // Higher is better; -1 means no match. Name matches outrank looser fields.
    function rank(a, q) {
        const name = (a.name || "").toLowerCase();
        const s = Fuzzy.score(name, q);
        if (s >= 0)
            return 1 + s + (name === q ? 100 : (name.indexOf(q) === 0 ? 40 : 0));
        if (Fuzzy.score((a.genericName || "").toLowerCase(), q) >= 0)
            return 0.6;
        let kw = "";
        try {
            kw = Array.prototype.join.call(a.keywords || [], " ").toLowerCase();
        } catch (e) {}
        if (kw !== "" && Fuzzy.score(kw, q) >= 0)
            return 0.5;
        if (Fuzzy.score((a.id || "").toLowerCase(), q) >= 0)
            return 0.4;
        return -1;
    }

    function refilter() {
        const q = input.text.toLowerCase().trim();
        const list = [];
        for (let i = 0; i < allApps.length; i++) {
            const a = allApps[i];
            const s = q === "" ? 0 : rank(a, q);
            if (s >= 0) {
                list.push({
                    "a": a,
                    "s": s,
                    "n": counts[a.id] || 0
                });
            }
        }
        list.sort((x, y) => (y.s - x.s) || (y.n - x.n) || x.a.name.localeCompare(y.a.name));
        filtered = list.map(x => x.a);
        peek = null;
        // Reset without animating across the list when the query changes.
        animateRing = false;
        ringTarget = 0;
        ringPos = 0;
        animateRing = true;
    }

    // ---- Actions --------------------------------------------------------
    function step(dir) {
        if (count < 2)
            return;
        peek = null;
        readShift = dir > 0 ? 18 : -18;
        ringTarget += dir;
        ringPos = ringTarget;
    }

    function stepTo(pos) {
        if (count < 2)
            return;
        peek = null;
        readShift = pos > ringTarget ? 18 : -18;
        ringTarget = pos;
        ringPos = ringTarget;
    }

    function saveCounts() {
        Quickshell.execDetached([
            "sh", "-c",
            'mkdir -p "$(dirname "$2")" && printf %s "$1" > "$2"',
            "sh", JSON.stringify(counts), countsPath
        ]);
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

    // Enter copies a calculator result, or starts the selected app.
    function activate() {
        if (calcResult !== "") {
            Quickshell.execDetached(["wl-copy", calcResult]);
            close();
        } else {
            launch(current);
        }
    }

    function open() {
        if (isOpen)
            return;
        targetScreen = Focus.screen;
        isOpen = true;
        closeAnim.stop();
        scanApps();
        input.text = "";
        refilter();
        reveal = 0;
        spinIn = 3.2;
        fan = 1;
        openAnim.restart();
        input.forceActiveFocus();
    }

    function close() {
        if (!isOpen)
            return;
        isOpen = false;
        openAnim.stop();
        closeAnim.restart();
    }

    function toggle() {
        if (isOpen)
            close();
        else
            open();
    }

    // ---- Window ---------------------------------------------------------
    visible: isOpen || reveal > 0.001
    screen: targetScreen
    color: "transparent"
    exclusiveZone: 0
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "qs-launcher"
    WlrLayershell.keyboardFocus: isOpen ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

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



    // One overlay panel at a time
    PanelLink {
        win: launcher
        name: "launcher"
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

    // Rises smoothly. The apps swing in from the left over a tight dome and
    // unfurl into the dial while the spectrum drains out of them.
    ParallelAnimation {
        id: openAnim

        NumberAnimation {
            target: launcher
            property: "reveal"
            from: 0
            to: 1
            duration: Style.sweepMs
            easing.type: Style.easeEnter
        }
        NumberAnimation {
            target: launcher
            property: "spinIn"
            from: 3.2
            to: 0
            duration: Style.sweepMs + Style.moveMs
            easing.type: Style.easeEnter
        }
        NumberAnimation {
            target: launcher
            property: "fan"
            from: 1
            to: 0
            duration: Style.sweepMs + Style.ambientMs / 2
            easing.type: Style.easeMove
        }
    }

    // Leaving: the dial curls back into the dome and the apps sweep off right.
    ParallelAnimation {
        id: closeAnim

        NumberAnimation {
            target: launcher
            property: "reveal"
            to: 0
            duration: Style.moveMs + Style.fadeMs
            easing.type: Style.easeExit
        }
        NumberAnimation {
            target: launcher
            property: "spinIn"
            to: -3.2
            duration: Style.moveMs + Style.fadeMs
            easing.type: Style.easeExit
        }
        NumberAnimation {
            target: launcher
            property: "fan"
            to: 1
            duration: Style.moveMs + Style.fadeMs
            easing.type: Style.easeExit
        }
    }

    // Slow breath for the ring around the selected app.
    SequentialAnimation {
        running: launcher.isOpen
        loops: Animation.Infinite

        NumberAnimation {
            target: launcher
            property: "breath"
            from: 0
            to: 1
            duration: Style.ambientMs * 2
            easing.type: Style.easeAmbient
        }
        NumberAnimation {
            target: launcher
            property: "breath"
            from: 1
            to: 0
            duration: Style.ambientMs * 2
            easing.type: Style.easeAmbient
        }
    }

    Connections {
        target: launcher
        function onDisplayChanged() {
            pop.restart();
        }
    }

    ParallelAnimation {
        id: pop

        NumberAnimation {
            target: readout
            property: "opacity"
            from: 0.3
            to: 1
            duration: Style.baseMs
            easing.type: Style.easeMove
        }
        NumberAnimation {
            target: readout
            property: "scale"
            from: 0.94
            to: 1
            duration: Style.baseMs
            easing.type: Style.easeMove
        }
        NumberAnimation {
            target: launcher
            property: "readShift"
            to: 0
            duration: Style.moveMs
            easing.type: Style.easeMove
        }
    }

    // The shared dim (Dim.qml): the same wash as the screenshot tool
    Dim {
        reveal: launcher.reveal
    }

    // Click outside the dial to close. The wheel rotates the app ring.
    MouseArea {
        anchors.fill: parent
        onClicked: launcher.close()
        onWheel: wheel => launcher.step(wheel.angleDelta.y < 0 ? 1 : -1)
    }

    // ---- Stage ----------------------------------------------------------
    Item {
        id: stage
        readonly property real cx: width / 2

        anchors.bottom: parent.bottom
        width: parent.width
        height: launcher.stageH
        opacity: Math.min(1, launcher.reveal * 3)
        transform: Translate {
            y: (1 - launcher.reveal) * (launcher.stageH + 40)
        }

        // Screenshot's feathered backing (StageShade.qml): a soft dark ellipse,
        // no visible panel boundary, over the shared dim under it.
        StageShade {}

        // Wide, low accent light on the horizon
        Shape {
            id: horizon
            readonly property real r: stage.width * 0.36

            x: stage.cx - r
            y: stage.height - r
            width: r * 2
            height: r * 2
            layer.enabled: true
            layer.samples: 4
            transform: Scale {
                origin.x: horizon.r
                origin.y: horizon.r
                yScale: 0.42
            }

            ShapePath {
                strokeColor: "transparent"
                startX: 0
                startY: horizon.r

                fillGradient: RadialGradient {
                    centerX: horizon.r
                    centerY: horizon.r
                    centerRadius: horizon.r
                    focalX: horizon.r
                    focalY: horizon.r

                    GradientStop {
                        position: 0
                        color: Qt.alpha(Colors.accent, 0.09)
                    }
                    GradientStop {
                        position: 0.5
                        color: Qt.alpha(Colors.accent, 0.03)
                    }
                    GradientStop {
                        position: 1
                        color: Qt.alpha(Colors.accent, 0)
                    }
                }

                PathArc {
                    x: horizon.r * 2
                    y: horizon.r
                    radiusX: horizon.r
                    radiusY: horizon.r
                }
                PathArc {
                    x: 0
                    y: horizon.r
                    radiusX: horizon.r
                    radiusY: horizon.r
                }
            }
        }

        // Fine dial ruler. It rotates counter to the apps at half speed.
        Repeater {
            model: launcher.tickCount

            delegate: Rectangle {
                id: tick
                required property int index

                readonly property real span: launcher.tickCount * launcher.tickGap
                readonly property real dx: ((index * launcher.tickGap + launcher.viewPos * launcher.stepPx * 0.5) % span + span) % span - span / 2
                readonly property real a: dx / launcher.dialNow
                readonly property real rr: launcher.dialNow - launcher.ruleDrop
                readonly property bool major: index % 10 === 0
                readonly property bool mid: index % 5 === 0

                x: stage.cx + rr * Math.sin(a) - 0.5
                y: launcher.topY + launcher.dialNow - rr * Math.cos(a)
                width: 1
                height: major ? 9 : (mid ? 6 : 3)
                radius: 0.5
                antialiasing: true
                visible: Math.abs(a) < 1.2 && y < stage.height - 70
                transformOrigin: Item.Top
                rotation: a * 180 / Math.PI
                color: launcher.spectral(Colors.foreground, x, major ? 0.95 : (mid ? 0.7 : 0.5))
                opacity: launcher.clamp((stage.cx - Math.abs(x - stage.cx)) / 230, 0, 1)
                         * launcher.clamp((stage.height - y) / 82, 0, 1)
                         * launcher.clamp(launcher.reveal * 2 - Math.abs(x - stage.cx) / stage.cx * 0.9, 0, 1)
            }
        }

        // Fine center marker on the ruler, with a soft bead at its foot.
        Rectangle {
            x: stage.cx - 0.75
            y: launcher.ruleY - 1
            width: 1.5
            height: 12
            radius: 0.5
            color: Colors.accent
        }
        Rectangle {
            x: stage.cx - width / 2
            y: launcher.ruleY + 14
            width: 5
            height: 5
            radius: 2.5
            color: Colors.accent
            opacity: 0.55 + 0.4 * launcher.breath
        }

        // Accent underline above the selected app; it breathes with the ring.
        Rectangle {
            x: stage.cx - width / 2
            y: launcher.topY - launcher.selectedSize * 0.62
            width: 20 + 10 * launcher.breath
            height: 2
            radius: 1
            color: Colors.accent
        }

        // ---- Apps -------------------------------------------------------
        Repeater {
            model: launcher.slotHalf * 2 + 1

            delegate: Item {
                id: slot
                required property int index

                readonly property int s: index - launcher.slotHalf
                readonly property int n: launcher.count
                readonly property int m: Math.min(launcher.slotHalf * 2 + 1, n)
                readonly property int lo: -Math.floor((m - 1) / 2)
                readonly property int hi: lo + m - 1
                readonly property int pos: Math.round(launcher.viewPos) + s
                readonly property real k: pos - launcher.viewPos
                readonly property var app: n > 0 ? launcher.filtered[((pos % n) + n) % n] : null
                readonly property real a: k * launcher.stepPx / launcher.dialNow
                readonly property real px: stage.cx + launcher.dialNow * Math.sin(a)
                readonly property real py: launcher.topY + launcher.dialNow * (1 - Math.cos(a))
                readonly property real c: Math.max(0, 1 - Math.abs(k))
                readonly property real sz: launcher.itemSize + (launcher.selectedSize - launcher.itemSize) * c
                readonly property bool current: Math.abs(k) < 0.5
                // The apps arrive in a left-to-right wave, each with a small
                // overshoot, and leave the same way.
                readonly property real delay: (launcher.clamp(s, -7, 7) + 7) * 0.026
                readonly property real appear: launcher.clamp((launcher.reveal - delay) / 0.42, 0, 1)
                readonly property real pop_: launcher.backOut(appear)
                // 0 at rest, 1 under the pointer: a gentle lift
                property real hover: area.containsMouse && !current ? 1 : 0
                // 0..1 while the ring around a newly selected app expands
                property real ping: 0
                // Shape: a squircle that rounds a little more as it is selected
                readonly property real corner: sz * (0.36 + 0.06 * c)
                readonly property real edge: launcher.clamp((stage.cx - Math.abs(px - stage.cx)) / 105, 0, 1)
                readonly property real horizon: launcher.clamp((stage.height - py + sz * 0.3) / (sz * 0.6), 0, 1)

                visible: app !== null && s >= lo && s <= hi && py - sz / 2 < stage.height
                x: px - sz / 2
                y: py - sz / 2
                width: sz
                height: sz
                z: 10 - Math.abs(k)
                opacity: appear * edge * horizon
                scale: 0.55 + 0.45 * pop_
                // Tilts along the dial, and rises from below as it arrives
                rotation: a * 180 / Math.PI * 0.6
                transform: Translate {
                    y: (1 - slot.appear) * 30 - 3 * slot.hover
                }

                Behavior on hover {
                    NumberAnimation {
                        duration: Style.baseMs
                        easing.type: Style.easeMove
                    }
                }

                // The selection changed to this app: a ring leaves it.
                onCurrentChanged: if (current && launcher.isOpen && launcher.reveal > 0.8)
                    pingAnim.restart()

                NumberAnimation {
                    id: pingAnim
                    target: slot
                    property: "ping"
                    from: 0
                    to: 1
                    duration: Style.sweepMs
                    easing.type: Style.easeMove
                }

                // Ring that leaves a newly selected app.
                Rectangle {
                    anchors.centerIn: parent
                    width: parent.width + 14 + 34 * slot.ping
                    height: width
                    radius: slot.corner + 7 + 17 * slot.ping
                    color: "transparent"
                    antialiasing: true
                    visible: slot.ping > 0.001 && slot.ping < 0.999
                    border.width: 1.5
                    border.color: Qt.alpha(Colors.accent, 0.5 * (1 - slot.ping))
                }

                // Breathing accent ring around the selected app.
                Rectangle {
                    anchors.centerIn: parent
                    width: parent.width + 14
                    height: width
                    radius: slot.corner + 7
                    color: "transparent"
                    antialiasing: true
                    visible: slot.c > 0.05
                    border.width: 1
                    border.color: Qt.alpha(Colors.accent, slot.c * (0.2 + 0.2 * launcher.breath))
                }

                // Keep the mouse area stable while the icon subtly presses in.
                Item {
                    anchors.fill: parent
                    scale: area.pressed ? 0.94 : 1

                    Behavior on scale {
                        NumberAnimation {
                            duration: Style.pressMs
                            easing.type: Style.easePress
                        }
                    }

                    // Glass, like the bar: one flat surface with a hairline outline.
                    // The outline takes the palette wash while the dial is
                    // arriving, and the accent once the app is selected.
                    Rectangle {
                        anchors.fill: parent
                        radius: slot.corner
                        antialiasing: true
                        color: Style.card
                        border.width: 1
                        border.color: slot.c > 0.45
                                     ? launcher.spectral(Colors.accent, slot.px, 0.6 + 0.4 * slot.c)
                                     : launcher.spectral(Colors.foreground, slot.px, 0.2)
                    }

                    // Light catching the top edge, as on the bar
                    Rectangle {
                        anchors.top: parent.top
                        anchors.topMargin: 1
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: parent.width - slot.corner * 1.2
                        height: 1

                        gradient: Gradient {
                            orientation: Gradient.Horizontal

                            GradientStop {
                                position: 0
                                color: Qt.alpha(Colors.foreground, 0)
                            }
                            GradientStop {
                                position: 0.5
                                color: Qt.alpha(Colors.foreground, 0.12)
                            }
                            GradientStop {
                                position: 1
                                color: Qt.alpha(Colors.foreground, 0)
                            }
                        }
                    }

                    // The shell's hover fill
                    Rectangle {
                        anchors.fill: parent
                        radius: slot.corner
                        antialiasing: true
                        color: area.containsMouse ? Style.hoverFill : "transparent"

                        Behavior on color {
                            ColorAnimation {
                                duration: Style.baseMs
                            }
                        }
                    }

                    IconImage {
                        anchors.centerIn: parent
                        anchors.verticalCenterOffset: -2 * launcher.breath * slot.c
                        width: Math.round(slot.sz * 0.56)
                        height: width
                        // The icon stays upright while the disc tilts with the dial
                        rotation: -slot.rotation
                        source: launcher.iconFor(slot.app)
                        opacity: area.containsMouse ? 1 : 0.92 + 0.08 * slot.c
                    }
                }

                MouseArea {
                    id: area
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onEntered: launcher.peek = slot.app
                    onExited: if (launcher.peek === slot.app)
                                  launcher.peek = null
                    onClicked: {
                        if (Math.abs(slot.k) < 0.5)
                            launcher.launch(slot.app);
                        else
                            launcher.stepTo(slot.pos);
                    }
                }
            }
        }

        // Clicking the central readout or search pill returns focus to search.
        MouseArea {
            x: stage.cx - 220
            y: readout.y
            width: 440
            height: pill.y + pill.height - readout.y
            onClicked: input.forceActiveFocus()
        }

        // ---- Central readout --------------------------------------------
        // Just the name, with a soft shadow in the background colour so it reads on any wallpaper.
        Item {
            id: readout
            x: stage.cx - width / 2
            y: launcher.ruleY + 30
            width: 460
            height: 30
            transform: Translate {
                x: launcher.readShift
                y: (1 - launcher.stage_(0.25, 0.8)) * 12
            }

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                height: parent.height
                spacing: Style.spaceMd

                // Calculator result glyph.
                Txt {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: launcher.calcResult !== ""
                    text: String.fromCodePoint(0xF00EC)
                    color: Colors.accent
                    font.pixelSize: 22
                }

                Item {
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.min(nameText.implicitWidth, readout.width - 44)
                    height: nameText.implicitHeight

                    Txt {
                        x: 0
                        y: 1.5
                        width: parent.width
                        elide: Text.ElideRight
                        text: nameText.text
                        color: Qt.alpha(Colors.background, 0.9)
                        font: nameText.font
                    }

                    Txt {
                        id: nameText
                        width: parent.width
                        elide: Text.ElideRight
                        text: launcher.calcResult !== ""
                              ? "= " + launcher.calcResult
                              : (launcher.display ? launcher.display.name : (launcher.allApps.length === 0 ? "" : "No matches"))
                        color: launcher.calcResult !== ""
                               ? Colors.accent
                               : (launcher.display ? Colors.foreground : Colors.muted)
                        font.pixelSize: 22
                        font.bold: true
                        font.letterSpacing: -0.2
                    }
                }
            }
        }

        // ---- Search pill -----------------------------------------------
        // The shell's SearchField on a glass backing, so it reads on any
        // wallpaper. Hidden until you type; the field keeps focus while hidden.
        Item {
            id: pill

            x: stage.cx - width / 2
            y: readout.y + readout.height + 14
            width: 300
            height: Style.fieldHeight
            opacity: input.text !== "" ? 1 : 0
            scale: input.text !== "" ? 1 : 0.94

            Behavior on opacity {
                NumberAnimation {
                    duration: Style.baseMs
                    easing.type: Style.easeMove
                }
            }
            Behavior on scale {
                NumberAnimation {
                    duration: Style.baseMs
                    easing.type: Style.easeMove
                }
            }

            Rectangle {
                anchors.fill: parent
                radius: height / 2
                antialiasing: true
                color: Style.surface
                border.width: 1
                border.color: Style.outline
            }

            // Light catching the top edge, as on the bar
            Rectangle {
                anchors.top: parent.top
                anchors.topMargin: 1
                anchors.horizontalCenter: parent.horizontalCenter
                width: parent.width - parent.height
                height: 1

                gradient: Gradient {
                    orientation: Gradient.Horizontal

                    GradientStop {
                        position: 0
                        color: Qt.alpha(Colors.foreground, 0)
                    }
                    GradientStop {
                        position: 0.5
                        color: Qt.alpha(Colors.foreground, 0.12)
                    }
                    GradientStop {
                        position: 1
                        color: Qt.alpha(Colors.foreground, 0)
                    }
                }
            }

            SearchField {
                id: input

                anchors.fill: parent
                placeholder: "Search apps, or type a sum"
                // Number of matches while typing
                badge: input.text !== "" && launcher.calcResult === "" ? String(launcher.count) : ""

                onTextChanged: launcher.refilter()
                Keys.onEscapePressed: {
                    if (text !== "")
                        text = "";
                    else
                        launcher.close();
                }
                Keys.onReturnPressed: launcher.activate()
                Keys.onEnterPressed: launcher.activate()
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
}
