// NotificationCenter.qml
// Notification history on the launcher's dial: the same borderless stage
// rising from the bottom edge, the same fine ruler, glass discs and accent
// underline.
// Every notification is a disc along the dial (its picture, its app's icon, or
// the app's first letter), newest on the left, the apps kept together with a
// small gap between them. The selected one sits big in the middle with the
// accent underline under it, and its words are read out below the ruler: the
// app and how long ago, the summary, the body. An accent dot marks what
// arrived since you last looked; an urgent one is ringed in the alert red.
// Under the readout: do not disturb, copy the text, the notification's own
// actions (two at most), dismiss, clear this app, clear all.
//   qs ipc call notifications toggle | open | close | clear | dnd
// Keys: ← → (h l, Tab, Ctrl+N / Ctrl+P) turn the dial   PageUp / PageDown jump
//       Home / End first / last   Delete (Backspace, x) dismiss
//       Shift+X clear the whole app   d do not disturb   esc close
//       Enter runs the first action (1 2 pick one)   c copy the text
//       Space reads the whole text (the dial lifts to make room)
//       Shift+← / Shift+→ jump to the previous / next app
//       Shift+D silence for an hour (d toggles do not disturb as before)
// Holding Delete, x, Enter, 1, 2, c, d or Space does not repeat: one press, one thing.
// Mouse: click a disc to bring it to the middle, scroll wheel turns the dial,
//        the buttons under the readout do the rest. Running an action tells
//        the app, removes the entry and closes the centre. Clear all needs a second
//        press. DND silences new toasts but they are still recorded here.
//
// Like the launcher it arrives as a rainbow: the discs swing in from the left
// over a tight dome and unfurl into the calm dial. Closing plays it in
// reverse. A dismissed disc shrinks away and its neighbours close the gap.
//
// Like the other dials this window is only as big as the stage, so the mouse
// still reaches other windows while it is open. The keyboard is the centre's
// until it closes (Esc).

import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland

