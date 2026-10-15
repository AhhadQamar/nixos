// ScreenTime.qml
// Screen time on the launcher's dial: the same borderless stage rising from
// the bottom edge, glass discs, accent underline and rainbow arrival. Backed
// by `screentime panel` (modules/shell/screentime).
// The discs are where the time went. The first one is the whole period, ringed
// as your daily goal (accent while under it, red once over); the apps follow,
// biggest first, each a letter in its category's colour and ringed with its
// share of the busiest app. The ruler is the chart: its ticks are the bars
// (24 hours for a day, one per day for a week or a month), tall for a busy
// hour, red where a day went over the goal. The accent's 2px stands under the
// bar the words are about: the one under the pointer, else the busiest.
// The middle reads out the selected disc. On the period it shows the total
// (rolling), how it compares with the one before, what is on screen right now,
// where the time went by category, and four or five facts. On an app it shows
// its time and share and the windows behind it (all of them on request).
// Under the readout: previous / next period, Day / Week / Month, Today, more
// apps, and the windows of the app.
//   qs ipc call screentime toggle | open | close
//   qs ipc call screentime show day | week | month
// Keys: ← → ↑ ↓ (h l k j, Ctrl+N / Ctrl+P) turn the dial   PageUp / PageDown jump 5
//       Home / End the period / the last app
//       Shift+← / Shift+→ (H / L) previous / next period   t jump to today
//       tab / shift+tab or 1 2 3 switch day / week / month
//       enter or space shows all windows of the selected app   a more / fewer apps
//       esc folds the windows, then closes
//       Holding enter, space, tab, a, t, 1 2 3 or shift+← / → does not repeat.
// Mouse: click a disc to bring it to the middle, click the app in the middle
//        again for its windows, hover the ruler to read a bar, scroll turns
//        the dial.
//
// Like the launcher it arrives as a rainbow: the discs and the chart swing in
// from the left over a tight dome and unfurl into the calm dial. Closing plays
// it in reverse. The bars and the strip rise in whenever fresh numbers land,
// and the numbers dip and come back when you change period.
//
// Like the other dials the window has one size and the stage inside it grows
// and shrinks with what is shown, so the dial glides up and down; only the
// stage takes the mouse, the rest of the screen reaches other windows. The
// keyboard is the panel's until it closes (Esc).

import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland

