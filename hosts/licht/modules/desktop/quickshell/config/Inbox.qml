// Inbox.qml
// Obsidian quick capture on the launcher's dial: the same borderless stage
// rising from the bottom edge, the same fine ruler, glass discs and accent
// underline. Type a thought and it lands in your vault.
//
// The three places a capture can go are three discs on the dial: Note (a new
// note in the Inbox folder, title = first line), Daily ("- 14:32 text" added
// to today's daily note) and Task ("- [ ] text" added to your task file, or to
// today's daily note). The one on top sits big with the accent underline, and
// its name is read out below the ruler with where the capture will be written
// as it will be written (the folder quiet, the file name clear), so you see
// what a title becomes before you save; #tags you type pop in beside it.
// Under that is the text box, which grows with what you write and scrolls past
// a limit, then your most recent notes, and Save.
//
//   qs ipc call capture toggle | open | close
//   qs ipc call capture show daily          open straight into a mode (note | daily | task)
//   qs ipc call capture add "<text>"        save a note without opening the panel
//   qs ipc call capture daily "<text>"      append to today's daily note
//   qs ipc call capture task "<text>"       append a - [ ] task
//
// Keys:  enter save   shift+enter new line   tab / shift+tab turn the dial (ctrl+1-3 jump)
//        ctrl+enter save and open in Obsidian   esc close
//        ctrl+n / ctrl+p pick a recent note, ctrl+o open it (or click it)
// Mouse: click a disc to pick that mode, click a recent note to open it
//
// Like the launcher it arrives as a rainbow: the discs swing in from the left
// over a tight dome and unfurl into the calm dial. Closing plays it in
// reverse. The stage grows and shrinks with the text box and the recent notes,
// the dial gliding with it.
//
// Like the other dials this window is only as big as the stage (and a fixed
// size, since resizing a layer surface on every frame of an animation is
// rough), so the mouse still reaches other windows while it is open. The
// keyboard is the capture's until it closes (Esc); what you typed is kept.

import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland

