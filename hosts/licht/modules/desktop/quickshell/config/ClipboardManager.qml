// ClipboardManager.qml
// Clipboard history on the launcher's dial: the same borderless stage rising
// from the bottom edge, the same fine ruler, glass discs and accent underline.
//
// Every entry is a disc along the dial, newest in the middle and older ones
// running off to the right: a picture for an image, a swatch for a colour, an
// icon for a link, a path or plain text. The one on top sits big with the
// accent underline under it, and what it holds is read out below the ruler:
// what it is and its details, then the text itself (three lines, or nine when
// you ask for more), a picture, or the colour's code. Under the readout:
// copy, delete, more / less, clear all. The search pill and the All / Text /
// Images switch sit at the foot.
//   qs ipc call clipboard toggle | open | close | clear
//
// Type to search (fuzzy). ← → ↑ ↓ (Ctrl+N / Ctrl+P, Ctrl+J / Ctrl+K), the
// wheel and PageUp / PageDown turn the dial, Ctrl+Home / Ctrl+End go to the
// ends. Tab / Shift+Tab switch between everything, text only and images only.
// Enter copies and closes, Delete removes the highlighted entry without
// closing, Ctrl+Space reads a long text in full, Esc clears the search and
// then closes. Clear all empties the whole history; press it twice.
// Mouse: click a disc to bring it to the middle, click the one in the middle
// again to copy it. The wheel turns the dial.
//
// Entries are told apart by what they look like: a link, a colour (#rgb or
// #rrggbb), a path, an image, or plain text. That only changes the icon and
// the line of details; copying always puts back the exact original.
//
// Like the launcher it arrives as a rainbow: the discs swing in from the left
// over a tight dome and unfurl into the calm dial. Closing plays it in
// reverse. A deleted disc shrinks away and its neighbours close the gap.
//
// Like the other dials it dims the screen (Dim.qml) and a click on the dim
// closes it. The keyboard is the clipboard's until it closes (Esc). Only the
// discs near the middle exist, so a history of hundreds costs nothing.

import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import Quickshell.Widgets