PanelWindow {
    id: panel

    // Opens on the monitor that has focus, and stays there while it is open
    property var targetScreen: Focus.screen

    // ---- Settings -------------------------------------------------------
    // Daily goal in minutes (set in Config.qml). 0 hides every goal marker.
    readonly property int dailyGoalMinutes: Config.dailyGoalMinutes
    readonly property var ranges: ["day", "week", "month"]
    readonly property real screenW: targetScreen ? targetScreen.width : 1920
    readonly property real screenH: targetScreen ? targetScreen.height : 1080
    readonly property int stageW: Math.min(780, Math.round(screenW * 0.9))
    // The stage grows and shrinks with what is shown (bodyH), so the dial
    // glides up and down; it never gets taller than this.
    readonly property int winH: Math.min(660, Math.round(screenH * 0.8))
    readonly property int topY: Style.panelTop
    readonly property real dialR: 900
    // The dome the dial starts as when it opens (and ends as when it closes)
    readonly property real rainbowR: 360
    readonly property real stepPx: 76
    readonly property int discSize: 48
    readonly property int selectedSize: 68
    // The ruler is the chart: how far below the discs it stands, how tall the
    // tallest bar is, and how wide the whole chart is
    readonly property int baseDrop: 88
    readonly property int chartH: 30
    readonly property real spanW: Math.max(300, Math.min(420, stageW - 360))
    // The size of the total in the middle
    readonly property int heroSize: 38
    // Windows of an app shown at first, and at most when all are asked for
    readonly property int titlesShort: 3
    readonly property int titlesLong: 12

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
    // 0..1 each time fresh numbers land: drives the bars and the strip rising
    property real intro: 1
    // The numbers dip and come back when the period or the selection changes
    property real swap: 1
    property string range: "day"
    property int offset: 0
    property string expandedApp: ""
    property bool showAll: false
    // The bar under the pointer, -1 when none
    property int hoverIndex: -1
    // The selected app; -1 is the period itself (the first disc)
    property int selApp: -1
    // Whether the dial glides to a new selection (off while opening)
    property bool animateView: false
    // Wheel movement not yet turned into a step (a touchpad sends many small ones)
    property real wheelAcc: 0
    property bool loadFailed: false
    property bool pendingRefresh: false
    // "range:offset" -> payload from `screentime panel`, so switching back and
    // forth is instant while a fresh copy loads in the background.
    property var cache: ({})
    // The payload on screen. It stays put while the next one loads, so a
    // period change never flashes empty.
    property var shownView: emptyView
    property string shownKey: ""

    readonly property var emptyView: ({
            "range": "day",
            "offset": 0,
            "total": 0,
            "prev_total": 0,
            "avg": 0,
            "label": "",
            "sublabel": "",
            "vs": "",
            "apps": [],
            "app_count": 0,
            "categories": [],
            "days": [],
            "hours": new Array(24).fill(0),
            "sessions": 0,
            "longest": 0,
            "first": "",
            "last": "",
            "now": null,
            "any_data": true,
            "has_older": false
        })
    readonly property var blankApp: ({
            "name": "",
            "class": "",
            "sec": 0,
            "cat": 0,
            "titles": []
        })
    readonly property string cacheKey: range + ":" + offset
    readonly property var cur: cache[cacheKey]
    readonly property var view: shownView
    readonly property bool loaded: shownKey !== ""
    readonly property bool settled: intro >= 1

    // Radius of the dial right now: curvature eases from the dome to the dial
    readonly property real dialNow: 1 / (1 / dialR + (1 / rainbowR - 1 / dialR) * fan)

    // The total rolls to its new value instead of jumping
    property real shownTotal: view.total

    Behavior on shownTotal {
        NumberAnimation {
            duration: Style.enterMs
            easing.type: Style.easeMove
        }
    }

    // ---- Derived --------------------------------------------------------
    readonly property bool dayView: view.range === "day"
    readonly property bool hasData: view.total > 0
    readonly property real goalSec: dailyGoalMinutes * 60
    readonly property bool overGoal: dayView && goalSec > 0 && view.total > goalSec

    readonly property bool hasDelta: view.prev_total > 0 && view.total > 0
    readonly property real deltaPct: hasDelta ? (view.total - view.prev_total) / view.prev_total * 100 : 0
    readonly property color deltaColor: Math.abs(deltaPct) < 2 ? Colors.muted : (deltaPct < 0 ? Colors.success : Colors.critical)

    // Chart: 24 hours for a day, one bar per day otherwise
    readonly property var bars: dayView ? view.hours : view.days.map(function (d) {
        return d[1];
    })
    readonly property real barMax: Math.max(1, Math.max.apply(null, bars))
    readonly property bool goalInRange: !dayView && goalSec > 0 && goalSec <= barMax * 1.6
    // A day's hour bar is "share of that hour", so its scale is fixed at 60 minutes.
    readonly property real chartMax: dayView ? 3600 : (goalInRange ? Math.max(barMax, goalSec) : barMax)
    readonly property int peakIndex: {
        let best = -1;
        let top = 0;
        for (let i = 0; i < bars.length; i++) {
            if (bars[i] > top) {
                top = bars[i];
                best = i;
            }
        }
        return best;
    }
    readonly property bool hovering: hoverIndex >= 0 && hoverIndex < bars.length
    // The bar the accent's 2px stands under: the one under the pointer, else
    // the busiest. It glides from bar to bar.
    readonly property int markIdx: hovering ? hoverIndex : peakIndex
    property real markI: markIdx >= 0 ? markIdx : 0

    Behavior on markI {
        NumberAnimation {
            duration: Style.baseMs
            easing.type: Style.easeMove
        }
    }

    readonly property var visibleApps: view.apps.slice(0, showAll ? 12 : 6)
    readonly property real topAppSec: view.apps.length > 0 ? Math.max(1, view.apps[0].sec) : 1
    // The period is the first disc, then the apps
    readonly property int slotCount: 1 + visibleApps.length
    readonly property real targetPos: selApp + 1
    property real viewPos: targetPos

    Behavior on viewPos {
        enabled: panel.animateView

        // The dial glides into place and settles, with no bounce
        NumberAnimation {
            duration: Style.enterMs
            easing.type: Style.easeEnter
        }
    }

    readonly property bool msgMode: loadFailed || (loaded && !hasData)
    readonly property bool appMode: !msgMode && hasData && selApp >= 0 && selApp < visibleApps.length
    readonly property bool hubMode: !msgMode && !appMode
    readonly property var curApp: appMode ? visibleApps[selApp] : blankApp
    readonly property bool curExpanded: appMode && curApp.class !== "" && expandedApp === curApp.class
    readonly property var shownTitles: appMode ? curApp.titles.slice(0, curExpanded ? titlesLong : titlesShort) : []
    // The light on the horizon, the underline and the marker: red while the
    // period is over its goal and is what is selected
    readonly property color tint: overGoal && selApp < 0 ? Colors.critical : Colors.accent

    readonly property var statTiles: {
        const t = dayView ? [
            {
                "v": view.first !== "" ? view.first + "\u2013" + view.last : "None",
                "k": "Active"
            },
            {
                "v": fmt(view.longest),
                "k": "Longest stretch"
            },
            {
                "v": String(view.sessions),
                "k": "Sessions"
            },
            {
                "v": String(view.app_count),
                "k": "Apps used"
            }
        ] : [
            {
                "v": fmt(view.avg),
                "k": "Daily average"
            },
            {
                "v": dayAt(peakIndex) !== "" ? dayAt(peakIndex) : "None",
                "k": "Busiest day"
            },
            {
                "v": fmt(view.longest),
                "k": "Longest stretch"
            },
            {
                "v": String(view.sessions),
                "k": "Sessions"
            }
        ];
        if (dayView && peakIndex >= 0)
            t.push({
                "v": pad2(peakIndex) + ":00",
                "k": "Busiest hour"
            });
        return t;
    }

    readonly property string heroSub: {
        if (!loaded)
            return "";
        if (!dayView)
            return "average " + fmt(view.avg) + " a day";
        if (goalSec <= 0)
            return "screen time";
        return overGoal ? "over your " + fmt(goalSec) + " goal by " + fmt(view.total - goalSec) : fmt(goalSec - view.total) + " left of your " + fmt(goalSec) + " goal";
    }

    // The bar under the pointer, in words
    readonly property string hoverText: {
        if (!hovering)
            return "";
        const i = hoverIndex;
        const when = dayView ? pad2(i) + ":00 to " + pad2((i + 1) % 24) + ":00" : dayAt(i);
        return when + "  ·  " + fmt(bars[i]);
    }

    // The small line above the readout: what the middle is about
    readonly property string headText: {
        if (hovering)
            return hoverText;
        if (!loaded)
            return "";
        if (msgMode)
            return view.label;
        if (appMode) {
            const c = catName(curApp.cat);
            return (c !== "" ? c + "  ·  " : "") + (selApp + 1) + "/" + visibleApps.length;
        }
        return view.label + (view.sublabel !== "" ? "  ·  " + view.sublabel : "");
    }

    readonly property string msgTitle: loadFailed ? "Couldn't read screen time data" : (view.any_data ? "Nothing recorded for this period" : "No data yet")
    readonly property string msgSub: loadFailed ? "Run `screentime panel day 0` in a terminal to see the error." : (view.any_data ? "" : "The logger starts with Hyprland. To start it now, run `screentime log` in a terminal.")

    // ---- Layout of what is under the dial ---------------------------------
    readonly property int readoutTop: topY + baseDrop + 28
    readonly property int actionsH: Style.buttonCompact
    // The height of the stage for what is on show right now
    property real bodyH: readoutTop + readout.height + 14 + actionsH + 16

    Behavior on bodyH {
        NumberAnimation {
            duration: Style.moveMs
            easing.type: Style.easeMove
        }
    }

    // ---- Helpers --------------------------------------------------------
    function clamp(v, a, b) {
        return Math.max(a, Math.min(b, v));
    }

    function ease(p) {
        return 1 - Math.pow(1 - p, 3);
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

    function pad2(n) {
        return (n < 10 ? "0" : "") + n;
    }

    function fmt(sec) {
        const m = Math.round(sec / 60);
        if (sec > 0 && m === 0)
            return "<1m";
        const h = Math.floor(m / 60);
        if (h > 0)
            return h + "h " + pad2(m % 60) + "m";
        return m + "m";
    }

    // Date label for bar i of a week / month view ("" while data is switching)
    function dayAt(i) {
        if (i < 0 || i >= view.days.length)
            return "";
        return Qt.formatDate(new Date(view.days[i][0] + "T00:00:00"), "ddd d MMM");
    }

    // One colour per category, stable across periods (index from screentime.py)
    function catColor(idx) {
        const palette = [Colors.color4, Colors.color2, Colors.color3, Colors.color5, Colors.color6, Colors.color1, Colors.color7];
        return idx < palette.length ? palette[idx] : Colors.muted;
    }

    function catName(idx) {
        for (const c of view.categories) {
            if (c.idx === idx)
                return c.name;
        }
        return "";
    }

    function isCurrent(i) {
        if (view.offset !== 0)
            return false;
        return dayView ? i === new Date().getHours() : i === bars.length - 1;
    }

    function showAxis(i) {
        if (dayView)
            return i % 6 === 0;
        if (view.range === "week")
            return true;
        return i % 5 === 0 || i === bars.length - 1;
    }

    function axisLabel(i) {
        if (dayView)
            return pad2(i);
        if (i >= view.days.length)
            return "";
        const d = new Date(view.days[i][0] + "T00:00:00");
        return view.range === "week" ? Qt.formatDate(d, "ddd") : String(d.getDate());
    }

    // ---- Data -----------------------------------------------------------
    function refresh() {
        if (fetcher.running) {
            pendingRefresh = true;
            return;
        }
        fetcher.command = ["screentime", "panel", range, String(offset)];
        fetcher.running = true;
    }

    // Put the payload for the period being looked at on screen. A fresh period
    // (not just a refresh of the same one) plays the rise-in.
    function showCurrent() {
        if (!cur)
            return;
        const fresh = shownKey !== cacheKey;
        shownKey = cacheKey;
        shownView = cur;
        if (fresh) {
            swapAnim.restart();
            introAnim.restart();
        }
    }

    onCurChanged: showCurrent()

    onLoadFailedChanged: {
        if (loadFailed)
            swap = 1;
    }

    onShowAllChanged: {
        if (selApp >= visibleApps.length)
            selApp = visibleApps.length - 1;
    }

    // The list can get shorter under the selection (a fresh payload)
    onVisibleAppsChanged: {
        if (selApp >= visibleApps.length)
            selApp = visibleApps.length - 1;
    }

    // Another disc is in the middle: the words fade up, and the windows fold
    onSelAppChanged: {
        expandedApp = "";
        if (isOpen)
            swapAnim.restart();
    }

    // ---- Actions --------------------------------------------------------
    function resetUi() {
        expandedApp = "";
        hoverIndex = -1;
        selApp = -1;
    }

    // Look at another period: dim the numbers now, bring them back when the
    // new ones are on screen
    function go(r, o) {
        // First: the selection moving back to the period restarts the fade,
        // and the numbers must stay dimmed until the new ones are on screen
        resetUi();
        swapAnim.stop();
        swap = 0.45;
        range = r;
        offset = o;
        refresh();
    }

    function setRange(r) {
        if (r === range)
            return;
        go(r, 0);
    }

    function cycleRange(dir) {
        const i = ranges.indexOf(range);
        go(ranges[(i + dir + ranges.length) % ranges.length], 0);
    }

    // dir: 1 = one period back, -1 = one period forward
    function step(dir) {
        const next = offset + dir;
        if (next < 0 || (dir > 0 && !view.has_older))
            return;
        go(range, next);
    }

    function goToday() {
        if (offset === 0)
            return;
        go(range, 0);
    }

    function toggleAll() {
        if (view.apps.length > 6)
            showAll = !showAll;
    }

    // Turn the dial: the period, then the apps
    function turn(d) {
        const n = visibleApps.length;
        if (n === 0)
            return;
        selApp = clamp(selApp + d, -1, n - 1);
    }

    function jump(last) {
        const n = visibleApps.length;
        selApp = last ? n - 1 : -1;
    }

    function toggleSelected() {
        if (!appMode)
            return;
        const c = curApp.class;
        expandedApp = expandedApp === c ? "" : c;
    }

    // ---- Open and close -------------------------------------------------
    function open() {
        if (isOpen)
            return;
        targetScreen = Focus.screen;
        closeAnim.stop();
        swapAnim.stop();
        swap = 1;
        offset = 0;
        wheelAcc = 0;
        // The dial starts on the period instead of gliding there
        animateView = false;
        resetUi();
        animateView = true;
        // Fully hidden: start from the dome. Re-opened while it was still
        // leaving: carry on from where it is instead of snapping away first.
        if (reveal <= 0.001) {
            reveal = 0;
            spinIn = 3.2;
            fan = 1;
        }
        isOpen = true;
        // Rise in again, from whatever was cached for this period
        shownKey = "";
        intro = 0;
        openAnim.restart();
        if (cur) {
            shownKey = cacheKey;
            shownView = cur;
            introAnim.restart();
        }
        refresh();
        keys.forceActiveFocus();
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
        windows: [panel]
        active: panel.isOpen && panel.visible
        onCleared: {
            panel.closedAt = Date.now();
            panel.close();
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
    WlrLayershell.namespace: "qs-screentime"
    // Exclusive, like the launcher and the notification centre: the keys work
    // the moment it opens, without clicking it first.
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

        function show(r: string): void {
            if (r !== "day" && r !== "week" && r !== "month")
                return;
            if (panel.isOpen) {
                panel.setRange(r);
            } else {
                panel.range = r;
                panel.open();
            }
        }

        target: "screentime"
    }

    PanelLink {
        win: panel
        name: "screentime"
    }

    // Rises smoothly. The discs and the chart swing in from the left over a
    // tight dome and unfurl into the dial.
    ParallelAnimation {
        id: openAnim

        NumberAnimation {
            target: panel
            property: "reveal"
            to: 1
            duration: Style.sweepMs
            easing.type: Style.easeEnter
        }
        NumberAnimation {
            target: panel
            property: "spinIn"
            to: 0
            duration: Style.sweepMs + Style.moveMs
            easing.type: Style.easeEnter
        }
        NumberAnimation {
            target: panel
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

    // Slow breath for the ring around the selected disc.
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

    // Drives the bars and the strip rising in
    NumberAnimation {
        id: introAnim

        target: panel
        property: "intro"
        from: 0
        to: 1
        duration: Style.sweepMs
        easing.type: Easing.Linear
    }

    // The numbers dip and come back when the period or the selection changes
    NumberAnimation {
        id: swapAnim

        target: panel
        property: "swap"
        from: 0.45
        to: 1
        duration: Style.baseMs
        easing.type: Style.easeMove
    }

    // Keep numbers fresh while the panel is open
    Timer {
        interval: 15000
        repeat: true
        running: panel.isOpen
        onTriggered: panel.refresh()
    }

    Process {
        id: fetcher

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(text);
                    const c = Object.assign({}, panel.cache);
                    c[d.range + ":" + d.offset] = d;
                    panel.cache = c;
                    panel.loadFailed = false;
                } catch (e) {
                    panel.loadFailed = true;
                }
            }
        }
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0)
                panel.loadFailed = true;
            if (panel.pendingRefresh) {
                panel.pendingRefresh = false;
                panel.refresh();
            }
        }
    }

    // Keyboard handling
    Item {
        id: keys

        anchors.fill: parent
        focus: panel.isOpen
        Keys.onPressed: event => {
            const k = event.key;
            const ctrl = (event.modifiers & Qt.ControlModifier) !== 0;
            const shift = (event.modifiers & Qt.ShiftModifier) !== 0;
            const plain = event.modifiers === Qt.NoModifier;
            const back = shift && (k === Qt.Key_Left || k === Qt.Key_H);
            const forward = shift && (k === Qt.Key_Right || k === Qt.Key_L);
            // Turning the dial may repeat; changing the period or toggling
            // something must not, or a held key would run through the history
            if (event.isAutoRepeat && (back || forward || k === Qt.Key_Escape || k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Space || k === Qt.Key_Tab || k === Qt.Key_Backtab || k === Qt.Key_A || k === Qt.Key_T || k === Qt.Key_1 || k === Qt.Key_2 || k === Qt.Key_3)) {
                event.accepted = true;
                return;
            }
            if (k === Qt.Key_Escape) {
                if (panel.expandedApp !== "")
                    panel.expandedApp = "";
                else
                    panel.close();
            } else if (back)
                panel.step(1);
            else if (forward)
                panel.step(-1);
            else if (k === Qt.Key_Right || k === Qt.Key_Down || (plain && (k === Qt.Key_L || k === Qt.Key_J)) || (ctrl && k === Qt.Key_N))
                panel.turn(1);
            else if (k === Qt.Key_Left || k === Qt.Key_Up || (plain && (k === Qt.Key_H || k === Qt.Key_K)) || (ctrl && k === Qt.Key_P))
                panel.turn(-1);
            else if (k === Qt.Key_PageDown)
                panel.turn(5);
            else if (k === Qt.Key_PageUp)
                panel.turn(-5);
            else if (k === Qt.Key_Home)
                panel.jump(false);
            else if (k === Qt.Key_End)
                panel.jump(true);
            else if (k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Space)
                panel.toggleSelected();
            else if (k === Qt.Key_Tab)
                panel.cycleRange(1);
            else if (k === Qt.Key_Backtab)
                panel.cycleRange(-1);
            else if (k === Qt.Key_1)
                panel.setRange("day");
            else if (k === Qt.Key_2)
                panel.setRange("week");
            else if (k === Qt.Key_3)
                panel.setRange("month");
            else if (k === Qt.Key_T)
                panel.goToday();
            else if (k === Qt.Key_A)
                panel.toggleAll();
            else
                return;
            event.accepted = true;
        }
    }

    // ---- Small pieces ---------------------------------------------------
    // A thin progress ring inside a disc: a faint track, and an arc of `frac`
    // of the circle from the top.
    component Ring: Shape {
        id: ring

        property real frac: 0
        property color tint: Colors.accent
        property real lineW: 2.5

        layer.enabled: true
        layer.samples: 4

        ShapePath {
            strokeColor: Qt.alpha(Colors.foreground, 0.14)
            strokeWidth: ring.lineW
            fillColor: "transparent"

            PathAngleArc {
                centerX: ring.width / 2
                centerY: ring.height / 2
                radiusX: ring.width / 2 - ring.lineW / 2
                radiusY: ring.height / 2 - ring.lineW / 2
                startAngle: -90
                sweepAngle: 360
            }
        }

        ShapePath {
            strokeColor: ring.frac > 0.004 ? ring.tint : "transparent"
            strokeWidth: ring.lineW
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap

            PathAngleArc {
                centerX: ring.width / 2
                centerY: ring.height / 2
                radiusX: ring.width / 2 - ring.lineW / 2
                radiusY: ring.height / 2 - ring.lineW / 2
                startAngle: -90
                sweepAngle: 359.9 * Math.min(1, Math.max(0, ring.frac))
            }
        }
    }

    // The shared dim (Dim.qml): the same wash as the screenshot tool
    Dim {
        reveal: panel.reveal
        closes: true
        onClicked: panel.close()
    }

    // ---- Stage ----------------------------------------------------------
    Item {
        id: stage

        readonly property real cx: width / 2

        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        width: panel.stageW
        height: Math.min(panel.bodyH, panel.winH)
        clip: true
        opacity: Math.min(1, panel.reveal * 3)
        transform: Translate {
            y: (1 - panel.reveal) * (stage.height + 40)
        }

        // Scroll wheel turns the dial
        MouseArea {
            anchors.fill: parent
            onWheel: wheel => {
                const d = wheel.angleDelta.y !== 0 ? wheel.angleDelta.y : -wheel.angleDelta.x;
                if (d === 0)
                    return;
                // One step per notch (120). A touchpad sends many small
                // deltas; counting them keeps one swipe from spinning the
                // dial through every app.
                if ((d < 0) !== (panel.wheelAcc < 0))
                    panel.wheelAcc = 0;
                panel.wheelAcc += d;
                while (panel.wheelAcc <= -120) {
                    panel.turn(1);
                    panel.wheelAcc += 120;
                }
                while (panel.wheelAcc >= 120) {
                    panel.turn(-1);
                    panel.wheelAcc -= 120;
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

        // Low light on the horizon: the accent, or red while the period is
        // over its goal and is what is selected.
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
                        color: Qt.alpha(panel.tint, 0.18)
                    }
                    GradientStop {
                        position: 0.5
                        color: Qt.alpha(panel.tint, 0.07)
                    }
                    GradientStop {
                        position: 1
                        color: Qt.alpha(panel.tint, 0)
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

        // ---- The ruler, which is the chart --------------------------------
        // One tick per bar, standing on the curve of the dial: a hairline for
        // the scale and a capsule as tall as the time. They sit still while
        // the dial turns; the period they describe is the one on screen.
        Repeater {
            // Not kept around while the panel is hidden
            model: panel.visible ? panel.bars.length : 0

            delegate: Item {
                id: col

                required property int index

                readonly property int n: panel.bars.length
                readonly property real value: index < n ? panel.bars[index] : 0
                readonly property real level: value > 0 ? Math.min(1, value / panel.chartMax) : 0
                // The bars rise one after another when fresh numbers land
                readonly property real grow: panel.ease(panel.clamp(panel.intro * 2.2 - index * 0.045, 0, 1))
                readonly property bool current: panel.isCurrent(index)
                readonly property bool over: !panel.dayView && panel.goalSec > 0 && value > panel.goalSec
                readonly property bool hot: panel.hoverIndex === index
                readonly property real gapX: panel.spanW / Math.max(1, n)
                readonly property real barW: Math.max(3, Math.min(10, gapX * 0.5))
                // Swung left while arriving, right while leaving, like the discs
                readonly property real s: (index - (n - 1) / 2) * gapX - panel.spinIn * panel.stepPx * 0.5
                readonly property real a: s / panel.dialNow
                readonly property real rr: panel.dialNow - panel.baseDrop

                // The bar the ruler shows; kept across refreshes so a changed
                // value glides instead of rebuilding
                property real shown: level

                x: stage.cx + rr * Math.sin(a) - width / 2
                y: panel.topY + panel.dialNow - rr * Math.cos(a) - height
                width: gapX
                height: panel.chartH
                visible: Math.abs(a) < 1.2
                transformOrigin: Item.Bottom
                rotation: a * 180 / Math.PI
                opacity: panel.clamp(panel.reveal * 2 - Math.abs(x + width / 2 - stage.cx) / stage.cx * 0.9, 0, 1)

                Behavior on shown {
                    enabled: panel.settled

                    NumberAnimation {
                        duration: Style.moveMs
                        easing.type: Style.easeMove
                    }
                }

                // The scale: a hairline for every bar, even an empty hour
                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    width: 1.5
                    height: parent.height
                    radius: 0.75
                    antialiasing: true
                    color: Qt.alpha(Colors.foreground, col.hot ? 0.4 : 0.16)

                    Behavior on color {
                        ColorAnimation {
                            duration: Style.pressMs
                        }
                    }
                }

                // The time
                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    width: col.barW
                    height: col.shown > 0 ? Math.max(4, parent.height * col.shown) * col.grow : 0
                    radius: width / 2
                    antialiasing: true
                    color: col.over ? Colors.critical : Colors.accent
                    opacity: col.current || col.hot ? 1.0 : 0.62

                    Behavior on opacity {
                        NumberAnimation {
                            duration: Style.pressMs
                        }
                    }
                    Behavior on color {
                        ColorAnimation {
                            duration: Style.baseMs
                        }
                    }
                }

                // The goal, as a short red dash across the bar
                Rectangle {
                    visible: panel.goalInRange
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: parent.height * (1 - panel.goalSec / panel.chartMax)
                    width: col.barW + 6
                    height: 1
                    color: Colors.critical
                    opacity: 0.6 * panel.clamp(panel.intro * 2 - 0.6, 0, 1)
                }

                Txt {
                    visible: panel.showAxis(col.index)
                    anchors.top: parent.bottom
                    anchors.topMargin: 11
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: panel.axisLabel(col.index)
                    color: col.current || col.hot ? Colors.foreground : Colors.muted
                    font.pixelSize: Style.fontXs
                    font.bold: col.current
                }

                // Hovering a bar reads it out
                HoverHandler {
                    onHoveredChanged: {
                        if (hovered)
                            panel.hoverIndex = col.index;
                        else if (panel.hoverIndex === col.index)
                            panel.hoverIndex = -1;
                    }
                }
            }
        }

        // The accent's 2px: it stands under the bar the words are about
        Rectangle {
            readonly property int n: panel.bars.length
            readonly property real gapX: panel.spanW / Math.max(1, n)
            readonly property real s: (panel.markI - (n - 1) / 2) * gapX - panel.spinIn * panel.stepPx * 0.5
            readonly property real a: s / panel.dialNow
            readonly property real rr: panel.dialNow - panel.baseDrop

            visible: panel.hasData && panel.markIdx >= 0
            x: stage.cx + rr * Math.sin(a) - 1
            y: panel.topY + panel.dialNow - rr * Math.cos(a) + 3
            width: 2
            height: 7
            radius: 1
            color: Colors.accent
            transformOrigin: Item.Top
            rotation: a * 180 / Math.PI
            opacity: panel.clamp(panel.reveal * 2 - 0.5, 0, 1)
        }

        // ---- The discs: the period, then the apps -------------------------
        Repeater {
            // The discs only exist while the panel is on screen
            model: panel.visible ? panel.slotCount : 0

            delegate: Item {
                id: slot

                required property int index

                readonly property bool hub: index === 0
                readonly property var app: !hub && index - 1 < panel.visibleApps.length ? panel.visibleApps[index - 1] : panel.blankApp
                readonly property bool current: panel.selApp === index - 1
                // The period is ringed in the accent (red when over the goal);
                // an app in its category's colour
                readonly property color ringTint: hub ? (panel.overGoal ? Colors.critical : Colors.accent) : panel.catColor(app.cat)
                readonly property real rel: index - panel.viewPos
                // Swung left while arriving, right while leaving
                readonly property real s: (rel - panel.spinIn) * panel.stepPx
                readonly property real a: s / panel.dialNow
                // 0 at rest, 1 when selected. Animated, so the disc swells.
                property real grow: current ? 1 : 0
                // 0..1 while the ring around a newly selected disc expands
                property real ping: 0
                // The ring: how much of the goal the period used, or how much
                // of the busiest app this one used
                property real frac: hub ? (panel.dayView && panel.goalSec > 0 ? Math.min(1, panel.shownTotal / panel.goalSec) : 0) : app.sec / panel.topAppSec
                readonly property real sz: panel.discSize + (panel.selectedSize - panel.discSize) * grow
                readonly property real px: stage.cx + panel.dialNow * Math.sin(a)
                // The selected one also lifts a little off the dial
                readonly property real py: panel.topY + panel.dialNow * (1 - Math.cos(a)) - 5 * grow
                // Arrive in a left-to-right wave, each with a small overshoot
                readonly property real appear: panel.clamp(panel.reveal * 2.2 - (panel.clamp(rel, -6, 6) + 6) * 0.09, 0, 1)
                readonly property real edge: panel.clamp((stage.cx - Math.abs(px - stage.cx)) / 90, 0, 1)

                visible: Math.abs(rel) < 7 && opacity > 0.01
                width: sz
                height: sz
                x: px - sz / 2
                y: py - sz / 2
                z: current ? 20 : 10
                opacity: appear * edge
                scale: 0.55 + 0.45 * panel.backOut(appear)
                // Tilts along the dial, and rises from below as it arrives
                rotation: a * 180 / Math.PI * 0.6
                transform: Translate {
                    y: (1 - slot.appear) * 30
                }

                // Swells with a little overshoot, settles back without one
                Behavior on grow {
                    NumberAnimation {
                        duration: Style.moveMs
                        easing.type: slot.current ? Style.easePop : Style.easeMove
                        easing.overshoot: 1.2
                    }
                }

                Behavior on frac {
                    enabled: panel.settled

                    NumberAnimation {
                        duration: Style.moveMs
                        easing.type: Style.easeMove
                    }
                }

                // The selection moved to this one: a ring leaves it.
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
                    border.color: Qt.alpha(Colors.accent, slot.grow * (0.25 + 0.25 * panel.breath))
                }

                // Glass, like the bar: one flat surface with a hairline
                // outline, lit in the accent once selected.
                Rectangle {
                    anchors.fill: parent
                    radius: width / 2
                    antialiasing: true
                    color: Style.card
                    border.width: 1
                    border.color: slot.current ? Qt.alpha(Colors.accent, 0.9) : Qt.alpha(Colors.foreground, 0.32)

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
                    color: slot.current ? Qt.alpha(Colors.accent, Style.tintAlpha) : (area.containsMouse ? Style.hoverFill : "transparent")

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

                // The share ring; it stays upright while the disc tilts
                Ring {
                    anchors.fill: parent
                    anchors.margins: 3
                    frac: slot.frac
                    tint: slot.ringTint
                    opacity: slot.current ? 1 : 0.7
                    rotation: -slot.rotation
                }

                // The period: a clock. An app: its first letter, in the
                // colour of its category (the colour is the data).
                Txt {
                    anchors.centerIn: parent
                    text: slot.hub ? Icons.clock : slot.app.name.charAt(0).toUpperCase()
                    color: slot.hub ? (slot.current ? Colors.accent : Colors.foreground) : slot.ringTint
                    font.pixelSize: slot.sz * (slot.hub ? 0.36 : 0.38)
                    font.bold: true
                    rotation: -slot.rotation

                    Behavior on color {
                        ColorAnimation {
                            duration: Style.fadeMs
                        }
                    }
                }

                // Click to bring it to the middle; click the app that is
                // there for its windows. Position, not hover, so the dial
                // never turns under a mouse you are only passing over.
                MouseArea {
                    id: area

                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (slot.current)
                            panel.toggleSelected();
                        else
                            panel.selApp = slot.index - 1;
                    }
                }
            }
        }

        // Accent underline under the selected disc; it breathes with the ring.
        Rectangle {
            readonly property real rel: panel.targetPos - panel.viewPos
            readonly property real a: (rel - panel.spinIn) * panel.stepPx / panel.dialNow

            width: 20 + 10 * panel.breath
            height: 2
            radius: 1
            color: panel.tint
            x: stage.cx + panel.dialNow * Math.sin(a) - width / 2
            y: panel.topY + panel.dialNow * (1 - Math.cos(a)) - 5 + panel.selectedSize / 2 + 6
            rotation: a * 180 / Math.PI
            opacity: panel.clamp(panel.reveal * 2 - 0.6, 0, 1)
        }

        // ---- The middle: what the selected disc says ----------------------
        Item {
            id: readout

            x: stage.cx - width / 2
            y: panel.readoutTop
            width: Math.min(640, stage.width - 48)
            height: readCol.implicitHeight
            // Clicks pass through to the dial
            enabled: false
            opacity: (0.25 + 0.75 * panel.swap) * panel.stage_(0.25, 0.8)
            transform: Translate {
                y: (1 - panel.stage_(0.25, 0.8)) * 12 + (1 - panel.swap) * 6
            }

            Column {
                id: readCol

                width: parent.width
                spacing: Style.spaceSm

                // What the middle is about: the period, the app's category and
                // its place in the list, or the bar under the pointer
                Txt {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    visible: text !== ""
                    elide: Text.ElideRight
                    text: panel.headText
                    // Brighter than the muted grey, with a thin outline in the
                    // background colour: it stays readable over any wallpaper
                    color: panel.hovering ? Colors.foreground : Qt.alpha(Colors.foreground, 0.78)
                    style: Text.Outline
                    styleColor: Qt.alpha(Colors.background, 0.85)
                    font.pixelSize: Style.fontSm
                    font.letterSpacing: 1.4
                    font.capitalization: Font.AllUppercase
                }

                // ---- The period: total, comparison, what is on screen -------
                Item {
                    id: heroRow

                    // Room each side of the total for the two chips
                    readonly property real flankW: Math.max(0, Math.min(230, (width - heroCol.width) / 2 - 24))

                    width: parent.width
                    height: heroCol.implicitHeight
                    visible: panel.hubMode

                    Column {
                        id: heroCol

                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: 0

                        // The total, with a soft shadow in the background colour
                        Item {
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: heroText.implicitWidth
                            height: heroText.implicitHeight

                            Txt {
                                y: 1.5
                                text: heroText.text
                                color: Qt.alpha(Colors.background, 0.9)
                                font: heroText.font
                            }

                            Txt {
                                id: heroText

                                text: panel.loaded ? panel.fmt(panel.shownTotal) : "\u2013"
                                color: panel.overGoal ? Colors.critical : Colors.foreground
                                font.pixelSize: panel.heroSize
                                font.bold: true

                                Behavior on color {
                                    ColorAnimation {
                                        duration: Style.baseMs
                                    }
                                }
                            }
                        }

                        Txt {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: panel.heroSub
                            color: panel.overGoal ? Colors.critical : Qt.alpha(Colors.foreground, 0.78)
                            style: Text.Outline
                            styleColor: Qt.alpha(Colors.background, 0.85)
                            font.pixelSize: Style.fontMd

                            Behavior on color {
                                ColorAnimation {
                                    duration: Style.baseMs
                                }
                            }
                        }
                    }

                    // vs the previous period
                    Column {
                        visible: panel.hasDelta
                        anchors.right: heroCol.left
                        anchors.rightMargin: 24
                        anchors.verticalCenter: parent.verticalCenter
                        width: heroRow.flankW
                        spacing: 3

                        Item {
                            width: parent.width
                            height: deltaChip.height

                            Rectangle {
                                id: deltaChip

                                anchors.right: parent.right
                                width: Math.min(deltaText.implicitWidth + 20, parent.width)
                                height: Style.itemHeight - 4
                                radius: height / 2
                                antialiasing: true
                                color: Qt.alpha(panel.deltaColor, Style.tintAlpha)

                                Behavior on color {
                                    ColorAnimation {
                                        duration: Style.baseMs
                                    }
                                }

                                Txt {
                                    id: deltaText

                                    anchors.centerIn: parent
                                    text: Math.abs(panel.deltaPct) < 2 ? "about the same" : (panel.deltaPct < 0 ? "\u25bc " : "\u25b2 ") + Math.round(Math.abs(panel.deltaPct)) + "%" + (panel.deltaPct < 0 ? " less" : " more")
                                    color: panel.deltaColor
                                    font.pixelSize: Style.fontMd
                                    font.bold: true

                                    Behavior on color {
                                        ColorAnimation {
                                            duration: Style.baseMs
                                        }
                                    }
                                }
                            }
                        }

                        Txt {
                            width: parent.width
                            horizontalAlignment: Text.AlignRight
                            elide: Text.ElideRight
                            text: "than " + panel.view.vs
                            color: Qt.alpha(Colors.foreground, 0.7)
                            style: Text.Outline
                            styleColor: Qt.alpha(Colors.background, 0.85)
                            font.pixelSize: Style.fontSm
                        }
                    }

                    // what is on screen right now
                    Rectangle {
                        id: nowChip

                        visible: !!panel.view.now
                        anchors.left: heroCol.right
                        anchors.leftMargin: 24
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.min(nowRow.implicitWidth + 20, heroRow.flankW)
                        height: Style.itemHeight - 2
                        radius: height / 2
                        antialiasing: true
                        color: Style.hoverFill

                        Row {
                            id: nowRow

                            anchors.centerIn: parent
                            spacing: 7

                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 8
                                height: 8
                                radius: 4
                                color: Colors.success

                                SequentialAnimation on opacity {
                                    running: panel.isOpen && nowChip.visible
                                    loops: Animation.Infinite

                                    NumberAnimation {
                                        to: 0.25
                                        duration: Style.ambientMs
                                        easing.type: Style.easeAmbient
                                    }

                                    NumberAnimation {
                                        to: 1.0
                                        duration: Style.ambientMs
                                        easing.type: Style.easeAmbient
                                    }
                                }
                            }

                            Txt {
                                id: nowName

                                anchors.verticalCenter: parent.verticalCenter
                                text: panel.view.now ? panel.view.now.name : ""
                                color: Colors.foreground
                                font.pixelSize: Style.fontMd
                                font.bold: true
                            }

                            Txt {
                                anchors.verticalCenter: parent.verticalCenter
                                // Only as much of the title as the chip has room for
                                readonly property real room: heroRow.flankW - 20 - 15 - nowName.implicitWidth - 7

                                visible: text !== "" && room > 24
                                width: Math.max(0, Math.min(implicitWidth, room))
                                text: panel.view.now ? panel.view.now.title : ""
                                elide: Text.ElideRight
                                color: Colors.muted
                                font.pixelSize: Style.fontMd
                            }
                        }
                    }
                }

                // Where the time went: one strip, its colours the discs' colours
                Item {
                    width: parent.width
                    height: 5
                    visible: panel.hubMode && panel.hasData

                    Row {
                        id: catBar

                        anchors.horizontalCenter: parent.horizontalCenter
                        width: Math.min(parent.width * 0.7, 420)
                        spacing: 2
                        opacity: panel.clamp(panel.intro * 1.8 - 0.4, 0, 1)

                        Repeater {
                            model: panel.view.categories.length

                            delegate: Rectangle {
                                id: seg

                                required property int index

                                readonly property var cat: index < panel.view.categories.length ? panel.view.categories[index] : ({
                                        "sec": 0,
                                        "idx": 0
                                    })
                                readonly property real grow: panel.ease(panel.clamp(panel.intro * 1.8 - 0.25 - index * 0.1, 0, 1))
                                property real frac: cat.sec / Math.max(1, panel.view.total)

                                width: Math.max(4, (catBar.width - (panel.view.categories.length - 1) * catBar.spacing) * frac) * grow
                                height: 5
                                radius: height / 2
                                antialiasing: true
                                color: panel.catColor(cat.idx)

                                Behavior on frac {
                                    enabled: panel.settled

                                    NumberAnimation {
                                        duration: Style.moveMs
                                        easing.type: Style.easeMove
                                    }
                                }
                                Behavior on color {
                                    ColorAnimation {
                                        duration: Style.baseMs
                                    }
                                }
                            }
                        }
                    }
                }

                // ...and its names. If the row is ever wider than the readout
                // it shrinks to fit.
                Item {
                    width: parent.width
                    height: legendRow.implicitHeight
                    visible: panel.hubMode && panel.hasData && panel.view.categories.length > 0

                    Row {
                        id: legendRow

                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: Style.spaceXl
                        scale: Math.min(1, parent.width / Math.max(1, legendRow.implicitWidth))

                        Repeater {
                            model: panel.view.categories

                            delegate: Row {
                                id: legend

                                required property var modelData

                                spacing: Style.spaceSm

                                Txt {
                                    text: "\u25cf"
                                    color: panel.catColor(legend.modelData.idx)
                                    font.pixelSize: Style.fontSm
                                }

                                Txt {
                                    text: legend.modelData.name
                                    color: Colors.foreground
                                    font.pixelSize: Style.fontMd
                                }

                                Txt {
                                    text: panel.fmt(legend.modelData.sec)
                                    color: Colors.muted
                                    font.pixelSize: Style.fontMd
                                }
                            }
                        }
                    }
                }

                // A few facts about the period
                Item {
                    width: parent.width
                    height: statsRow.implicitHeight + 6
                    visible: panel.hubMode && panel.hasData
                    opacity: panel.clamp(panel.intro * 1.8 - 0.6, 0, 1)

                    Row {
                        id: statsRow

                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.bottom
                        spacing: 28
                        scale: Math.min(1, parent.width / Math.max(1, statsRow.implicitWidth))

                        Repeater {
                            model: panel.statTiles

                            delegate: Item {
                                id: tile

                                required property int index
                                required property var modelData

                                width: tileCol.implicitWidth
                                height: tileCol.implicitHeight

                                Column {
                                    id: tileCol

                                    spacing: 1

                                    Txt {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        text: tile.modelData.v
                                        color: Colors.foreground
                                        style: Text.Outline
                                        styleColor: Qt.alpha(Colors.background, 0.85)
                                        font.pixelSize: Style.fontMd
                                        font.bold: true
                                    }

                                    Txt {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        text: tile.modelData.k
                                        color: Qt.alpha(Colors.foreground, 0.7)
                                        style: Text.Outline
                                        styleColor: Qt.alpha(Colors.background, 0.85)
                                        font.pixelSize: Style.fontXs
                                    }
                                }

                                Rectangle {
                                    visible: tile.index > 0
                                    anchors.verticalCenter: parent.verticalCenter
                                    x: -14.5
                                    width: 1
                                    height: parent.height * 0.6
                                    color: Style.outline
                                }
                            }
                        }
                    }
                }

                // ---- An app: its time and share, and its windows -----------
                Item {
                    width: parent.width
                    height: appName.implicitHeight
                    visible: panel.appMode

                    Txt {
                        y: 1.5
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                        text: appName.text
                        color: Qt.alpha(Colors.background, 0.9)
                        font.pixelSize: Style.fontXl
                        font.bold: true
                    }

                    Txt {
                        id: appName

                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                        text: panel.curApp.name
                        color: Colors.foreground
                        font.pixelSize: Style.fontXl
                        font.bold: true
                    }
                }

                Txt {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    visible: panel.appMode
                    text: panel.fmt(panel.curApp.sec) + "  ·  " + Math.round(panel.curApp.sec / Math.max(1, panel.view.total) * 100) + "% of the total"
                    color: Qt.alpha(Colors.foreground, 0.86)
                    style: Text.Outline
                    styleColor: Qt.alpha(Colors.background, 0.8)
                    font.pixelSize: Style.fontBase
                }

                // Against the busiest app, in the app's own colour
                Item {
                    width: parent.width
                    height: 5
                    visible: panel.appMode

                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: 260
                        height: parent.height
                        radius: height / 2
                        antialiasing: true
                        color: Style.hoverFill

                        Rectangle {
                            width: parent.width * Math.min(1, panel.curApp.sec / panel.topAppSec)
                            height: parent.height
                            radius: height / 2
                            antialiasing: true
                            color: panel.catColor(panel.curApp.cat)

                            Behavior on width {
                                NumberAnimation {
                                    duration: Style.moveMs
                                    easing.type: Style.easeMove
                                }
                            }
                            Behavior on color {
                                ColorAnimation {
                                    duration: Style.baseMs
                                }
                            }
                        }
                    }
                }

                // The windows behind this app, biggest first
                Item {
                    width: parent.width
                    height: titlesCol.implicitHeight
                    visible: panel.appMode && panel.shownTitles.length > 0

                    Column {
                        id: titlesCol

                        anchors.horizontalCenter: parent.horizontalCenter
                        width: Math.min(parent.width, 480)
                        spacing: 2

                        Repeater {
                            model: panel.shownTitles

                            delegate: Item {
                                id: titleRow

                                required property int index
                                required property var modelData

                                // Each title eases in after the one above it
                                property real appear: 0

                                width: titlesCol.width
                                height: titleText.implicitHeight + 4
                                opacity: appear
                                transform: Translate {
                                    x: (1 - titleRow.appear) * 8
                                }
                                Component.onCompleted: appearAnim.start()

                                SequentialAnimation {
                                    id: appearAnim

                                    PauseAnimation {
                                        duration: Math.min(titleRow.index, 6) * 30
                                    }
                                    NumberAnimation {
                                        target: titleRow
                                        property: "appear"
                                        to: 1
                                        duration: Style.baseMs
                                        easing.type: Style.easeMove
                                    }
                                }

                                Txt {
                                    id: titleText

                                    anchors.left: parent.left
                                    anchors.right: titleTime.left
                                    anchors.rightMargin: Style.spaceLg
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: titleRow.modelData[0] !== "" ? titleRow.modelData[0] : "(untitled)"
                                    elide: Text.ElideRight
                                    color: Qt.alpha(Colors.foreground, 0.86)
                                    style: Text.Outline
                                    styleColor: Qt.alpha(Colors.background, 0.8)
                                    font.pixelSize: Style.fontMd
                                }

                                Txt {
                                    id: titleTime

                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: panel.fmt(titleRow.modelData[1])
                                    color: Qt.alpha(Colors.foreground, 0.7)
                                    style: Text.Outline
                                    styleColor: Qt.alpha(Colors.background, 0.8)
                                    font.pixelSize: Style.fontSm
                                }
                            }
                        }
                    }
                }

                // More windows than are shown
                Txt {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    visible: panel.appMode && panel.curApp.titles.length > panel.shownTitles.length
                    text: "and " + (panel.curApp.titles.length - panel.shownTitles.length) + " more"
                    color: Qt.alpha(Colors.foreground, 0.7)
                    style: Text.Outline
                    styleColor: Qt.alpha(Colors.background, 0.85)
                    font.pixelSize: Style.fontSm
                }

                // ---- Nothing to show, or the numbers could not be read -----
                Txt {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    visible: panel.msgMode
                    text: panel.msgTitle
                    color: Colors.foreground
                    style: Text.Outline
                    styleColor: Qt.alpha(Colors.background, 0.85)
                    font.pixelSize: Style.fontLg
                    font.bold: true
                }

                Txt {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    visible: panel.msgMode && text !== ""
                    text: panel.msgSub
                    color: Qt.alpha(Colors.foreground, 0.78)
                    style: Text.Outline
                    styleColor: Qt.alpha(Colors.background, 0.85)
                    font.pixelSize: Style.fontMd
                }
            }
        }

        // ---- Under the readout: the few things you can do -----------------
        Row {
            id: actions

            x: stage.cx - width / 2
            y: stage.height - panel.actionsH - Style.panelFoot
            spacing: Style.spaceMd
            // If the row is ever wider than the stage it shrinks to fit
            scale: Math.min(1, (stage.width - 32) / Math.max(1, actions.implicitWidth))
            opacity: panel.stage_(0.35, 0.9)
            transform: Translate {
                y: (1 - panel.stage_(0.35, 0.9)) * 10
            }

            IconButton {
                anchors.verticalCenter: parent.verticalCenter
                glyph: Icons.chevronLeft
                glyphSize: 16
                active: panel.view.has_older
                onClicked: panel.step(1)
            }

            // Day / Week / Month
            TextButton {
                compact: true
                primary: panel.range === "day"
                text: "Day"
                onClicked: panel.setRange("day")
            }
            TextButton {
                compact: true
                primary: panel.range === "week"
                text: "Week"
                onClicked: panel.setRange("week")
            }
            TextButton {
                compact: true
                primary: panel.range === "month"
                text: "Month"
                onClicked: panel.setRange("month")
            }

            IconButton {
                anchors.verticalCenter: parent.verticalCenter
                glyph: Icons.chevronRight
                glyphSize: 16
                active: panel.offset > 0
                onClicked: panel.step(-1)
            }

            // Back to the present, when looking at the past
            TextButton {
                compact: true
                visible: panel.offset > 0
                text: "Today"
                onClicked: panel.goToday()
            }

            TextButton {
                compact: true
                visible: panel.hasData && panel.view.apps.length > 6
                text: panel.showAll ? "Fewer apps" : "More apps"
                onClicked: panel.toggleAll()
            }

            // Only for an app with more windows than are shown
            TextButton {
                compact: true
                visible: panel.appMode && panel.curApp.titles.length > panel.titlesShort
                text: panel.curExpanded ? "Fewer windows" : "All windows"
                onClicked: panel.toggleSelected()
            }
        }
    }
}
