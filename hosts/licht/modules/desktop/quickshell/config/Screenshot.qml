// Screenshot.qml
// The screenshot tool on the launcher's dial: the screen freezes and dims, you
// pick what to capture, and the same borderless stage as the launcher and the
// capture panel rises from the bottom edge with the same fine ruler, glass
// discs and accent underline.
//
// The three things you can capture are three discs on the dial: Region (drag
// an area, then move it or pull its handles), Window (point at one and click)
// and Screen (the whole monitor). The one on top sits big with the accent
// underline and its name is read out below the ruler, with what it will
// capture (the size in pixels, the window's title, the monitor). Under that:
// where it goes (Copy to the clipboard, Save to a file, or both) and Capture.
//
//   qs ipc call screenshot toggle | open | close
//   qs ipc call screenshot show window           open on a mode (region | window | screen)
//   qs ipc call screenshot showTo region copy    ...and set where it goes (copy | save | both)
//
// Keys:  tab / shift+tab turn the dial (1-3 jump)   c copy   s save
//        left / right (or h / l) turn the dial too   ctrl+arrows nudge the region (+shift = 10px)
//        enter capture   esc close
// The selection is a ruler frame: its edges carry the dial's ticks, which rise beside the
//        pointer, and the corner you pull lights up (ShotRuler.qml). Each edge has a small
//        pill to pull, and a loupe magnifies the pixels under the pointer while you
//        place a corner. Letting go of a region locks it on, like an autofocus: the
//        brackets close in and a ring leaves the frame. A spark circles an idle frame,
//        a ratio badge clicks in at 16:9, 3:2 and friends, and a small dial of ticks
//        turns at the middle of a region as you move it.
//        The frame wakes in the wallpaper's palette while you work it: the launcher's
//        spectrum runs round its edges and brackets and drains to the accent when you
//        let go. A scan line sweeps the frozen picture as it arrives. Edges and the
//        middle snap to the screen's edges and to every window's edges, with a guide
//        line and its pixel position (hold Alt to move freely).
// Mouse: region: drag to select, drag inside to move, drag a handle to resize,
//        double-click or Enter to capture. window / screen: click to capture.
//        right click clears the selection (or closes when there is none)
//
// How it captures: the freeze is a ScreencopyView, so you pick on a still
// picture. When you confirm, the panel hides itself first and `grim` then
// takes the picture of the live screen (it would otherwise be in the shot),
// so the file holds what is on screen at that moment, at full resolution.
//
// Needs `grim` and `wl-copy` (wl-clipboard). The folder for saved files is
// Config.screenshotDir.

import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets

