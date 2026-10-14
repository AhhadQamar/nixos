// WallpaperSwitcher.qml
// Wallpaper picker on the launcher's dial: the same borderless stage rising
// from the bottom edge, the same fine ruler, glass frames and accent light.
// The wallpapers are large thumbnails along the dial: the selected one sits big
// in the middle and lights the stage with its own colours (a soft blurred copy
// of the picture glows behind it), its neighbours tilt away along the arc.
// Under the dial there is only the file name; the search pill appears when you
// type. A check marks the wallpaper that is applied right now.
//   qs ipc call wallpaper toggle | open | close | rescan
// Keys: type to filter   ← → ↑ ↓ (Tab, Ctrl+N / Ctrl+P) turn the dial
//       Home / End first / last   enter apply   ctrl+r random   F5 rescan
//       esc clears the search, then closes
// Mouse: click a wallpaper to bring it to the middle, click it again to apply,
//        scroll wheel turns the dial, the two quiet buttons beside the name
//        pick a random one and rescan the folder
//
// Applying runs `wal -i` (which regenerates your whole colour palette, so the
// bar, borders and everything else follow) and sets the image with awww. The
// applied wallpaper's frame lights up, a ring leaves it and a glint crosses it.
//
// Like the launcher it arrives as a rainbow: the wallpapers swing in from the
// left over a tight dome, washed with the wallpaper's palette colours, in a
// wave with a small overshoot, then unfurl into the calm dial as the colour
// drains. Closing plays it in reverse.

import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets // ClippingRectangle: a Rectangle that clips its children to rounded corners