PanelWindow {
    id: capture

    // Opens on the monitor that has focus (set in open())
    property var targetScreen: Focus.screen

    // ---- Settings -------------------------------------------------------
    // Your vault (set in Config.qml)
    readonly property string vaultDir: Config.vaultDir
    // Folders and files below are relative to the vault.
    readonly property string inboxFolder: "Inbox"
    readonly property string dailyFolder: "Daily"      // "" if daily notes live in the vault root
    readonly property string dailyFormat: "yyyy-MM-dd" // must match Obsidian's daily note format
    // Tasks go here, e.g. "Tasks.md". Leave empty to put them in today's daily note.
    readonly property string taskFile: ""
    // Give new notes a `created:` (and `tags:`) property header.
    readonly property bool addFrontmatter: true
    // Keep what you typed if you dismiss the panel, selected so typing replaces it.
    readonly property bool keepDraft: true
    readonly property bool notifyOnSave: true
    readonly property int recentCount: 4

    readonly property var modes: [
        {
            "id": "note",
            "label": "Note",
            "glyph": Icons.file,
            "hint": "Capture a thought…"
        },
        {
            "id": "daily",
            "label": "Daily",
            "glyph": Icons.calendar,
            "hint": "Add to today's daily note…"
        },
        {
            "id": "task",
            "label": "Task",
            "glyph": Icons.checkbox,
            "hint": "Add a task…"
        }
    ]
    // Runs as: sh -c <script> sh <text> <file> <append|create> <stamp>
    // The text and paths are arguments, never pasted into the script, so
    // quotes or $ in a note can't break it. Prints the file it wrote.
    readonly property var writeLines: ['mkdir -p "$(dirname "$2")" || exit 1', 'f="$2"', 'if [ "$3" = append ]; then', '  if [ -s "$f" ] && [ -n "$(tail -c1 "$f")" ]; then printf "\\n" >> "$f"; fi', '  printf "%s\\n" "$1" >> "$f"', 'else', '  if [ -e "$f" ]; then f="${2%.md} $4.md"; fi', '  set -C', '  printf "%s\\n" "$1" > "$f" || exit 1', 'fi', 'printf "%s" "$f"']


    // ---- Settings (layout) ----------------------------------------------
    readonly property real screenW: targetScreen ? targetScreen.width : 1920
    readonly property int stageW: Math.min(720, Math.round(screenW * 0.9))
    // The window is this tall always; the stage inside it grows and shrinks
    // with the text box and the recent notes (bodyH), so the dial glides up and
    // down instead of the layer surface being resized.
    readonly property int winH: 520
    readonly property int topY: 56
    readonly property int ruleDrop: 46
    readonly property int ruleY: topY + ruleDrop
    readonly property real dialR: 900
    // The dome the dial starts as when it opens (and ends as when it closes)
    readonly property real rainbowR: 360
    readonly property real stepPx: 92
    readonly property int discSize: 50
    readonly property int selectedSize: 72
    readonly property int tickGap: 12
    readonly property int tickN: Math.ceil(stageW / tickGap) + 24
    readonly property int boxMin: 52
    readonly property int boxMax: 170
    readonly property int chipH: Style.buttonCompact
    readonly property int foot: 16

    // ---- State ----------------------------------------------------------
    property bool isOpen: false
    // 0 = hidden below the edge, 1 = in place
    property real reveal: 0
    // Slots the dial is swung to the left while arriving (and right when leaving)
    property real spinIn: 0
    // 1 = tight rainbow dome, 0 = the resting dial
    property real fan: 1
    // A slow pulse (0..1) for the selected disc's ring
    property real breath: 0
    // 0 -> 1 each time the mode changes: the readout fades up
    property real swap: 1
    // 0..1 each time the panel opens: the recent notes rise in one after another
    property real intro: 1
    property int mode: 0
    property bool openAfter: false
    property int lastMode: 0
    property string pendingText: ""
    // Notes in the Inbox folder, newest first: { name, t } (t = modified, epoch seconds)
    property var inboxNotes: []
    // The recent note picked with the keyboard (-1 = none)
    property int recentIndex: -1
    // Kept fresh while open, so "5 min" stays true
    property real nowSec: Date.now() / 1000

    // ---- Derived --------------------------------------------------------
    readonly property var current: modes[mode]
    readonly property string vaultName: vaultDir.split("/").pop()
    readonly property string destLabel: {
        const t = input.text.trim();
        if (mode === 0 && t === "")
            return inboxFolder + "/";
        return destinationOf(mode, t);
    }
    // The folder and the file name, so they can be drawn differently
    readonly property string destDir: destLabel.indexOf("/") >= 0 ? destLabel.slice(0, destLabel.lastIndexOf("/") + 1) : ""
    readonly property string destName: destLabel.slice(destDir.length)
    readonly property var tags: tagsIn(input.text)
    readonly property var recents: inboxNotes.slice(0, recentCount)
    readonly property bool canSave: input.text.trim() !== "" && !writer.running
    // Radius of the dial right now: curvature eases from the dome to the dial
    readonly property real dialNow: 1 / (1 / dialR + (1 / rainbowR - 1 / dialR) * fan)
    // Where the dial is turned to; glides to the chosen mode
    property real viewPos: mode

    // ---- Layout of what is under the dial ---------------------------------
    readonly property int readoutTop: ruleY + 30
    readonly property int boxH: Math.min(boxMax, Math.max(boxMin, input.contentHeight + 32))
    // The height of the stage for what is on show right now
    property real bodyH: readoutTop + readout.height + 14 + boxH + (recents.length > 0 ? 12 + chipH : 0) + 14 + Style.buttonHeight + foot

    Behavior on viewPos {
        // The dial glides into place and settles, with no bounce
        NumberAnimation {
            duration: Style.enterMs
            easing.type: Style.easeEnter
        }
    }

    Behavior on bodyH {
        // Not while the stage is still rising in
        enabled: capture.reveal >= 1

        NumberAnimation {
            duration: Style.baseMs
            easing.type: Style.easeMove
        }
    }

    onModeChanged: if (isOpen)
        swapAnim.restart()

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

    // ---- Text helpers ---------------------------------------------------
    // Note title: first non-empty line, minus #tags and anything Obsidian
    // refuses in a file name.
    function slugFor(text) {
        const lines = text.split("\n");
        let first = "";
        for (let i = 0; i < lines.length; i++) {
            const line = lines[i].replace(/(^|\s)#[A-Za-z0-9_\/-]+/g, " ").replace(/[\\\/:*?"<>|#^\[\]]/g, "").replace(/\s+/g, " ").replace(/^[.\s]+|[.\s]+$/g, "");
            if (line !== "") {
                first = line;
                break;
            }
        }
        return first.slice(0, 60).replace(/[.\s]+$/g, "") || "Capture";
    }

    function tagsIn(text) {
        const found = [];
        const re = /(?:^|\s)#([A-Za-z0-9_\/-]+)/g;
        let m;
        while ((m = re.exec(text)) !== null) {
            // Obsidian doesn't treat all-digit words like #1 as tags
            if (/\D/.test(m[1]) && found.indexOf(m[1]) === -1)
                found.push(m[1]);
        }
        return found;
    }

    function indentRest(text, pad) {
        return text.split("\n").map((l, i) => {
            return i === 0 ? l : pad + l;
        }).join("\n");
    }

    // Vault-relative path a capture in mode `m` will be written to.
    function destinationOf(m, text) {
        const day = Qt.formatDateTime(new Date(), dailyFormat) + ".md";
        const daily = dailyFolder !== "" ? dailyFolder + "/" + day : day;
        if (m === 1)
            return daily;
        if (m === 2)
            return taskFile !== "" ? taskFile : daily;
        return inboxFolder + "/" + slugFor(text) + ".md";
    }

    function bodyFor(m, text) {
        const now = new Date();
        if (m === 1)
            return "- " + Qt.formatDateTime(now, "HH:mm") + " " + indentRest(text.replace(/^[-*]\s+/, ""), "  ");
        if (m === 2)
            return "- [ ] " + indentRest(text.replace(/^(?:[-*]\s+)?(?:\[[ xX]?\]\s*)?/, ""), "  ");
        if (!addFrontmatter)
            return text;
        const tags = tagsIn(text);
        let head = "---\ncreated: " + Qt.formatDateTime(now, "yyyy-MM-dd'T'HH:mm") + "\n";
        if (tags.length > 0)
            head += "tags: [" + tags.join(", ") + "]\n";
        return head + "---\n\n" + text;
    }

    // ---- Actions --------------------------------------------------------
    function save(m, text, andOpen) {
        const clean = text.trim();
        if (clean === "" || writer.running)
            return false;
        lastMode = m;
        openAfter = andOpen === true;
        pendingText = clean;
        writer.command = ["sh", "-c", writeLines.join("\n"), "sh", bodyFor(m, clean), vaultDir + "/" + destinationOf(m, clean), m === 0 ? "create" : "append", Qt.formatDateTime(new Date(), "yyyy-MM-dd HHmmss")];
        writer.running = true;
        return true;
    }

    function submit(andOpen) {
        if (save(mode, input.text, andOpen)) {
            input.text = "";
            close();
        }
    }

    function saved(path) {
        const prefix = vaultDir + "/";
        const rel = path.indexOf(prefix) === 0 ? path.slice(prefix.length) : path;
        const name = rel.split("/").pop().replace(/\.md$/, "");
        const titles = ["Saved to Inbox", "Added to daily note", "Task added"];
        if (notifyOnSave)
            Quickshell.execDetached(["notify-send", "-a", "Inbox", "-i", "document-save", titles[lastMode], name]);
        if (openAfter)
            openNote(rel);
        scanInbox();
    }

    function failed() {
        Quickshell.execDetached(["notify-send", "-a", "Inbox", "-u", "critical", "-i", "dialog-error", "Capture failed", "Couldn't write to " + vaultDir]);
        // Put the text back so nothing is lost
        if (input.text === "")
            input.text = pendingText;
    }

    // Opens a vault-relative path in Obsidian through its URI scheme.
    function openNote(rel) {
        const uri = "obsidian://open?vault=" + encodeURIComponent(vaultName) + "&file=" + encodeURIComponent(rel.replace(/\.md$/, ""));
        Quickshell.execDetached(["obsidian", uri]);
    }

    function clamp(v, a, b) {
        return Math.max(a, Math.min(b, v));
    }

    function scanInbox() {
        lister.running = true;
    }

    function cycleMode(step) {
        mode = (mode + step + modes.length) % modes.length;
    }

    // ctrl+n / ctrl+p walk through the recent notes; -1 is "none picked"
    function moveRecent(step) {
        const n = recents.length;
        if (n === 0)
            return;
        recentIndex = clamp(recentIndex + step, -1, n - 1);
    }

    function openRecent(i) {
        if (i < 0 || i >= recents.length)
            return;
        openNote(inboxFolder + "/" + recents[i].name);
        close();
    }

    // "now", "5 min", "3 h", "2 d", then a date
    function agoText(t) {
        const s = Math.max(0, nowSec - t);
        if (s < 60)
            return "now";
        if (s < 3600)
            return Math.floor(s / 60) + " min";
        if (s < 86400)
            return Math.floor(s / 3600) + " h";
        if (s < 86400 * 14)
            return Math.floor(s / 86400) + " d";
        return Qt.formatDateTime(new Date(t * 1000), "d MMM");
    }


    // ---- Open and close -------------------------------------------------
    function open(name) {
        mode = Math.max(0, modes.findIndex(m => {
            return m.id === name;
        }));
        targetScreen = Focus.screen;
        nowSec = Date.now() / 1000;
        recentIndex = -1;
        if (!isOpen) {
            isOpen = true;
            closeAnim.stop();
            // Fully hidden: start from the dome. Re-opened while it was still
            // leaving: carry on from where it is instead of snapping away first.
            if (reveal <= 0.001) {
                reveal = 0;
                spinIn = 3.2;
                fan = 1;
            }
            intro = 0;
            openAnim.restart();
            introAnim.restart();
        }
        scanInbox();
        input.forceActiveFocus();
        if (input.text !== "")
            input.selectAll();
    }

    function close() {
        if (!isOpen)
            return;
        isOpen = false;
        openAnim.stop();
        closeAnim.restart();
        if (!keepDraft)
            input.text = "";
    }

    // When the last click outside the panel closed it. The same click can
    // land on the bar item that toggles it, which must not open it again.
    property double closedAt: 0

    function toggle() {
        if (!isOpen && Date.now() - closedAt < 250)
            return;
        if (isOpen)
            close();
        else
            open();
    }

    // Click outside the panel to close it. The window only covers the panel
    // (clicks beside it reach what is underneath), so the compositor's focus
    // grab tells us about a click anywhere else.
    HyprlandFocusGrab {
        windows: [capture]
        active: capture.isOpen && capture.visible
        onCleared: {
            capture.closedAt = Date.now();
            capture.close();
        }
    }

    // ---- Window ---------------------------------------------------------
    // Full screen, like the launcher: the shared dim goes over the whole screen and
    // the stage rises from the bottom edge, centred. A click on the dim closes.
    visible: isOpen || reveal > 0.001
    color: "transparent"
    screen: targetScreen
    exclusiveZone: 0
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "qs-capture"
    // Exclusive, like the launcher: you can type the moment it opens
    WlrLayershell.keyboardFocus: isOpen ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    IpcHandler {
        function toggle(): void {
            capture.toggle();
        }

        function open(): void {
            capture.open();
        }

        function show(which: string): void {
            capture.open(which);
        }

        function close(): void {
            capture.close();
        }

        function add(text: string): void {
            capture.save(0, text, false);
        }

        function daily(text: string): void {
            capture.save(1, text, false);
        }

        function task(text: string): void {
            capture.save(2, text, false);
        }

        target: "capture"
    }

    Process {
        id: writer

        stdout: StdioCollector {
            onStreamFinished: {
                if (text.trim() !== "")
                    capture.saved(text.trim());
            }
        }

        stderr: StdioCollector {
            onStreamFinished: {
                if (text.trim() !== "")
                    console.log("Inbox: " + text.trim());
            }
        }

        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0)
                capture.failed();
        }
    }

    // Notes in the Inbox folder with when they were last changed, newest first
    Process {
        id: lister

        command: ["sh", "-c", 'd="$1"; [ -d "$d" ] && find "$d" -maxdepth 1 -type f -name "*.md" -printf "%T@ %f\\n" | sort -rn', "sh", capture.vaultDir + "/" + capture.inboxFolder]
        stdout: StdioCollector {
            onStreamFinished: {
                const out = [];
                const lines = text.split("\n");
                for (let i = 0; i < lines.length; i++) {
                    const sp = lines[i].indexOf(" ");
                    if (sp < 1)
                        continue;
                    out.push({
                        "name": lines[i].slice(sp + 1),
                        "t": parseFloat(lines[i].slice(0, sp))
                    });
                }
                capture.inboxNotes = out;
                if (capture.recentIndex >= capture.recents.length)
                    capture.recentIndex = -1;
            }
        }
    }

    Timer {
        interval: 30000
        repeat: true
        running: capture.isOpen
        onTriggered: capture.nowSec = Date.now() / 1000
    }

    PanelLink {
        win: capture
        name: "capture"
    }

    // Rises smoothly. The discs swing in from the left over a tight dome and
    // unfurl into the dial.
    ParallelAnimation {
        id: openAnim

        NumberAnimation {
            target: capture
            property: "reveal"
            to: 1
            duration: Style.sweepMs
            easing.type: Style.easeEnter
        }
        NumberAnimation {
            target: capture
            property: "spinIn"
            to: 0
            duration: Style.sweepMs + Style.moveMs
            easing.type: Style.easeEnter
        }
        NumberAnimation {
            target: capture
            property: "fan"
            to: 0
            duration: Style.sweepMs + Style.ambientMs / 2
            easing.type: Style.easeMove
        }
    }

    // Leaving: the dial curls back into the dome and sweeps off right.
    ParallelAnimation {
        id: closeAnim

        NumberAnimation {
            target: capture
            property: "reveal"
            to: 0
            duration: Style.moveMs + Style.fadeMs
            easing.type: Style.easeExit
        }
        NumberAnimation {
            target: capture
            property: "spinIn"
            to: -3.2
            duration: Style.moveMs + Style.fadeMs
            easing.type: Style.easeExit
        }
        NumberAnimation {
            target: capture
            property: "fan"
            to: 1
            duration: Style.moveMs + Style.fadeMs
            easing.type: Style.easeExit
        }
    }

    // Slow breath for the ring around the selected disc.
    SequentialAnimation {
        running: capture.isOpen
        loops: Animation.Infinite

        NumberAnimation {
            target: capture
            property: "breath"
            from: 0
            to: 1
            duration: Style.ambientMs * 2
            easing.type: Style.easeAmbient
        }
        NumberAnimation {
            target: capture
            property: "breath"
            from: 1
            to: 0
            duration: Style.ambientMs * 2
            easing.type: Style.easeAmbient
        }
    }

    // A different mode is chosen: the words fade up
    NumberAnimation {
        id: swapAnim

        target: capture
        property: "swap"
        from: 0
        to: 1
        duration: Style.baseMs
        easing.type: Style.easeMove
    }

    // Drives the recent notes rising in
    NumberAnimation {
        id: introAnim

        target: capture
        property: "intro"
        from: 0
        to: 1
        duration: Style.enterMs + Style.baseMs
        easing.type: Style.easeMove
    }

    // The shared dim (Dim.qml): the same wash as the screenshot tool
    Dim {
        reveal: capture.reveal
        closes: true
        onClicked: capture.close()
    }

    // ---- Stage ----------------------------------------------------------
    Item {
        id: stage

        readonly property real cx: width / 2

        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        width: capture.stageW
        height: capture.bodyH
        clip: true
        opacity: Math.min(1, capture.reveal * 3)
        transform: Translate {
            y: (1 - capture.reveal) * (stage.height + 40)
        }

        // Pressing the empty stage gives the keyboard back to the text box
        MouseArea {
            anchors.fill: parent
            onPressed: mouse => {
                input.forceActiveFocus();
                mouse.accepted = false;
            }
        }

        // Feathered backing: a soft dark ellipse keeps the words and the scale
        // readable over any wallpaper without a visible panel edge. It is as
        // tall as the stage is, so it never meets the edge of the window.
        Shape {
            id: scrimShape

            readonly property real r: stage.width * 0.5

            x: stage.cx - r
            y: stage.height - r
            width: r * 2
            height: r * 2
            layer.enabled: true
            layer.samples: 4
            transform: Scale {
                origin.x: scrimShape.r
                origin.y: scrimShape.r
                yScale: stage.height * 0.96 / scrimShape.r
            }

            ShapePath {
                strokeColor: "transparent"
                startX: 0
                startY: scrimShape.r

                fillGradient: RadialGradient {
                    centerX: scrimShape.r
                    centerY: scrimShape.r
                    centerRadius: scrimShape.r
                    focalX: scrimShape.r
                    focalY: scrimShape.r

                    GradientStop {
                        position: 0
                        color: Qt.alpha(Colors.background, 0.88)
                    }
                    GradientStop {
                        position: 0.55
                        color: Qt.alpha(Colors.background, 0.6)
                    }
                    GradientStop {
                        position: 1
                        color: Qt.alpha(Colors.background, 0)
                    }
                }

                PathArc {
                    x: scrimShape.r * 2
                    y: scrimShape.r
                    radiusX: scrimShape.r
                    radiusY: scrimShape.r
                }
                PathArc {
                    x: 0
                    y: scrimShape.r
                    radiusX: scrimShape.r
                    radiusY: scrimShape.r
                }
            }
        }

        // Low accent light on the horizon
        Shape {
            id: horizon

            readonly property real r: stage.width * 0.46

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
                        color: Qt.alpha(Colors.accent, 0.14)
                    }
                    GradientStop {
                        position: 0.5
                        color: Qt.alpha(Colors.accent, 0.05)
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

        // ---- The ruler: it turns with the dial, and the ticks by the middle
        // rise a little, like a magnifier --------------------------------
        Repeater {
            // Not kept around while the panel is hidden
            model: capture.visible ? capture.tickN : 0

            delegate: Rectangle {
                id: tick

                required property int index

                readonly property real s: (index - capture.tickN / 2) * capture.tickGap - (((capture.viewPos * capture.stepPx - capture.spinIn * capture.stepPx * 0.5) % (capture.tickGap * 10)) + capture.tickGap * 10) % (capture.tickGap * 10)
                readonly property real a: s / capture.dialNow
                readonly property real rr: capture.dialNow - capture.ruleDrop
                readonly property bool major: index % 10 === 0
                readonly property real near: Math.max(0, 1 - Math.abs(s) / 90)

                x: stage.cx + rr * Math.sin(a) - 0.75
                y: capture.topY + capture.dialNow - rr * Math.cos(a)
                width: 1.5
                height: (major ? 9 : 5) + 6 * near
                radius: 0.75
                antialiasing: true
                visible: Math.abs(a) < 1.2
                transformOrigin: Item.Top
                rotation: a * 180 / Math.PI
                color: Qt.tint(Qt.alpha(Colors.foreground, major ? 0.46 : 0.28), Qt.alpha(Colors.accent, 0.7 * near))
                opacity: capture.clamp((stage.cx - Math.abs(x - stage.cx)) / 90, 0, 1) * capture.clamp(capture.reveal * 2 - Math.abs(x - stage.cx) / stage.cx * 0.9, 0, 1)
            }
        }

        // The middle of the ruler: the accent's 2px, standing where the
        // selected mode is.
        Rectangle {
            x: stage.cx - 1
            y: capture.ruleY - 3
            width: 2
            height: 16
            radius: 1
            color: Colors.accent
            opacity: capture.clamp(capture.reveal * 2 - 0.5, 0, 1)
        }

        // ---- The discs: Note, Daily, Task -----------------------------------
        Repeater {
            model: capture.modes

            delegate: Item {
                id: slot

                required property int index
                required property var modelData

                readonly property bool current: capture.mode === index
                readonly property real rel: index - capture.viewPos
                // Swung left while arriving, right while leaving
                readonly property real s: (rel - capture.spinIn) * capture.stepPx
                readonly property real a: s / capture.dialNow
                // 0 at rest, 1 when selected. Animated, so the disc swells.
                property real grow: current ? 1 : 0
                // 0..1 while the ring around a newly selected disc expands
                property real ping: 0
                // 0 at rest, 1 under the pointer: a gentle lift
                property real hover: area.containsMouse && !current ? 1 : 0
                readonly property real sz: capture.discSize + (capture.selectedSize - capture.discSize) * grow
                readonly property real px: stage.cx + capture.dialNow * Math.sin(a)
                // The selected one also lifts a little off the dial
                readonly property real py: capture.topY + capture.dialNow * (1 - Math.cos(a)) - 5 * grow
                // Arrive in a left-to-right wave, each with a small overshoot
                readonly property real appear: capture.clamp(capture.reveal * 2.2 - index * 0.12, 0, 1)
                readonly property real edge: capture.clamp((stage.cx - Math.abs(px - stage.cx)) / 90, 0, 1)

                visible: opacity > 0.01
                width: sz
                height: sz
                x: px - sz / 2
                y: py - sz / 2
                z: current ? 20 : 10
                opacity: appear * edge
                scale: 0.55 + 0.45 * capture.backOut(appear)
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

                // Swells with a little overshoot, settles back without one
                Behavior on grow {
                    NumberAnimation {
                        duration: Style.moveMs
                        easing.type: slot.current ? Style.easePop : Style.easeMove
                        easing.overshoot: 1.2
                    }
                }

                // The selection moved to this one: a ring leaves it.
                onCurrentChanged: if (current && capture.isOpen && capture.reveal > 0.8)
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

                // Ring that leaves a newly selected disc.
                Rectangle {
                    anchors.centerIn: parent
                    width: parent.width + 14 + 34 * slot.ping
                    height: width
                    radius: width / 2
                    color: "transparent"
                    antialiasing: true
                    visible: slot.ping > 0.001 && slot.ping < 0.999
                    border.width: 1.5
                    border.color: Qt.alpha(Colors.accent, 0.5 * (1 - slot.ping))
                }

                // Breathing ring around the selected disc.
                Rectangle {
                    anchors.centerIn: parent
                    width: parent.width + 12
                    height: width
                    radius: width / 2
                    color: "transparent"
                    antialiasing: true
                    visible: slot.grow > 0.05
                    border.width: 1
                    border.color: Qt.alpha(Colors.accent, slot.grow * (0.25 + 0.25 * capture.breath))
                }

                // Glass, like the bar: one flat surface with a hairline
                // outline, lit in the accent once selected.
                Rectangle {
                    anchors.fill: parent
                    radius: width / 2
                    antialiasing: true
                    color: Style.card
                    border.width: 1
                    border.color: slot.current ? Qt.alpha(Colors.accent, 0.9) : Qt.alpha(Colors.foreground, slot.hover > 0.5 ? 0.5 : 0.32)

                    Behavior on border.color {
                        ColorAnimation {
                            duration: Style.baseMs
                        }
                    }
                }

                // The soft tint inside the glass
                Rectangle {
                    anchors.fill: parent
                    anchors.margins: 1
                    radius: width / 2
                    antialiasing: true
                    color: Qt.alpha(Colors.accent, slot.current ? Style.tintAlpha : 0)

                    Behavior on color {
                        ColorAnimation {
                            duration: Style.baseMs
                        }
                    }
                }

                // Light catching the top edge, as on the bar
                Rectangle {
                    anchors.top: parent.top
                    anchors.topMargin: 1
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: parent.width * 0.5
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

                Txt {
                    anchors.centerIn: parent
                    text: slot.modelData.glyph
                    color: slot.current ? Colors.accent : Colors.foreground
                    opacity: slot.current ? 1 : 0.8
                    font.pixelSize: slot.sz * 0.4
                    // Stays upright while the disc tilts with the dial
                    rotation: -slot.rotation

                    Behavior on color {
                        ColorAnimation {
                            duration: Style.fadeMs
                        }
                    }
                }

                MouseArea {
                    id: area

                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        capture.mode = slot.index;
                        input.forceActiveFocus();
                    }
                }
            }
        }

        // Accent underline under the selected disc; it breathes with the ring.
        Rectangle {
            readonly property real rel: capture.mode - capture.viewPos
            readonly property real a: (rel - capture.spinIn) * capture.stepPx / capture.dialNow

            width: 20 + 10 * capture.breath
            height: 2
            radius: 1
            color: Colors.accent
            x: stage.cx + capture.dialNow * Math.sin(a) - width / 2
            y: capture.topY + capture.dialNow * (1 - Math.cos(a)) - 5 + capture.selectedSize / 2 + 6
            rotation: a * 180 / Math.PI
            opacity: capture.clamp(capture.reveal * 2 - 0.6, 0, 1)
        }

        // ---- The middle: the mode, and where the capture will land -----------
        Item {
            id: readout

            x: stage.cx - width / 2
            y: capture.readoutTop
            width: Math.min(640, stage.width - 48)
            height: 56
            opacity: (0.25 + 0.75 * capture.swap) * capture.stage_(0.25, 0.8)
            transform: Translate {
                y: (1 - capture.stage_(0.25, 0.8)) * 12 + (1 - capture.swap) * 6
            }

            // The mode, with a soft shadow in the background colour so it reads on any wallpaper
            Item {
                id: nameBox

                anchors.horizontalCenter: parent.horizontalCenter
                width: nameText.implicitWidth
                height: nameText.implicitHeight

                Txt {
                    x: 0
                    y: 1.5
                    text: nameText.text
                    color: Qt.alpha(Colors.background, 0.9)
                    font: nameText.font
                }

                Txt {
                    id: nameText

                    text: capture.current.label
                    color: Colors.foreground
                    font.pixelSize: 22
                    font.bold: true
                    font.letterSpacing: -0.2
                }
            }

            // Where it will land: the folder is quiet and the file name is
            // clear; the name follows what you type. #tags pop in beside it.
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: nameBox.bottom
                anchors.topMargin: 8
                spacing: Style.spaceMd

                Txt {
                    anchors.verticalCenter: parent.verticalCenter
                    text: Icons.folder
                    color: Qt.alpha(Colors.foreground, 0.78)
                    style: Text.Outline
                    styleColor: Qt.alpha(Colors.background, 0.85)
                    font.pixelSize: Style.fontMd
                }

                Txt {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: capture.destDir !== ""
                    text: capture.destDir
                    color: Qt.alpha(Colors.foreground, 0.7)
                    style: Text.Outline
                    styleColor: Qt.alpha(Colors.background, 0.85)
                    font.pixelSize: Style.fontMd
                    // The folder and the name touch: no gap between them
                    rightPadding: -Style.spaceMd
                }

                Txt {
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.min(implicitWidth, 300)
                    elide: Text.ElideMiddle
                    text: capture.destName
                    color: Colors.foreground
                    style: Text.Outline
                    styleColor: Qt.alpha(Colors.background, 0.85)
                    font.pixelSize: Style.fontMd
                }

                Repeater {
                    model: capture.tags.slice(0, 3)

                    delegate: Rectangle {
                        id: chip

                        required property string modelData

                        anchors.verticalCenter: parent.verticalCenter
                        implicitWidth: chipText.implicitWidth + 16
                        implicitHeight: 20
                        radius: height / 2
                        antialiasing: true
                        color: Qt.alpha(Colors.accent, Style.tintAlpha)

                        // A tag pops in as you finish typing it
                        NumberAnimation on scale {
                            from: 0.8
                            to: 1
                            duration: Style.moveMs
                            easing.type: Style.easePop
                        }

                        Txt {
                            id: chipText

                            anchors.centerIn: parent
                            text: "#" + chip.modelData
                            color: Colors.accent
                            font.pixelSize: Style.fontSm
                        }
                    }
                }
            }
        }

        // ---- The text box ---------------------------------------------------
        // Glass, like the search pill. Grows with the text up to a limit, then
        // scrolls. Focus only tints the fill and adds a faint accent edge.
        Item {
            id: boxWrap

            x: stage.cx - width / 2
            y: readout.y + readout.height + 14
            width: Math.min(560, stage.width - 48)
            height: capture.boxH
            opacity: capture.stage_(0.3, 0.85)
            transform: Translate {
                y: (1 - capture.stage_(0.3, 0.85)) * 10
            }

            Behavior on height {
                NumberAnimation {
                    duration: Style.baseMs
                    easing.type: Style.easeMove
                }
            }

            Rectangle {
                anchors.fill: parent
                radius: Style.radiusXl
                antialiasing: true
                color: input.activeFocus ? Qt.tint(Style.surface, Style.hoverFill) : Style.surface
                border.width: 1
                border.color: input.activeFocus ? Qt.alpha(Colors.accent, 0.5) : Style.outline

                Behavior on color {
                    ColorAnimation {
                        duration: Style.baseMs
                    }
                }
                Behavior on border.color {
                    ColorAnimation {
                        duration: Style.baseMs
                    }
                }
            }

            // Light catching the top edge, as on the bar
            Rectangle {
                anchors.top: parent.top
                anchors.topMargin: 1
                anchors.horizontalCenter: parent.horizontalCenter
                width: parent.width - Style.radiusXl * 2
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

            // Clicking the padding focuses the text
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.IBeamCursor
                onClicked: input.forceActiveFocus()
            }

            Flickable {
                id: scroller

                anchors.fill: parent
                anchors.leftMargin: 18
                anchors.rightMargin: 18
                anchors.topMargin: 16
                anchors.bottomMargin: 16
                contentWidth: width
                contentHeight: input.contentHeight
                clip: true
                interactive: contentHeight > height
                boundsBehavior: Flickable.StopAtBounds

                // Keep the cursor in view as you type past the limit
                function ensureVisible(r) {
                    if (contentY >= r.y)
                        contentY = r.y;
                    else if (contentY + height <= r.y + r.height)
                        contentY = r.y + r.height - height;
                }

                TextEdit {
                    id: input

                    width: scroller.width
                    wrapMode: TextEdit.Wrap
                    color: Colors.foreground
                    selectionColor: Colors.accent
                    selectedTextColor: Colors.onAccent
                    selectByMouse: true
                    onCursorRectangleChanged: scroller.ensureVisible(cursorRectangle)
                    Keys.onPressed: event => {
                        const k = event.key;
                        const shift = (event.modifiers & Qt.ShiftModifier) !== 0;
                        const ctrl = (event.modifiers & Qt.ControlModifier) !== 0;
                        if (k === Qt.Key_Return || k === Qt.Key_Enter) {
                            // shift+enter falls through and inserts a new line
                            if (!shift) {
                                capture.submit(ctrl);
                                event.accepted = true;
                            }
                        } else if (k === Qt.Key_Escape) {
                            capture.close();
                            event.accepted = true;
                        } else if (k === Qt.Key_Tab) {
                            capture.cycleMode(1);
                            event.accepted = true;
                        } else if (k === Qt.Key_Backtab) {
                            capture.cycleMode(-1);
                            event.accepted = true;
                        } else if (ctrl && k >= Qt.Key_1 && k <= Qt.Key_3) {
                            capture.mode = k - Qt.Key_1;
                            event.accepted = true;
                        } else if (ctrl && k === Qt.Key_N) {
                            capture.moveRecent(1);
                            event.accepted = true;
                        } else if (ctrl && k === Qt.Key_P) {
                            capture.moveRecent(-1);
                            event.accepted = true;
                        } else if (ctrl && k === Qt.Key_O) {
                            capture.openRecent(capture.recentIndex);
                            event.accepted = true;
                        }
                    }

                    font {
                        family: Style.fontFamily
                        pixelSize: Style.fontLg
                    }

                    Txt {
                        visible: input.text.length === 0
                        text: capture.current.hint
                        color: Colors.muted
                        font.pixelSize: Style.fontLg
                    }
                }
            }
        }

        // ---- Recent notes ---------------------------------------------------
        // Small glass chips, newest first; ctrl+n / ctrl+p walk through them
        // and the picked one is lit in the accent. Click one to open it.
        Row {
            id: recentRow

            x: stage.cx - width / 2
            y: boxWrap.y + boxWrap.height + 12
            spacing: Style.spaceMd
            visible: capture.recents.length > 0
            // If the row is ever wider than the stage it shrinks to fit
            scale: Math.min(1, (stage.width - 32) / Math.max(1, recentRow.implicitWidth))

            Repeater {
                model: capture.recents

                delegate: Rectangle {
                    id: row

                    required property int index
                    required property var modelData

                    readonly property bool sel: capture.recentIndex === index
                    readonly property bool lit: rowHover.hovered || sel
                    // The notes rise in one after another when the panel opens
                    readonly property real inP: capture.clamp(capture.intro * 1.7 - 0.2 - index * 0.1, 0, 1)

                    implicitHeight: capture.chipH
                    implicitWidth: rowContent.implicitWidth + 24
                    radius: height / 2
                    antialiasing: true
                    color: sel ? Qt.alpha(Colors.accent, Style.selectedAlpha) : (rowHover.hovered ? Style.hoverFill : Style.well)
                    border.width: 1
                    border.color: sel ? Qt.alpha(Colors.accent, 0.5) : "transparent"
                    opacity: inP
                    scale: rowTap.pressed ? 0.97 : 1
                    transform: Translate {
                        y: (1 - row.inP) * 10
                    }

                    Behavior on color {
                        ColorAnimation {
                            duration: Style.baseMs
                        }
                    }
                    Behavior on border.color {
                        ColorAnimation {
                            duration: Style.baseMs
                        }
                    }
                    Behavior on scale {
                        NumberAnimation {
                            duration: Style.pressMs
                            easing.type: Style.easePress
                        }
                    }

                    Row {
                        id: rowContent

                        anchors.centerIn: parent
                        spacing: Style.spaceSm

                        Txt {
                            anchors.verticalCenter: parent.verticalCenter
                            text: row.lit ? Icons.openExternal : Icons.file
                            color: row.lit ? Colors.accent : Colors.muted
                            font.pixelSize: Style.fontMd

                            Behavior on color {
                                ColorAnimation {
                                    duration: Style.baseMs
                                }
                            }
                        }

                        Txt {
                            anchors.verticalCenter: parent.verticalCenter
                            width: Math.min(implicitWidth, 96)
                            elide: Text.ElideRight
                            text: row.modelData.name.replace(/\.md$/, "")
                            color: Colors.foreground
                            opacity: row.lit ? 1 : 0.8
                            font.pixelSize: Style.fontMd

                            Behavior on opacity {
                                NumberAnimation {
                                    duration: Style.fadeMs
                                }
                            }
                        }

                        Txt {
                            anchors.verticalCenter: parent.verticalCenter
                            text: capture.agoText(row.modelData.t)
                            color: Colors.muted
                            font.pixelSize: Style.fontSm
                        }
                    }

                    HoverHandler {
                        id: rowHover

                        cursorShape: Qt.PointingHandCursor
                    }

                    TapHandler {
                        id: rowTap

                        onTapped: capture.openRecent(row.index)
                    }
                }
            }
        }

        // ---- Save -----------------------------------------------------------
        Row {
            id: buttons

            x: stage.cx - width / 2
            y: stage.height - capture.foot - Style.buttonHeight
            spacing: Style.spaceMd
            opacity: capture.stage_(0.35, 0.9)

            TextButton {
                enabled: capture.canSave
                text: "Save and open"
                hint: "Ctrl+Enter"
                onClicked: capture.submit(true)
            }

            TextButton {
                enabled: capture.canSave
                primary: true
                text: "Save"
                hint: "Enter"
                onClicked: capture.submit(false)
            }
        }
    }
}