PanelWindow {
    id: shot

    // Opens on the monitor that has focus (set in open())
    property var targetScreen: Focus.screen

    // ---- Settings -------------------------------------------------------
    readonly property string saveDir: Config.screenshotDir
    readonly property bool notifyOnDone: true
    // A selection smaller than this (px) does not count
    readonly property int minSel: 4

    readonly property var modes: [
        {
            "id": "region",
            "label": "Region"
        },
        {
            "id": "window",
            "label": "Window"
        },
        {
            "id": "screen",
            "label": "Screen"
        }
    ]
    // Runs as: sh -c <script> sh <geometry> <copy 1|0> <folder or empty> <stamp>
    // Everything is an argument, never pasted into the script. Prints the file
    // it ends up with (the saved one, or the scratch copy when nothing is saved).
    readonly property var grabLines: ['sleep 0.15', 'geo="$1"; copy="$2"; dir="$3"; stamp="$4"', 'tmp="${XDG_RUNTIME_DIR:-/tmp}/qs-screenshot.png"', 'level=0; [ -n "$dir" ] && level=6', 'grim -l "$level" -g "$geo" "$tmp" || exit 1', 'f="$tmp"', 'if [ -n "$dir" ]; then', '  mkdir -p "$dir" || exit 1', '  f="$dir/Screenshot $stamp.png"', '  cp -- "$tmp" "$f" || exit 1', 'fi', 'if [ "$copy" = 1 ]; then wl-copy --type image/png < "$tmp" || exit 1; fi', 'printf "%s" "$f"']

    // ---- Settings (layout of the dial, as in the capture panel) ----------
    readonly property int stageW: Math.min(560, Math.round(width * 0.9))
    readonly property int topY: 46
    readonly property int ruleDrop: 40
    readonly property int ruleY: topY + ruleDrop
    readonly property real dialR: 900
    // The dome the dial starts as when it opens (and ends as when it closes)
    readonly property real rainbowR: 360
    readonly property real stepPx: 92
    readonly property int discSize: 44
    readonly property int selectedSize: 64
    readonly property int tickGap: 12
    readonly property int tickN: Math.ceil(stageW / tickGap) + 24
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
    // 1 when a target has just been picked, running to 0 (a little past it): the
    // brackets close in from outside, like an autofocus
    property real lock: 0
    // 1 when the frame clicks onto a ratio, running to 0
    property real snap: 0
    // The ring that leaves the frame on either of those
    readonly property real flash: Math.max(0, lock, snap)
    // Distance in pixels the spark has run round the frame; it never stops
    property real orbit: 0
    property string lastRatio: ""
    // 1 while you work the frame, easing back to 0 a while after: the palette's
    // spectrum runs round the frame by this much
    property real heat: dragging ? 1 : 0
    // Where the spectrum is round the frame (0..1, turns forever while it shows)
    property real chase: 0
    // The scan line over the frozen picture: 0 at the top, 1 = done
    property real scan: 1
    // Snapping: how close (px) an edge has to get, the lines on offer, the one
    // you are on now (-1 = none), and a flash when you click onto one
    readonly property int snapReach: 8
    property bool noSnap: false
    property var guideXs: [0]
    property var guideYs: [0]
    property real guideX: -1
    property real guideY: -1
    property real guideFlash: 0
    // 0 -> 1 each time the mode changes: the readout fades up
    property real swap: 1
    property int mode: 0
    // The frozen picture is in and the panel has started to arrive
    property bool revealed: false
    // Confirmed: everything is hidden while grim takes the picture
    property bool capturing: false

    // Where it goes. Both can be on; at least one always is.
    property bool toClipboard: true
    property bool toFile: false
    property bool lastCopy: true
    property bool lastSave: false
    property string pendingGeo: ""

    // The region, in pixels from the screen's top left
    property real selX: 0
    property real selY: 0
    property real selW: 0
    property real selH: 0
    // Window mode: what is under the pointer, and the windows of this screen
    // (frontmost first), each { x, y, w, h, title, cls }
    property var hoverWin: null
    property var windows: []
    // The pointer, in pixels from the screen's top left
    property real px: -1
    property real py: -1
    // A press that is moving the selection right now: new, move, or the edges
    // being pulled (t, b, l, r and the corners tl, tr, bl, br)
    property bool dragging: false
    property string grab: ""
    property real ax: 0
    property real ay: 0
    property real gx: 0
    property real gy: 0
    property real ox: 0
    property real oy: 0
    property real ow: 0
    property real oh: 0
    property string hoverGrab: "new"

    // ---- Derived --------------------------------------------------------
    readonly property var current: modes[mode]
    readonly property real dpr: targetScreen ? targetScreen.devicePixelRatio : 1
    readonly property bool hasSel: selW >= minSel && selH >= minSel
    readonly property bool hasTarget: mode === 0 ? hasSel : (mode === 1 ? hoverWin !== null : true)
    // What would be captured, in pixels from the screen's top left
    readonly property real tx: mode === 0 ? selX : (mode === 1 && hoverWin ? hoverWin.x : 0)
    readonly property real ty: mode === 0 ? selY : (mode === 1 && hoverWin ? hoverWin.y : 0)
    readonly property real tw: mode === 0 ? selW : (mode === 1 && hoverWin ? hoverWin.w : width)
    readonly property real th: mode === 0 ? selH : (mode === 1 && hoverWin ? hoverWin.h : height)
    readonly property string dimsText: Math.round(tw * dpr) + " \u00d7 " + Math.round(th * dpr)
    readonly property string detail: {
        if (mode === 0)
            return hasSel ? dimsText : "Drag to select an area";
        if (mode === 1)
            return hoverWin ? (hoverWin.title !== "" ? hoverWin.title : hoverWin.cls) : "Point at a window and click";
        return (targetScreen ? targetScreen.name : "") + "   \u00b7   " + dimsText;
    }
    // Ratios the region clicks onto (width, height, name)
    readonly property var ratios: [[1, 1, "1:1"], [4, 3, "4:3"], [3, 2, "3:2"], [16, 10, "16:10"], [16, 9, "16:9"], [21, 9, "21:9"], [3, 4, "3:4"], [2, 3, "2:3"], [10, 16, "10:16"], [9, 16, "9:16"]]
    readonly property string snapRatio: {
        if (mode !== 0 || !hasSel)
            return "";
        const r = selW / selH;
        for (let i = 0; i < ratios.length; i++) {
            if (Math.abs(r / (ratios[i][0] / ratios[i][1]) - 1) < 0.012)
                return ratios[i][2];
        }
        return "";
    }
    // The hole in the dim: glides between windows and modes, follows the
    // pointer exactly while you drag. With nothing to show it closes to the pointer.
    property real hx: hasTarget ? tx : Math.max(0, px)
    property real hy: hasTarget ? ty : Math.max(0, py)
    property real hw: hasTarget ? tw : 0
    property real hh: hasTarget ? th : 0
    // What a press would pull right now, or is pulling: "" when nothing
    readonly property string activeGrab: dragging ? grab : (mode === 0 && hasSel && hoverGrab !== "new" ? hoverGrab : "")
    // The corner being pulled (while drawing a new one, the one under the pointer)
    readonly property string activeCorner: {
        if (activeGrab === "new")
            return (py >= ay ? "b" : "t") + (px >= ax ? "r" : "l");
        return activeGrab.length === 2 ? activeGrab : "";
    }
    // The edges that are alive: the ones being pulled, or all four while moving
    readonly property string litEdges: activeGrab === "move" ? "tblr" : (activeGrab === "new" ? activeCorner : activeGrab)
    // The dim over what is not selected: the background with a breath of the accent
    readonly property color dimColor: Qt.alpha(Qt.tint(Colors.background, Qt.alpha(Colors.accent, 0.08)), 0.55 * clamp(reveal * 2, 0, 1))
    // Radius of the dial right now: curvature eases from the dome to the dial
    readonly property real dialNow: 1 / (1 / dialR + (1 / rainbowR - 1 / dialR) * fan)
    // Where the dial is turned to; glides to the chosen mode
    property real viewPos: mode
    readonly property int readoutTop: ruleY + 30
    readonly property real bodyH: readoutTop + 52 + 14 + Style.buttonHeight + foot

    Behavior on viewPos {
        // The dial glides into place and settles, with no bounce
        NumberAnimation {
            duration: Style.enterMs
            easing.type: Style.easeEnter
        }
    }
    Behavior on hx {
        enabled: shot.hasTarget && !shot.dragging
        NumberAnimation {
            duration: Style.moveMs
            easing.type: Style.easeMove
        }
    }
    Behavior on hy {
        enabled: shot.hasTarget && !shot.dragging
        NumberAnimation {
            duration: Style.moveMs
            easing.type: Style.easeMove
        }
    }
    Behavior on hw {
        enabled: shot.hasTarget && !shot.dragging
        NumberAnimation {
            duration: Style.moveMs
            easing.type: Style.easeMove
        }
    }
    Behavior on hh {
        enabled: shot.hasTarget && !shot.dragging
        NumberAnimation {
            duration: Style.moveMs
            easing.type: Style.easeMove
        }
    }

    Behavior on heat {
        // Wakes fast, drains slowly, like the spectrum leaving the dial
        NumberAnimation {
            duration: shot.dragging ? Style.fadeMs : Style.ambientMs * 2
            easing.type: Style.easeMove
        }
    }

    onWidthChanged: rebuildGuides()
    onHeightChanged: rebuildGuides()
    onGuideXChanged: {
        if (guideX >= 0)
            guideAnim.restart();
    }
    onGuideYChanged: {
        if (guideY >= 0)
            guideAnim.restart();
    }

    onModeChanged: {
        if (isOpen) {
            swapAnim.restart();
            lockAnim.restart();
        }
        hoverAt(px, py);
    }

    // Pointing at another window: the frame locks onto it
    onHoverWinChanged: {
        if (hoverWin && isOpen)
            lockAnim.restart();
    }

    onSnapRatioChanged: {
        if (snapRatio !== "") {
            lastRatio = snapRatio;
            snapAnim.restart();
        }
    }

    // Ease-out with a small overshoot for the arrival of each disc
    function backOut(t) {
        const c1 = 0.8;
        const u = t - 1;
        return 1 + (c1 + 1) * u * u * u + c1 * u * u;
    }

    function clamp(v, a, b) {
        return Math.max(a, Math.min(b, v));
    }

    // Staggered arrival: 0 until `from`, 1 at `to` (in reveal units).
    function phase(from, to) {
        return clamp((reveal - from) / (to - from), 0, 1);
    }

    // A colour round the ring of the palette (color1 to color6 and back to
    // color1) at t, 0..1. The same ramp the launcher washes its dial with.
    function ringColor(t) {
        const ramp = [Colors.color1, Colors.color2, Colors.color3, Colors.color4, Colors.color5, Colors.color6, Colors.color1];
        const n = ramp.length - 1;
        const x = (((t % 1) + 1) % 1) * n;
        const i = Math.min(n - 1, Math.floor(x));
        return Qt.tint(ramp[i], Qt.alpha(ramp[i + 1], x - i));
    }

    // The lines a region clicks onto: the screen's edges and middle, and the
    // edges of every window on it
    function rebuildGuides() {
        const xs = [0, width / 2, width];
        const ys = [0, height / 2, height];
        for (let i = 0; i < windows.length; i++) {
            const w = windows[i];
            xs.push(w.x, w.x + w.w);
            ys.push(w.y, w.y + w.h);
        }
        guideXs = xs;
        guideYs = ys;
    }

    // The line closest to any of `edges`, if it is within reach: how far to
    // shift, and which line. Holding Alt turns snapping off.
    function nearest(edges, lines) {
        if (noSnap)
            return null;
        let best = null;
        for (let i = 0; i < lines.length; i++) {
            for (let j = 0; j < edges.length; j++) {
                const d = lines[i] - edges[j];
                if (Math.abs(d) <= snapReach && (best === null || Math.abs(d) < Math.abs(best.d)))
                    best = {
                        "d": d,
                        "line": lines[i]
                    };
            }
        }
        return best;
    }

    // ---- Selection ------------------------------------------------------
    function setSel(x0, y0, x1, y1) {
        selX = Math.round(Math.min(x0, x1));
        selY = Math.round(Math.min(y0, y1));
        selW = Math.round(Math.abs(x1 - x0));
        selH = Math.round(Math.abs(y1 - y0));
    }

    function clearSel() {
        selX = 0;
        selY = 0;
        selW = 0;
        selH = 0;
    }

    // What a press at (mx, my) would do to the region: pull an edge or
    // corner (within 9px of it), move it (inside), or start a new one.
    function hitAt(mx, my) {
        if (!hasSel)
            return "new";
        const t = 9;
        const inX = mx >= selX - t && mx <= selX + selW + t;
        const inY = my >= selY - t && my <= selY + selH + t;
        let s = "";
        if (inX && Math.abs(my - selY) <= t)
            s += "t";
        else if (inX && Math.abs(my - (selY + selH)) <= t)
            s += "b";
        if (inY && Math.abs(mx - selX) <= t)
            s += "l";
        else if (inY && Math.abs(mx - (selX + selW)) <= t)
            s += "r";
        if (s !== "")
            return s;
        if (mx >= selX && mx <= selX + selW && my >= selY && my <= selY + selH)
            return "move";
        return "new";
    }

    function cursorFor(g) {
        if (mode !== 0)
            return Qt.PointingHandCursor;
        if (g === "tl" || g === "br")
            return Qt.SizeFDiagCursor;
        if (g === "tr" || g === "bl")
            return Qt.SizeBDiagCursor;
        if (g === "t" || g === "b")
            return Qt.SizeVerCursor;
        if (g === "l" || g === "r")
            return Qt.SizeHorCursor;
        if (g === "move")
            return Qt.SizeAllCursor;
        return Qt.CrossCursor;
    }

    function pressAt(mx, my) {
        if (mode !== 0)
            return;
        grab = hitAt(mx, my);
        gx = mx;
        gy = my;
        ox = selX;
        oy = selY;
        ow = selW;
        oh = selH;
        dragging = true;
        if (grab === "new") {
            const sx = nearest([mx], guideXs);
            const sy = nearest([my], guideYs);
            ax = sx ? sx.line : mx;
            ay = sy ? sy.line : my;
            selX = ax;
            selY = ay;
            selW = 0;
            selH = 0;
        }
    }

    function dragTo(mx, my) {
        let cx = clamp(mx, 0, width);
        let cy = clamp(my, 0, height);
        let lineX = -1;
        let lineY = -1;
        if (grab === "move") {
            // Left, right or middle of the region, whichever is closest to a line
            let nx = ox + mx - gx;
            let ny = oy + my - gy;
            const hx = nearest([nx, nx + ow, nx + ow / 2], guideXs);
            const hy = nearest([ny, ny + oh, ny + oh / 2], guideYs);
            if (hx) {
                nx += hx.d;
                lineX = hx.line;
            }
            if (hy) {
                ny += hy.d;
                lineY = hy.line;
            }
            selX = Math.round(clamp(nx, 0, width - ow));
            selY = Math.round(clamp(ny, 0, height - oh));
        } else if (grab !== "") {
            // Only the sides being pulled snap
            const useX = grab === "new" || grab.indexOf("l") >= 0 || grab.indexOf("r") >= 0;
            const useY = grab === "new" || grab.indexOf("t") >= 0 || grab.indexOf("b") >= 0;
            const hx = useX ? nearest([cx], guideXs) : null;
            const hy = useY ? nearest([cy], guideYs) : null;
            if (hx) {
                cx = hx.line;
                lineX = hx.line;
            }
            if (hy) {
                cy = hy.line;
                lineY = hy.line;
            }
            if (grab === "new") {
                setSel(ax, ay, cx, cy);
            } else {
                let x0 = ox, x1 = ox + ow, y0 = oy, y1 = oy + oh;
                if (grab.indexOf("l") >= 0)
                    x0 = cx;
                if (grab.indexOf("r") >= 0)
                    x1 = cx;
                if (grab.indexOf("t") >= 0)
                    y0 = cy;
                if (grab.indexOf("b") >= 0)
                    y1 = cy;
                setSel(x0, y0, x1, y1);
            }
        }
        guideX = lineX;
        guideY = lineY;
    }

    function release() {
        dragging = false;
        grab = "";
        guideX = -1;
        guideY = -1;
        // A click, or a sliver: not a selection
        if (!hasSel)
            clearSel();
        else if (mode === 0)
            lockAnim.restart();
    }

    function nudge(dx, dy) {
        if (mode !== 0 || !hasSel)
            return;
        selX = clamp(selX + dx, 0, width - selW);
        selY = clamp(selY + dy, 0, height - selH);
    }

    // ---- Windows --------------------------------------------------------
    function hoverAt(mx, my) {
        if (mode !== 1) {
            hoverWin = null;
            return;
        }
        let found = null;
        for (let i = 0; i < windows.length; i++) {
            const w = windows[i];
            if (mx >= w.x && mx <= w.x + w.w && my >= w.y && my <= w.y + w.h) {
                found = w;
                break;
            }
        }
        hoverWin = found;
    }

    // `hyprctl -j clients; @@; monitors`: the windows on this screen's workspace
    // (and the special workspace over it, if one is open), frontmost first.
    function parseWindows(raw) {
        const parts = raw.split("@@");
        let clients, monitors;
        try {
            clients = JSON.parse(parts[0]);
            monitors = JSON.parse(parts[1]);
        } catch (e) {
            console.warn("Screenshot: could not read hyprctl output: " + e);
            return;
        }
        const scr = targetScreen;
        const mon = scr ? monitors.find(m => m.name === scr.name) : null;
        if (!mon)
            return;
        const special = mon.specialWorkspace ? mon.specialWorkspace.id : 0;
        const active = mon.activeWorkspace ? mon.activeWorkspace.id : -1;
        const out = [];
        for (let i = 0; i < clients.length; i++) {
            const c = clients[i];
            if (c.mapped === false || c.hidden === true || !c.workspace || c.monitor !== mon.id)
                continue;
            const ws = c.workspace.id;
            const onSpecial = special !== 0 && ws === special;
            if (ws !== active && !onSpecial)
                continue;
            // Keep it on the screen
            const x0 = Math.max(0, c.at[0] - mon.x);
            const y0 = Math.max(0, c.at[1] - mon.y);
            const x1 = Math.min(width, c.at[0] + c.size[0] - mon.x);
            const y1 = Math.min(height, c.at[1] + c.size[1] - mon.y);
            if (x1 - x0 < minSel || y1 - y0 < minSel)
                continue;
            out.push({
                "x": x0,
                "y": y0,
                "w": x1 - x0,
                "h": y1 - y0,
                "title": c.title || "",
                "cls": c["class"] || c.initialClass || "",
                // special workspace first, then floating, then most recently focused
                "rank": (onSpecial ? 0 : 10000) + (c.floating ? 0 : 1000) + (c.focusHistoryID ?? 999)
            });
        }
        out.sort((a, b) => a.rank - b.rank);
        windows = out;
        rebuildGuides();
        hoverAt(px, py);
    }

    // Turn the dial one disc, wrapping round
    function turn(step) {
        mode = (mode + step + modes.length) % modes.length;
    }

    // ---- Destination ----------------------------------------------------
    function toggleCopy() {
        toClipboard = !toClipboard;
        if (!toClipboard && !toFile)
            toFile = true;
    }

    function toggleSave() {
        toFile = !toFile;
        if (!toFile && !toClipboard)
            toClipboard = true;
    }

    function setDest(dest) {
        if (dest === "copy") {
            toClipboard = true;
            toFile = false;
        } else if (dest === "save") {
            toClipboard = false;
            toFile = true;
        } else if (dest === "both") {
            toClipboard = true;
            toFile = true;
        }
    }

    // ---- Capture --------------------------------------------------------
    // Hides everything first (the panel would be in the picture), then after
    // a moment closes the window and lets grim take the shot.
    function capture() {
        if (capturing || !isOpen || !hasTarget || !targetScreen)
            return;
        const gx0 = Math.round(targetScreen.x + tx);
        const gy0 = Math.round(targetScreen.y + ty);
        pendingGeo = gx0 + "," + gy0 + " " + Math.max(1, Math.round(tw)) + "x" + Math.max(1, Math.round(th));
        lastCopy = toClipboard;
        lastSave = toFile;
        capturing = true;
        hideTimer.restart();
    }

    function finishCapture() {
        isOpen = false;
        revealed = false;
        openAnim.stop();
        closeAnim.stop();
        reveal = 0;
        grabber.command = ["sh", "-c", grabLines.join("\n"), "sh", pendingGeo, lastCopy ? "1" : "0", lastSave ? saveDir : "", Qt.formatDateTime(new Date(), "yyyy-MM-dd HHmmss")];
        grabber.running = true;
    }

    function done(path) {
        if (!notifyOnDone)
            return;
        const title = lastSave && lastCopy ? "Screenshot saved and copied" : (lastSave ? "Screenshot saved" : "Screenshot copied");
        const body = lastSave ? path.split("/").pop().replace(/\.png$/, "") : "On the clipboard";
        Quickshell.execDetached(["notify-send", "-a", "Screenshot", "-i", path, title, body]);
    }

    function failed() {
        Quickshell.execDetached(["notify-send", "-a", "Screenshot", "-u", "critical", "-i", "dialog-error", "Screenshot failed", "grim or wl-copy did not run. Are both installed?"]);
    }

    // ---- Open and close -------------------------------------------------
    // which: "region" | "window" | "screen" (or "" to keep the last one)
    // dest: "copy" | "save" | "both" (or "" to keep the last choice)
    function open(which, dest) {
        const i = modes.findIndex(m => m.id === which);
        if (i >= 0)
            mode = i;
        setDest(dest);
        if (isOpen)
            return;
        targetScreen = Focus.screen;
        clearSel();
        hoverWin = null;
        windows = [];
        rebuildGuides();
        guideX = -1;
        guideY = -1;
        px = -1;
        py = -1;
        capturing = false;
        revealed = false;
        dragging = false;
        grab = "";
        isOpen = true;
        if (!lister.running)
            lister.running = true;
        focusTimer.restart();
    }

    // The still picture is in: now the panel arrives
    function beginReveal() {
        if (revealed || !isOpen)
            return;
        revealed = true;
        keys.forceActiveFocus();
        closeAnim.stop();
        if (px < 0) {
            px = width / 2;
            py = height / 2;
        }
        if (reveal <= 0.001) {
            reveal = 0;
            spinIn = 3.2;
            fan = 1;
        }
        openAnim.restart();
        scan = 0;
        scanAnim.restart();
    }

    function close() {
        if (!isOpen)
            return;
        isOpen = false;
        revealed = false;
        openAnim.stop();
        closeAnim.restart();
    }

    function toggle() {
        if (isOpen)
            close();
        else
            open("", "");
    }

    // ---- Window ---------------------------------------------------------
    // Covers the whole screen, bar included (ExclusionMode.Ignore), with the
    // keyboard to itself while it is open.
    visible: isOpen || reveal > 0.001
    color: "transparent"
    screen: targetScreen
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "qs-screenshot"
    WlrLayershell.keyboardFocus: isOpen ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    IpcHandler {
        function toggle(): void {
            shot.toggle();
        }

        function open(): void {
            shot.open("", "");
        }

        function show(which: string): void {
            shot.open(which, "");
        }

        function showTo(which: string, dest: string): void {
            shot.open(which, dest);
        }

        function close(): void {
            shot.close();
        }

        target: "screenshot"
    }

    Process {
        id: lister

        command: ["sh", "-c", "hyprctl -j clients; echo @@; hyprctl -j monitors"]
        stdout: StdioCollector {
            onStreamFinished: shot.parseWindows(text)
        }
    }

    Process {
        id: grabber

        stdout: StdioCollector {
            onStreamFinished: {
                if (text.trim() !== "")
                    shot.done(text.trim());
            }
        }
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0)
                shot.failed();
        }
    }

    PanelLink {
        win: shot
        name: "screenshot"
    }

    // A frame later the panel is off the screen: then grim takes the picture
    Timer {
        id: hideTimer

        interval: 60
        onTriggered: shot.finishCapture()
    }

    // The window is not mapped yet when open() runs, so ask for the keyboard
    // again a moment later
    Timer {
        id: focusTimer

        interval: 40
        onTriggered: keys.forceActiveFocus()
    }

    // If the still picture never arrives (no screencopy), carry on without it
    Timer {
        interval: 300
        running: shot.isOpen && !shot.revealed
        onTriggered: shot.beginReveal()
    }

    // Rises smoothly. The discs swing in from the left over a tight dome and
    // unfurl into the dial.
    ParallelAnimation {
        id: openAnim

        NumberAnimation {
            target: shot
            property: "reveal"
            to: 1
            duration: Style.sweepMs
            easing.type: Style.easeEnter
        }
        NumberAnimation {
            target: shot
            property: "spinIn"
            to: 0
            duration: Style.sweepMs + Style.moveMs
            easing.type: Style.easeEnter
        }
        NumberAnimation {
            target: shot
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
            target: shot
            property: "reveal"
            to: 0
            duration: Style.moveMs + Style.fadeMs
            easing.type: Style.easeExit
        }
        NumberAnimation {
            target: shot
            property: "spinIn"
            to: -3.2
            duration: Style.moveMs + Style.fadeMs
            easing.type: Style.easeExit
        }
        NumberAnimation {
            target: shot
            property: "fan"
            to: 1
            duration: Style.moveMs + Style.fadeMs
            easing.type: Style.easeExit
        }
    }

    // Slow breath for the ring around the selected disc.
    SequentialAnimation {
        running: shot.isOpen && !shot.dragging
        loops: Animation.Infinite

        NumberAnimation {
            target: shot
            property: "breath"
            from: 0
            to: 1
            duration: Style.ambientMs * 2
            easing.type: Style.easeAmbient
        }
        NumberAnimation {
            target: shot
            property: "breath"
            from: 1
            to: 0
            duration: Style.ambientMs * 2
            easing.type: Style.easeAmbient
        }
    }

    // The frame locks on: the brackets start outside and close in, a little
    // past home, and settle
    NumberAnimation {
        id: lockAnim

        target: shot
        property: "lock"
        from: 1
        to: 0
        duration: Style.moveMs + Style.fadeMs
        easing.type: Style.easePop
    }

    // The frame clicks onto a ratio
    NumberAnimation {
        id: snapAnim

        target: shot
        property: "snap"
        from: 1
        to: 0
        duration: Style.moveMs + Style.fadeMs
        easing.type: Style.easeMove
    }

    // The spark: a steady 330px a second round whatever frame it is on; it
    // holds still while you drag
    NumberAnimation {
        target: shot
        property: "orbit"
        from: 0
        to: 100000
        duration: 300000
        loops: Animation.Infinite
        running: shot.isOpen
        paused: !shot.hasTarget || shot.dragging
    }

    // The scan line crosses the frozen picture once as it arrives
    NumberAnimation {
        id: scanAnim

        target: shot
        property: "scan"
        from: 0
        to: 1
        duration: Style.sweepMs
        easing.type: Style.easeMove
    }

    // A flash on the guide line when an edge clicks onto it
    NumberAnimation {
        id: guideAnim

        target: shot
        property: "guideFlash"
        from: 1
        to: 0
        duration: Style.moveMs
        easing.type: Style.easeMove
    }

    // The spectrum runs round the frame, but only while it shows
    NumberAnimation {
        target: shot
        property: "chase"
        from: 0
        to: 1
        duration: 5000
        loops: Animation.Infinite
        running: shot.isOpen && shot.heat > 0.01
    }

    // A different mode is chosen: the words fade up
    NumberAnimation {
        id: swapAnim

        target: shot
        property: "swap"
        from: 0
        to: 1
        duration: Style.baseMs
        easing.type: Style.easeMove
    }

    // ---- Keys -----------------------------------------------------------
    Item {
        id: keys

        anchors.fill: parent
        focus: shot.isOpen
        Keys.onPressed: event => {
            if (shot.capturing)
                return;
            const k = event.key;
            const shift = (event.modifiers & Qt.ShiftModifier) !== 0;
            const ctrl = (event.modifiers & Qt.ControlModifier) !== 0;
            const step = shift ? 10 : 1;
            if (k === Qt.Key_Escape)
                shot.close();
            else if (k === Qt.Key_Return || k === Qt.Key_Enter)
                shot.capture();
            else if (ctrl && k === Qt.Key_Left)
                shot.nudge(-step, 0);
            else if (ctrl && k === Qt.Key_Right)
                shot.nudge(step, 0);
            else if (ctrl && k === Qt.Key_Up)
                shot.nudge(0, -step);
            else if (ctrl && k === Qt.Key_Down)
                shot.nudge(0, step);
            else if (k === Qt.Key_Right || k === Qt.Key_Down || k === Qt.Key_L || k === Qt.Key_J || k === Qt.Key_Tab)
                shot.turn(1);
            else if (k === Qt.Key_Left || k === Qt.Key_Up || k === Qt.Key_H || k === Qt.Key_K || k === Qt.Key_Backtab)
                shot.turn(-1);
            else if (k >= Qt.Key_1 && k < Qt.Key_1 + shot.modes.length)
                shot.mode = k - Qt.Key_1;
            else if (k === Qt.Key_C)
                shot.toggleCopy();
            else if (k === Qt.Key_S)
                shot.toggleSave();
        }
    }

    // ---- Everything that is hidden while grim takes the picture -----------
    Item {
        id: content

        anchors.fill: parent
        visible: !shot.capturing

        // The still picture of the screen
        Loader {
            id: frozen

            anchors.fill: parent
            active: shot.visible

            sourceComponent: ScreencopyView {
                captureSource: shot.targetScreen
                live: false
                onHasContentChanged: {
                    if (hasContent)
                        shot.beginReveal();
                }
                Component.onCompleted: captureFrame()
            }
        }

        // The dim, in four pieces around the hole
        Rectangle {
            x: 0
            y: 0
            width: shot.width
            height: shot.hy
            color: shot.dimColor
        }
        Rectangle {
            x: 0
            y: shot.hy + shot.hh
            width: shot.width
            height: Math.max(0, shot.height - shot.hy - shot.hh)
            color: shot.dimColor
        }
        Rectangle {
            x: 0
            y: shot.hy
            width: shot.hx
            height: shot.hh
            color: shot.dimColor
        }
        Rectangle {
            x: shot.hx + shot.hw
            y: shot.hy
            width: Math.max(0, shot.width - shot.hx - shot.hw)
            height: shot.hh
            color: shot.dimColor
        }

        // The scan: a line crosses the frozen picture as it arrives, in the
        // palette's colours, with a soft trail above it
        Rectangle {
            readonly property real at: shot.scan * (shot.height + 90) - 90

            x: 0
            y: at
            width: shot.width
            height: 90
            visible: shot.scan > 0.001 && shot.scan < 0.999

            gradient: Gradient {
                GradientStop {
                    position: 0
                    color: Qt.alpha(Colors.accent, 0)
                }
                GradientStop {
                    position: 1
                    color: Qt.alpha(Colors.accent, 0.16)
                }
            }

            Rectangle {
                y: parent.height - 1
                width: parent.width
                height: 2

                gradient: Gradient {
                    orientation: Gradient.Horizontal

                    GradientStop {
                        position: 0
                        color: shot.ringColor(0)
                    }
                    GradientStop {
                        position: 0.2
                        color: shot.ringColor(0.17)
                    }
                    GradientStop {
                        position: 0.4
                        color: shot.ringColor(0.34)
                    }
                    GradientStop {
                        position: 0.6
                        color: shot.ringColor(0.5)
                    }
                    GradientStop {
                        position: 0.8
                        color: shot.ringColor(0.67)
                    }
                    GradientStop {
                        position: 1
                        color: shot.ringColor(0.83)
                    }
                }
            }
        }

        // Crosshair while nothing is selected yet: two hairlines that are
        // strongest at the pointer and fade out along their length, like the
        // ruler ticks that wake beside it
        Rectangle {
            x: shot.px
            y: shot.py - 300
            width: 1
            height: 600
            opacity: shot.mode === 0 && !shot.hasSel && !shot.dragging && shot.px >= 0 ? 1 : 0

            gradient: Gradient {
                GradientStop {
                    position: 0
                    color: Qt.alpha(Colors.foreground, 0)
                }
                GradientStop {
                    position: 0.5
                    color: Qt.alpha(Colors.foreground, 0.55)
                }
                GradientStop {
                    position: 1
                    color: Qt.alpha(Colors.foreground, 0)
                }
            }

            Behavior on opacity {
                NumberAnimation {
                    duration: Style.fadeMs
                }
            }
        }
        Rectangle {
            x: shot.px - 300
            y: shot.py
            width: 600
            height: 1
            opacity: shot.mode === 0 && !shot.hasSel && !shot.dragging && shot.px >= 0 ? 1 : 0

            gradient: Gradient {
                orientation: Gradient.Horizontal

                GradientStop {
                    position: 0
                    color: Qt.alpha(Colors.foreground, 0)
                }
                GradientStop {
                    position: 0.5
                    color: Qt.alpha(Colors.foreground, 0.55)
                }
                GradientStop {
                    position: 1
                    color: Qt.alpha(Colors.foreground, 0)
                }
            }

            Behavior on opacity {
                NumberAnimation {
                    duration: Style.fadeMs
                }
            }
        }

        // ---- The selection: a viewfinder drawn like the dial's ruler --------
        // Corner brackets with a few ticks on each arm, a pill on each edge
        // to pull, the width and height on rulers outside the frame, and
        // thirds while you drag. Window mode names the window; screen mode
        // sits the frame a little inside the screen so its corners show.
        Item {
            id: sel

            property real ins: shot.mode === 2 ? 14 : 0
            // The thirds show while you drag
            property real guides: shot.dragging ? 1 : 0
            readonly property real arm: Math.max(0, Math.min(28, width / 3, height / 3))
            // The rulers go on the side that has room
            readonly property bool roomAbove: y >= 34
            readonly property bool roomLeft: x >= 34
            readonly property real perimeter: 2 * (width + height)

            // The point d pixels round the frame, clockwise from the top left
            function around(d) {
                const P = perimeter;
                let t = ((d % P) + P) % P;
                if (t < width)
                    return Qt.point(t, 0);
                t -= width;
                if (t < height)
                    return Qt.point(width, t);
                t -= height;
                if (t < width)
                    return Qt.point(width - t, height);
                t -= width;
                return Qt.point(0, height - t);
            }
            // A window keeps its own rounded corners (Hyprland's rounding), a
            // window that fills the screen has none. The brackets are for squares.
            readonly property real corner: shot.mode === 1 && !(shot.hw >= shot.width - 1 && shot.hh >= shot.height - 1) ? 14 : 0

            x: shot.hx + ins
            y: shot.hy + ins
            width: Math.max(0, shot.hw - 2 * ins)
            height: Math.max(0, shot.hh - 2 * ins)
            opacity: shot.hasTarget ? shot.clamp(shot.reveal * 2, 0, 1) : 0
            visible: opacity > 0.01

            Behavior on ins {
                NumberAnimation {
                    duration: Style.moveMs
                    easing.type: Style.easeMove
                }
            }
            Behavior on guides {
                NumberAnimation {
                    duration: Style.baseMs
                }
            }
            Behavior on opacity {
                NumberAnimation {
                    duration: Style.fadeMs
                }
            }

            // A faint halo just outside the frame
            Rectangle {
                anchors.fill: parent
                anchors.margins: -3
                radius: sel.corner > 0 ? sel.corner + 3 : 0
                color: "transparent"
                border.width: 3
                border.color: Qt.alpha(Colors.accent, 0.12)
            }

            // The flash: a ring that leaves the frame when it locks on or a
            // ratio clicks in
            Rectangle {
                anchors.fill: parent
                anchors.margins: -(4 + 16 * (1 - shot.flash))
                radius: sel.corner > 0 ? sel.corner + 8 : 0
                color: "transparent"
                antialiasing: true
                border.width: 1.5
                // Washed with the palette by where the frame is across the screen, as the launcher does
                border.color: Qt.alpha(Qt.tint(Colors.accent, Qt.alpha(shot.ringColor((sel.x + sel.width / 2) / shot.width * 0.83), 0.7)), 0.8 * shot.flash)
                visible: shot.flash > 0.01
            }

            // The frame: a hairline in the accent. In window mode the window
            // is washed with a little accent too.
            Rectangle {
                anchors.fill: parent
                anchors.margins: -shot.lock * 8
                radius: sel.corner
                color: Qt.alpha(Colors.accent, shot.mode === 1 ? 0.1 : 0)
                border.width: 1
                border.color: Qt.alpha(Colors.accent, 0.85)

                Behavior on color {
                    ColorAnimation {
                        duration: Style.baseMs
                    }
                }

                EdgeLight {
                    corner: Math.max(8, sel.corner)
                }
            }

            // The spark: a bead of accent that circles the frame while you
            // leave it alone, with a trail, and a dimmer one opposite
            Repeater {
                model: 2

                delegate: Item {
                    id: comet

                    required property int index

                    Repeater {
                        model: 9

                        delegate: Rectangle {
                            id: bead

                            required property int index

                            readonly property point p: sel.around(shot.orbit + comet.index * sel.perimeter / 2 - index * 9)

                            width: 6 - index * 0.5
                            height: width
                            radius: width / 2
                            x: p.x - width / 2
                            y: p.y - height / 2
                            color: Colors.accent
                            opacity: shot.dragging ? 0 : (1 - index / 9) * (comet.index === 0 ? 0.9 : 0.4)
                            visible: sel.width > 40 && sel.height > 40 && opacity > 0.02
                        }
                    }
                }
            }

            // Thirds
            Repeater {
                model: [1, 2]

                delegate: Item {
                    required property int modelData

                    Rectangle {
                        x: sel.width * parent.modelData / 3
                        width: 1
                        height: sel.height
                        color: Qt.alpha(Colors.foreground, 0.2 * sel.guides)
                        visible: sel.guides > 0.01
                    }
                    Rectangle {
                        y: sel.height * parent.modelData / 3
                        width: sel.width
                        height: 1
                        color: Qt.alpha(Colors.foreground, 0.2 * sel.guides)
                        visible: sel.guides > 0.01
                    }
                }
            }

            // Pointing inside a region: a small dial of ticks at its middle,
            // which turns as you move the region, like the dial turning under
            // the ruler
            Item {
                x: sel.width / 2
                y: sel.height / 2
                opacity: shot.activeGrab === "move" && sel.width > 90 && sel.height > 90 ? 1 : 0
                visible: opacity > 0.01
                rotation: (sel.x + sel.y) * 1.2 + shot.orbit * 0.12
                scale: opacity > 0.5 ? 1 : 0.7

                Behavior on opacity {
                    NumberAnimation {
                        duration: Style.fadeMs
                    }
                }
                Behavior on scale {
                    NumberAnimation {
                        duration: Style.moveMs
                        easing.type: Style.easePop
                    }
                }

                Repeater {
                    model: 36

                    delegate: Item {
                        required property int index

                        rotation: index * 10

                        Rectangle {
                            x: -0.75
                            y: -26
                            width: 1.5
                            height: index % 9 === 0 ? 9 : 4
                            radius: 0.75
                            color: index % 9 === 0 ? Colors.accent : Qt.alpha(Colors.foreground, 0.55)
                        }
                    }
                }
            }

            // The middle, marked
            Rectangle {
                x: sel.width / 2 - 5
                y: sel.height / 2
                width: 10
                height: 1
                color: Qt.alpha(Colors.accent, 0.7)
                visible: sel.width > 80 && sel.height > 80
            }
            Rectangle {
                x: sel.width / 2
                y: sel.height / 2 - 5
                width: 1
                height: 10
                color: Qt.alpha(Colors.accent, 0.7)
                visible: sel.width > 80 && sel.height > 80
            }

            // The ratio badge: clicks in when the frame is a ratio you know
            ShotPill {
                x: sel.width / 2 - width / 2
                y: sel.height - height - 14
                text: shot.snapRatio !== "" ? shot.snapRatio : shot.lastRatio
                textColor: Colors.accent
                opacity: shot.snapRatio !== "" && sel.width > 110 && sel.height > 70 ? 1 : 0
                visible: opacity > 0.01
                scale: opacity > 0.5 ? 1 : 0.8

                Behavior on opacity {
                    NumberAnimation {
                        duration: Style.fadeMs
                    }
                }
                Behavior on scale {
                    NumberAnimation {
                        duration: Style.moveMs
                        easing.type: Style.easePop
                    }
                }
            }

            // ---- The four edges, as rulers ---------------------------------
            ShotRuler {
                horizontal: true
                length: sel.width
                along: shot.px - sel.x
                away: Math.abs(shot.py - sel.y)
                lit: shot.litEdges.indexOf("t") >= 0
            }
            ShotRuler {
                y: sel.height
                horizontal: true
                flip: true
                length: sel.width
                along: shot.px - sel.x
                away: Math.abs(shot.py - (sel.y + sel.height))
                lit: shot.litEdges.indexOf("b") >= 0
            }
            ShotRuler {
                horizontal: false
                length: sel.height
                along: shot.py - sel.y
                away: Math.abs(shot.px - sel.x)
                lit: shot.litEdges.indexOf("l") >= 0
            }
            ShotRuler {
                x: sel.width
                horizontal: false
                flip: true
                length: sel.height
                along: shot.py - sel.y
                away: Math.abs(shot.px - (sel.x + sel.width))
                lit: shot.litEdges.indexOf("r") >= 0
            }

            // An edge that is being pulled glows in the accent
            Rectangle {
                x: 0
                y: -1
                width: sel.width
                height: 2
                color: Colors.accent
                opacity: shot.litEdges.indexOf("t") >= 0 ? 1 : 0

                Behavior on opacity {
                    NumberAnimation {
                        duration: Style.fadeMs
                    }
                }
            }
            Rectangle {
                x: 0
                y: sel.height - 1
                width: sel.width
                height: 2
                color: Colors.accent
                opacity: shot.litEdges.indexOf("b") >= 0 ? 1 : 0

                Behavior on opacity {
                    NumberAnimation {
                        duration: Style.fadeMs
                    }
                }
            }
            Rectangle {
                x: -1
                y: 0
                width: 2
                height: sel.height
                color: Colors.accent
                opacity: shot.litEdges.indexOf("l") >= 0 ? 1 : 0

                Behavior on opacity {
                    NumberAnimation {
                        duration: Style.fadeMs
                    }
                }
            }
            Rectangle {
                x: sel.width - 1
                y: 0
                width: 2
                height: sel.height
                color: Colors.accent
                opacity: shot.litEdges.indexOf("r") >= 0 ? 1 : 0

                Behavior on opacity {
                    NumberAnimation {
                        duration: Style.fadeMs
                    }
                }
            }

            // The spectrum: while you work the frame the palette's colours run
            // round its edges (a ring that turns), and drain to the accent when
            // you let go. Each edge takes its own share of the ring.
            Rectangle {
                y: -1
                width: sel.width
                height: 2
                opacity: shot.heat
                visible: opacity > 0.01

                gradient: Gradient {
                    orientation: Gradient.Horizontal

                    GradientStop {
                        position: 0
                        color: shot.ringColor(shot.chase)
                    }
                    GradientStop {
                        position: 0.5
                        color: shot.ringColor(shot.chase + 0.5 * sel.width / sel.perimeter)
                    }
                    GradientStop {
                        position: 1
                        color: shot.ringColor(shot.chase + sel.width / sel.perimeter)
                    }
                }
            }
            Rectangle {
                x: sel.width - 1
                width: 2
                height: sel.height
                opacity: shot.heat
                visible: opacity > 0.01

                gradient: Gradient {
                    GradientStop {
                        position: 0
                        color: shot.ringColor(shot.chase + sel.width / sel.perimeter)
                    }
                    GradientStop {
                        position: 0.5
                        color: shot.ringColor(shot.chase + (sel.width + 0.5 * sel.height) / sel.perimeter)
                    }
                    GradientStop {
                        position: 1
                        color: shot.ringColor(shot.chase + (sel.width + sel.height) / sel.perimeter)
                    }
                }
            }
            Rectangle {
                y: sel.height - 1
                width: sel.width
                height: 2
                opacity: shot.heat
                visible: opacity > 0.01

                gradient: Gradient {
                    orientation: Gradient.Horizontal

                    GradientStop {
                        position: 0
                        color: shot.ringColor(shot.chase + (2 * sel.width + sel.height) / sel.perimeter)
                    }
                    GradientStop {
                        position: 0.5
                        color: shot.ringColor(shot.chase + (1.5 * sel.width + sel.height) / sel.perimeter)
                    }
                    GradientStop {
                        position: 1
                        color: shot.ringColor(shot.chase + (sel.width + sel.height) / sel.perimeter)
                    }
                }
            }
            Rectangle {
                x: -1
                width: 2
                height: sel.height
                opacity: shot.heat
                visible: opacity > 0.01

                gradient: Gradient {
                    GradientStop {
                        position: 0
                        color: shot.ringColor(shot.chase + 1)
                    }
                    GradientStop {
                        position: 0.5
                        color: shot.ringColor(shot.chase + (2 * sel.width + 1.5 * sel.height) / sel.perimeter)
                    }
                    GradientStop {
                        position: 1
                        color: shot.ringColor(shot.chase + (2 * sel.width + sel.height) / sel.perimeter)
                    }
                }
            }

            // The corners: a bracket, and a glass disc that pops out of the
            // one you are pulling, like the discs on the dial.
            Repeater {
                // corner x, corner y, which way its arms point, and its name
                model: [[0, 0, 1, 1, "tl"], [1, 0, -1, 1, "tr"], [1, 1, -1, -1, "br"], [0, 1, 1, -1, "bl"]]

                delegate: Item {
                    id: corner

                    required property var modelData

                    readonly property int dx: modelData[2]
                    readonly property int dy: modelData[3]
                    readonly property bool active: shot.activeCorner === modelData[4]
                    // Where this corner is round the ring, and its colour: the accent at rest, its slice of the spectrum while you work
                    readonly property real ringAt: modelData[4] === "tl" ? 0 : (modelData[4] === "tr" ? sel.width / sel.perimeter : (modelData[4] === "br" ? (sel.width + sel.height) / sel.perimeter : (2 * sel.width + sel.height) / sel.perimeter))
                    readonly property color tone: Qt.tint(Colors.accent, Qt.alpha(shot.ringColor(shot.chase + ringAt), 0.9 * shot.heat))

                    visible: sel.corner === 0
                    x: sel.width * modelData[0] - dx * shot.lock * 14
                    y: sel.height * modelData[1] - dy * shot.lock * 14

                    Rectangle {
                        x: corner.dx > 0 ? -1.5 : -sel.arm + 1.5
                        y: -1.5
                        width: sel.arm
                        height: 3
                        radius: 1.5
                        color: corner.tone
                    }
                    Rectangle {
                        x: -1.5
                        y: corner.dy > 0 ? -1.5 : -sel.arm + 1.5
                        width: 3
                        height: sel.arm
                        radius: 1.5
                        color: corner.tone
                    }

                    // Fine ticks along both arms, pointing in, like the ruler
                    Repeater {
                        model: sel.arm > 24 ? 3 : 0

                        delegate: Item {
                            id: armTick

                            required property int index

                            readonly property real at: 8 + index * 6
                            readonly property real len: 6 - index * 1.5

                            Rectangle {
                                x: corner.dx > 0 ? armTick.at : -armTick.at - 1
                                y: corner.dy > 0 ? 3 : -3 - armTick.len
                                width: 1
                                height: armTick.len
                                color: Qt.alpha(Colors.accent, 0.7)
                            }
                            Rectangle {
                                x: corner.dx > 0 ? 3 : -3 - armTick.len
                                y: corner.dy > 0 ? armTick.at : -armTick.at - 1
                                width: armTick.len
                                height: 1
                                color: Qt.alpha(Colors.accent, 0.7)
                            }
                        }
                    }

                    Rectangle {
                        x: -7
                        y: -7
                        width: 14
                        height: 14
                        radius: 7
                        antialiasing: true
                        color: Style.card
                        border.width: 1.5
                        border.color: Colors.accent
                        opacity: corner.active ? 1 : 0
                        scale: corner.active ? 1 : 0.4
                        visible: opacity > 0.01

                        Behavior on opacity {
                            NumberAnimation {
                                duration: Style.fadeMs
                            }
                        }
                        Behavior on scale {
                            NumberAnimation {
                                duration: Style.moveMs
                                easing.type: Style.easePop
                            }
                        }

                        Rectangle {
                            anchors.centerIn: parent
                            width: 4
                            height: 4
                            radius: 2
                            color: Colors.accent
                        }
                    }
                }
            }

            // The edges: a small glass pill on each, to pull. Quiet until the
            // pointer comes near; the one being pulled fills with the accent.
            Repeater {
                // which edge, where along the frame (as fractions), and whether it runs sideways
                model: [["t", 0.5, 0, true], ["b", 0.5, 1, true], ["l", 0, 0.5, false], ["r", 1, 0.5, false]]

                delegate: Item {
                    id: edge

                    required property var modelData

                    readonly property bool sideways: modelData[3]
                    readonly property bool lit: shot.activeGrab === modelData[0]
                    // How close the pointer is to this pill: 0 far, 1 on it
                    readonly property real near: {
                        const dx = shot.px - (sel.x + x);
                        const dy = shot.py - (sel.y + y);
                        return shot.clamp(1 - Math.sqrt(dx * dx + dy * dy) / 150, 0, 1);
                    }
                    readonly property bool roomy: (sideways ? sel.width : sel.height) > 90

                    x: sel.width * modelData[1]
                    y: sel.height * modelData[2]
                    opacity: shot.mode === 0 && roomy ? (shot.dragging ? (lit ? 1 : 0) : 0.3 + 0.7 * Math.max(near, lit ? 1 : 0)) : 0
                    visible: opacity > 0.01

                    Behavior on opacity {
                        NumberAnimation {
                            duration: Style.fadeMs
                        }
                    }

                    Rectangle {
                        anchors.centerIn: parent
                        width: edge.sideways ? 26 : 7
                        height: edge.sideways ? 7 : 26
                        radius: 3.5
                        antialiasing: true
                        color: edge.lit ? Colors.accent : Style.card
                        border.width: 1.5
                        border.color: Qt.alpha(Colors.accent, 0.9)
                        scale: edge.lit ? 1.2 : 1

                        Behavior on color {
                            ColorAnimation {
                                duration: Style.baseMs
                            }
                        }
                        Behavior on scale {
                            NumberAnimation {
                                duration: Style.moveMs
                                easing.type: Style.easePop
                            }
                        }
                    }
                }
            }

            // The width, on a ruler above the frame (below it with no room)
            Item {
                y: sel.roomAbove ? -18 : sel.height + 18
                width: sel.width
                visible: shot.mode !== 2 && sel.width > 60

                Rectangle {
                    width: parent.width
                    height: 1
                    color: Qt.alpha(Colors.accent, 0.5)
                }
                Rectangle {
                    x: 0
                    y: -4
                    width: 1
                    height: 9
                    color: Qt.alpha(Colors.accent, 0.8)
                }
                Rectangle {
                    x: parent.width - 1
                    y: -4
                    width: 1
                    height: 9
                    color: Qt.alpha(Colors.accent, 0.8)
                }
                ShotPill {
                    x: parent.width / 2 - width / 2
                    y: -height / 2
                    text: String(Math.round(shot.tw * shot.dpr))
                }
            }

            // The height, on a ruler beside it
            Item {
                x: sel.roomLeft ? -18 : sel.width + 18
                height: sel.height
                visible: shot.mode !== 2 && sel.height > 60

                Rectangle {
                    width: 1
                    height: parent.height
                    color: Qt.alpha(Colors.accent, 0.5)
                }
                Rectangle {
                    x: -4
                    y: 0
                    width: 9
                    height: 1
                    color: Qt.alpha(Colors.accent, 0.8)
                }
                Rectangle {
                    x: -4
                    y: parent.height - 1
                    width: 9
                    height: 1
                    color: Qt.alpha(Colors.accent, 0.8)
                }
                Item {
                    y: parent.height / 2

                    ShotPill {
                        anchors.centerIn: parent
                        rotation: -90
                        text: String(Math.round(shot.th * shot.dpr))
                    }
                }
            }

            // Window mode: whose window this is
            ShotPill {
                x: 10
                y: 10
                visible: shot.mode === 1 && shot.hoverWin !== null && sel.width > 90 && text !== ""
                text: shot.hoverWin ? shot.hoverWin.cls : ""
                textColor: Colors.accent
            }

            // Screen mode: the monitor, in the middle
            ShotPill {
                x: sel.width / 2 - width / 2
                y: sel.height / 2 - height - 14
                visible: shot.mode === 2
                text: (shot.targetScreen ? shot.targetScreen.name + "   \u00b7   " : "") + shot.dimsText
            }
        }

        // The guides: the line an edge has clicked onto, across the whole
        // screen, with its pixel position at the end. It flashes as it catches.
        Rectangle {
            x: shot.guideX - 0.5
            y: 0
            width: 1 + shot.guideFlash
            height: shot.height
            color: Qt.alpha(Colors.accent, 0.5 + 0.45 * shot.guideFlash)
            visible: shot.dragging && shot.guideX >= 0

            ShotPill {
                x: -width / 2
                y: 10
                text: Math.round(shot.guideX * shot.dpr)
                textColor: Colors.accent
            }
        }
        Rectangle {
            x: 0
            y: shot.guideY - 0.5
            width: shot.width
            height: 1 + shot.guideFlash
            color: Qt.alpha(Colors.accent, 0.5 + 0.45 * shot.guideFlash)
            visible: shot.dragging && shot.guideY >= 0

            ShotPill {
                x: 10
                y: -height / 2
                text: Math.round(shot.guideY * shot.dpr)
                textColor: Colors.accent
            }
        }

        // The loupe: the pixels under the pointer, magnified, while you place
        // a corner. A glass disc with the accent's ring (it breathes with the
        // dial's) and a fine crosshair; where the pointer is reads out under
        // it. It sits to the lower right of the pointer and turns to the
        // other side near the edges of the screen.
        Item {
            id: loupe

            readonly property int size: 128
            readonly property int zoom: 8
            readonly property real span: size / zoom
            readonly property int gap: 26
            readonly property bool shown: shot.mode === 0 && shot.px >= 0 && (shot.dragging || !shot.hasSel)
            readonly property bool flipX: shot.px + gap + size > shot.width - 8
            readonly property bool flipY: shot.py + gap + height > shot.height - 8

            width: size
            height: size + 28
            x: flipX ? shot.px - gap - size : shot.px + gap
            y: flipY ? shot.py - gap - height : shot.py + gap
            opacity: shown ? shot.clamp(shot.reveal * 2, 0, 1) : 0
            scale: shown ? 1 : 0.85
            visible: opacity > 0.01

            Behavior on opacity {
                NumberAnimation {
                    duration: Style.fadeMs
                }
            }
            Behavior on scale {
                NumberAnimation {
                    duration: Style.baseMs
                    easing.type: Style.easePop
                }
            }

            ClippingRectangle {
                width: loupe.size
                height: loupe.size
                radius: loupe.size / 2
                color: Style.card

                // The frozen picture, a few pixels of it, blown up
                ShaderEffectSource {
                    anchors.fill: parent
                    visible: frozen.item !== null
                    sourceItem: frozen.item
                    sourceRect: Qt.rect(shot.px - loupe.span / 2, shot.py - loupe.span / 2, loupe.span, loupe.span)
                    live: true
                    smooth: false
                }

                // A fine crosshair with a gap in the middle, so the pixel you
                // are placing stays in view. Each arm: x, y, width, height.
                Repeater {
                    model: [[0, 63.5, 56, 1], [72, 63.5, 56, 1], [63.5, 0, 1, 56], [63.5, 72, 1, 56]]

                    delegate: Rectangle {
                        required property var modelData

                        x: modelData[0]
                        y: modelData[1]
                        width: modelData[2]
                        height: modelData[3]
                        color: Qt.alpha(Colors.accent, 0.6)
                    }
                }
                Rectangle {
                    anchors.centerIn: parent
                    width: 3
                    height: 3
                    radius: 1.5
                    color: Colors.accent
                }
            }

            // The ring, a breathing halo outside it, and the light on its top edge
            Rectangle {
                width: loupe.size
                height: loupe.size
                radius: width / 2
                antialiasing: true
                color: "transparent"
                border.width: 1.5
                border.color: Qt.alpha(Qt.tint(Colors.accent, Qt.alpha(shot.ringColor(shot.chase), 0.85 * shot.heat)), 0.9)

                EdgeLight {
                    corner: loupe.size / 2
                }
            }
            Rectangle {
                x: -5
                y: -5
                width: loupe.size + 10
                height: width
                radius: width / 2
                antialiasing: true
                color: "transparent"
                border.width: 1
                border.color: Qt.alpha(Colors.accent, 0.15 + 0.2 * shot.breath)
            }

            ShotPill {
                anchors.horizontalCenter: parent.horizontalCenter
                y: loupe.size + 8
                text: Math.round(shot.px * shot.dpr) + "  \u00b7  " + Math.round(shot.py * shot.dpr)
            }
        }

        // The pointer: what you point at, what you drag. The stage below
        // swallows its own clicks.
        MouseArea {
            id: overlay

            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            cursorShape: shot.cursorFor(shot.dragging ? shot.grab : shot.hoverGrab)
            onPositionChanged: mouse => {
                shot.px = mouse.x;
                shot.py = mouse.y;
                shot.noSnap = (mouse.modifiers & Qt.AltModifier) !== 0;
                if (pressed && shot.dragging)
                    shot.dragTo(mouse.x, mouse.y);
                else {
                    shot.hoverGrab = shot.hitAt(mouse.x, mouse.y);
                    shot.hoverAt(mouse.x, mouse.y);
                }
            }
            onPressed: mouse => {
                shot.px = mouse.x;
                shot.py = mouse.y;
                shot.noSnap = (mouse.modifiers & Qt.AltModifier) !== 0;
                if (mouse.button === Qt.LeftButton)
                    shot.pressAt(mouse.x, mouse.y);
            }
            onReleased: mouse => {
                if (mouse.button === Qt.LeftButton && shot.dragging)
                    shot.release();
            }
            onClicked: mouse => {
                if (mouse.button === Qt.RightButton) {
                    if (shot.mode === 0 && shot.hasSel)
                        shot.clearSel();
                    else
                        shot.close();
                } else if (shot.mode !== 0) {
                    shot.capture();
                }
            }
            onDoubleClicked: mouse => {
                if (mouse.button === Qt.LeftButton && shot.mode === 0 && shot.hasSel)
                    shot.capture();
            }
        }

        // ---- Stage ------------------------------------------------------
        Item {
            id: stage

            readonly property real cx: width / 2
            // Steps back while you drag, so it is not in the way of the picture
            property real fade: shot.dragging ? 0 : 1

            anchors.bottom: parent.bottom
            anchors.horizontalCenter: parent.horizontalCenter
            width: shot.stageW
            height: shot.bodyH
            clip: true
            opacity: Math.min(1, shot.reveal * 3) * fade
            visible: opacity > 0.01
            transform: Translate {
                y: (1 - shot.reveal) * (stage.height + 40)
            }

            Behavior on fade {
                NumberAnimation {
                    duration: Style.fadeMs
                }
            }

            // Feathered backing: a soft dark ellipse keeps the words and the
            // scale readable over any picture without a visible panel edge.
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

            // ---- The ruler: it turns with the dial, and the ticks by the
            // middle rise a little, like a magnifier ----------------------
            Repeater {
                // Not kept around while the panel is hidden
                model: shot.visible ? shot.tickN : 0

                delegate: Rectangle {
                    id: tick

                    required property int index

                    readonly property real s: (index - shot.tickN / 2) * shot.tickGap - (((shot.viewPos * shot.stepPx - shot.spinIn * shot.stepPx * 0.5) % (shot.tickGap * 10)) + shot.tickGap * 10) % (shot.tickGap * 10)
                    readonly property real a: s / shot.dialNow
                    readonly property real rr: shot.dialNow - shot.ruleDrop
                    readonly property bool major: index % 10 === 0
                    readonly property real near: Math.max(0, 1 - Math.abs(s) / 90)

                    x: stage.cx + rr * Math.sin(a) - 0.75
                    y: shot.topY + shot.dialNow - rr * Math.cos(a)
                    width: 1.5
                    height: (major ? 9 : 5) + 6 * near
                    radius: 0.75
                    antialiasing: true
                    visible: Math.abs(a) < 1.2
                    transformOrigin: Item.Top
                    rotation: a * 180 / Math.PI
                    color: Qt.tint(Qt.alpha(Colors.foreground, major ? 0.46 : 0.28), Qt.alpha(Colors.accent, 0.7 * near))
                    opacity: shot.clamp((stage.cx - Math.abs(x - stage.cx)) / 90, 0, 1) * shot.clamp(shot.reveal * 2 - Math.abs(x - stage.cx) / stage.cx * 0.9, 0, 1)
                }
            }

            // The middle of the ruler: the accent's 2px, standing where the
            // selected mode is.
            Rectangle {
                x: stage.cx - 1
                y: shot.ruleY - 3
                width: 2
                height: 16
                radius: 1
                color: Colors.accent
                opacity: shot.clamp(shot.reveal * 2 - 0.5, 0, 1)
            }

            // ---- The discs: Region, Window, Screen -------------------------
            Repeater {
                model: shot.modes

                delegate: Item {
                    id: slot

                    required property int index
                    required property var modelData

                    readonly property bool current: shot.mode === index
                    readonly property real rel: index - shot.viewPos
                    // Swung left while arriving, right while leaving
                    readonly property real s: (rel - shot.spinIn) * shot.stepPx
                    readonly property real a: s / shot.dialNow
                    // 0 at rest, 1 when selected. Animated, so the disc swells.
                    property real grow: current ? 1 : 0
                    // 0..1 while the ring around a newly selected disc expands
                    property real ping: 0
                    // 0 at rest, 1 under the pointer: a gentle lift
                    property real hover: area.containsMouse && !current ? 1 : 0
                    readonly property real sz: shot.discSize + (shot.selectedSize - shot.discSize) * grow
                    readonly property real dx: stage.cx + shot.dialNow * Math.sin(a)
                    // The selected one also lifts a little off the dial
                    readonly property real dy: shot.topY + shot.dialNow * (1 - Math.cos(a)) - 5 * grow
                    // Arrive in a left-to-right wave, each with a small overshoot
                    readonly property real appear: shot.clamp(shot.reveal * 2.2 - index * 0.12, 0, 1)
                    readonly property real edge: shot.clamp((stage.cx - Math.abs(dx - stage.cx)) / 90, 0, 1)

                    visible: opacity > 0.01
                    width: sz
                    height: sz
                    x: dx - sz / 2
                    y: dy - sz / 2
                    z: current ? 20 : 10
                    opacity: appear * edge
                    scale: 0.55 + 0.45 * shot.backOut(appear)
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
                    onCurrentChanged: if (current && shot.isOpen && shot.reveal > 0.8)
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
                        border.color: Qt.alpha(Colors.accent, slot.grow * (0.25 + 0.25 * shot.breath))
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
                    EdgeLight {
                        corner: slot.width / 2
                    }

                    ShotGlyph {
                        anchors.centerIn: parent
                        width: slot.sz * 0.42
                        height: width
                        kind: slot.modelData.id
                        color: slot.current ? Colors.accent : Colors.foreground
                        opacity: slot.current ? 1 : 0.8
                        // Stays upright while the disc tilts with the dial
                        rotation: -slot.rotation
                    }

                    MouseArea {
                        id: area

                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: shot.mode = slot.index
                    }
                }
            }

            // Accent underline under the selected disc; it breathes with the ring.
            Rectangle {
                readonly property real rel: shot.mode - shot.viewPos
                readonly property real a: (rel - shot.spinIn) * shot.stepPx / shot.dialNow

                width: 20 + 10 * shot.breath
                height: 2
                radius: 1
                color: Colors.accent
                x: stage.cx + shot.dialNow * Math.sin(a) - width / 2
                y: shot.topY + shot.dialNow * (1 - Math.cos(a)) - 5 + shot.selectedSize / 2 + 6
                rotation: a * 180 / Math.PI
                opacity: shot.clamp(shot.reveal * 2 - 0.6, 0, 1)
            }

            // ---- The middle: the mode, and what it will capture ---------------
            Item {
                id: readout

                x: stage.cx - width / 2
                y: shot.readoutTop
                width: Math.min(480, stage.width - 48)
                height: 52
                opacity: (0.25 + 0.75 * shot.swap) * shot.phase(0.25, 0.8)
                transform: Translate {
                    y: (1 - shot.phase(0.25, 0.8)) * 12 + (1 - shot.swap) * 6
                }

                // The mode, with a soft shadow in the background colour so it reads on any picture
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

                        text: shot.current.label
                        color: Colors.foreground
                        font.pixelSize: 22
                        font.bold: true
                        font.letterSpacing: -0.2
                    }
                }

                // The same keys, as buttons: they turn the dial
                KeyCap {
                    anchors.verticalCenter: nameBox.verticalCenter
                    anchors.right: nameBox.left
                    anchors.rightMargin: 18
                    label: "\u2190"

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: shot.turn(-1)
                    }
                }

                KeyCap {
                    anchors.verticalCenter: nameBox.verticalCenter
                    anchors.left: nameBox.right
                    anchors.leftMargin: 18
                    label: "\u2192"

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: shot.turn(1)
                    }
                }

                // What it will capture: the size, the window, the monitor
                Txt {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: nameBox.bottom
                    anchors.topMargin: 8
                    width: Math.min(implicitWidth, parent.width)
                    elide: Text.ElideRight
                    horizontalAlignment: Text.AlignHCenter
                    text: shot.detail
                    color: shot.hasTarget ? Colors.foreground : Colors.muted
                    style: Text.Outline
                    styleColor: Qt.alpha(Colors.background, 0.85)
                    font.pixelSize: Style.fontMd
                }
            }

            // ---- Where it goes, and Capture ---------------------------------
            Row {
                id: buttons

                x: stage.cx - width / 2
                y: stage.height - shot.foot - Style.buttonHeight
                spacing: Style.spaceMd
                opacity: shot.phase(0.35, 0.9)

                TextButton {
                    glyph: Icons.copy
                    text: "Copy"
                    primary: shot.toClipboard
                    onClicked: shot.toggleCopy()
                }

                TextButton {
                    glyph: Icons.folder
                    text: "Save"
                    primary: shot.toFile
                    onClicked: shot.toggleSave()
                }

                // A hairline between where it goes and the thing that does it
                Item {
                    width: 1
                    height: Style.buttonHeight

                    Rectangle {
                        anchors.centerIn: parent
                        width: 1
                        height: 18
                        color: Style.outline
                    }
                }

                ShotGo {
                    enabled: shot.hasTarget && !shot.capturing
                    breath: shot.breath
                    glyph: Icons.check
                    text: "Capture"
                    onClicked: shot.capture()
                }
            }
        }
    }
}