PanelWindow {
    id: switcher

    // ---- Settings -------------------------------------------------------
    readonly property string wallpaperDir: Config.wallpaperDir
    // Small pre-resized copies of every wallpaper live here, so opening the
    // panel doesn't decode 4K images just to draw thumbnails.
    readonly property string thumbCacheDir: Config.home + "/.cache/quickshell/wall-thumbs"
    // Close the panel after applying a wallpaper?
    readonly property bool closeOnApply: false

    // The stage: the launcher's proportions, taller for the pictures.
    readonly property int stageH: 372
    readonly property int topY: 124
    // Thumbnails are 320x200 on disk, so every size stays at the same 8:5 ratio.
    readonly property int itemW: 172
    readonly property int itemH: 108
    readonly property int selW: 300
    readonly property int selH: 188
    // Distance along the dial from the selected one to its neighbour, and
    // between the others
    readonly property real nearPx: 248
    readonly property real farPx: 190
    readonly property real dialR: Math.max(900, width * 0.92)
    // The dome the dial starts as when it opens (and ends as when it closes).
    readonly property real rainbowR: Math.min(380, Math.max(280, width * 0.2))

    readonly property int ruleDrop: 114
    readonly property int ruleY: topY + ruleDrop
    readonly property int tickGap: 12
    readonly property int tickCount: Math.ceil(width / tickGap / 10) * 10 + 20
    readonly property int slotHalf: Math.min(9, Math.ceil(width * 0.52 / farPx) + 1)

    // Strength of the lower-edge shade (0 = none, 1 = solid). Lighter than the
    // launcher's: here you want to see the wallpaper behind the dial.
    readonly property real scrim: 0.72

    // Opens on the monitor that has focus (set in open()).
    property var targetScreen: Focus.screen

    // ---- State ----------------------------------------------------------
    // Each entry is { path, thumb }
    property var wallpapers: []
    property var filtered: []
    property string currentPath: ""   // the wallpaper that is applied right now
    property string applyingPath: ""  // the one being applied (for ~1s)
    property bool scanned: false
    property bool isOpen: false
    property int ringTarget: 0
    property real ringPos: 0
    property real spinIn: 0
    // 0 = hidden below the edge, 1 = in place
    property real reveal: 0
    property bool animateRing: true
    // The wallpaper under the mouse: its name shows in the middle
    property var peek: null

    // 1 = tight rainbow dome with spectral tint, 0 = the resting dial
    property real fan: 1
    // A slow pulse (0..1) for the selected wallpaper's ring and glow
    property real breath: 0
    // Sideways nudge of the name when the dial turns: it slides in from the
    // side the new wallpaper came from.
    property real readShift: 0
    // Radius of the dial right now: curvature eases from the dome to the dial
    readonly property real dialNow: 1 / (1 / dialR + (1 / rainbowR - 1 / dialR) * fan)

    readonly property real viewPos: ringPos + spinIn
    readonly property int count: filtered.length
    readonly property int selectedIndex: count > 0 ? ((ringTarget % count) + count) % count : 0
    readonly property var selectedEntry: count > 0 ? filtered[selectedIndex] : null
    readonly property var display: peek ? peek : selectedEntry
    readonly property bool displayIsCurrent: display !== null && currentPath === display.path
    readonly property bool displayIsApplying: display !== null && applyingPath === display.path

    Behavior on ringPos {
        enabled: switcher.animateRing

        // The dial glides into place and settles, with no bounce
        NumberAnimation {
            duration: Style.enterMs
            easing.type: Style.easeEnter
        }
    }

    // ---- Helpers --------------------------------------------------------
    function clamp(v, a, b) {
        return Math.max(a, Math.min(b, v));
    }

    // Ease-out with a small overshoot for the arrival of each wallpaper (0..1
    // in, about 1.04 at the peak): the shell's `pop`, kept gentle.
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

    // Distance along the dial for a slot k places from the middle: the first
    // step is wider, because the middle one is much larger than the rest.
    function offsetFor(k) {
        const a = Math.abs(k);
        const d = Math.min(a, 1) * nearPx + Math.max(a - 1, 0) * farPx;
        return k < 0 ? -d : d;
    }

    // "/home/me/Pictures/Wallpapers/forest_dusk.jpg" -> "forest_dusk"
    function nameOf(entry) {
        return entry ? entry.path.split("/").pop().replace(/\.[^.]+$/, "") : "";
    }

    // ---- Actions --------------------------------------------------------
    // Fuzzy on the file name: the typed letters only have to appear in order.
    // Best match first. With nothing typed, the dial opens on the wallpaper
    // that is applied now.
    function refilter() {
        const q = input.text.trim();
        if (q.length === 0) {
            filtered = wallpapers.slice();
        } else {
            const scored = [];
            for (let i = 0; i < wallpapers.length; i++) {
                const s = Fuzzy.score(wallpapers[i].path.split("/").pop(), q);
                if (s >= 0)
                    scored.push({
                        "w": wallpapers[i],
                        "s": s,
                        "i": i
                    });
            }
            scored.sort((a, b) => (b.s - a.s) || (a.i - b.i));
            filtered = scored.map(x => x.w);
        }
        peek = null;
        // The list changes under the dial: jump there, don't spin there
        const at = q.length === 0 ? filtered.findIndex(w => w.path === currentPath) : 0;
        animateRing = false;
        ringTarget = Math.max(0, at);
        ringPos = ringTarget;
        animateRing = true;
    }

    // The folder is scanned once, not on every open. `force` is the refresh button.
    function scan(force) {
        if (scanned && !force)
            return;
        scanner.running = true;
    }

    function setWallpaper(entry) {
        if (!entry)
            return;
        applyingPath = entry.path;
        // The path is passed as an argument ($1), never pasted into the script,
        // so odd characters in a file name can't break the command.
        Quickshell.execDetached(["bash", "-c", "wal -i \"$1\" -n; ln -sf \"$1\" \"$2/.current_wallpaper\"; awww img \"$1\" --transition-type simple --transition-fps 30; hyprctl reload", "_", entry.path, wallpaperDir]);
        currentPath = entry.path; // move the "current" check straight away
        appliedTimer.restart();
        if (closeOnApply)
            close();
    }

    // dir: +1 = next, -1 = previous (the dial wraps round)
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

    // Turn to index i by the shorter way round
    function goTo(i) {
        if (count < 2)
            return;
        let d = i - selectedIndex;
        if (d > count / 2)
            d -= count;
        if (d < -count / 2)
            d += count;
        stepTo(ringTarget + d);
    }

    function applyRandom() {
        if (count === 0)
            return;
        let i = Math.floor(Math.random() * count);
        // Not the one that is already in the middle, when there is a choice
        if (count > 1 && i === selectedIndex)
            i = (i + 1) % count;
        goTo(i);
        setWallpaper(filtered[i]);
    }

    function open() {
        if (isOpen)
            return;
        targetScreen = Focus.screen;
        isOpen = true;
        closeAnim.stop();
        scan(false);
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
    // Fullscreen and invisible, like the launcher: it only exists so a click
    // outside the dial can close the picker.
    visible: isOpen || reveal > 0.001
    screen: targetScreen
    color: "transparent"
    exclusiveZone: 0
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "qs-wallpaper"
    WlrLayershell.keyboardFocus: isOpen ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    IpcHandler {
        function toggle() {
            switcher.toggle();
        }

        function open() {
            switcher.open();
        }

        function close() {
            switcher.close();
        }

        // Re-read the wallpaper folder (after adding new wallpapers)
        function rescan() {
            switcher.scan(true);
        }

        target: "wallpaper"
    }

    PanelLink {
        win: switcher
        name: "wallpaper"
    }

    Timer {
        id: appliedTimer

        interval: 1200
        onTriggered: switcher.applyingPath = ""
    }

    // Rises smoothly. The wallpapers swing in from the left over a tight dome
    // and unfurl into the dial while the spectrum drains out of them.
    ParallelAnimation {
        id: openAnim

        NumberAnimation {
            target: switcher
            property: "reveal"
            from: 0
            to: 1
            duration: Style.sweepMs
            easing.type: Style.easeEnter
        }
        NumberAnimation {
            target: switcher
            property: "spinIn"
            from: 3.2
            to: 0
            duration: Style.sweepMs + Style.moveMs
            easing.type: Style.easeEnter
        }
        NumberAnimation {
            target: switcher
            property: "fan"
            from: 1
            to: 0
            duration: Style.sweepMs + Style.ambientMs / 2
            easing.type: Style.easeMove
        }
    }

    // Leaving: the dial curls back into the dome and the wallpapers sweep off right.
    ParallelAnimation {
        id: closeAnim

        NumberAnimation {
            target: switcher
            property: "reveal"
            to: 0
            duration: Style.moveMs + Style.fadeMs
            easing.type: Style.easeExit
        }
        NumberAnimation {
            target: switcher
            property: "spinIn"
            to: -3.2
            duration: Style.moveMs + Style.fadeMs
            easing.type: Style.easeExit
        }
        NumberAnimation {
            target: switcher
            property: "fan"
            to: 1
            duration: Style.moveMs + Style.fadeMs
            easing.type: Style.easeExit
        }
    }

    // Slow breath for the ring and the glow around the selected wallpaper.
    SequentialAnimation {
        running: switcher.isOpen
        loops: Animation.Infinite

        NumberAnimation {
            target: switcher
            property: "breath"
            from: 0
            to: 1
            duration: Style.ambientMs * 2
            easing.type: Style.easeAmbient
        }
        NumberAnimation {
            target: switcher
            property: "breath"
            from: 1
            to: 0
            duration: Style.ambientMs * 2
            easing.type: Style.easeAmbient
        }
    }

    // ---- Scan + thumbnails ----------------------------------------------
    // Runs once. For each image it makes a small thumbnail (only if one isn't
    // cached yet) and prints "fullpath|thumbpath". The last line it prints is
    // pywal's own record of the current wallpaper, so the "current" check
    // survives restarts. $1 and $2 are the two folders, passed in below.
    Process {
        id: scanner

        command: ["bash", "-c", `
            mkdir -p "$2"
            shopt -s nullglob
            cd "$1" 2>/dev/null || exit 0
            for f in *.jpg *.jpeg *.png *.webp *.JPG *.JPEG *.PNG *.WEBP; do
                full="$1/$f"
                hash=$(printf '%s' "$full" | md5sum | cut -d' ' -f1)
                thumb="$2/$hash.png"
                if [ ! -f "$thumb" ]; then
                    convert "$full" -thumbnail 320x200^ -gravity center -extent 320x200 "$thumb" 2>/dev/null
                fi
                if [ ! -s "$thumb" ]; then thumb="$full"; fi
                echo "$full|$thumb"
            done | sort
            cat "$HOME/.cache/wal/wal" 2>/dev/null || true
        `, "bash", switcher.wallpaperDir, switcher.thumbCacheDir]

        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.split("\n").filter(l => {
                    return l.trim().length > 0;
                });
                const entries = [];
                let current = "";
                for (const line of lines) {
                    if (line.includes("|")) {
                        const parts = line.split("|");
                        entries.push({
                            "path": parts[0],
                            "thumb": parts[1]
                        });
                    } else {
                        // the one line without "|" is pywal's current wallpaper
                        current = line.trim();
                    }
                }
                switcher.wallpapers = entries;
                switcher.currentPath = current;
                switcher.scanned = true;
                switcher.refilter();
            }
        }
    }

    // The name changes with the dial: it fades and settles
    Connections {
        target: switcher

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
            target: switcher
            property: "readShift"
            to: 0
            duration: Style.moveMs
            easing.type: Style.easeMove
        }
    }

    // The shared dim (Dim.qml): the same wash as the screenshot tool
    Dim {
        reveal: switcher.reveal
        strength: 0.25
    }

    // Click outside the dial to close. The wheel turns the dial.
    MouseArea {
        anchors.fill: parent
        onClicked: switcher.close()
        onWheel: wheel => switcher.step(wheel.angleDelta.y < 0 ? 1 : -1)
    }

    // ---- Stage ----------------------------------------------------------
    Item {
        id: stage

        readonly property real cx: width / 2

        anchors.bottom: parent.bottom
        width: parent.width
        height: switcher.stageH
        opacity: Math.min(1, switcher.reveal * 3)
        transform: Translate {
            y: (1 - switcher.reveal) * (switcher.stageH + 40)
        }

        // Screenshot's feathered backing (StageShade.qml): a soft dark ellipse,
        // no visible panel boundary, over the shared dim under it.
        StageShade {
            strength: 0.85
        }

        // Wide, low accent glow that feels like light on the horizon.
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
                        color: Qt.alpha(Colors.accent, 0.2)
                    }
                    GradientStop {
                        position: 0.5
                        color: Qt.alpha(Colors.accent, 0.065)
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

        // Fine dial ruler. It rotates counter to the wallpapers at half speed.
        Repeater {
            model: switcher.tickCount

            delegate: Rectangle {
                id: tick
                required property int index

                readonly property real span: switcher.tickCount * switcher.tickGap
                readonly property real dx: ((index * switcher.tickGap + switcher.viewPos * switcher.farPx * 0.5) % span + span) % span - span / 2
                readonly property real a: dx / switcher.dialNow
                readonly property real rr: switcher.dialNow - switcher.ruleDrop
                readonly property bool major: index % 10 === 0
                readonly property bool mid: index % 5 === 0

                x: stage.cx + rr * Math.sin(a) - 0.5
                y: switcher.topY + switcher.dialNow - rr * Math.cos(a)
                width: 1
                height: major ? 9 : (mid ? 6 : 3)
                radius: 0.5
                antialiasing: true
                visible: Math.abs(a) < 1.2 && y < stage.height - 70
                transformOrigin: Item.Top
                rotation: a * 180 / Math.PI
                color: switcher.spectral(Colors.foreground, x, major ? 0.8 : (mid ? 0.52 : 0.3))
                opacity: switcher.clamp((stage.cx - Math.abs(x - stage.cx)) / 230, 0, 1)
                         * switcher.clamp((stage.height - y) / 82, 0, 1)
                         * switcher.clamp(switcher.reveal * 2 - Math.abs(x - stage.cx) / stage.cx * 0.9, 0, 1)
            }
        }

        // Fine center marker on the ruler, with a soft bead at its foot.
        Rectangle {
            x: stage.cx - 0.75
            y: switcher.ruleY - 1
            width: 1.5
            height: 12
            radius: 0.5
            color: Colors.accent
        }
        Rectangle {
            x: stage.cx - width / 2
            y: switcher.ruleY + 14
            width: 5
            height: 5
            radius: 2.5
            color: Colors.accent
            opacity: 0.55 + 0.4 * switcher.breath
        }

        // Accent underline above the selected wallpaper; it breathes with the ring.
        Rectangle {
            x: stage.cx - width / 2
            y: switcher.topY - switcher.selH / 2 - 18
            width: 20 + 10 * switcher.breath
            height: 2
            radius: 1
            color: Colors.accent
            opacity: switcher.count > 0 ? switcher.stage_(0.3, 0.7) : 0
        }

        // ---- The wallpapers ---------------------------------------------
        Repeater {
            model: switcher.slotHalf * 2 + 1

            delegate: Item {
                id: slot
                required property int index

                readonly property int s: index - switcher.slotHalf
                readonly property int n: switcher.count
                readonly property int m: Math.min(switcher.slotHalf * 2 + 1, n)
                readonly property int lo: -Math.floor((m - 1) / 2)
                readonly property int hi: lo + m - 1
                readonly property int pos: Math.round(switcher.viewPos) + s
                readonly property real k: pos - switcher.viewPos
                readonly property var app: n > 0 ? switcher.filtered[((pos % n) + n) % n] : null
                readonly property real a: switcher.offsetFor(k) / switcher.dialNow
                readonly property real px: stage.cx + switcher.dialNow * Math.sin(a)
                readonly property real py: switcher.topY + switcher.dialNow * (1 - Math.cos(a))
                // 1 in the middle, falling to 0 a whole slot away
                readonly property real c: Math.max(0, 1 - Math.abs(k))
                readonly property bool current: Math.abs(k) < 0.5
                readonly property real w: switcher.itemW + (switcher.selW - switcher.itemW) * c
                readonly property real h: switcher.itemH + (switcher.selH - switcher.itemH) * c
                // Shape: rounded corners that soften a little as it is selected
                readonly property real corner: Style.radiusLg + 6 * c
                readonly property bool applied: app !== null && app.path === switcher.currentPath
                readonly property bool applying: app !== null && app.path === switcher.applyingPath
                // The wallpapers arrive in a left-to-right wave, each with a
                // small overshoot, and leave the same way.
                readonly property real delay: (switcher.clamp(s, -7, 7) + 7) * 0.024
                readonly property real appear: switcher.clamp((switcher.reveal - delay) / 0.42, 0, 1)
                readonly property real pop_: switcher.backOut(appear)
                readonly property real edge: switcher.clamp((stage.cx - Math.abs(px - stage.cx)) / 120, 0, 1)
                readonly property real horizon: switcher.clamp((stage.height - py + h * 0.3) / (h * 0.6), 0, 1)
                // 0 under the pointer: a gentle lift
                property real hover: area.containsMouse && !current ? 1 : 0
                // 0..1 while the ring around a newly selected wallpaper expands
                property real ping: 0

                visible: app !== null && s >= lo && s <= hi && py - h / 2 < stage.height
                x: px - w / 2
                y: py - h / 2
                width: w
                height: h
                z: 10 - Math.abs(k)
                opacity: appear * edge * horizon
                scale: 0.55 + 0.45 * pop_
                transform: Translate {
                    y: (1 - slot.appear) * 30 - 4 * slot.hover
                }

                Behavior on hover {
                    NumberAnimation {
                        duration: Style.baseMs
                        easing.type: Style.easeMove
                    }
                }

                // The selection moved here: a ring leaves it.
                onCurrentChanged: if (current && switcher.isOpen && switcher.reveal > 0.8)
                    pingAnim.restart()

                // It was just applied: ring, edge and glint.
                onApplyingChanged: if (applying) {
                    pingAnim.restart();
                    flashAnim.restart();
                    glintAnim.restart();
                }

                NumberAnimation {
                    id: pingAnim
                    target: slot
                    property: "ping"
                    from: 0
                    to: 1
                    duration: Style.sweepMs
                    easing.type: Style.easeMove
                }

                // The frame tilts along the dial.
                Item {
                    id: tilt

                    anchors.fill: parent
                    rotation: slot.a * 180 / Math.PI * 0.6

                    // The picture lights the stage: a soft blurred copy of it
                    // glows behind the selected wallpaper.
                    Item {
                        anchors.fill: parent
                        visible: slot.c > 0.05

                        Image {
                            id: glowSrc

                            anchors.fill: parent
                            source: slot.app && slot.c > 0.05 ? "file://" + slot.app.thumb : ""
                            sourceSize.width: 160
                            sourceSize.height: 100
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            visible: false
                        }

                        MultiEffect {
                            anchors.centerIn: parent
                            width: parent.width * 1.2
                            height: parent.height * 1.3
                            source: glowSrc
                            blurEnabled: true
                            blur: 1.0
                            blurMax: 64
                            saturation: 0.3
                            opacity: slot.c * (0.5 + 0.14 * switcher.breath)
                        }
                    }

                    // Ring that leaves a newly selected wallpaper.
                    Rectangle {
                        anchors.centerIn: parent
                        width: parent.width + 14 + 44 * slot.ping
                        height: parent.height + 14 + 44 * slot.ping
                        radius: slot.corner + 7 + 22 * slot.ping
                        color: "transparent"
                        antialiasing: true
                        visible: slot.ping > 0.001 && slot.ping < 0.999
                        border.width: 1.5
                        border.color: Qt.alpha(Colors.accent, 0.5 * (1 - slot.ping))
                    }

                    // Breathing accent ring around the selected wallpaper.
                    Rectangle {
                        anchors.centerIn: parent
                        width: parent.width + 14
                        height: parent.height + 14
                        radius: slot.corner + 7
                        color: "transparent"
                        antialiasing: true
                        visible: slot.c > 0.05
                        border.width: 1
                        border.color: Qt.alpha(Colors.accent, slot.c * (0.14 + 0.22 * switcher.breath))
                    }

                    // Everything that can be pressed sits in here, so the press
                    // shrink never changes the area the mouse reacts to
                    Item {
                        anchors.fill: parent
                        scale: (area.pressed ? 0.95 : 1) * (1 + 0.03 * slot.hover)

                        Behavior on scale {
                            NumberAnimation {
                                duration: Style.pressMs
                                easing.type: Style.easePress
                            }
                        }

                        // The picture
                        ClippingRectangle {
                            id: pic

                            anchors.fill: parent
                            radius: slot.corner
                            color: Colors.raised

                            Image {
                                anchors.fill: parent
                                source: slot.app ? "file://" + slot.app.thumb : ""
                                sourceSize.width: 320
                                sourceSize.height: 200
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                smooth: true
                                // Fades in when it has loaded instead of popping
                                opacity: status === Image.Ready ? 1 : 0

                                Behavior on opacity {
                                    NumberAnimation {
                                        duration: Style.baseMs
                                    }
                                }
                            }

                            // Wallpapers away from the middle sit back, like the
                            // bar's inactive workspaces; hovering lifts them
                            Rectangle {
                                anchors.fill: parent
                                color: Colors.background
                                opacity: 0.5 * (1 - slot.c) * (1 - 0.7 * slot.hover)
                            }

                            // A faint top light, so the picture reads as glass
                            Rectangle {
                                anchors.fill: parent
                                gradient: Gradient {
                                    GradientStop {
                                        position: 0.0
                                        color: Qt.alpha(Colors.foreground, 0.1)
                                    }
                                    GradientStop {
                                        position: 0.35
                                        color: Qt.alpha(Colors.foreground, 0)
                                    }
                                }
                            }

                            // A glint crosses the picture when it is applied
                            Rectangle {
                                id: glint

                                width: 56
                                height: parent.height * 1.8
                                anchors.verticalCenter: parent.verticalCenter
                                x: -width - 160
                                rotation: 20
                                // Only exists while it crosses; at rest it is out of sight
                                visible: glintAnim.running
                                gradient: Gradient {
                                    orientation: Gradient.Horizontal

                                    GradientStop {
                                        position: 0
                                        color: Qt.alpha(Colors.foreground, 0)
                                    }
                                    GradientStop {
                                        position: 0.5
                                        color: Qt.alpha(Colors.foreground, 0.34)
                                    }
                                    GradientStop {
                                        position: 1
                                        color: Qt.alpha(Colors.foreground, 0)
                                    }
                                }
                            }

                            NumberAnimation {
                                id: glintAnim

                                target: glint
                                property: "x"
                                from: -glint.width - 160
                                to: pic.width + 160
                                duration: Style.sweepMs
                                easing.type: Style.easeMove
                            }

                            // Check on the wallpaper that is applied right now;
                            // it pops in when a wallpaper becomes the current one
                            Rectangle {
                                anchors.top: parent.top
                                anchors.right: parent.right
                                anchors.margins: Style.spaceMd
                                width: 20
                                height: 20
                                radius: 10
                                antialiasing: true
                                color: Colors.accent
                                scale: slot.applied ? 1 : 0
                                visible: scale > 0.01

                                Behavior on scale {
                                    NumberAnimation {
                                        duration: Style.moveMs
                                        easing.type: Style.easePop
                                        easing.overshoot: 2
                                    }
                                }

                                Txt {
                                    anchors.centerIn: parent
                                    text: Icons.check
                                    color: Colors.onAccent
                                    font.pixelSize: Style.fontXs
                                }
                            }
                        }

                        // Rim: the spectrum while arriving, the accent once selected
                        Rectangle {
                            anchors.fill: parent
                            radius: slot.corner
                            antialiasing: true
                            color: "transparent"
                            border.width: slot.c > 0.45 ? 1.5 : 1
                            border.color: slot.c > 0.45
                                          ? switcher.spectral(Colors.accent, slot.px, 0.45 + 0.43 * slot.c)
                                          : switcher.spectral(Colors.foreground, slot.px, 0.26)
                        }

                        // Inner hairline, where light would catch the rim.
                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: 2
                            radius: slot.corner - 2
                            antialiasing: true
                            color: "transparent"
                            border.width: 1
                            border.color: Qt.alpha(Colors.foreground, 0.05 + 0.07 * slot.c)
                        }

                        // Applying: the edge lights up and fades
                        Rectangle {
                            id: flash

                            anchors.fill: parent
                            radius: slot.corner
                            color: "transparent"
                            border.width: 2
                            border.color: Colors.accent
                            opacity: 0
                            antialiasing: true
                        }

                        NumberAnimation {
                            id: flashAnim

                            target: flash
                            property: "opacity"
                            from: 0.95
                            to: 0
                            duration: Style.sweepMs
                            easing.type: Style.easeMove
                        }
                    }

                    MouseArea {
                        id: area

                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onEntered: switcher.peek = slot.app
                        onExited: if (switcher.peek === slot.app)
                            switcher.peek = null
                        // First click turns it to the middle, clicking the
                        // selected one applies it
                        onClicked: {
                            if (slot.current)
                                switcher.setWallpaper(slot.app);
                            else
                                switcher.stepTo(slot.pos);
                        }
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
        // Just the file name, with a soft shadow so it reads on any wallpaper.
        Item {
            id: readout
            x: stage.cx - width / 2
            y: switcher.ruleY + 26
            width: 520
            height: 30
            transform: Translate {
                x: switcher.readShift
                y: (1 - switcher.stage_(0.25, 0.8)) * 12
            }

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                height: parent.height
                spacing: Style.spaceMd

                // Check on the wallpaper that is applied right now.
                Txt {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: switcher.displayIsCurrent || switcher.displayIsApplying
                    text: Icons.check
                    color: Colors.accent
                    font.pixelSize: Style.fontXl
                }

                Item {
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.min(nameText.implicitWidth, readout.width - 30)
                    height: nameText.implicitHeight
                    // Breathes while the folder is being scanned
                    opacity: switcher.scanned ? 1 : 0.55 + 0.45 * switcher.breath

                    Txt {
                        y: 1.5
                        width: parent.width
                        elide: Text.ElideMiddle
                        text: nameText.text
                        color: Qt.alpha(Colors.background, 0.9)
                        font: nameText.font
                    }

                    Txt {
                        id: nameText
                        width: parent.width
                        elide: Text.ElideMiddle
                        text: switcher.display
                              ? switcher.nameOf(switcher.display)
                              : (!switcher.scanned
                                 ? "Scanning…"
                                 : (switcher.wallpapers.length === 0
                                    ? "No wallpapers in " + switcher.wallpaperDir.replace(Config.home, "~")
                                    : "No matches"))
                        color: switcher.display ? Colors.foreground : Colors.muted
                        font.pixelSize: 22
                        font.bold: true
                        font.letterSpacing: -0.2
                    }
                }
            }
        }

        // Two quiet buttons beside the name: a random wallpaper, and a rescan
        // of the folder. They sit back until the mouse is over them.
        Item {
            x: stage.cx - 276 - width / 2
            y: readout.y + 1
            width: 28
            height: 28
            opacity: (randomHover.hovered ? 1 : 0.4) * switcher.stage_(0.45, 0.95)

            Behavior on opacity {
                NumberAnimation {
                    duration: Style.fadeMs
                }
            }

            IconButton {
                anchors.fill: parent
                size: 28
                glyphSize: 13
                glyph: ""
                onClicked: switcher.applyRandom()
            }

            HoverHandler {
                id: randomHover
            }
        }

        Item {
            x: stage.cx + 276 - width / 2
            y: readout.y + 1
            width: 28
            height: 28
            opacity: (rescanHover.hovered || scanner.running ? 1 : 0.4) * switcher.stage_(0.45, 0.95)

            Behavior on opacity {
                NumberAnimation {
                    duration: Style.fadeMs
                }
            }

            // The arrows turn while it works.
            IconButton {
                id: rescanBtn

                anchors.fill: parent
                size: 28
                glyphSize: 13
                glyph: Icons.refresh
                on: scanner.running
                onClicked: switcher.scan(true)

                NumberAnimation on rotation {
                    running: scanner.running
                    loops: Animation.Infinite
                    from: 0
                    to: 360
                    duration: Style.ambientMs
                    // Settle back upright when the scan ends
                    onRunningChanged: if (!running)
                        rescanBtn.rotation = 0
                }
            }

            HoverHandler {
                id: rescanHover
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
                placeholder: "Search wallpapers"
                // Number of matches while typing
                badge: input.text !== "" ? String(switcher.count) : ""

                onTextChanged: switcher.refilter()
                Keys.onEscapePressed: {
                    if (text !== "")
                        text = "";
                    else
                        switcher.close();
                }
                Keys.onReturnPressed: switcher.setWallpaper(switcher.selectedEntry)
                Keys.onEnterPressed: switcher.setWallpaper(switcher.selectedEntry)
                Keys.onLeftPressed: switcher.step(-1)
                Keys.onUpPressed: switcher.step(-1)
                Keys.onBacktabPressed: switcher.step(-1)
                Keys.onRightPressed: switcher.step(1)
                Keys.onDownPressed: switcher.step(1)
                Keys.onTabPressed: switcher.step(1)
                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Home) {
                        switcher.stepTo(switcher.ringTarget - switcher.selectedIndex);
                        event.accepted = true;
                    } else if (event.key === Qt.Key_End) {
                        // The dial wraps, so the last one is one step back from the first
                        switcher.stepTo(switcher.ringTarget - switcher.selectedIndex - 1);
                        event.accepted = true;
                    } else if (event.key === Qt.Key_F5) {
                        switcher.scan(true);
                        event.accepted = true;
                    } else if (event.modifiers & Qt.ControlModifier) {
                        if (event.key === Qt.Key_N) {
                            switcher.step(1);
                            event.accepted = true;
                        } else if (event.key === Qt.Key_P) {
                            switcher.step(-1);
                            event.accepted = true;
                        } else if (event.key === Qt.Key_R) {
                            switcher.applyRandom();
                            event.accepted = true;
                        }
                    }
                }
            }
        }
    }
}