PanelWindow {
    id: center

    // Opens on the monitor that has focus, and stays there while it is open
    property var targetScreen: Focus.screen

    // ---- Settings -------------------------------------------------------
    readonly property real screenW: targetScreen ? targetScreen.width : 1920
    readonly property int stageW: Math.min(780, Math.round(screenW * 0.9))
    readonly property int baseH: 300
    // Extra room (and the dial lifting to make it) while a long text is read in full
    readonly property int expandH: 112
    readonly property int stageH: baseH + (expanded ? expandH : 0)
    readonly property int topY: 54
    readonly property int ruleDrop: 46
    readonly property int ruleY: topY + ruleDrop
    readonly property real dialR: 900
    // The dome the dial starts as when it opens (and ends as when it closes)
    readonly property real rainbowR: 360
    // Pixels between discs, and the extra gap (in discs) between two apps
    readonly property real stepPx: 76
    readonly property real groupGap: 0.45
    readonly property int discSize: 48
    readonly property int selectedSize: 68
    readonly property int tickGap: 12
    readonly property int tickN: Math.ceil(stageW / tickGap) + 24
    // How long a dismissed disc takes to shrink away, in ms
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
    // The highlighted entry, by id, so it stays put while discs come and go
    property var selId: ""
    // Ids of entries that are shrinking away before they are removed for real
    property var leaving: ({})
    // The Clear all button has been pressed once
    property bool clearArmed: false
    // Entries newer than this get the accent dot
    property double lastClosed: Date.now()
    property double newSince: 0
    // Whether the dial glides to a new selection (off while opening)
    property bool animateView: false
    // The text was just copied (the button shows a tick for a moment)
    property bool copied: false
    // The whole text of the selected notification is showing
    property bool expanded: false
    // Wheel movement not yet turned into a step (a touchpad sends many small ones)
    property real wheelAcc: 0

    // Radius of the dial right now: curvature eases from the dome to the dial
    readonly property real dialNow: 1 / (1 / dialR + (1 / rainbowR - 1 / dialR) * fan)

    // One entry per notification, in dial order. `pos` is where it sits along
    // the dial in disc units; a dismissed one shares the spot of the next, so
    // its neighbours close the gap while it shrinks.
    readonly property var entries: {
        const lv = leaving;
        const out = [];
        let g = -1;
        let idx = 0;
        for (const r of NotificationServer.grouped) {
            if (r.header === true) {
                g++;
                continue;
            }
            // Keyed by id and arrival time: an app that replaces a notification
            // while it is shrinking away must not lose the new one with it
            const gone = lv[r.id] === r.time;
            out.push({
                "id": r.id,
                "m": r,
                "gone": gone,
                "pos": idx + groupGap * g
            });
            if (!gone)
                idx++;
        }
        return out;
    }
    readonly property int total: NotificationServer.history.length
    readonly property int selIndex: indexOfId(selId)
    readonly property var cur: selIndex >= 0 ? entries[selIndex].m : null
    readonly property bool selCritical: cur !== null && cur.critical === true
    readonly property color tint: selCritical ? Colors.critical : Colors.accent
    readonly property real targetPos: selIndex >= 0 ? entries[selIndex].pos : 0
    // Where the dial is turned to; glides to the selected entry
    property real viewPos: targetPos
    // How many entries the selected one's app has
    readonly property int groupCount: {
        if (cur === null)
            return 0;
        let n = 0;
        for (const e of entries) {
            if (!e.gone && e.m.appName === cur.appName)
                n++;
        }
        return n;
    }
    // Position among the ones still here, for the readout
    readonly property int humanIndex: {
        let n = 0;
        for (let i = 0; i <= selIndex && i < entries.length; i++) {
            if (!entries[i].gone)
                n++;
        }
        return n;
    }
    // The selected notification's own buttons, two at most. An app that only
    // offers the click on the notification ("default") gets one, "Open". Empty
    // once the app has taken the notification back.
    readonly property var curActions: {
        const c = cur;
        if (c === null || !c.ref)
            return [];
        const all = c.actions || [];
        const own = all.filter(a => a.id !== "default" && a.text !== "");
        if (own.length === 0 && all.some(a => a.id === "default"))
            return [
                {
                    "id": "default",
                    "text": "Open"
                }
            ];
        return own.slice(0, 2);
    }
    // What the empty centre says about do not disturb
    readonly property string dndText: {
        if (!NotificationServer.doNotDisturb)
            return "New ones will show up here.";
        if (NotificationServer.dndUntil > 0)
            return "Do not disturb until " + Qt.formatTime(new Date(NotificationServer.dndUntil), "HH:mm") + ".";
        return "Do not disturb is on.";
    }
    readonly property int liveCount: {
        let n = 0;
        for (const e of entries) {
            if (!e.gone)
                n++;
        }
        return n;
    }

    Behavior on viewPos {
        enabled: center.animateView

        // The dial glides into place and settles, with no bounce
        NumberAnimation {
            duration: Style.enterMs
            easing.type: Style.easeEnter
        }
    }

    onEntriesChanged: fixSel()
    onSelIdChanged: {
        copied = false;
        expanded = false;
        if (isOpen)
            swapAnim.restart();
    }

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

    // ---- Selection ------------------------------------------------------
    function indexOfId(id) {
        const g = entries;
        for (let i = 0; i < g.length; i++) {
            if (g[i].id === id)
                return i;
        }
        return -1;
    }

    function firstEntryId() {
        const g = entries;
        for (let i = 0; i < g.length; i++) {
            if (!g[i].gone)
                return g[i].id;
        }
        return "";
    }

    // The entry to land on when `id` goes away: the next one, else the previous
    function neighborId(id) {
        const g = entries;
        const at = indexOfId(id);
        for (let i = at + 1; i < g.length; i++) {
            if (!g[i].gone)
                return g[i].id;
        }
        for (let i = at - 1; i >= 0; i--) {
            if (!g[i].gone)
                return g[i].id;
        }
        return "";
    }

    // The nearest entry that is not from `appName`, for when a whole app goes
    function neighborOutside(appName) {
        const g = entries;
        const at = Math.max(0, selIndex);
        for (let i = at; i < g.length; i++) {
            if (!g[i].gone && g[i].m.appName !== appName)
                return g[i].id;
        }
        for (let i = at; i >= 0; i--) {
            if (!g[i].gone && g[i].m.appName !== appName)
                return g[i].id;
        }
        return "";
    }

    function stepOne(dir) {
        const g = entries;
        let i = selIndex;
        if (i < 0)
            i = dir > 0 ? -1 : g.length;
        for (let j = i + dir; j >= 0 && j < g.length; j += dir) {
            if (!g[j].gone) {
                selId = g[j].id;
                return;
            }
        }
    }

    function step(n) {
        const dir = n > 0 ? 1 : -1;
        for (let k = 0; k < Math.abs(n); k++)
            stepOne(dir);
    }

    // First entry of the previous (dir < 0) or next (dir > 0) app
    function stepGroup(dir) {
        const g = entries;
        const at = selIndex;
        if (at < 0)
            return;
        const app = g[at].m.appName;
        if (dir > 0) {
            for (let i = at + 1; i < g.length; i++) {
                if (!g[i].gone && g[i].m.appName !== app) {
                    selId = g[i].id;
                    return;
                }
            }
            return;
        }
        let j = at - 1;
        while (j >= 0 && (g[j].gone || g[j].m.appName === app))
            j--;
        if (j < 0)
            return;
        const prev = g[j].m.appName;
        while (j > 0 && g[j - 1].m.appName === prev)
            j--;
        for (let i = j; i < g.length; i++) {
            if (!g[i].gone && g[i].m.appName === prev) {
                selId = g[i].id;
                return;
            }
        }
    }

    function jumpTo(last) {
        const g = entries;
        if (last) {
            for (let i = g.length - 1; i >= 0; i--) {
                if (!g[i].gone) {
                    selId = g[i].id;
                    return;
                }
            }
        } else {
            selId = firstEntryId();
        }
    }

    // Keep the highlight on something after the list changed under it
    function fixSel() {
        if (indexOfId(selId) < 0)
            selId = firstEntryId();
    }

    // ---- Removing -------------------------------------------------------
    // Discs shrink first, then all of them are removed in one go
    function queueRemove(ids) {
        const t = {};
        for (const n of NotificationServer.history)
            t[n.id] = n.time;
        const m = Object.assign({}, leaving);
        for (const id of ids) {
            if (t[id] !== undefined)
                m[id] = t[id];
        }
        leaving = m;
        commitTimer.restart();
    }

    function commit() {
        const m = leaving;
        // Tell the apps these were closed by the user, and let go of them
        for (const n of NotificationServer.history) {
            if (m[n.id] === n.time)
                NotificationServer.release(n);
        }
        NotificationServer.history = NotificationServer.history.filter(n => m[n.id] !== n.time);
        leaving = ({});
    }

    // Everything at once, for the IPC call: with the centre open the discs
    // shrink away like they do for Clear all, otherwise it is just emptied
    function clearAll() {
        if (!isOpen) {
            NotificationServer.clearHistory();
            return;
        }
        const ids = [];
        for (const n of NotificationServer.history)
            ids.push(n.id);
        queueRemove(ids);
        selId = "";
        NotificationServer.unread = 0;
    }

    function dismiss(id) {
        if (id === selId)
            selId = neighborId(id);
        queueRemove([id]);
    }

    function removeSel() {
        if (selIndex >= 0)
            dismiss(selId);
    }

    // Run one of the selected notification's actions: the app is told, the
    // entry goes, and the centre gets out of the way of whatever opens.
    function runAction(actionId) {
        const c = cur;
        if (c === null)
            return;
        NotificationServer.invokeAction(c, actionId);
        dismiss(c.id);
        close();
    }

    // Put the selected notification's text on the clipboard (a code, a link)
    function copyBody() {
        const c = cur;
        if (c === null)
            return;
        const t = c.body !== "" ? c.body : c.summary;
        if (t === "")
            return;
        // `--`: text that starts with a dash is not an option
        Quickshell.execDetached(["wl-copy", "--", t]);
        copied = true;
        copiedTimer.restart();
    }

    // Every entry of one app
    function dismissGroup(appName) {
        const ids = [];
        for (const n of NotificationServer.history) {
            if (n.appName === appName)
                ids.push(n.id);
        }
        const next = neighborOutside(appName);
        queueRemove(ids);
        selId = next;
    }

    function requestClear() {
        if (!clearArmed) {
            clearArmed = true;
            clearTimer.restart();
            return;
        }
        clearArmed = false;
        const ids = [];
        for (const e of entries)
            ids.push(e.id);
        queueRemove(ids);
        selId = "";
    }

    // ---- Open and close -------------------------------------------------
    function open() {
        if (isOpen)
            return;
        targetScreen = Focus.screen;
        closeAnim.stop();
        newSince = lastClosed;
        clearArmed = false;
        expanded = false;
        wheelAcc = 0;
        leaving = ({});
        // The dial starts on the right entry instead of gliding there. The
        // discs are only built once the centre is open (see the Repeater), so
        // this is settled before they exist.
        animateView = false;
        selId = firstEntryId();
        animateView = true;
        // Fully hidden: start from the dome. Re-opened while it was still
        // leaving: carry on from where it is instead of snapping away first.
        if (reveal <= 0.001) {
            reveal = 0;
            spinIn = 3.2;
            fan = 1;
        }
        isOpen = true;
        NotificationServer.centerOpen = true;
        NotificationServer.markRead();
        openAnim.restart();
        keys.forceActiveFocus();
    }

    function close() {
        if (!isOpen)
            return;
        isOpen = false;
        lastClosed = Date.now();
        NotificationServer.centerOpen = false;
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
        windows: [center]
        active: center.isOpen && center.visible
        onCleared: {
            center.closedAt = Date.now();
            center.close();
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
    WlrLayershell.namespace: "qs-notifications"
    // Exclusive, like the power menu and launcher: the keys work the moment it
    // opens, without clicking it first (on demand only focuses it on a click).
    WlrLayershell.keyboardFocus: isOpen ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    Connections {
        target: Panels

        function onToggleNotifications() {
            center.toggle();
        }
    }

    IpcHandler {
        function toggle() {
            center.toggle();
        }

        function open() {
            center.open();
        }

        function close() {
            center.close();
        }

        function clear() {
            center.clearAll();
        }

        function dnd() {
            NotificationServer.toggleDnd();
        }

        target: "notifications"
    }

    // Keeps the "5m" labels current
    SystemClock {
        id: clock

        precision: SystemClock.Minutes
        // Only the open centre shows these labels; it catches up the moment it opens
        enabled: center.isOpen
    }

    Timer {
        id: commitTimer

        interval: center.collapseMs + 10
        onTriggered: center.commit()
    }

    Timer {
        id: copiedTimer

        interval: 1400
        onTriggered: center.copied = false
    }

    Timer {
        id: clearTimer

        interval: 3000
        onTriggered: center.clearArmed = false
    }

    PanelLink {
        win: center
        name: "notifications"
    }

    // Rises smoothly. The discs swing in from the left over a tight dome and
    // unfurl into the dial.
    ParallelAnimation {
        id: openAnim

        NumberAnimation {
            target: center
            property: "reveal"
            to: 1
            duration: Style.sweepMs
            easing.type: Style.easeEnter
        }
        NumberAnimation {
            target: center
            property: "spinIn"
            to: 0
            duration: Style.sweepMs + Style.moveMs
            easing.type: Style.easeEnter
        }
        NumberAnimation {
            target: center
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
            target: center
            property: "reveal"
            to: 0
            duration: Style.moveMs + Style.fadeMs
            easing.type: Style.easeExit
        }
        NumberAnimation {
            target: center
            property: "spinIn"
            to: -3.2
            duration: Style.moveMs + Style.fadeMs
            easing.type: Style.easeExit
        }
        NumberAnimation {
            target: center
            property: "fan"
            to: 1
            duration: Style.moveMs + Style.fadeMs
            easing.type: Style.easeExit
        }
    }

    // Slow breath for the ring around the selected disc.
    SequentialAnimation {
        running: center.isOpen
        loops: Animation.Infinite

        NumberAnimation {
            target: center
            property: "breath"
            from: 0
            to: 1
            duration: Style.ambientMs * 2
            easing.type: Style.easeAmbient
        }
        NumberAnimation {
            target: center
            property: "breath"
            from: 1
            to: 0
            duration: Style.ambientMs * 2
            easing.type: Style.easeAmbient
        }
    }

    // A different notification is selected: the words fade up
    NumberAnimation {
        id: swapAnim

        target: center
        property: "swap"
        from: 0
        to: 1
        duration: Style.baseMs
        easing.type: Style.easeMove
    }

    Item {
        id: keys

        anchors.fill: parent
        focus: center.isOpen
        Keys.onPressed: event => {
            const k = event.key;
            const ctrl = (event.modifiers & Qt.ControlModifier) !== 0;
            const shift = (event.modifiers & Qt.ShiftModifier) !== 0;
            const plain = event.modifiers === Qt.NoModifier;
            // Turning the dial may repeat; removing, running or toggling
            // something must not, or a held key would sweep the whole log away
            if (event.isAutoRepeat && (k === Qt.Key_Delete || k === Qt.Key_Backspace || k === Qt.Key_X || k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_1 || k === Qt.Key_2 || k === Qt.Key_C || k === Qt.Key_D || k === Qt.Key_Space || k === Qt.Key_Escape)) {
                event.accepted = true;
                return;
            }
            if (k === Qt.Key_Escape)
                center.close();
            else if (shift && k === Qt.Key_Right)
                center.stepGroup(1);
            else if (shift && k === Qt.Key_Left)
                center.stepGroup(-1);
            else if (k === Qt.Key_Right || k === Qt.Key_Down || k === Qt.Key_Tab || (plain && (k === Qt.Key_L || k === Qt.Key_J)) || (ctrl && k === Qt.Key_N))
                center.step(1);
            else if (k === Qt.Key_Left || k === Qt.Key_Up || k === Qt.Key_Backtab || (plain && (k === Qt.Key_H || k === Qt.Key_K)) || (ctrl && k === Qt.Key_P))
                center.step(-1);
            else if (k === Qt.Key_PageDown)
                center.step(4);
            else if (k === Qt.Key_PageUp)
                center.step(-4);
            else if (k === Qt.Key_Home)
                center.jumpTo(false);
            else if (k === Qt.Key_End)
                center.jumpTo(true);
            else if (shift && k === Qt.Key_X) {
                if (center.cur)
                    center.dismissGroup(center.cur.appName);
            } else if (k === Qt.Key_Delete || k === Qt.Key_Backspace || (plain && k === Qt.Key_X))
                center.removeSel();
            else if (shift && k === Qt.Key_D)
                NotificationServer.dndFor(60);
            else if (plain && k === Qt.Key_Space)
                center.expanded = !center.expanded && bodyText.truncated;
            else if (plain && k === Qt.Key_D)
                NotificationServer.toggleDnd();
            else if (plain && k === Qt.Key_C)
                center.copyBody();
            else if ((k === Qt.Key_Return || k === Qt.Key_Enter) && center.curActions.length > 0)
                center.runAction(center.curActions[0].id);
            else if (plain && k === Qt.Key_1 && center.curActions.length > 0)
                center.runAction(center.curActions[0].id);
            else if (plain && k === Qt.Key_2 && center.curActions.length > 1)
                center.runAction(center.curActions[1].id);
            else
                return;
            event.accepted = true;
        }
    }

    // The shared dim (Dim.qml): the same wash as the screenshot tool
    Dim {
        reveal: center.reveal
        closes: true
        onClicked: center.close()
    }

    // ---- Stage ----------------------------------------------------------
    Item {
        id: stage

        readonly property real cx: width / 2

        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        width: center.stageW
        height: center.stageH
        clip: true
        opacity: Math.min(1, center.reveal * 3)
        transform: Translate {
            y: (1 - center.reveal) * (center.stageH + 40)
        }

        // Scroll wheel turns the dial
        MouseArea {
            anchors.fill: parent
            onWheel: wheel => {
                const d = wheel.angleDelta.y !== 0 ? wheel.angleDelta.y : -wheel.angleDelta.x;
                if (d === 0)
                    return;
                // One step per notch (120). A touchpad sends many small
                // deltas; counting them keeps one swipe from spinning the dial
                // through the whole log.
                if ((d < 0) !== (center.wheelAcc < 0))
                    center.wheelAcc = 0;
                center.wheelAcc += d;
                while (center.wheelAcc <= -120) {
                    center.step(1);
                    center.wheelAcc += 120;
                }
                while (center.wheelAcc >= 120) {
                    center.step(-1);
                    center.wheelAcc -= 120;
                }
            }
        }

        // Feathered backing: a soft dark ellipse keeps the words and the scale
        // readable over any wallpaper without a visible panel edge.
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
                yScale: 0.62
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

        // Low light in the colour of the selected entry: the accent, or red
        // while an urgent one is selected.
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
                        color: Qt.alpha(center.tint, 0.18)
                    }
                    GradientStop {
                        position: 0.5
                        color: Qt.alpha(center.tint, 0.07)
                    }
                    GradientStop {
                        position: 1
                        color: Qt.alpha(center.tint, 0)
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
            // Not kept around while the centre is hidden
            model: center.visible ? center.tickN : 0

            delegate: Rectangle {
                id: tick

                required property int index

                readonly property real s: (index - center.tickN / 2) * center.tickGap - center.mod(center.viewPos * center.stepPx - center.spinIn * center.stepPx * 0.5, center.tickGap * 10)
                readonly property real a: s / center.dialNow
                readonly property real rr: center.dialNow - center.ruleDrop
                readonly property bool major: index % 10 === 0
                readonly property real near: Math.max(0, 1 - Math.abs(s) / 90)

                x: stage.cx + rr * Math.sin(a) - 0.75
                y: center.topY + center.dialNow - rr * Math.cos(a)
                width: 1.5
                height: (major ? 9 : 5) + 6 * near
                radius: 0.75
                antialiasing: true
                visible: Math.abs(a) < 1.2
                transformOrigin: Item.Top
                rotation: a * 180 / Math.PI
                color: Qt.tint(Qt.alpha(Colors.foreground, major ? 0.46 : 0.28), Qt.alpha(center.tint, 0.7 * near))
                opacity: center.clamp((stage.cx - Math.abs(x - stage.cx)) / 90, 0, 1) * center.clamp(center.reveal * 2 - Math.abs(x - stage.cx) / stage.cx * 0.9, 0, 1)
            }
        }

        // The middle of the ruler: the accent's 2px, standing where the
        // selected entry is.
        Rectangle {
            x: stage.cx - 1
            y: center.ruleY - 3
            width: 2
            height: 16
            radius: 1
            color: center.tint
            opacity: center.clamp(center.reveal * 2 - 0.5, 0, 1)
        }

        // ---- The discs --------------------------------------------------
        Repeater {
            // The discs only exist while the centre is on screen: hidden, there
            // is nothing to draw, and a log of 100 would otherwise be kept
            // up to date for nothing every time a notification arrives.
            model: ScriptModel {
                values: center.visible ? center.entries : []
                objectProp: "id"
            }

            delegate: Item {
                id: slot

                required property var modelData

                readonly property var m: modelData ? modelData.m : null
                // Animated, so the neighbours of a dismissed disc glide closed
                property real pos: modelData ? modelData.pos : 0
                readonly property bool current: modelData ? modelData.id === center.selId : false
                readonly property bool critical: m ? m.critical === true : false
                readonly property bool fresh: m ? m.time > center.newSince : false
                // Pictures and icons load only for discs near the middle: the
                // rest are out of sight, and a full log of pictures is a lot
                // to decode for nothing. The window is wider than what is shown.
                readonly property bool near: Math.abs(rel) < 10
                readonly property string appIcon: m ? NotificationServer.appIconSource(m) : ""
                readonly property bool hasPicture: m ? m.image !== "" : false
                // The picture can stop loading once its app has taken the
                // notification back; the disc then falls back to the app's
                // icon or letter instead of staying blank.
                readonly property bool photo: hasPicture && slotPhoto.status !== Image.Error
                readonly property real rel: pos - center.viewPos
                // Swung left while arriving, right while leaving
                readonly property real s: (rel - center.spinIn) * center.stepPx
                readonly property real a: s / center.dialNow
                // 0 at rest, 1 when selected. Animated, so the disc swells.
                property real grow: current ? 1 : 0
                // 0 -> 1 while the disc shrinks away after being dismissed
                property real gone: modelData && modelData.gone ? 1 : 0
                // 0..1 while the ring around a newly selected disc expands
                property real ping: 0
                readonly property real sz: center.discSize + (center.selectedSize - center.discSize) * grow
                readonly property real px: stage.cx + center.dialNow * Math.sin(a)
                // The selected one also lifts a little off the dial
                readonly property real py: center.topY + center.dialNow * (1 - Math.cos(a)) - 5 * grow
                // Arrive in a left-to-right wave, each with a small overshoot
                readonly property real appear: center.clamp(center.reveal * 2.2 - (center.clamp(rel, -6, 6) + 6) * 0.09, 0, 1)
                readonly property real edge: center.clamp((stage.cx - Math.abs(px - stage.cx)) / 90, 0, 1)
                readonly property color ringColor: critical ? Colors.critical : Colors.accent

                visible: Math.abs(rel) < 7 && opacity > 0.01
                width: sz
                height: sz
                x: px - sz / 2
                y: py - sz / 2
                z: current ? 20 : 10
                opacity: appear * edge * (1 - gone)
                scale: (0.55 + 0.45 * center.backOut(appear)) * (1 - 0.7 * gone)
                // Tilts along the dial, and rises from below as it arrives
                rotation: a * 180 / Math.PI * 0.6
                transform: Translate {
                    y: (1 - slot.appear) * 30
                }

                Behavior on pos {
                    enabled: center.isOpen && center.reveal > 0.8

                    NumberAnimation {
                        duration: Style.moveMs
                        easing.type: Style.easeMove
                    }
                }

                Behavior on gone {
                    NumberAnimation {
                        duration: center.collapseMs
                        easing.type: Style.easeExit
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
                onCurrentChanged: if (current && center.isOpen && center.reveal > 0.8)
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
                    border.color: Qt.alpha(slot.ringColor, 0.5 * (1 - slot.ping))
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
                    border.color: Qt.alpha(slot.ringColor, slot.grow * (0.25 + 0.25 * center.breath))
                }

                // Glass, like the bar: one flat surface with a hairline
                // outline, lit in the entry's colour once selected. An urgent
                // one is red even at rest.
                Rectangle {
                    anchors.fill: parent
                    radius: width / 2
                    antialiasing: true
                    color: Style.card
                    border.width: 1
                    border.color: slot.current ? Qt.alpha(slot.ringColor, 0.9) : (slot.critical ? Qt.alpha(Colors.critical, 0.65) : Qt.alpha(Colors.foreground, 0.32))

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
                    color: Qt.alpha(slot.ringColor, slot.current ? Style.tintAlpha : (slot.critical ? Style.tintAlpha * 0.6 : 0))

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

                // The notification's own picture, in a circle
                Photo {
                    id: slotPhoto

                    anchors.fill: parent
                    anchors.margins: 4
                    visible: slot.photo
                    radius: width / 2
                    source: slot.hasPicture && slot.near ? slot.m.image : ""
                    // Stays upright while the disc tilts with the dial
                    rotation: -slot.rotation
                }

                // The app's icon
                Image {
                    id: slotImg

                    anchors.fill: parent
                    anchors.margins: slot.sz * 0.24
                    visible: slot.appIcon !== "" && !slot.photo && status === Image.Ready
                    source: slot.photo || !slot.near ? "" : slot.appIcon
                    sourceSize.width: 96
                    sourceSize.height: 96
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                    rotation: -slot.rotation
                }

                // Or the app's first letter
                Txt {
                    anchors.centerIn: parent
                    visible: slot.photo ? false : !(slot.appIcon !== "" && slotImg.status === Image.Ready)
                    text: slot.m ? NotificationServer.initial(slot.m.appName) : ""
                    color: slot.critical ? Colors.critical : (slot.current ? Colors.accent : Colors.foreground)
                    font.pixelSize: slot.sz * 0.38
                    font.bold: true
                    rotation: -slot.rotation

                    Behavior on color {
                        ColorAnimation {
                            duration: Style.fadeMs
                        }
                    }
                }

                // Arrived since you last looked
                Rectangle {
                    x: parent.width * 0.72
                    y: parent.height * 0.02
                    width: 12
                    height: 12
                    radius: 6
                    antialiasing: true
                    color: Colors.accent
                    border.width: 2
                    border.color: Style.card
                    opacity: slot.fresh ? 1 : 0
                    scale: slot.fresh ? 1 : 0.4

                    Behavior on opacity {
                        NumberAnimation {
                            duration: Style.baseMs
                        }
                    }
                    Behavior on scale {
                        NumberAnimation {
                            duration: Style.baseMs
                            easing.type: Style.easeMove
                        }
                    }
                }

                // Click to bring it to the middle. Position, not hover, so the
                // dial never turns under a mouse you are only passing over.
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: if (slot.modelData)
                        center.selId = slot.modelData.id
                }
            }
        }

        // Nothing here: one quiet disc in the middle, in place of the dial
        Item {
            id: emptyDisc

            readonly property real appear: center.stage_(0.1, 0.6)

            x: stage.cx - width / 2
            y: center.topY - 5 - height / 2
            width: center.selectedSize
            height: center.selectedSize
            opacity: center.total === 0 ? appear : 0
            visible: opacity > 0.01
            scale: 0.55 + 0.45 * center.backOut(appear)

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
                border.color: NotificationServer.doNotDisturb ? Qt.alpha(Colors.accent, 0.8) : Qt.alpha(Colors.foreground, 0.2)

                Behavior on border.color {
                    ColorAnimation {
                        duration: Style.baseMs
                    }
                }
            }

            Txt {
                anchors.centerIn: parent
                text: NotificationServer.doNotDisturb ? Icons.bellOff : Icons.bell
                color: NotificationServer.doNotDisturb ? Colors.accent : Colors.muted
                font.pixelSize: 24
            }
        }

        // Accent underline under the selected disc; it breathes with the ring.
        Rectangle {
            readonly property real rel: center.targetPos - center.viewPos
            readonly property real a: (rel - center.spinIn) * center.stepPx / center.dialNow

            visible: center.total > 0
            width: 20 + 10 * center.breath
            height: 2
            radius: 1
            color: center.tint
            x: stage.cx + center.dialNow * Math.sin(a) - width / 2
            y: center.topY + center.dialNow * (1 - Math.cos(a)) - 5 + center.selectedSize / 2 + 6
            rotation: a * 180 / Math.PI
            opacity: center.clamp(center.reveal * 2 - 0.6, 0, 1)
        }

        // ---- The middle: what the selected notification says -----------------
        Item {
            id: readout

            x: stage.cx - width / 2
            y: center.ruleY + 30
            width: Math.min(460, stage.width - 48)
            height: 124 + (center.expanded ? center.expandH : 0)
            // Clicks pass through to the dial
            enabled: false
            opacity: (0.25 + 0.75 * center.swap) * center.stage_(0.25, 0.8)
            transform: Translate {
                y: (1 - center.stage_(0.25, 0.8)) * 12 + (1 - center.swap) * 6
            }

            Column {
                width: parent.width
                spacing: 4

                // Which app, how long ago, and where it is in the history
                Txt {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    visible: text !== ""
                    elide: Text.ElideRight
                    text: {
                        const c = center.cur;
                        if (c === null)
                            return "";
                        let t = (c.critical ? "Urgent  ·  " : "") + c.appName + "  ·  " + NotificationServer.ago(c.time, clock.date);
                        if (center.liveCount > 1)
                            t += "  ·  " + center.humanIndex + "/" + center.liveCount;
                        return t;
                    }
                    // Brighter than the muted grey, with a thin outline in the
                    // background colour: it stays readable over any wallpaper
                    color: center.selCritical ? Colors.critical : Qt.alpha(Colors.foreground, 0.78)
                    style: Text.Outline
                    styleColor: Qt.alpha(Colors.background, 0.85)
                    font.pixelSize: Style.fontSm
                    font.letterSpacing: 1.4
                    font.capitalization: Font.AllUppercase
                }

                // The summary, with a soft shadow in the background colour so it reads on any wallpaper
                Item {
                    width: parent.width
                    height: summary.implicitHeight
                    visible: summary.text !== ""

                    Txt {
                        y: 1.5
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.Wrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                        text: summary.text
                        color: Qt.alpha(Colors.background, 0.9)
                        font.pixelSize: Style.fontXl
                        font.bold: true
                    }

                    Txt {
                        id: summary

                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.Wrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                        text: center.cur ? center.cur.summary : "No notifications"
                        color: Colors.foreground
                        font.pixelSize: Style.fontXl
                        font.bold: true
                    }
                }

                Txt {
                    id: bodyText

                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    visible: text !== ""
                    wrapMode: Text.Wrap
                    maximumLineCount: center.expanded ? 9 : 3
                    elide: Text.ElideRight
                    text: center.cur ? center.cur.body : center.dndText
                    // The words of the notification are what you came for:
                    // near the foreground colour, outlined for any wallpaper
                    color: Qt.alpha(Colors.foreground, 0.86)
                    style: Text.Outline
                    styleColor: Qt.alpha(Colors.background, 0.8)
                    font.pixelSize: Style.fontBase
                }
            }
        }

        // ---- Under the readout: the few things you can do --------------------
        Row {
            id: controls

            x: stage.cx - width / 2
            y: center.stageH - Style.buttonCompact - 16
            spacing: Style.spaceMd
            // Long labels are cut (below); this is the net under that: if the
            // row is still wider than the stage it shrinks to fit
            scale: Math.min(1, (stage.width - 32) / Math.max(1, controls.implicitWidth))
            opacity: center.stage_(0.35, 0.9)
            transform: Translate {
                y: (1 - center.stage_(0.35, 0.9)) * 10
            }

            IconButton {
                anchors.verticalCenter: parent.verticalCenter
                glyph: NotificationServer.doNotDisturb ? Icons.bellOff : Icons.bell
                on: NotificationServer.doNotDisturb
                onClicked: NotificationServer.toggleDnd()
            }

            // Copy the text: a code, a link
            IconButton {
                anchors.verticalCenter: parent.verticalCenter
                visible: center.cur !== null && (center.cur.body !== "" || center.cur.summary !== "")
                glyph: center.copied ? Icons.check : Icons.copy
                on: center.copied
                onClicked: center.copyBody()
            }

            // A long text: read all of it
            TextButton {
                compact: true
                visible: center.expanded || bodyText.truncated
                text: center.expanded ? "Less" : "More"
                hint: "Space"
                onClicked: center.expanded = !center.expanded
            }

            // The notification's own buttons
            Repeater {
                model: center.curActions

                delegate: TextButton {
                    required property var modelData
                    required property int index

                    compact: true
                    primary: index === 0
                    text: NotificationServer.clip(modelData.text, 18)
                    onClicked: center.runAction(modelData.id)
                }
            }

            TextButton {
                compact: true
                visible: center.cur !== null
                text: "Dismiss"
                onClicked: center.removeSel()
            }

            // Only when the app has more than this one
            TextButton {
                compact: true
                visible: center.groupCount > 1
                text: center.cur ? "Clear " + NotificationServer.clip(center.cur.appName, 16) : ""
                onClicked: center.dismissGroup(center.cur.appName)
            }

            // Empty the whole history: press twice
            TextButton {
                compact: true
                visible: center.liveCount > 0
                minWidth: 92
                danger: center.clearArmed
                armed: center.clearArmed
                text: center.clearArmed ? "Press again" : "Clear all"
                onClicked: center.requestClear()
            }
        }
    }
}