PanelWindow {
    id: clipboard

    // Opens on the monitor that has focus (set in open())
    property var targetScreen: Focus.screen

    // ---- Settings -------------------------------------------------------
    readonly property real screenW: targetScreen ? targetScreen.width : 1920
    readonly property int stageW: Math.min(900, Math.round(screenW * 0.9))
    // The stage grows and shrinks with what is shown (bodyH), so the dial
    // glides up and down; it never gets taller than this.
    readonly property int winH: 600
    readonly property int topY: Style.panelTop
    readonly property int ruleDrop: 46
    readonly property int ruleY: topY + ruleDrop
    readonly property real dialR: 900
    // The dome the dial starts as when it opens (and ends as when it closes)
    readonly property real rainbowR: 360
    readonly property real stepPx: 76
    readonly property int discSize: 48
    readonly property int selectedSize: 68
    readonly property int tickGap: 12
    readonly property int tickN: Math.ceil(stageW / tickGap) + 24
    // Discs kept on either side of the selected one
    readonly property int windowN: 11
    // How much of an entry the preview decodes (bytes)
    readonly property int previewBytes: 6000
    // Lines of text under the dial, and when it is read in full
    readonly property int linesShort: 3
    readonly property int linesLong: 9
    readonly property int imageH: 290
    // How long a deleted disc takes to shrink away, in ms
    readonly property int collapseMs: 200

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
    // 0 -> 1 each time the selection changes: the readout fades up
    property real swap: 1
    // Whether the dial glides to a new selection (off while opening and for long jumps)
    property bool animateView: false
    // Nothing is shown as "empty" until the first scan has come back
    property bool loaded: false
    property var allEntries: [] // raw "id\tpreview" lines from cliphist
    property var filtered: []
    property int selectedIndex: 0
    // Entries that were just deleted and are shrinking away: { line, at }
    property var ghosts: []
    // 0 = everything, 1 = text, 2 = images
    property int typeFilter: 0
    property int textCount: 0
    property int imageCount: 0
    // The Clear all button has been pressed once
    property bool clearArmed: false
    // A long text is shown in full
    property bool expanded: false
    // Wheel movement not yet turned into a step (a touchpad sends many small ones)
    property real wheelAcc: 0

    // Pictures for image entries: ids that have one, and where they live
    property var thumbs: ({})
    property var thumbIds: []
    readonly property string thumbDir: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/qs-clip"

    // The highlighted entry, and its decoded text for the preview
    readonly property string currentLine: filtered[selectedIndex] ?? ""
    readonly property string currentId: currentLine !== "" ? idOf(currentLine) : ""
    readonly property bool currentBinary: currentLine !== "" && isBinary(currentLine)
    property string previewText: ""
    // Which entry previewText belongs to, so the preview never shows another's text
    property string previewId: ""
    property string wantId: ""
    // The same for a picture that has to be decoded on demand
    property string wantImg: ""

    readonly property bool previewReady: currentId !== "" && previewId === currentId && previewText !== ""
    // Until the full text has been decoded, the one-line preview stands in
    readonly property string shownText: previewReady ? previewText : (currentLine !== "" ? previewOf(currentLine) : "")
    readonly property string currentKind: currentLine !== "" ? kindOf(shownText, currentBinary) : "text"
    readonly property string currentThumb: currentBinary ? thumbUrl(currentId) : ""
    // Whether the decoded text hit the byte limit
    readonly property bool previewCut: previewReady && byteLength(previewText) >= previewBytes
    readonly property bool hasCur: currentLine !== ""
    readonly property bool searching: searchField.text.trim() !== ""

    // The line of details above the readout
    readonly property var metaItems: {
        if (currentLine === "")
            return [];
        const t = shownText.trim();
        if (currentKind === "image")
            return imageMeta(currentLine);
        if (currentKind === "color") {
            const c = Qt.color(t);
            return ["rgb(" + Math.round(c.r * 255) + ", " + Math.round(c.g * 255) + ", " + Math.round(c.b * 255) + ")"];
        }
        if (currentKind === "link") {
            const h = hostOf(t);
            return h !== "" ? [h] : [];
        }
        if (!previewReady)
            return [];
        const out = [grouped(previewText.length) + (previewCut ? "+" : "") + " characters"];
        const nl = previewText.split("\n").length - (previewText.endsWith("\n") ? 1 : 0);
        if (nl > 1)
            out.push(grouped(nl) + (previewCut ? "+" : "") + " lines");
        return out;
    }

    // Radius of the dial right now: curvature eases from the dome to the dial
    readonly property real dialNow: 1 / (1 / dialR + (1 / rainbowR - 1 / dialR) * fan)

    // Where the dial is turned to; glides to the selected entry
    property real viewPos: selectedIndex

    // The discs that exist: those near the selected one, plus the ones that
    // are shrinking away. `pos` is where each sits along the dial in disc
    // units; a deleted one keeps the spot it had, which the next entry now
    // takes, so its neighbours close the gap while it shrinks.
    readonly property var entries: {
        const n = filtered.length;
        const lo = Math.max(0, selectedIndex - windowN);
        const hi = Math.min(n, selectedIndex + windowN + 1);
        const out = [];
        for (let i = lo; i < hi; i++) {
            out.push({
                "id": filtered[i],
                "line": filtered[i],
                "pos": i,
                "gone": false
            });
        }
        for (const g of ghosts) {
            if (g.at >= lo - 1 && g.at <= hi) {
                out.push({
                    "id": g.line,
                    "line": g.line,
                    "pos": g.at,
                    "gone": true
                });
            }
        }
        return out;
    }

    // ---- Layout of what is under the dial ---------------------------------
    readonly property int readoutTop: ruleY + 30
    readonly property int actionsH: Style.buttonCompact
    readonly property int pillH: Style.fieldHeight
    readonly property int foot: Style.panelFoot
    // The height of the stage for what is on show right now
    property real bodyH: readoutTop + readout.height + (hasCur ? 14 + actionsH : 0) + 14 + pillH + foot

    Behavior on viewPos {
        enabled: clipboard.animateView

        // The dial glides into place and settles, with no bounce
        NumberAnimation {
            duration: Style.enterMs
            easing.type: Style.easeEnter
        }
    }

    Behavior on bodyH {
        NumberAnimation {
            duration: Style.moveMs
            easing.type: Style.easeMove
        }
    }

    onCurrentIdChanged: {
        expanded = false;
        if (isOpen)
            swapAnim.restart();
        previewTimer.restart();
    }

    // ---- Helpers --------------------------------------------------------
    function clamp(v, a, b) {
        return Math.max(a, Math.min(b, v));
    }

    function mod(a, b) {
        return ((a % b) + b) % b;
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

    // cliphist lines are "<id>\t<preview>"; only the preview is shown.
    function previewOf(line) {
        return line.replace(/^\S+\s+/, "");
    }

    function isBinary(line) {
        return /^\S+\s+\[\[ binary data/.test(line);
    }

    // The id at the start of a cliphist line
    function idOf(line) {
        return line.split(/\s+/)[0];
    }

    // What an entry looks like: image, color, link, path or text
    function kindOf(text, binary) {
        if (binary)
            return "image";
        const t = String(text).trim();
        if (t === "" || t.indexOf("\n") >= 0)
            return "text";
        // Three or six digits only: an eight-digit hex means #AARRGGBB to Qt
        // and #RRGGBBAA to CSS, so it is not guessed at
        if (/^#(?:[0-9a-fA-F]{3}|[0-9a-fA-F]{6})$/.test(t))
            return "color";
        if (/^(?:https?|ftp|magnet):\S+$/i.test(t))
            return "link";
        if (t.length > 1 && /^(?:~|\/)\S*$/.test(t))
            return "path";
        return "text";
    }

    function kindGlyph(kind) {
        switch (kind) {
        case "image":
            return Icons.image;
        case "color":
            return Icons.palette;
        case "link":
            return Icons.link;
        case "path":
            return Icons.folder;
        default:
            return Icons.file;
        }
    }

    function kindLabel(kind) {
        switch (kind) {
        case "image":
            return "Image";
        case "color":
            return "Colour";
        case "link":
            return "Link";
        case "path":
            return "Path";
        default:
            return "Text";
        }
    }

    // "[[ binary data 1.2 MiB png 1920x1080 ]]" -> ["png", "1920 × 1080", "1.2 MiB"]
    function imageMeta(line) {
        const m = /\[\[ binary data (\S+ \S+) (\S+) (\S+) \]\]/.exec(line);
        return m ? [m[2], m[3].replace("x", " × "), m[1]] : [];
    }

    function hostOf(url) {
        const m = /^[a-z]+:\/\/([^\/?#]+)/i.exec(url);
        return m ? m[1] : "";
    }

    function grouped(n) {
        return String(n).replace(/\B(?=(\d{3})+(?!\d))/g, ",");
    }

    function byteLength(str) {
        return unescape(encodeURIComponent(str)).length;
    }

    function thumbUrl(id) {
        return thumbs[id] ? "file://" + thumbDir + "/" + id + ".img" : "";
    }

    // ---- Actions --------------------------------------------------------
    function scan() {
        scanner.running = true;
    }

    function recount() {
        let t = 0;
        for (let i = 0; i < allEntries.length; i++) {
            if (!isBinary(allEntries[i]))
                t++;
        }
        textCount = t;
        imageCount = allEntries.length - t;
    }

    // Put the dial on `i` without gliding there (opening, a new search, a long jump)
    function snapTo(i) {
        animateView = false;
        selectedIndex = i;
        animateView = true;
    }

    // Fuzzy: the typed letters only have to appear in order. Best match first.
    function refilter() {
        const q = searchField.text.trim();
        let base = allEntries;
        if (typeFilter !== 0) {
            const wantImages = typeFilter === 2;
            base = allEntries.filter(l => isBinary(l) === wantImages);
        }
        if (q.length === 0) {
            filtered = base;
        } else {
            const scored = [];
            for (let i = 0; i < base.length; i++) {
                const s = Fuzzy.score(previewOf(base[i]), q);
                if (s >= 0)
                    scored.push({
                        "line": base[i],
                        "s": s,
                        "i": i
                    });
            }
            scored.sort((a, b) => (b.s - a.s) || (a.i - b.i));
            filtered = scored.map(x => x.line);
        }
        ghosts = [];
        snapTo(0);
    }

    function setFilter(i) {
        if (i === typeFilter)
            return;
        typeFilter = i;
        refilter();
    }

    function cycleFilter(step) {
        setFilter((typeFilter + step + 3) % 3);
    }

    function jump(i) {
        if (filtered.length === 0)
            return;
        const t = clamp(i, 0, filtered.length - 1);
        // A long way: put the dial there instead of spinning it past hundreds
        if (Math.abs(t - selectedIndex) > 8)
            snapTo(t);
        else
            selectedIndex = t;
    }

    function move(delta) {
        jump(selectedIndex + delta);
    }

    // The entry is passed to bash as an argument ($1), not pasted into the
    // script, so nothing in it can be taken for shell code
    function selectEntry(line) {
        if (!line)
            return;
        Quickshell.execDetached(["bash", "-c", "printf '%s\\n' \"$1\" | cliphist decode | wl-copy", "_", line]);
        close();
    }

    function deleteEntry(line) {
        if (!line)
            return;
        const at = filtered.indexOf(line);
        const id = idOf(line);
        let script = "printf '%s\\n' \"$1\" | cliphist delete";
        const args = [line];
        // Its picture goes too, if it had one (the id is checked, since it
        // becomes part of a path)
        if (/^\d+$/.test(id)) {
            script += "; rm -f -- \"$2/$3.img\"";
            args.push(thumbDir, id);
        }
        Quickshell.execDetached(["bash", "-c", script, "_"].concat(args));
        allEntries = allEntries.filter(l => l !== line);
        filtered = filtered.filter(l => l !== line);
        recount();
        // The disc shrinks where it was while the ones after it close the gap
        if (at >= 0 && isOpen) {
            ghosts = ghosts.concat([
                {
                    "line": line,
                    "at": at
                }
            ]);
            ghostTimer.restart();
        }
        selectedIndex = Math.max(0, Math.min(at < 0 ? selectedIndex : at, filtered.length - 1));
        // The highlight now sits on another entry
        previewText = "";
        previewId = "";
        previewTimer.restart();
    }

    function removeCurrent() {
        deleteEntry(currentLine);
    }

    // Empty the whole history now (also what `qs ipc call clipboard clear` does)
    function wipeNow() {
        Quickshell.execDetached(["bash", "-c", "cliphist wipe; rm -rf -- \"$1\"", "_", thumbDir]);
        allEntries = [];
        filtered = [];
        ghosts = [];
        thumbs = ({});
        previewText = "";
        previewId = "";
        recount();
        snapTo(0);
    }

    // The Clear all button: the first press arms it, the second wipes
    function requestClear() {
        if (!clearArmed) {
            clearArmed = true;
            clearTimer.restart();
            return;
        }
        clearArmed = false;
        clearSeq.restart();
    }

    function loadPreview() {
        if (currentId === "" || !/^\d+$/.test(currentId)) {
            previewText = "";
            previewId = "";
            return;
        }
        if (currentBinary) {
            // A picture: make sure there is a file for it to show
            if (!thumbs[currentId]) {
                wantImg = currentId;
                if (!imgProc.running)
                    startImg();
            }
            return;
        }
        wantId = currentId;
        if (!decodeProc.running)
            startDecode();
    }

    function startDecode() {
        decodeProc.pendingId = wantId;
        decodeProc.command = ["bash", "-c", "cliphist decode \"$1\" | head -c \"$2\"", "_", wantId, String(previewBytes)];
        decodeProc.running = true;
    }

    function startImg() {
        imgProc.pendingId = wantImg;
        imgProc.command = ["bash", "-c", "umask 077; mkdir -p \"$1\" && cliphist decode \"$2\" > \"$1/$2.img\" && [ -s \"$1/$2.img\" ] || { rm -f \"$1/$2.img\"; exit 1; }", "_", thumbDir, wantImg];
        imgProc.running = true;
    }

    function open() {
        if (isOpen)
            return;
        targetScreen = Focus.screen;
        closeAnim.stop();
        searchField.text = "";
        typeFilter = 0;
        clearArmed = false;
        expanded = false;
        wheelAcc = 0;
        // Start empty so the discs play their entrance once the scan returns
        loaded = false;
        allEntries = [];
        filtered = [];
        ghosts = [];
        previewText = "";
        previewId = "";
        recount();
        // The dial starts on the newest entry instead of gliding there
        snapTo(0);
        scan();
        // Fully hidden: start from the dome. Re-opened while it was still
        // leaving: carry on from where it is instead of snapping away first.
        if (reveal <= 0.001) {
            reveal = 0;
            spinIn = 3.2;
            fan = 1;
        }
        isOpen = true;
        openAnim.restart();
        searchField.forceActiveFocus();
    }

    function close() {
        if (!isOpen)
            return;
        isOpen = false;
        openAnim.stop();
        closeAnim.restart();
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
        windows: [clipboard]
        active: clipboard.isOpen && clipboard.visible
        onCleared: {
            clipboard.closedAt = Date.now();
            clipboard.close();
        }
    }

    // ---- Window ---------------------------------------------------------
    // Full screen, like the launcher: the shared dim goes over the whole screen and
    // the stage rises from the bottom edge, centred. A click on the dim closes.
    visible: isOpen || reveal > 0.001
    screen: targetScreen
    color: "transparent"
    exclusiveZone: 0
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "qs-clipboard"
    // Exclusive, like the launcher and the notification centre: the keys work
    // the moment it opens, without clicking it first.
    WlrLayershell.keyboardFocus: isOpen ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    Timer {
        id: ghostTimer

        interval: clipboard.collapseMs + 10
        onTriggered: clipboard.ghosts = []
    }

    Timer {
        id: previewTimer

        interval: 90
        onTriggered: clipboard.loadPreview()
    }

    Timer {
        id: clearTimer

        interval: 3000
        onTriggered: clipboard.clearArmed = false
    }

    IpcHandler {
        function toggle() {
            clipboard.toggle();
        }

        function open() {
            clipboard.open();
        }

        function close() {
            clipboard.close();
        }

        function clear() {
            clipboard.wipeNow();
        }

        target: "clipboard"
    }

    Process {
        id: scanner

        command: ["cliphist", "list"]

        stdout: StdioCollector {
            onStreamFinished: {
                clipboard.allEntries = text.split("\n").filter(l => {
                    return l.trim().length > 0;
                });
                clipboard.loaded = true;
                clipboard.recount();
                clipboard.refilter();
                if (!thumbProc.running) {
                    clipboard.thumbIds = [];
                    thumbProc.running = true;
                }
            }
        }
    }

    // Pictures for the newest image entries, so the discs can show them
    Process {
        id: thumbProc

        command: ["bash", Quickshell.shellPath("clip/thumbs.sh"), clipboard.thumbDir, "24"]

        stdout: SplitParser {
            onRead: data => clipboard.thumbIds.push(data.trim())
        }

        onExited: {
            // Add to what is known, so a picture decoded on demand is kept
            const m = {};
            for (const id in clipboard.thumbs)
                m[id] = true;
            for (const id of clipboard.thumbIds)
                m[id] = true;
            clipboard.thumbs = m;
        }
    }

    // The picture of an older entry, decoded when you get to it. If the
    // highlight moved while it ran, it simply runs again for the new one.
    Process {
        id: imgProc

        property string pendingId: ""

        onExited: code => {
            if (code === 0) {
                const m = {};
                for (const id in clipboard.thumbs)
                    m[id] = true;
                m[imgProc.pendingId] = true;
                clipboard.thumbs = m;
            }
            if (clipboard.wantImg !== imgProc.pendingId && !clipboard.thumbs[clipboard.wantImg])
                clipboard.startImg();
        }
    }

    // Full text of the highlighted entry for the readout. Same idea: if the
    // highlight moved while it ran, it runs again for the new one.
    Process {
        id: decodeProc

        property string pendingId: ""

        stdout: StdioCollector {
            onStreamFinished: {
                if (decodeProc.pendingId === clipboard.wantId) {
                    clipboard.previewText = text;
                    clipboard.previewId = decodeProc.pendingId;
                }
            }
        }

        onExited: {
            if (clipboard.wantId !== decodeProc.pendingId)
                clipboard.startDecode();
        }
    }

    PanelLink {
        win: clipboard
        name: "clipboard"
    }

    // Rises smoothly. The discs swing in from the left over a tight dome and
    // unfurl into the dial.
    ParallelAnimation {
        id: openAnim

        NumberAnimation {
            target: clipboard
            property: "reveal"
            to: 1
            duration: Style.sweepMs
            easing.type: Style.easeEnter
        }
        NumberAnimation {
            target: clipboard
            property: "spinIn"
            to: 0
            duration: Style.sweepMs + Style.moveMs
            easing.type: Style.easeEnter
        }
        NumberAnimation {
            target: clipboard
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
            target: clipboard
            property: "reveal"
            to: 0
            duration: Style.moveMs + Style.fadeMs
            easing.type: Style.easeExit
        }
        NumberAnimation {
            target: clipboard
            property: "spinIn"
            to: -3.2
            duration: Style.moveMs + Style.fadeMs
            easing.type: Style.easeExit
        }
        NumberAnimation {
            target: clipboard
            property: "fan"
            to: 1
            duration: Style.moveMs + Style.fadeMs
            easing.type: Style.easeExit
        }
    }

    // Slow breath for the ring around the selected disc.
    SequentialAnimation {
        running: clipboard.isOpen
        loops: Animation.Infinite

        NumberAnimation {
            target: clipboard
            property: "breath"
            from: 0
            to: 1
            duration: Style.ambientMs * 2
            easing.type: Style.easeAmbient
        }
        NumberAnimation {
            target: clipboard
            property: "breath"
            from: 1
            to: 0
            duration: Style.ambientMs * 2
            easing.type: Style.easeAmbient
        }
    }

    // A different entry is selected: the words fade up
    NumberAnimation {
        id: swapAnim

        target: clipboard
        property: "swap"
        from: 0
        to: 1
        duration: Style.baseMs
        easing.type: Style.easeMove
    }

    // Clear all: the discs fade out, the history is wiped, and the empty
    // state fades in
    SequentialAnimation {
        id: clearSeq

        NumberAnimation {
            target: dialLayer
            property: "opacity"
            to: 0
            duration: Style.fadeMs
            easing.type: Style.easeExit
        }
        ScriptAction {
            script: clipboard.wipeNow()
        }
        NumberAnimation {
            target: dialLayer
            property: "opacity"
            to: 1
            duration: Style.baseMs
            easing.type: Style.easeMove
        }
    }

    // The shared dim (Dim.qml): the same wash as the screenshot tool
    Dim {
        reveal: clipboard.reveal
        closes: true
        onClicked: clipboard.close()
    }

    // ---- Stage ----------------------------------------------------------
    Item {
        id: stage

        readonly property real cx: width / 2

        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        width: clipboard.stageW
        height: Math.min(clipboard.bodyH, clipboard.winH)
        clip: true
        opacity: Math.min(1, clipboard.reveal * 3)
        transform: Translate {
            y: (1 - clipboard.reveal) * (stage.height + 40)
        }

        // Scroll wheel turns the dial. Pressing anywhere on the stage gives
        // the keyboard back to the search field.
        MouseArea {
            anchors.fill: parent
            onPressed: mouse => {
                searchField.forceActiveFocus();
                mouse.accepted = false;
            }
            onWheel: wheel => {
                const d = wheel.angleDelta.y !== 0 ? wheel.angleDelta.y : -wheel.angleDelta.x;
                if (d === 0)
                    return;
                // One step per notch (120). A touchpad sends many small
                // deltas; counting them keeps one swipe from spinning the dial
                // through the whole history.
                if ((d < 0) !== (clipboard.wheelAcc < 0))
                    clipboard.wheelAcc = 0;
                clipboard.wheelAcc += d;
                while (clipboard.wheelAcc <= -120) {
                    clipboard.move(1);
                    clipboard.wheelAcc += 120;
                }
                while (clipboard.wheelAcc >= 120) {
                    clipboard.move(-1);
                    clipboard.wheelAcc -= 120;
                }
            }
        }

        // Feathered backing: a soft dark ellipse keeps the words and the scale
        // readable over any wallpaper without a visible panel edge. It is as
        // tall as the stage is, so it never meets the edge of the window.
        StageShade {
            id: scrimShape
            yScale: Math.min(1.2, stage.height * 0.94 / scrimShape.r)
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
            model: clipboard.visible ? clipboard.tickN : 0

            delegate: Rectangle {
                id: tick

                required property int index

                readonly property real s: (index - clipboard.tickN / 2) * clipboard.tickGap - clipboard.mod(clipboard.viewPos * clipboard.stepPx - clipboard.spinIn * clipboard.stepPx * 0.5, clipboard.tickGap * 10)
                readonly property real a: s / clipboard.dialNow
                readonly property real rr: clipboard.dialNow - clipboard.ruleDrop
                readonly property bool major: index % 10 === 0
                readonly property real near: Math.max(0, 1 - Math.abs(s) / 90)

                x: stage.cx + rr * Math.sin(a) - 0.75
                y: clipboard.topY + clipboard.dialNow - rr * Math.cos(a)
                width: 1.5
                height: (major ? 9 : 5) + 6 * near
                radius: 0.75
                antialiasing: true
                visible: Math.abs(a) < 1.2
                transformOrigin: Item.Top
                rotation: a * 180 / Math.PI
                color: Qt.tint(Qt.alpha(Colors.foreground, major ? 0.46 : 0.28), Qt.alpha(Colors.accent, 0.7 * near))
                opacity: clipboard.clamp((stage.cx - Math.abs(x - stage.cx)) / 90, 0, 1) * clipboard.clamp(clipboard.reveal * 2 - Math.abs(x - stage.cx) / stage.cx * 0.9, 0, 1)
            }
        }

        // The middle of the ruler: the accent's 2px, standing where the
        // selected entry is.
        Rectangle {
            x: stage.cx - 1
            y: clipboard.ruleY - 3
            width: 2
            height: 16
            radius: 1
            color: Colors.accent
            opacity: clipboard.clamp(clipboard.reveal * 2 - 0.5, 0, 1)
        }

        // ---- The discs --------------------------------------------------
        Item {
            id: dialLayer

            anchors.fill: parent

            Repeater {
                // The discs only exist while the panel is on screen, and only
                // the ones near the middle
                model: ScriptModel {
                    values: clipboard.visible ? clipboard.entries : []
                    objectProp: "id"
                }

                delegate: Item {
                    id: slot

                    required property var modelData

                    readonly property string line: modelData ? modelData.line : ""
                    // Animated, so the neighbours of a deleted disc glide closed
                    property real pos: modelData ? modelData.pos : 0
                    readonly property bool binary: clipboard.isBinary(line)
                    readonly property string cid: clipboard.idOf(line)
                    readonly property string snippet: clipboard.previewOf(line)
                    readonly property string kind: clipboard.kindOf(snippet, binary)
                    // Pictures load only for discs near the middle
                    readonly property bool near: Math.abs(rel) < 8
                    readonly property string thumb: binary && near ? clipboard.thumbUrl(cid) : ""
                    readonly property bool photo: thumb !== "" && slotPhoto.status !== Image.Error
                    readonly property bool swatch: kind === "color"
                    readonly property bool current: modelData ? !modelData.gone && modelData.pos === clipboard.selectedIndex : false
                    readonly property real rel: pos - clipboard.viewPos
                    // Swung left while arriving, right while leaving
                    readonly property real s: (rel - clipboard.spinIn) * clipboard.stepPx
                    readonly property real a: s / clipboard.dialNow
                    // 0 at rest, 1 when selected. Animated, so the disc swells.
                    property real grow: current ? 1 : 0
                    // 0 -> 1 while the disc shrinks away after being deleted
                    property real gone: modelData && modelData.gone ? 1 : 0
                    // 0..1 while the ring around a newly selected disc expands
                    property real ping: 0
                    // 0 at rest, 1 under the pointer: a gentle lift
                    property real hover: area.containsMouse && !current ? 1 : 0
                    readonly property real sz: clipboard.discSize + (clipboard.selectedSize - clipboard.discSize) * grow
                    readonly property real px: stage.cx + clipboard.dialNow * Math.sin(a)
                    // The selected one also lifts a little off the dial
                    readonly property real py: clipboard.topY + clipboard.dialNow * (1 - Math.cos(a)) - 5 * grow
                    // Arrive in a left-to-right wave, each with a small overshoot
                    readonly property real appear: clipboard.clamp(clipboard.reveal * 2.2 - (clipboard.clamp(rel, -6, 6) + 6) * 0.09, 0, 1)
                    readonly property real edge: clipboard.clamp((stage.cx - Math.abs(px - stage.cx)) / 90, 0, 1)

                    visible: Math.abs(rel) < 7 && opacity > 0.01
                    width: sz
                    height: sz
                    x: px - sz / 2
                    y: py - sz / 2
                    z: current ? 20 : 10
                    opacity: appear * edge * (1 - gone)
                    scale: (0.55 + 0.45 * clipboard.backOut(appear)) * (1 - 0.7 * gone)
                    // Tilts along the dial, and rises from below as it arrives
                    rotation: a * 180 / Math.PI * 0.6
                    transform: Translate {
                        y: (1 - slot.appear) * 30 - 3 * slot.hover
                    }

                    Behavior on pos {
                        enabled: clipboard.isOpen && clipboard.reveal > 0.8

                        NumberAnimation {
                            duration: Style.moveMs
                            easing.type: Style.easeMove
                        }
                    }

                    Behavior on gone {
                        NumberAnimation {
                            duration: clipboard.collapseMs
                            easing.type: Style.easeExit
                        }
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
                    onCurrentChanged: if (current && clipboard.isOpen && clipboard.reveal > 0.8)
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
                        border.color: Qt.alpha(Colors.accent, slot.grow * (0.25 + 0.25 * clipboard.breath))
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
                        color: slot.swatch ? Qt.color(slot.snippet.trim()) : Qt.alpha(Colors.accent, slot.current ? Style.tintAlpha : 0)

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

                    // A picture, in a circle
                    Photo {
                        id: slotPhoto

                        anchors.fill: parent
                        anchors.margins: 4
                        visible: slot.photo
                        radius: width / 2
                        source: slot.thumb
                        // Stays upright while the disc tilts with the dial
                        rotation: -slot.rotation
                    }

                    // Everything else: what kind of thing it is
                    Txt {
                        anchors.centerIn: parent
                        visible: !slot.photo && !slot.swatch
                        text: clipboard.kindGlyph(slot.kind)
                        color: slot.current ? Colors.accent : Colors.foreground
                        opacity: slot.current ? 1 : 0.8
                        font.pixelSize: slot.sz * 0.4
                        rotation: -slot.rotation

                        Behavior on color {
                            ColorAnimation {
                                duration: Style.fadeMs
                            }
                        }
                    }

                    // Click to bring it to the middle; click the one in the
                    // middle to copy it. Position, not hover, so the dial
                    // never turns under a mouse you are only passing over.
                    MouseArea {
                        id: area

                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (!slot.modelData || slot.modelData.gone)
                                return;
                            if (slot.current)
                                clipboard.selectEntry(slot.line);
                            else
                                clipboard.jump(slot.modelData.pos);
                        }
                    }
                }
            }
        }

        // Nothing here: one quiet disc in the middle, in place of the dial
        Item {
            id: emptyDisc

            readonly property real appear: clipboard.stage_(0.1, 0.6)

            x: stage.cx - width / 2
            y: clipboard.topY - 5 - height / 2
            width: clipboard.selectedSize
            height: clipboard.selectedSize
            opacity: clipboard.loaded && clipboard.filtered.length === 0 ? appear : 0
            visible: opacity > 0.01
            scale: 0.55 + 0.45 * clipboard.backOut(appear)

            Behavior on opacity {
                NumberAnimation {
                    duration: Style.baseMs
                }
            }

            Rectangle {
                anchors.fill: parent
                radius: width / 2
                antialiasing: true
                color: Style.card
                border.width: 1
                border.color: Qt.alpha(Colors.foreground, 0.2)
            }

            Txt {
                anchors.centerIn: parent
                text: clipboard.searching ? Icons.search : Icons.copy
                color: Colors.muted
                font.pixelSize: 24
            }
        }

        // Accent underline under the selected disc; it breathes with the ring.
        Rectangle {
            visible: clipboard.hasCur
            width: 20 + 10 * clipboard.breath
            height: 2
            radius: 1
            color: Colors.accent
            x: stage.cx - width / 2
            y: clipboard.topY - 5 + clipboard.selectedSize / 2 + 6
            opacity: clipboard.clamp(clipboard.reveal * 2 - 0.6, 0, 1)
        }

        // ---- The middle: what the selected entry holds ------------------------
        Item {
            id: readout

            x: stage.cx - width / 2
            y: clipboard.readoutTop
            width: Math.min(clipboard.hasCur && clipboard.currentKind === "image" ? 680 : 520, stage.width - 48)
            height: readCol.implicitHeight
            // Clicks pass through to the dial
            enabled: false
            opacity: (0.25 + 0.75 * clipboard.swap) * clipboard.stage_(0.25, 0.8)
            transform: Translate {
                y: (1 - clipboard.stage_(0.25, 0.8)) * 12 + (1 - clipboard.swap) * 6
            }

            Column {
                id: readCol

                width: parent.width
                spacing: 8

                // What it is, its details, and where it is in the history
                Txt {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    visible: clipboard.hasCur
                    height: visible ? implicitHeight : 0
                    elide: Text.ElideRight
                    text: {
                        if (!clipboard.hasCur)
                            return "";
                        let t = clipboard.kindLabel(clipboard.currentKind);
                        for (const m of clipboard.metaItems)
                            t += "  ·  " + m;
                        if (clipboard.filtered.length > 1)
                            t += "  ·  " + (clipboard.selectedIndex + 1) + "/" + clipboard.filtered.length + (clipboard.searching ? " matches" : "");
                        return t;
                    }
                    // Brighter than the muted grey, with a thin outline in the
                    // background colour: it stays readable over any wallpaper
                    color: Qt.alpha(Colors.foreground, 0.78)
                    style: Text.Outline
                    styleColor: Qt.alpha(Colors.background, 0.85)
                    font.pixelSize: Style.fontSm
                    font.letterSpacing: 1.4
                    font.capitalization: Font.AllUppercase
                }

                // Empty: say so, in the same place the words would be
                Item {
                    width: parent.width
                    height: visible ? emptyText.implicitHeight : 0
                    visible: !clipboard.hasCur

                    Txt {
                        y: 1.5
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        text: emptyText.text
                        color: Qt.alpha(Colors.background, 0.9)
                        font: emptyText.font
                    }

                    Txt {
                        id: emptyText

                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        text: !clipboard.loaded ? "" : (clipboard.allEntries.length === 0 ? "Nothing copied yet" : "No matches")
                        color: Colors.muted
                        font.pixelSize: Style.fontXl
                        font.bold: true
                    }
                }

                // Text, a link or a path: as much of it as fits, or all of it
                // (up to what was decoded) when asked
                Txt {
                    id: bodyText

                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    visible: clipboard.hasCur && (clipboard.currentKind === "text" || clipboard.currentKind === "link" || clipboard.currentKind === "path")
                    height: visible ? implicitHeight : 0
                    wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                    maximumLineCount: clipboard.expanded ? clipboard.linesLong : clipboard.linesShort
                    elide: Text.ElideRight
                    lineHeight: 1.2
                    text: clipboard.shownText
                    // The words are what you came for: near the foreground
                    // colour, outlined for any wallpaper
                    color: Qt.alpha(Colors.foreground, 0.9)
                    style: Text.Outline
                    styleColor: Qt.alpha(Colors.background, 0.8)
                    font.pixelSize: Style.fontBase
                }

                // A colour: its code, large
                Item {
                    width: parent.width
                    height: visible ? colorText.implicitHeight : 0
                    visible: clipboard.hasCur && clipboard.currentKind === "color"

                    Txt {
                        y: 1.5
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        text: colorText.text
                        color: Qt.alpha(Colors.background, 0.9)
                        font: colorText.font
                    }

                    Txt {
                        id: colorText

                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        text: clipboard.currentKind === "color" ? clipboard.shownText.trim() : ""
                        color: Colors.foreground
                        font.pixelSize: 22
                        font.bold: true
                    }
                }

                // A picture, as large as the room allows
                Item {
                    width: parent.width
                    height: visible ? clipboard.imageH : 0
                    visible: clipboard.hasCur && clipboard.currentKind === "image"

                    ClippingRectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: parent.width
                        height: parent.height
                        radius: Style.radiusLg
                        color: Style.well
                        border.width: 1
                        border.color: Style.outline

                        Image {
                            anchors.fill: parent
                            anchors.margins: 4
                            source: clipboard.currentThumb
                            sourceSize.width: 1200
                            sourceSize.height: 1200
                            fillMode: Image.PreserveAspectFit
                            asynchronous: true
                            cache: false
                            opacity: status === Image.Ready ? 1 : 0

                            Behavior on opacity {
                                NumberAnimation {
                                    duration: Style.baseMs
                                }
                            }
                        }

                        Txt {
                            anchors.centerIn: parent
                            visible: clipboard.currentThumb === ""
                            text: "Preparing preview…"
                            color: Colors.muted
                            font.pixelSize: Style.fontMd
                        }
                    }
                }
            }
        }

        // ---- Under the readout: the few things you can do ----------------------
        Row {
            id: actions

            x: stage.cx - width / 2
            y: pillRow.y - 14 - clipboard.actionsH
            spacing: Style.spaceMd
            visible: clipboard.hasCur
            // If the row is ever wider than the stage it shrinks to fit
            scale: Math.min(1, (stage.width - 32) / Math.max(1, actions.implicitWidth))
            opacity: clipboard.stage_(0.35, 0.9)

            TextButton {
                compact: true
                primary: true
                text: "Copy"
                onClicked: clipboard.selectEntry(clipboard.currentLine)
            }

            // A long text: read all of it
            TextButton {
                compact: true
                visible: clipboard.expanded || bodyText.truncated
                text: clipboard.expanded ? "Less" : "More"
                onClicked: {
                    clipboard.expanded = !clipboard.expanded;
                    searchField.forceActiveFocus();
                }
            }

            TextButton {
                compact: true
                text: "Delete"
                onClicked: {
                    clipboard.removeCurrent();
                    searchField.forceActiveFocus();
                }
            }

            // Empty the whole history: press twice
            TextButton {
                compact: true
                minWidth: 92
                danger: clipboard.clearArmed
                armed: clipboard.clearArmed
                text: clipboard.clearArmed ? "Press again" : "Clear all"
                onClicked: clipboard.requestClear()
            }
        }

        // ---- The foot: search, and what kind of entry ---------------------------
        Row {
            id: pillRow

            x: stage.cx - width / 2
            y: stage.height - clipboard.foot - clipboard.pillH
            spacing: Style.spaceMd
            scale: Math.min(1, (stage.width - 32) / Math.max(1, pillRow.implicitWidth))
            opacity: clipboard.stage_(0.35, 0.9)

            SearchField {
                id: searchField

                width: 280
                anchors.verticalCenter: parent.verticalCenter
                placeholder: "Search clipboard"
                // Number of matches while typing
                badge: clipboard.searching ? String(clipboard.filtered.length) : ""

                onTextChanged: clipboard.refilter()
                Keys.onEscapePressed: {
                    if (text !== "")
                        text = "";
                    else
                        clipboard.close();
                }
                Keys.onLeftPressed: clipboard.move(-1)
                Keys.onUpPressed: clipboard.move(-1)
                Keys.onRightPressed: clipboard.move(1)
                Keys.onDownPressed: clipboard.move(1)
                Keys.onTabPressed: clipboard.cycleFilter(1)
                Keys.onBacktabPressed: clipboard.cycleFilter(-1)
                Keys.onReturnPressed: clipboard.selectEntry(clipboard.currentLine)
                Keys.onEnterPressed: clipboard.selectEntry(clipboard.currentLine)
                Keys.onPressed: event => {
                    const ctrl = (event.modifiers & Qt.ControlModifier) !== 0;
                    // Removing something must not repeat, or a held key would
                    // sweep the whole history away
                    if (event.key === Qt.Key_Delete) {
                        if (!event.isAutoRepeat)
                            clipboard.removeCurrent();
                        event.accepted = true;
                    } else if (event.key === Qt.Key_PageDown) {
                        clipboard.move(5);
                        event.accepted = true;
                    } else if (event.key === Qt.Key_PageUp) {
                        clipboard.move(-5);
                        event.accepted = true;
                    } else if (ctrl) {
                        if (event.key === Qt.Key_N || event.key === Qt.Key_J) {
                            clipboard.move(1);
                            event.accepted = true;
                        } else if (event.key === Qt.Key_P || event.key === Qt.Key_K) {
                            clipboard.move(-1);
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Home) {
                            clipboard.jump(0);
                            event.accepted = true;
                        } else if (event.key === Qt.Key_End) {
                            clipboard.jump(clipboard.filtered.length - 1);
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Space) {
                            if (!event.isAutoRepeat)
                                clipboard.expanded = !clipboard.expanded && bodyText.truncated;
                            event.accepted = true;
                        }
                    }
                }
            }

            // Everything / text / images
            Repeater {
                model: [
                    {
                        "label": "All",
                        "n": clipboard.allEntries.length
                    },
                    {
                        "label": "Text",
                        "n": clipboard.textCount
                    },
                    {
                        "label": "Images",
                        "n": clipboard.imageCount
                    }
                ]

                delegate: TextButton {
                    required property int index
                    required property var modelData

                    anchors.verticalCenter: parent.verticalCenter
                    compact: true
                    primary: clipboard.typeFilter === index
                    text: modelData.label + "  " + modelData.n
                    onClicked: {
                        clipboard.setFilter(index);
                        searchField.forceActiveFocus();
                    }
                }
            }
        }
    }
}
