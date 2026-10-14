// PackageSearch.qml
// Nix package search on the launcher's dial: the same borderless stage rising
// from the bottom edge, the same fine ruler, bar-style glass discs and accent
// underline. Each match is a monogram disc on the dial; the one on top is
// named in the middle, with its version, licence, flags and description, and
// its actions underneath. The search pill sits below, always visible.
// Like the launcher it arrives as a rainbow: the discs swing in from the left
// over a tight dome, washed with the wallpaper's palette colours, then unfurl
// into the calm dial as the colour drains. Closing plays it in reverse.
// The index, search and actions live in Pkgs.qml; this file is the interface.
//
//   qs ipc call pkgsearch toggle | open | close | search "<words>"
// Type to search nixpkgs (the version your flake is pinned to).
// Keys: ← → ↑ ↓ tab (or ctrl+n / ctrl+p) move   pgup pgdn jump 8
//       enter throwaway shell   ctrl+enter run   shift+enter copy the name
//       esc clears the search, then closes
// Mouse: hover a disc to read it, click it to pick it, click the picked disc
//        for a shell, scroll to move, click outside to close
//
// Shell and Run open a terminal, so the panel closes behind them. Copy and
// "Add to home.nix" stay open and say what happened in the line at the foot.

import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

PanelWindow {
    id: panel

    // ---- Settings -------------------------------------------------------
    readonly property int topY: 70
    readonly property real stepPx: 78
    readonly property real dialR: Math.max(900, width * 0.92)
    // The dome the dial starts as when it opens (and ends as when it closes)
    readonly property real rainbowR: Math.min(380, Math.max(280, width * 0.2))

    readonly property int itemSize: 44
    readonly property int selectedSize: 72

    readonly property int ruleDrop: 46
    readonly property int ruleY: topY + ruleDrop
    readonly property int tickGap: 12
    readonly property int tickCount: Math.ceil(width / tickGap / 10) * 10 + 20
    readonly property int slotHalf: Math.min(22, Math.ceil(width * 0.52 / stepPx) + 1)

    // Rows of the stage, top to bottom (all measured from the top of the stage)
    readonly property int nameY: ruleY + 26
    readonly property int chipsY: nameY + 34
    readonly property int descY: chipsY + 28
    readonly property int actionsY: descY + 46
    readonly property int pillY: actionsY + 48
    readonly property int footY: pillY + Style.fieldHeight + 10
    readonly property int stageH: footY + 34

    // Strength of the lower-edge shade (0 = none, 1 = solid)
    readonly property real scrim: 0.95

    // ---- State ----------------------------------------------------------
    // Opens on the monitor that has focus (set in open())
    property var targetScreen: Focus.screen
    property bool isOpen: false
    // 0 = hidden below the edge, 1 = in place
    property real reveal: 0
    // Slots the dial is swung to the left while arriving (and right when leaving)
    property real spinIn: 0
    // 1 = tight rainbow dome with spectral tint, 0 = the resting dial
    property real fan: 1
    // A slow pulse (0..1) for the picked disc's ring
    property real breath: 0
    // Where the dial is turned to, in slots; follows the picked package
    property real ringPos: 0
    property bool animateRing: true
    // True for a moment after new matches land, so the dial jumps to the new
    // first match instead of gliding across the list
    property bool snapNext: false
    property int lastIdx: 0
    // The match under the pointer (read only: nothing is loaded for it)
    property var peek: null
    // Sideways nudge of the name when the dial turns
    property real readShift: 0

    readonly property int count: Pkgs.results.length
    // Where the picked package sits in the list (-1 when none)
    readonly property int selIndex: Pkgs.results.findIndex(r => r.attr === Pkgs.selected)
    readonly property real viewPos: ringPos + spinIn
    // Radius of the dial right now: curvature eases from the dome to the dial
    readonly property real dialNow: 1 / (1 / dialR + (1 / rainbowR - 1 / dialR) * fan)

    // What the middle reads out: the match under the pointer, else the picked one
    readonly property var shown: peek ? peek : Pkgs.current
    readonly property bool peeking: peek !== null
    readonly property bool busy: Pkgs.searching || Pkgs.building

    readonly property string emptyTitle: Pkgs.building ? "Building the package index…" : (!Pkgs.ready ? "No package index yet" : (input.text.trim() === "" ? "Search nixpkgs" : (Pkgs.searching ? "Searching…" : "No packages match")))
    readonly property string emptySub: Pkgs.building ? Pkgs.buildNote : (!Pkgs.ready ? "Use Update index below to build it" : (input.text.trim() === "" ? "By name or description, in the version your flake is pinned to" : (Pkgs.searching ? "" : "Try fewer or different words")))
    readonly property string descText: {
        if (!shown)
            return emptySub;
        if (peeking)
            return shown.desc;
        const detail = Pkgs.info.longDescription ? Pkgs.info.longDescription.replace(/\s+/g, " ").trim() : "";
        return detail !== "" ? detail : shown.desc;
    }

    Behavior on ringPos {
        enabled: panel.animateRing

        // The dial glides into place and settles, with no bounce
        NumberAnimation {
            duration: Style.enterMs
            easing.type: Style.easeEnter
        }
    }

    onSelIndexChanged: {
        peek = null;
        if (selIndex < 0)
            return;
        const d = selIndex - lastIdx;
        lastIdx = selIndex;
        if (snapNext) {
            animateRing = false;
            ringPos = selIndex;
            animateRing = true;
        } else {
            ringPos = selIndex;
        }
        if (isOpen)
            bump(snapNext ? 0 : (d > 0 ? 1 : -1));
    }

    onPeekChanged: if (isOpen)
        bump(0)

    // ---- Helpers --------------------------------------------------------
    function clamp(v, a, b) {
        return Math.max(a, Math.min(b, v));
    }

    // Ease-out with a small overshoot for the arrival of each disc (0..1 in,
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

    // The letter a package wears on its disc: python312Packages.numpy -> N
    function letterFor(attr) {
        const base = String(attr).split(".").pop();
        const ch = base.replace(/^[^A-Za-z0-9]+/, "").charAt(0);
        return ch === "" ? "·" : ch.toUpperCase();
    }

    // The readout fades and settles; with a direction it slides in from there
    function bump(dir) {
        if (dir !== 0)
            readShift = dir > 0 ? 18 : -18;
        pop.restart();
    }

    // ---- Actions --------------------------------------------------------
    function toggle() {
        if (isOpen)
            close();
        else
            open();
    }

    function open() {
        if (isOpen)
            return;
        targetScreen = Focus.screen;
        isOpen = true;
        closeAnim.stop();
        peek = null;
        animateRing = false;
        ringPos = Math.max(0, selIndex);
        animateRing = true;
        reveal = 0;
        spinIn = 3.2;
        fan = 1;
        openAnim.restart();
        Pkgs.refreshStatus();
        input.forceActiveFocus();
        input.selectAll();
        autoBuild.restart();
    }

    function close() {
        if (!isOpen)
            return;
        isOpen = false;
        openAnim.stop();
        closeAnim.restart();
    }

    // Pick the package `step` places further along the list
    function move(step) {
        if (count === 0)
            return;
        const i = clamp((selIndex < 0 ? 0 : selIndex) + step, 0, count - 1);
        Pkgs.select(Pkgs.results[i].attr);
    }

    function launchShell() {
        if (Pkgs.selected === "")
            return;
        Pkgs.tryShell(Pkgs.selected);
        close();
    }

    function launchRun() {
        if (Pkgs.selected === "" || !Pkgs.info.mainProgram)
            return;
        Pkgs.tryRun(Pkgs.selected);
        close();
    }

    function copyName() {
        if (Pkgs.selected === "")
            return;
        Pkgs.copy(Pkgs.selected);
        copyBtn.confirm();
    }

    // ---- Window ---------------------------------------------------------
    // Fullscreen and invisible, like the launcher: the stage rises from the
    // bottom edge, and a click outside it closes the panel.
    visible: isOpen || reveal > 0.001
    screen: targetScreen
    color: "transparent"
    exclusiveZone: 0
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "qs-pkgsearch"
    WlrLayershell.keyboardFocus: isOpen ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    IpcHandler {
        function toggle() {
            panel.toggle();
        }

        function open() {
            panel.open();
        }

        function close() {
            panel.close();
        }

        function search(words: string) {
            panel.open();
            input.text = words;
        }

        target: "pkgsearch"
    }

    // One overlay panel at a time
    PanelLink {
        win: panel
        name: "pkgsearch"
    }

    // First use: build the index once the status check has come back empty
    Timer {
        id: autoBuild

        interval: 700
        onTriggered: if (!Pkgs.ready && !Pkgs.building)
            Pkgs.buildIndex()
    }

    // New matches landed: the dial jumps to them instead of gliding. The
    // picked package is set a moment later in the same step, so the flag only
    // has to live until the event loop turns.
    Connections {
        target: Pkgs

        function onResultsChanged() {
            panel.snapNext = true;
            Qt.callLater(() => {
                panel.snapNext = false;
            });
        }

        function onSelectedChanged() {
            if (panel.isOpen)
                panel.bump(0);
        }
    }

    // ---- Motion ---------------------------------------------------------
    // Rises smoothly. The discs swing in from the left over a tight dome and
    // unfurl into the dial while the spectrum drains out of them.
    ParallelAnimation {
        id: openAnim

        NumberAnimation {
            target: panel
            property: "reveal"
            from: 0
            to: 1
            duration: Style.sweepMs
            easing.type: Style.easeEnter
        }
        NumberAnimation {
            target: panel
            property: "spinIn"
            from: 3.2
            to: 0
            duration: Style.sweepMs + Style.moveMs
            easing.type: Style.easeEnter
        }
        NumberAnimation {
            target: panel
            property: "fan"
            from: 1
            to: 0
            duration: Style.sweepMs + Style.ambientMs / 2
            easing.type: Style.easeMove
        }
    }

    // Leaving: the dial curls back into the dome and the discs sweep off right.
    ParallelAnimation {
        id: closeAnim

        NumberAnimation {
            target: panel
            property: "reveal"
            to: 0
            duration: Style.moveMs + Style.fadeMs
            easing.type: Style.easeExit
        }
        NumberAnimation {
            target: panel
            property: "spinIn"
            to: -3.2
            duration: Style.moveMs + Style.fadeMs
            easing.type: Style.easeExit
        }
        NumberAnimation {
            target: panel
            property: "fan"
            to: 1
            duration: Style.moveMs + Style.fadeMs
            easing.type: Style.easeExit
        }
    }

    // Slow breath for the ring around the picked disc, and for the middle
    // while something is going on.
    SequentialAnimation {
        running: panel.isOpen
        loops: Animation.Infinite

        NumberAnimation {
            target: panel
            property: "breath"
            from: 0
            to: 1
            duration: Style.ambientMs * 2
            easing.type: Style.easeAmbient
        }
        NumberAnimation {
            target: panel
            property: "breath"
            from: 1
            to: 0
            duration: Style.ambientMs * 2
            easing.type: Style.easeAmbient
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
            target: panel
            property: "readShift"
            to: 0
            duration: Style.moveMs
            easing.type: Style.easeMove
        }
    }

    // The line at the foot changes (stats, or the latest message): a quick fade
    NumberAnimation {
        id: statFade

        target: statLine
        property: "opacity"
        from: 0.3
        to: 1
        duration: Style.baseMs
        easing.type: Style.easeMove
    }

    // ---- Small pieces ---------------------------------------------------
    // A thin glint that runs along a track while something is going on
    component Sweep: Item {
        id: sweep

        property bool running: false
        property int glintW: 80

        clip: true
        opacity: running ? 1 : 0
        visible: opacity > 0.01

        Behavior on opacity {
            NumberAnimation {
                duration: Style.fadeMs
            }
        }

        Rectangle {
            id: glint

            width: sweep.glintW
            height: parent.height
            radius: height / 2
            x: -width

            gradient: Gradient {
                orientation: Gradient.Horizontal

                GradientStop {
                    position: 0
                    color: Qt.alpha(Colors.accent, 0)
                }
                GradientStop {
                    position: 0.5
                    color: Colors.accent
                }
                GradientStop {
                    position: 1
                    color: Qt.alpha(Colors.accent, 0)
                }
            }

            SequentialAnimation on x {
                running: sweep.running && sweep.visible
                loops: Animation.Infinite

                NumberAnimation {
                    from: -glint.width
                    to: sweep.width
                    duration: Style.ambientMs * 2
                    easing.type: Style.easeAmbient
                }
            }
        }
    }

    // A small pill label. With `popIn` it pops in with a little overshoot
    // whenever it appears (the package's details arriving); with `clickable`
    // it is a link.
    component Chip: Rectangle {
        id: chip

        property string text: ""
        property string glyph: ""
        property color tint: Colors.muted
        property bool popIn: false
        property bool clickable: false

        signal clicked

        implicitHeight: 22
        implicitWidth: chipRow.implicitWidth + 18
        radius: height / 2
        antialiasing: true
        color: Qt.alpha(tint, clickable && chipHover.hovered ? Style.selectedAlpha + 0.08 : Style.tintAlpha)
        onVisibleChanged: if (visible && popIn)
            popAnim.restart()
        Component.onCompleted: if (visible && popIn)
            popAnim.restart()

        Behavior on color {
            ColorAnimation {
                duration: Style.baseMs
            }
        }

        NumberAnimation {
            id: popAnim

            target: chip
            property: "scale"
            from: 0.7
            to: 1
            duration: Style.moveMs
            easing.type: Style.easePop
            easing.overshoot: 2
        }

        Row {
            id: chipRow

            anchors.centerIn: parent
            spacing: 5

            Txt {
                anchors.verticalCenter: parent.verticalCenter
                visible: chip.glyph !== ""
                text: chip.glyph
                color: chip.tint
                font.pixelSize: Style.fontSm
            }
            Txt {
                anchors.verticalCenter: parent.verticalCenter
                text: chip.text
                color: chip.tint
                font.pixelSize: Style.fontSm
            }
        }

        HoverHandler {
            id: chipHover

            cursorShape: chip.clickable ? Qt.PointingHandCursor : Qt.ArrowCursor
        }
        TapHandler {
            enabled: chip.clickable
            onTapped: chip.clicked()
        }
    }

    // The shared dim (Dim.qml): the same wash as the screenshot tool
    Dim {
        reveal: panel.reveal
    }

    // ---- Click outside, scroll -------------------------------------------
    // The wheel moves along the list. A click on the lower stage (the readout,
    // the buttons, the search) belongs to it and does not close the panel.
    MouseArea {
        anchors.fill: parent
        onClicked: mouse => {
            if (mouse.y > stage.y + panel.ruleY - 12 && Math.abs(mouse.x - stage.cx) < 340)
                return;
            panel.close();
        }
        onWheel: wheel => panel.move(wheel.angleDelta.y < 0 ? 1 : -1)
    }

    // ---- Stage ----------------------------------------------------------
    Item {
        id: stage

        readonly property real cx: width / 2

        anchors.bottom: parent.bottom
        width: parent.width
        height: panel.stageH
        opacity: Math.min(1, panel.reveal * 3)
        transform: Translate {
            y: (1 - panel.reveal) * (panel.stageH + 40)
        }

        // Screenshot's feathered backing (StageShade.qml): a soft dark ellipse,
        // no visible panel boundary, over the shared dim under it.
        StageShade {}

        // Wide, low accent light on the horizon
        Shape {
            id: glow

            readonly property real r: stage.width * 0.36

            x: stage.cx - r
            y: stage.height - r
            width: r * 2
            height: r * 2
            layer.enabled: true
            layer.samples: 4
            transform: Scale {
                origin.x: glow.r
                origin.y: glow.r
                yScale: 0.42
            }

            ShapePath {
                strokeColor: "transparent"
                startX: 0
                startY: glow.r

                fillGradient: RadialGradient {
                    centerX: glow.r
                    centerY: glow.r
                    centerRadius: glow.r
                    focalX: glow.r
                    focalY: glow.r

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
                    x: glow.r * 2
                    y: glow.r
                    radiusX: glow.r
                    radiusY: glow.r
                }
                PathArc {
                    x: 0
                    y: glow.r
                    radiusX: glow.r
                    radiusY: glow.r
                }
            }
        }

        // Fine dial ruler. It rotates counter to the discs at half speed.
        Repeater {
            model: panel.tickCount

            delegate: Rectangle {
                id: tick

                required property int index

                readonly property real span: panel.tickCount * panel.tickGap
                readonly property real dx: ((index * panel.tickGap + panel.viewPos * panel.stepPx * 0.5) % span + span) % span - span / 2
                readonly property real a: dx / panel.dialNow
                readonly property real rr: panel.dialNow - panel.ruleDrop
                readonly property bool major: index % 10 === 0
                readonly property bool mid: index % 5 === 0

                x: stage.cx + rr * Math.sin(a) - 0.5
                y: panel.topY + panel.dialNow - rr * Math.cos(a)
                width: 1
                height: major ? 9 : (mid ? 6 : 3)
                radius: 0.5
                antialiasing: true
                visible: Math.abs(a) < 1.2 && y < stage.height - 70
                transformOrigin: Item.Top
                rotation: a * 180 / Math.PI
                color: panel.spectral(Colors.foreground, x, major ? 0.95 : (mid ? 0.7 : 0.5))
                opacity: panel.clamp((stage.cx - Math.abs(x - stage.cx)) / 230, 0, 1) * panel.clamp((stage.height - y) / 82, 0, 1) * panel.clamp(panel.reveal * 2 - Math.abs(x - stage.cx) / stage.cx * 0.9, 0, 1)
            }
        }

        // Fine center marker on the ruler, with a soft bead at its foot.
        Rectangle {
            x: stage.cx - 0.75
            y: panel.ruleY - 1
            width: 1.5
            height: 12
            radius: 0.5
            color: Colors.accent
        }
        Rectangle {
            x: stage.cx - width / 2
            y: panel.ruleY + 14
            width: 5
            height: 5
            radius: 2.5
            color: Colors.accent
            opacity: 0.55 + 0.4 * panel.breath
        }

        // Accent underline above the picked disc; it breathes with the ring.
        Rectangle {
            x: stage.cx - width / 2
            y: panel.topY - panel.selectedSize * 0.62
            width: 20 + 10 * panel.breath
            height: 2
            radius: 1
            color: Colors.accent
            opacity: panel.count > 0 ? 1 : 0

            Behavior on opacity {
                NumberAnimation {
                    duration: Style.baseMs
                }
            }
        }

        // ---- The matches, one disc each -----------------------------------
        Repeater {
            model: panel.slotHalf * 2 + 1

            delegate: Item {
                id: slot

                required property int index

                readonly property int s: index - panel.slotHalf
                readonly property int pos: Math.round(panel.viewPos) + s
                readonly property real k: pos - panel.viewPos
                // The list has a first and a last match: the dial does not wrap
                readonly property var row: pos >= 0 && pos < panel.count ? Pkgs.results[pos] : null
                readonly property real a: k * panel.stepPx / panel.dialNow
                readonly property real px: stage.cx + panel.dialNow * Math.sin(a)
                readonly property real py: panel.topY + panel.dialNow * (1 - Math.cos(a))
                readonly property real c: Math.max(0, 1 - Math.abs(k))
                readonly property real sz: panel.itemSize + (panel.selectedSize - panel.itemSize) * c
                readonly property bool current: Math.abs(k) < 0.5
                // The discs arrive in a left-to-right wave, each with a small
                // overshoot, and leave the same way.
                readonly property real delay: (panel.clamp(s, -7, 7) + 7) * 0.026
                readonly property real appear: panel.clamp((panel.reveal - delay) / 0.42, 0, 1)
                readonly property real pop_: panel.backOut(appear)
                // 0 at rest, 1 under the pointer: a gentle lift
                property real hover: area.containsMouse && !current ? 1 : 0
                // 0..1 while the ring around a newly picked disc expands
                property real ping: 0
                // Shape: a squircle that rounds a little more as it is picked
                readonly property real corner: sz * (0.36 + 0.06 * c)
                readonly property real edge: panel.clamp((stage.cx - Math.abs(px - stage.cx)) / 105, 0, 1)
                readonly property real lowFade: panel.clamp((stage.height - py + sz * 0.3) / (sz * 0.6), 0, 1)

                visible: row !== null && py - sz / 2 < stage.height
                x: px - sz / 2
                y: py - sz / 2
                width: sz
                height: sz
                z: 10 - Math.abs(k)
                opacity: appear * edge * lowFade
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

                // The pick moved to this disc: a ring leaves it.
                onCurrentChanged: if (current && panel.isOpen && panel.reveal > 0.8)
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

                // Ring that leaves a newly picked disc.
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

                // Breathing accent ring around the picked disc.
                Rectangle {
                    anchors.centerIn: parent
                    width: parent.width + 14
                    height: width
                    radius: slot.corner + 7
                    color: "transparent"
                    antialiasing: true
                    visible: slot.c > 0.05
                    border.width: 1
                    border.color: Qt.alpha(Colors.accent, slot.c * (0.2 + 0.2 * panel.breath))
                }

                // Everything that can be pressed sits in here, so the press
                // shrink never changes the area the mouse reacts to
                Item {
                    anchors.fill: parent
                    scale: area.pressed ? 0.94 : 1

                    Behavior on scale {
                        NumberAnimation {
                            duration: Style.pressMs
                            easing.type: Style.easePress
                        }
                    }

                    // Glass, like the bar: one flat surface with a hairline
                    // outline. The outline takes the palette wash while the
                    // dial is arriving, and the accent once the disc is picked.
                    Rectangle {
                        anchors.fill: parent
                        radius: slot.corner
                        antialiasing: true
                        color: Style.card
                        border.width: 1
                        border.color: slot.c > 0.45 ? panel.spectral(Colors.accent, slot.px, 0.6 + 0.4 * slot.c) : panel.spectral(Colors.foreground, slot.px, 0.2)
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

                    // The monogram. It stays upright while the disc tilts
                    // with the dial.
                    Txt {
                        anchors.centerIn: parent
                        anchors.verticalCenterOffset: -2 * panel.breath * slot.c
                        rotation: -slot.rotation
                        text: slot.row ? panel.letterFor(slot.row.attr) : ""
                        color: slot.current ? Colors.accent : Colors.foreground
                        opacity: area.containsMouse ? 1 : 0.7 + 0.3 * slot.c
                        font.pixelSize: Math.round(slot.sz * 0.4)
                        font.bold: slot.current

                        Behavior on color {
                            ColorAnimation {
                                duration: Style.baseMs
                            }
                        }
                    }
                }

                MouseArea {
                    id: area

                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    // Hovering only reads the match out; nothing is loaded
                    // until you pick it
                    onEntered: if (!slot.current && slot.row)
                        panel.peek = slot.row
                    onExited: if (panel.peek && slot.row && panel.peek.attr === slot.row.attr)
                        panel.peek = null
                    onClicked: {
                        if (!slot.row)
                            return;
                        if (slot.current)
                            panel.launchShell();
                        else
                            Pkgs.select(slot.row.attr);
                    }
                }
            }
        }

        // ---- The middle: the name, what it is, and what it does ------------
        // Without a match it says what is going on instead.
        Item {
            id: readout

            x: stage.cx - width / 2
            y: panel.nameY
            width: 600
            height: panel.descY + 36 - panel.nameY
            transform: Translate {
                x: panel.readShift
                y: (1 - panel.stage_(0.25, 0.8)) * 12
            }

            // The name, with a soft shadow in the background colour so it
            // reads on any wallpaper
            Item {
                id: nameBox

                anchors.horizontalCenter: parent.horizontalCenter
                width: Math.min(nameText.implicitWidth, parent.width)
                height: nameText.implicitHeight
                opacity: !panel.shown && panel.busy ? 0.55 + 0.45 * panel.breath : 1

                Txt {
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
                    text: panel.shown ? panel.shown.attr : panel.emptyTitle
                    color: panel.shown ? Colors.foreground : (panel.busy ? Colors.accent : Colors.muted)
                    font.pixelSize: 22
                    font.bold: true
                    font.letterSpacing: -0.2

                    Behavior on color {
                        ColorAnimation {
                            duration: Style.baseMs
                        }
                    }
                }
            }

            // Version, licence, flags and the homepage link. Only the version
            // while the pointer is just reading a disc: the rest needs the
            // package to be picked.
            Row {
                y: panel.chipsY - panel.nameY
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: Style.spaceSm
                visible: panel.shown !== null

                Chip {
                    visible: !!panel.shown && panel.shown.version !== ""
                    popIn: true
                    text: panel.shown ? panel.shown.version : ""
                    tint: Colors.accent
                }
                Chip {
                    visible: !panel.peeking && (Pkgs.info.license || "") !== ""
                    popIn: true
                    text: Pkgs.info.license || ""
                }
                Chip {
                    visible: !panel.peeking && Pkgs.info.unfree === true
                    popIn: true
                    text: "unfree"
                    tint: Colors.critical
                }
                Chip {
                    visible: !panel.peeking && Pkgs.info.broken === true
                    popIn: true
                    text: "broken"
                    tint: Colors.critical
                }
                Chip {
                    visible: !panel.peeking && Pkgs.listed
                    popIn: true
                    text: "in home.nix"
                    tint: Colors.success
                }
                Chip {
                    visible: !panel.peeking && (Pkgs.info.homepage || "") !== ""
                    popIn: true
                    glyph: Icons.openExternal
                    text: "Homepage"
                    tint: Colors.accent
                    clickable: true
                    onClicked: Pkgs.openHomepage()
                }
            }

            // A thin bar with a glint while the index is built
            Rectangle {
                y: panel.chipsY - panel.nameY + 9
                anchors.horizontalCenter: parent.horizontalCenter
                visible: Pkgs.building && !panel.shown
                width: 180
                height: 3
                radius: 2
                color: Style.hoverFill

                Sweep {
                    anchors.fill: parent
                    running: Pkgs.building && panel.isOpen
                    glintW: 70
                }
            }

            Txt {
                y: panel.descY - panel.nameY
                anchors.horizontalCenter: parent.horizontalCenter
                width: Math.min(parent.width, 560)
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                maximumLineCount: 2
                elide: Text.ElideRight
                lineHeight: 1.15
                text: panel.descText
                color: Colors.muted
                font.pixelSize: Style.fontMd
            }
        }

        // ---- Actions on the picked package ---------------------------------
        Row {
            id: actions

            x: stage.cx - width / 2
            y: panel.actionsY
            spacing: Style.spaceMd
            opacity: Pkgs.current !== null ? (panel.peeking ? 0.35 : 1) : 0
            visible: opacity > 0.01
            enabled: Pkgs.current !== null && !panel.peeking
            transform: Translate {
                y: (1 - panel.stage_(0.35, 0.9)) * 10
            }

            Behavior on opacity {
                NumberAnimation {
                    duration: Style.baseMs
                }
            }

            TextButton {
                id: shellBtn

                text: "Shell"
                hint: "↵"
                primary: true
                raised: true
                onClicked: panel.launchShell()
            }
            TextButton {
                visible: !!Pkgs.info.mainProgram
                text: "Run " + (Pkgs.info.mainProgram || "")
                raised: true
                onClicked: panel.launchRun()
            }
            TextButton {
                id: copyBtn

                text: "Copy name"
                hint: "⇧↵"
                raised: true
                onClicked: panel.copyName()
            }
            TextButton {
                visible: !Pkgs.listed
                text: Pkgs.addArmed ? "Press again to add" : "Add to home.nix"
                raised: !Pkgs.addArmed
                danger: Pkgs.addArmed
                armed: Pkgs.addArmed
                flashColor: Colors.success
                onClicked: {
                    const second = Pkgs.addArmed;
                    Pkgs.addToHome();
                    if (second)
                        confirm();
                }
            }
        }

        // ---- Search pill -------------------------------------------------
        // The shell's SearchField on a glass backing, so it reads on any
        // wallpaper. Always there: typing is what this panel is for.
        Item {
            id: pill

            x: stage.cx - width / 2
            y: panel.pillY
            width: 360
            height: Style.fieldHeight
            transform: Translate {
                y: (1 - panel.stage_(0.4, 0.95)) * 10
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
                placeholder: "Search nixpkgs"
                busy: panel.busy
                // Where the pick sits among the matches
                badge: panel.count > 0 && input.text !== "" && panel.selIndex >= 0 ? (panel.selIndex + 1) + " / " + (panel.count >= 80 ? "80+" : panel.count) : ""

                onTextChanged: Pkgs.setQuery(text)
                Keys.onPressed: event => {
                    const k = event.key;
                    const ctrl = (event.modifiers & Qt.ControlModifier) !== 0;
                    const shift = (event.modifiers & Qt.ShiftModifier) !== 0;
                    if (k === Qt.Key_Escape) {
                        if (text !== "")
                            text = "";
                        else
                            panel.close();
                    } else if (k === Qt.Key_Right || k === Qt.Key_Down || k === Qt.Key_Tab || (ctrl && k === Qt.Key_N)) {
                        panel.move(1);
                    } else if (k === Qt.Key_Left || k === Qt.Key_Up || k === Qt.Key_Backtab || (ctrl && k === Qt.Key_P)) {
                        panel.move(-1);
                    } else if (k === Qt.Key_PageDown) {
                        panel.move(8);
                    } else if (k === Qt.Key_PageUp) {
                        panel.move(-8);
                    } else if (k === Qt.Key_Return || k === Qt.Key_Enter) {
                        if (shift)
                            panel.copyName();
                        else if (ctrl)
                            panel.launchRun();
                        else
                            panel.launchShell();
                    } else {
                        return;
                    }
                    event.accepted = true;
                }

                // A glint runs along the bottom of the field while it searches
                Sweep {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.leftMargin: 16
                    anchors.rightMargin: 16
                    height: 2
                    running: Pkgs.searching && panel.isOpen
                }
            }
        }

        // ---- Foot: stats, or the latest message, and the index ------------
        Item {
            x: stage.cx - width / 2
            y: panel.footY
            width: 560
            height: 16
            opacity: panel.stage_(0.5, 1)

            Row {
                anchors.centerIn: parent
                spacing: Style.spaceMd

                Txt {
                    id: statLine

                    text: Pkgs.message !== "" ? Pkgs.message : (Pkgs.ready ? Pkgs.indexCount.toLocaleString(Qt.locale(), "f", 0) + " packages  ·  nixpkgs " + Pkgs.refShort + "  ·  indexed " + Pkgs.age(Pkgs.indexTime) : "")
                    color: Pkgs.message !== "" ? Colors.accent : Colors.muted
                    font.pixelSize: Style.fontSm
                    onTextChanged: statFade.restart()

                    Behavior on color {
                        ColorAnimation {
                            duration: Style.baseMs
                        }
                    }
                }

                Txt {
                    id: updateLink

                    text: Pkgs.building ? "Indexing…" : "Update index"
                    color: Pkgs.building ? Colors.accent : (updateHover.hovered ? Colors.accent : Colors.muted)
                    opacity: Pkgs.building ? 0.55 + 0.45 * panel.breath : 0.8
                    font.pixelSize: Style.fontSm

                    Behavior on color {
                        ColorAnimation {
                            duration: Style.baseMs
                        }
                    }

                    HoverHandler {
                        id: updateHover

                        cursorShape: Pkgs.building ? Qt.ArrowCursor : Qt.PointingHandCursor
                    }
                    TapHandler {
                        enabled: !Pkgs.building
                        onTapped: Pkgs.buildIndex()
                    }
                }
            }
        }
    }
}
