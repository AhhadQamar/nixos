import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland

// The notification centre: no panel, just the cards. Each notification is a glass
// card of its own, hung off a thin ruler against the right edge. The card the
// cursor is on is the widest and opens; the others narrow and fade with their
// distance from it, like the magnifier in the bar's ruler.
//
//   chips           what is new, the tabs, search, do not disturb, clear all
//   the cards       newest first, by day
//   keys            what the keys do
//
// All state lives in NotificationServer.qml. This file is only what is on
// screen: the tab, the search, which row the cursor is on, which are ticked, and
// the keys. The window is created when the centre opens and dropped after it
// closes, so a closed centre costs nothing.
PanelWindow {
    id: panel

    // ---- View state ---------------------------------------------------------
    property string tab: "all"
    property string query: ""
    property string cursorKey: ""
    property int lastIndex: 0
    property var ticked: ({})
    property bool showHelp: false
    property bool groupByApp: false
    property bool searching: false
    property bool clearArmed: false
    property string tip: ""
    property string note: ""
    property bool noteIsError: false
    property real reveal: 0
    property var targetScreen: Focus.screen

    // "New" is the big count at the top (click it, or Tab through); the tab row
    // shows the other three
    readonly property var tabs: [
        {
            "id": "all",
            "label": "All"
        },
        {
            "id": "fresh",
            "label": "New"
        },
        {
            "id": "urgent",
            "label": "Urgent"
        },
        {
            "id": "snoozed",
            "label": "Snoozed"
        }
    ]
    readonly property var shownTabs: tabs.filter(t => t.id !== "fresh")

    // ---- Layout -------------------------------------------------------------
    readonly property real screenW: targetScreen ? targetScreen.width : 1920
    readonly property real screenH: targetScreen ? targetScreen.height : 1080
    // The column the cards and the rail sit in, against the right edge
    readonly property int cardW: Math.round(Math.min(470, screenW - 32))
    readonly property int edge: Style.barGap + 2
    readonly property int railTop: Style.barGap + Style.barHeight + Style.barGap
    readonly property int chipsH: 36
    readonly property int footH: 34
    readonly property int listTop: railTop + chipsH + 12
    readonly property int colX: Math.round(screenW) - edge - cardW

    // ---- The list as shown --------------------------------------------------
    readonly property var counts: {
        let all = 0;
        let fresh = 0;
        let urgent = 0;
        let snoozed = 0;
        for (const n of NotificationServer.history) {
            if (n.snoozeUntil > 0) {
                snoozed++;
                continue;
            }
            all++;
            if (n.time > NotificationServer.newSince)
                fresh++;
            if (n.critical)
                urgent++;
        }
        return {
            "all": all,
            "fresh": fresh,
            "urgent": urgent,
            "snoozed": snoozed
        };
    }
    readonly property var shownRows: {
        const q = query.trim();
        const src = NotificationServer.history;
        const items = [];
        for (let i = 0; i < src.length; i++) {
            const n = src[i];
            const snoozed = n.snoozeUntil > 0;
            if (tab === "snoozed") {
                if (!snoozed)
                    continue;
            } else if (snoozed) {
                continue;
            }
            if (tab === "fresh" && n.time <= NotificationServer.newSince)
                continue;
            if (tab === "urgent" && !n.critical)
                continue;
            let s = 0;
            if (q !== "") {
                s = Fuzzy.score(n.summary + " " + n.body + " " + n.appName, q);
                if (s < 0)
                    continue;
            }
            items.push({
                "n": n,
                "s": s,
                "i": i
            });
        }
        // Search results are ranked, not grouped
        if (q !== "") {
            items.sort((a, b) => b.s - a.s || a.i - b.i);
            return items.map(x => x.n);
        }
        if (!groupByApp) {
            // Newest first, each day under its own title (today's has none)
            const now = new Date();
            const today = new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime();
            const yesterday = new Date(now.getFullYear(), now.getMonth(), now.getDate() - 1).getTime();
            const days = [];
            let last = -1;
            for (const x of items) {
                const d = new Date(x.n.time);
                const ds = new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime();
                if (ds !== last) {
                    last = ds;
                    if (ds !== today)
                        days.push({
                            "header": true,
                            "day": true,
                            "key": "d:" + ds,
                            "appName": ds === yesterday ? "yesterday" : Qt.formatDate(new Date(ds), "ddd d MMM"),
                            "count": 0
                        });
                }
                days.push(x.n);
            }
            return days;
        }
        // Apps ordered by their newest notification, each under its own title
        const order = [];
        const by = Object.create(null);
        for (const x of items) {
            const a = x.n.appName;
            if (by[a] === undefined) {
                by[a] = [];
                order.push(a);
            }
            by[a].push(x.n);
        }
        const out = [];
        for (const a of order) {
            out.push({
                "header": true,
                "key": "h:" + a,
                "appName": a,
                "count": by[a].length
            });
            for (const n of by[a])
                out.push(n);
        }
        return out;
    }
    readonly property var entryRows: shownRows.filter(r => r.header !== true)
    readonly property int entryIndex: {
        const l = entryRows;
        for (let i = 0; i < l.length; i++) {
            if (l[i].key === cursorKey)
                return i;
        }
        return -1;
    }
    readonly property int cursorIndex: {
        const l = shownRows;
        for (let i = 0; i < l.length; i++) {
            if (l[i].key === cursorKey)
                return i;
        }
        return -1;
    }
    readonly property var cur: entryIndex >= 0 ? entryRows[entryIndex] : null
    readonly property int tickedCount: Object.keys(ticked).length
    readonly property bool curCritical: cur !== null && cur.critical === true
    readonly property color tint: curCritical ? Colors.critical : Colors.accent
    readonly property bool curSnoozed: cur !== null && cur.snoozeUntil > 0
    readonly property string curCode: cur !== null ? NotificationServer.codeOf(cur) : ""
    readonly property string curLink: cur !== null ? NotificationServer.linkOf(cur) : ""
    // The notification's own buttons: all of them, four at most. An app that
    // only offers the click on the notification ("default") gets one, "Open".
    // Empty once the app has taken the notification back.
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
        return own.slice(0, 4);
    }
    // What the empty centre says about do not disturb
    readonly property string dndText: {
        if (!NotificationServer.doNotDisturb)
            return "New ones will show up here";
        if (NotificationServer.dndUntil > 0)
            return "Do not disturb until " + Qt.formatTime(new Date(NotificationServer.dndUntil), "HH:mm");
        return "Do not disturb is on";
    }
    readonly property string curMeta: {
        if (cur === null)
            return "";
        const parts = [cur.appName, NotificationServer.ago(cur.time, clock.date.getTime()) === "now" ? "just now" : NotificationServer.ago(cur.time, clock.date.getTime()) + " ago"];
        if (cur.critical)
            parts.push("Urgent");
        if (curSnoozed)
            parts.push("snoozed until " + Qt.formatTime(new Date(cur.snoozeUntil), "HH:mm"));
        if (cur.restored)
            parts.push("from before the restart");
        return parts.join("  \u00b7  ");
    }

    readonly property var keyHelp: [
        {
            "k": ["\u2191", "\u2193"],
            "d": "Move  (j k)"
        },
        {
            "k": ["\u2190", "\u2192"],
            "d": "Switch tab  (h l)"
        },
        {
            "k": ["[", "]"],
            "d": "Previous / next app"
        },
        {
            "k": ["Enter"],
            "d": "Run the first button"
        },
        {
            "k": ["1\u20134"],
            "d": "Run that button"
        },
        {
            "k": ["x"],
            "d": "Dismiss  (Del)"
        },
        {
            "k": ["Shift", "X"],
            "d": "Clear the whole app"
        },
        {
            "k": ["c"],
            "d": "Copy the code, or the text"
        },
        {
            "k": ["Shift", "C"],
            "d": "Copy the text"
        },
        {
            "k": ["o"],
            "d": "Open the link in it"
        },
        {
            "k": ["z"],
            "d": "Snooze 10 minutes"
        },
        {
            "k": ["m"],
            "d": "Snooze until 8:00"
        },
        {
            "k": ["Shift", "Z"],
            "d": "Snooze an hour"
        },
        {
            "k": ["Space"],
            "d": "Tick a row"
        },
        {
            "k": ["a"],
            "d": "Tick all shown"
        },
        {
            "k": ["d"],
            "d": "Do not disturb"
        },
        {
            "k": ["Shift", "D"],
            "d": "Silence for an hour"
        },
        {
            "k": ["g"],
            "d": "Group by app, or by day"
        },
        {
            "k": ["/"],
            "d": "Search"
        },
        {
            "k": ["Esc"],
            "d": "Back / close"
        }
    ]

    screen: targetScreen
    // `ready` makes the window appear one step after it is built, so PanelLink,
    // which reacts to the window becoming visible, sees it open
    property bool ready: false
    visible: ready && (NotificationServer.centerOpen || reveal > 0.001)
    color: "transparent"
    exclusiveZone: 0
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "qs-notifications"
    WlrLayershell.keyboardFocus: NotificationServer.centerOpen ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    // ---- Opening and closing ------------------------------------------------
    function close() {
        NotificationServer.closeCenter();
    }

    function go(open) {
        anim.stop();
        anim.to = open ? 1 : 0;
        anim.duration = open ? Style.enterMs : Style.baseMs;
        anim.easing.type = open ? Style.easeEnter : Style.easeExit;
        anim.start();
    }

    function resetView() {
        ticked = {};
        showHelp = false;
        clearArmed = false;
        query = "";
        searchField.text = "";
        searching = false;
        keys.forceActiveFocus();
    }

    function openSearch() {
        searching = true;
        Qt.callLater(() => searchField.forceActiveFocus());
    }

    function say(text, isError) {
        note = text;
        noteIsError = !!isError;
        noteTimer.restart();
    }

    function leaveInput() {
        keys.forceActiveFocus();
        if (query === "")
            searching = false;
    }

    // ---- The cursor ---------------------------------------------------------
    function jump(i) {
        const l = entryRows;
        if (l.length === 0)
            return;
        cursorKey = l[Math.max(0, Math.min(l.length - 1, i))].key;
    }

    function moveCursor(d) {
        jump((entryIndex < 0 ? 0 : entryIndex) + d);
    }

    // First entry of the previous (dir < 0) or next (dir > 0) app
    function stepApp(dir) {
        const l = entryRows;
        if (entryIndex < 0)
            return;
        const app = l[entryIndex].appName;
        if (dir > 0) {
            for (let i = entryIndex + 1; i < l.length; i++) {
                if (l[i].appName !== app) {
                    cursorKey = l[i].key;
                    return;
                }
            }
            return;
        }
        let j = entryIndex - 1;
        while (j >= 0 && l[j].appName === app)
            j--;
        if (j < 0)
            return;
        const prev = l[j].appName;
        while (j > 0 && l[j - 1].appName === prev)
            j--;
        cursorKey = l[j].key;
    }

    // Keeps the cursor on a real row as the list changes under it
    function fixCursor() {
        const l = entryRows;
        const t = {};
        const live = {};
        l.forEach(e => live[e.key] = true);
        Object.keys(ticked).forEach(function (k) {
            if (live[k])
                t[k] = true;
        });
        if (Object.keys(t).length !== tickedCount)
            ticked = t;
        if (l.length === 0) {
            cursorKey = "";
            return;
        }
        for (let i = 0; i < l.length; i++) {
            if (l[i].key === cursorKey) {
                lastIndex = i;
                return;
            }
        }
        cursorKey = l[Math.min(lastIndex, l.length - 1)].key;
    }

    onEntryRowsChanged: fixCursor()
    onCursorKeyChanged: {
        if (entryIndex >= 0)
            lastIndex = entryIndex;
    }

    function targets() {
        if (tickedCount > 0)
            return entryRows.filter(e => ticked[e.key] === true);
        return cur !== null ? [cur] : [];
    }

    function toggleTick(key) {
        const t = Object.assign({}, ticked);
        if (t[key])
            delete t[key];
        else
            t[key] = true;
        ticked = t;
    }

    function tickAll() {
        const t = {};
        entryRows.forEach(e => t[e.key] = true);
        ticked = t;
    }

    function stepTab(d) {
        const i = tabs.findIndex(t => t.id === tab);
        tab = tabs[(i + d + tabs.length) % tabs.length].id;
    }

    // ---- Doing things -------------------------------------------------------
    function dismissTargets() {
        const t = targets();
        if (t.length === 0)
            return;
        NotificationServer.dismissEntries(t);
        ticked = {};
    }

    function clearThisApp() {
        if (cur === null)
            return;
        NotificationServer.clearApp(cur.appName);
    }

    // The code in it if there is one, else the text; wl-copy's `--` keeps text that
    // starts with a dash from being taken as an option
    function copyEntry(e, forceText) {
        if (!e)
            return;
        const code = forceText ? "" : NotificationServer.codeOf(e);
        const t = code !== "" ? code : (e.body !== "" ? e.body : e.summary);
        if (t === "")
            return;
        Quickshell.execDetached(["wl-copy", "--", t]);
        say(code !== "" ? "Copied the code " + code : "Copied", false);
    }

    function openLink(e) {
        const l = e ? NotificationServer.linkOf(e) : "";
        if (l === "") {
            say("No link in this one", true);
            return;
        }
        Quickshell.execDetached(["xdg-open", l]);
        close();
    }

    // Run one of the notification's buttons: the app is told, the entry goes, and
    // the centre gets out of the way of whatever opens.
    function runAction(actionId) {
        const c = cur;
        if (c === null)
            return;
        NotificationServer.invokeAction(c, actionId);
        NotificationServer.dismissEntries([c]);
        close();
    }

    function runFirstAction() {
        if (curActions.length > 0)
            runAction(curActions[0].id);
        else if (curLink !== "")
            openLink(cur);
    }

    function snoozeTargets(minutes) {
        const t = targets();
        if (t.length === 0)
            return;
        if (t.every(e => e.snoozeUntil > 0)) {
            NotificationServer.unsnooze(t);
            say("Brought back", false);
        } else {
            NotificationServer.snooze(t.filter(e => !(e.snoozeUntil > 0)), minutes);
            say(minutes === 60 ? "Snoozed for an hour" : (minutes === 480 ? "Snoozed until the morning" : "Snoozed for " + minutes + " minutes"), false);
        }
        ticked = {};
    }

    function snoozeMorning() {
        const t = targets().filter(e => !(e.snoozeUntil > 0));
        if (t.length === 0)
            return;
        NotificationServer.snoozeUntilHour(t, 8);
        say("Snoozed until 8:00", false);
        ticked = {};
    }

    function clearPressed() {
        if (NotificationServer.history.length === 0)
            return;
        if (!clearArmed) {
            clearArmed = true;
            clearTimer.restart();
            say("Press again to clear everything", true);
            return;
        }
        clearArmed = false;
        NotificationServer.clearHistory();
        ticked = {};
    }

    function rowClicked(key, ctrl) {
        leaveInput();
        if (ctrl) {
            cursorKey = key;
            toggleTick(key);
        } else {
            cursorKey = key;
        }
    }

    // ---- Keys ---------------------------------------------------------------
    function handleKey(event) {
        const k = event.key;
        const ctrl = (event.modifiers & Qt.ControlModifier) !== 0;
        const shift = (event.modifiers & Qt.ShiftModifier) !== 0;
        // One press, one thing: holding these does not repeat
        const once = [Qt.Key_Delete, Qt.Key_Backspace, Qt.Key_X, Qt.Key_Return, Qt.Key_Enter, Qt.Key_1, Qt.Key_2, Qt.Key_3, Qt.Key_4, Qt.Key_C, Qt.Key_D, Qt.Key_Z, Qt.Key_Space, Qt.Key_Escape, Qt.Key_O, Qt.Key_G, Qt.Key_A, Qt.Key_M];
        if (event.isAutoRepeat && once.indexOf(k) >= 0) {
            event.accepted = true;
            return;
        }
        if (showHelp) {
            if (k === Qt.Key_Escape || k === Qt.Key_Question || k === Qt.Key_Return || k === Qt.Key_Enter)
                showHelp = false;
            event.accepted = true;
            return;
        }
        event.accepted = true;
        if (k === Qt.Key_Escape) {
            if (tickedCount > 0)
                ticked = {};
            else if (query !== "") {
                searchField.text = "";
                searching = false;
            } else
                close();
            return;
        }
        if (ctrl) {
            if (k === Qt.Key_N)
                moveCursor(1);
            else if (k === Qt.Key_P)
                moveCursor(-1);
            else
                event.accepted = false;
            return;
        }
        switch (k) {
        case Qt.Key_Down:
        case Qt.Key_J:
            moveCursor(1);
            return;
        case Qt.Key_Up:
        case Qt.Key_K:
            moveCursor(-1);
            return;
        case Qt.Key_PageDown:
            moveCursor(6);
            return;
        case Qt.Key_PageUp:
            moveCursor(-6);
            return;
        case Qt.Key_Home:
            jump(0);
            return;
        case Qt.Key_End:
            jump(entryRows.length - 1);
            return;
        case Qt.Key_Right:
        case Qt.Key_Tab:
        case Qt.Key_L:
            stepTab(1);
            return;
        case Qt.Key_Left:
        case Qt.Key_Backtab:
        case Qt.Key_H:
            stepTab(-1);
            return;
        case Qt.Key_BracketRight:
            stepApp(1);
            return;
        case Qt.Key_BracketLeft:
            stepApp(-1);
            return;
        case Qt.Key_Return:
        case Qt.Key_Enter:
            runFirstAction();
            return;
        case Qt.Key_1:
        case Qt.Key_2:
        case Qt.Key_3:
        case Qt.Key_4:
            {
                const a = curActions[k - Qt.Key_1];
                if (a)
                    runAction(a.id);
                return;
            }
        case Qt.Key_X:
            if (shift)
                clearThisApp();
            else
                dismissTargets();
            return;
        case Qt.Key_Delete:
        case Qt.Key_Backspace:
            dismissTargets();
            return;
        case Qt.Key_C:
            copyEntry(cur, shift);
            return;
        case Qt.Key_O:
            openLink(cur);
            return;
        case Qt.Key_Z:
            snoozeTargets(shift ? 60 : 10);
            return;
        case Qt.Key_M:
            snoozeMorning();
            return;
        case Qt.Key_Space:
            if (cursorKey !== "")
                toggleTick(cursorKey);
            return;
        case Qt.Key_A:
            tickAll();
            return;
        case Qt.Key_D:
            if (shift)
                NotificationServer.dndFor(60);
            else
                NotificationServer.toggleDnd();
            return;
        case Qt.Key_G:
            groupByApp = !groupByApp;
            return;
        case Qt.Key_Slash:
            openSearch();
            return;
        case Qt.Key_Question:
            showHelp = true;
            return;
        default:
            event.accepted = false;
        }
    }

    Component.onCompleted: {
        targetScreen = Focus.screen;
        fixCursor();
        go(true);
        keys.forceActiveFocus();
        Qt.callLater(() => ready = true);
    }

    Connections {
        target: NotificationServer

        function onCenterOpenChanged() {
            panel.go(NotificationServer.centerOpen);
            if (NotificationServer.centerOpen)
                panel.resetView();
        }
    }

    NumberAnimation {
        id: anim

        target: panel
        property: "reveal"
        onFinished: {
            if (!NotificationServer.centerOpen)
                Qt.callLater(NotificationServer.panelGone);
        }
    }

    // Keeps the "5m" labels current while the centre is open
    SystemClock {
        id: clock

        precision: SystemClock.Minutes
        enabled: NotificationServer.centerOpen
    }

    Timer {
        id: clearTimer

        interval: 3000
        onTriggered: panel.clearArmed = false
    }

    Timer {
        id: noteTimer

        interval: 3000
        onTriggered: panel.note = ""
    }

    PanelLink {
        win: panel
        name: "notifications"
    }

    // Like the other panels: a click that lands anywhere the compositor does not
    // consider this window closes it (and toggleCenter ignores the same click if
    // it landed on the bell that toggles the centre)
    HyprlandFocusGrab {
        windows: [panel]
        active: NotificationServer.centerOpen && panel.visible
        onCleared: {
            NotificationServer.closedAt = Date.now();
            NotificationServer.closeCenter();
        }
    }

    Dim {
        reveal: panel.reveal
        closes: true
        onClicked: panel.close()
    }

    Item {
        id: keys

        anchors.fill: parent
        focus: true
        Keys.onPressed: event => panel.handleKey(event)
    }

    // A soft shade down the right edge so the cards and the rail read over any window
    Rectangle {
        x: panel.colX - 90
        y: 0
        width: panel.width - x
        height: panel.height
        opacity: panel.reveal

        gradient: Gradient {
            orientation: Gradient.Horizontal

            GradientStop {
                position: 0
                color: Qt.alpha(Colors.background, 0)
            }
            GradientStop {
                position: 0.4
                color: Qt.alpha(Colors.background, 0.55)
            }
            GradientStop {
                position: 1
                color: Qt.alpha(Colors.background, 0.78)
            }
        }
    }

    // ---- Header: the tabs as chips, and the switches ------------------------------
    Item {
        id: chips

        x: panel.width - panel.edge - panel.cardW
        y: panel.railTop
        width: panel.cardW - 28
        height: panel.chipsH
        opacity: panel.reveal

        Row {
            id: chipRow

            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6
            visible: !(panel.searching || panel.query !== "")

            // One filter: click to go round all, new, urgent, snoozed
            Rectangle {
                id: filter

                readonly property string label: panel.tab === "fresh" ? "new" : panel.tab
                readonly property int n: panel.counts[panel.tab] || 0

                height: 28
                width: filterRow.width + 26
                radius: 14
                color: panel.tab === "all" ? (filterHover.hovered ? Style.hoverFill : Style.well) : Qt.alpha(panel.tab === "urgent" ? Colors.critical : Colors.accent, 0.18)
                border.width: 1
                border.color: panel.tab === "all" ? "transparent" : Qt.alpha(panel.tab === "urgent" ? Colors.critical : Colors.accent, 0.5)

                Row {
                    id: filterRow

                    anchors.centerIn: parent
                    spacing: 6

                    Txt {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: panel.tab !== "all"
                        text: String(filter.n)
                        color: panel.tab === "urgent" ? Colors.critical : Colors.accent
                        font.pixelSize: Style.fontBase
                    }

                    Txt {
                        anchors.verticalCenter: parent.verticalCenter
                        text: panel.tab === "all" ? "all  \u00b7  " + panel.counts.all : filter.label
                        color: panel.tab === "all" ? Colors.foreground : (panel.tab === "urgent" ? Colors.critical : Colors.accent)
                        font.pixelSize: Style.fontMd
                    }

                    Txt {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: panel.tab === "all" && panel.counts.fresh > 0
                        text: panel.counts.fresh + " new"
                        color: Colors.accent
                        font.pixelSize: Style.fontMd
                    }
                }

                HoverHandler {
                    id: filterHover

                    cursorShape: Qt.PointingHandCursor
                }
                TapHandler {
                    onTapped: {
                        const order = ["all", "fresh", "urgent", "snoozed"];
                        panel.tab = order[(order.indexOf(panel.tab) + 1) % order.length];
                        panel.leaveInput();
                    }
                }
            }

            IconButton {
                glyph: Icons.search
                tip: "Search ( / )"
                onClicked: panel.openSearch()
                onHoveredChanged: panel.tip = hovered ? tip : ""
            }

            IconButton {
                glyph: NotificationServer.doNotDisturb ? Icons.bellOff : Icons.bell
                on: NotificationServer.doNotDisturb
                tip: "Do not disturb (d)  \u00b7  an hour (Shift+D)"
                onClicked: NotificationServer.toggleDnd()
                onHoveredChanged: panel.tip = hovered ? tip : ""
            }

            IconButton {
                visible: NotificationServer.history.length > 0
                glyph: Icons.trash
                danger: true
                on: panel.clearArmed
                tip: panel.clearArmed ? "Press again to clear everything" : "Clear everything"
                onClicked: panel.clearPressed()
                onHoveredChanged: panel.tip = hovered ? tip : ""
            }
        }

        SearchField {
            id: searchField

            visible: panel.searching || panel.query !== ""
            anchors.fill: parent
            placeholder: "Search  ( / )"
            fontSize: Style.fontMd
            badge: panel.query.trim() !== "" ? String(panel.entryRows.length) : ""
            onTextChanged: panel.query = text
            onAccepted: panel.leaveInput()
            Keys.onEscapePressed: {
                if (text !== "")
                    text = "";
                panel.searching = false;
                panel.leaveInput();
            }
            Keys.onDownPressed: {
                panel.moveCursor(1);
                panel.leaveInput();
            }
            Keys.onUpPressed: {
                panel.moveCursor(-1);
                panel.leaveInput();
            }
        }
    }

    // ---- The rail ---------------------------------------------------------------
    Rectangle {
        x: panel.colX + panel.cardW - 13 - 0.5 + (1 - panel.reveal) * 40
        y: panel.railTop
        width: 1
        height: panel.height - panel.railTop - panel.edge
        opacity: panel.reveal
        gradient: Gradient {
            GradientStop {
                position: 0
                color: "transparent"
            }
            GradientStop {
                position: 0.1
                color: Qt.alpha(Colors.foreground, 0.14)
            }
            GradientStop {
                position: 0.9
                color: Qt.alpha(Colors.foreground, 0.14)
            }
            GradientStop {
                position: 1
                color: "transparent"
            }
        }
    }

    // ---- The cards, or the keys ---------------------------------------------------
    Item {
        id: listArea

        x: panel.colX + (1 - panel.reveal) * 40
        y: panel.listTop
        width: panel.cardW
        height: panel.height - panel.listTop - panel.footH - panel.edge
        opacity: panel.reveal
        visible: !panel.showHelp

        ListView {
            id: list

            anchors.fill: parent
            visible: count > 0
            clip: true
            spacing: 0
            boundsBehavior: Flickable.StopAtBounds
            cacheBuffer: 300
            currentIndex: panel.cursorIndex
            onCurrentIndexChanged: if (currentIndex >= 0)
                positionViewAtIndex(currentIndex, ListView.Contain)

            model: ScriptModel {
                values: panel.shownRows
                objectProp: "key"
            }

            // A dismissed row fades and its neighbours close the gap
            remove: Transition {
                ParallelAnimation {
                    NumberAnimation {
                        property: "opacity"
                        to: 0
                        duration: Style.baseMs
                    }
                    NumberAnimation {
                        property: "scale"
                        to: 0.92
                        duration: Style.baseMs
                    }
                }
            }

            displaced: Transition {
                NumberAnimation {
                    properties: "y"
                    duration: Style.moveMs
                    easing.type: Style.easeMove
                }
            }

            delegate: NotificationRow {
                width: list.width
                dist: panel.cursorIndex < 0 ? 1 : Math.abs(index - panel.cursorIndex)
                current: modelData.key === panel.cursorKey
                ticked: panel.ticked[modelData.key] === true
                nowMs: clock.date.getTime()
                actions: current ? panel.curActions : []
                onClicked: ctrl => panel.rowClicked(modelData.key, ctrl)
                onActionClicked: id => panel.runAction(id)
                onCopyClicked: panel.copyEntry(modelData, false)
                onCopyTextClicked: panel.copyEntry(modelData, true)
                onLinkClicked: panel.openLink(modelData)
                onSnoozeClicked: {
                    if (modelData.snoozeUntil > 0)
                        NotificationServer.unsnooze([modelData]);
                    else
                        NotificationServer.snooze([modelData], 10);
                }
                onDismissClicked: NotificationServer.dismissEntries([modelData])
                onGroupClearClicked: NotificationServer.clearApp(modelData.appName)
                onTipped: text => panel.tip = text
                // The open row grows: keep all of it in view
                onHeightChanged: if (current && list.moving === false)
                    list.positionViewAtIndex(index, ListView.Contain)
            }
        }

        // The log fades out at the foot
        Rectangle {
            visible: list.visible
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 40

            gradient: Gradient {
                GradientStop {
                    position: 0
                    color: Qt.alpha(Colors.background, 0)
                }
                GradientStop {
                    position: 1
                    color: Style.card
                }
            }
        }

        // Nothing to show
        Column {
            visible: list.count === 0
            anchors.centerIn: parent
            spacing: 10

            Txt {
                anchors.horizontalCenter: parent.horizontalCenter
                text: panel.query.trim() !== "" ? Icons.search : (NotificationServer.doNotDisturb ? Icons.bellOff : Icons.bell)
                color: NotificationServer.doNotDisturb ? Colors.accent : Colors.muted
                opacity: NotificationServer.doNotDisturb ? 1 : 0.6
                font.pixelSize: 26
            }

            Txt {
                anchors.horizontalCenter: parent.horizontalCenter
                text: panel.query.trim() !== "" ? "Nothing matches" : (panel.tab === "snoozed" ? "Nothing snoozed" : (panel.tab === "urgent" ? "Nothing urgent" : (panel.tab === "fresh" ? "Nothing new" : "Nothing to see")))
                color: Colors.foreground
                opacity: 0.85
                font.pixelSize: Style.fontBase
            }

            Txt {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: panel.query.trim() === "" && panel.tab === "all"
                text: panel.dndText
                wrapMode: Text.WordWrap
                horizontalAlignment: Text.AlignHCenter
                width: Math.min(implicitWidth, 260)
                color: Colors.muted
                font.pixelSize: Style.fontSm
            }

            TextButton {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: NotificationServer.doNotDisturb && panel.query.trim() === "" && panel.tab === "all"
                compact: true
                primary: true
                text: "turn do not disturb off"
                onClicked: NotificationServer.toggleDnd()
            }
        }
    }

    Rectangle {
        visible: panel.showHelp
        x: panel.colX + (1 - panel.reveal) * 40
        y: panel.listTop
        width: panel.cardW - 38
        height: Math.min(helpGrid.height + 32, panel.height - panel.listTop - panel.footH - panel.edge)
        radius: Style.radiusXl + 2
        color: Style.card
        border.width: 1
        border.color: Style.outline
        opacity: panel.reveal

        EdgeLight {}

        Grid {
            id: helpGrid

            anchors.centerIn: parent
            columns: 2
            columnSpacing: 20
            rowSpacing: 7
            flow: Grid.TopToBottom
            rows: Math.ceil(panel.keyHelp.length / 2)

            Repeater {
                model: panel.keyHelp

                delegate: Item {
                    required property var modelData

                    width: (panel.cardW - 38 - 32 - 20) / 2
                    height: 22

                    Row {
                        spacing: 3
                        width: 70

                        Repeater {
                            model: modelData.k

                            delegate: KeyCap {
                                required property string modelData

                                label: modelData
                            }
                        }
                    }

                    Txt {
                        x: 74
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 74
                        text: modelData.d
                        color: Colors.foreground
                        opacity: 0.8
                        font.pixelSize: Style.fontSm
                        elide: Text.ElideRight
                    }
                }
            }
        }
    }

    // ---- What the keys do right now ---------------------------------------------------
    Item {
        id: foot

        x: panel.colX
        y: panel.height - panel.edge - panel.footH
        width: panel.cardW - 38
        height: panel.footH
        opacity: panel.reveal

        // The tip for what the pointer is over, or what is ticked
        Txt {
            anchors.left: parent.left
            anchors.right: more.left
            anchors.rightMargin: 14
            anchors.verticalCenter: parent.verticalCenter
            visible: panel.tip !== "" || panel.tickedCount > 0
            horizontalAlignment: Text.AlignRight
            text: panel.tip !== "" ? panel.tip : panel.tickedCount + " ticked  \u00b7  x dismisses them  \u00b7  z snoozes  \u00b7  Esc unticks"
            color: Colors.muted
            font.pixelSize: Style.fontSm
            elide: Text.ElideLeft
        }

        Row {
            id: more

            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6

            KeyCap {
                anchors.verticalCenter: parent.verticalCenter
                label: "?"
            }

            Txt {
                anchors.verticalCenter: parent.verticalCenter
                text: panel.showHelp ? "back" : "keys"
                color: Colors.muted
                font.pixelSize: Style.fontSm
            }

            HoverHandler {
                cursorShape: Qt.PointingHandCursor
            }
            TapHandler {
                onTapped: panel.showHelp = !panel.showHelp
            }
        }
    }

    // ---- Feedback ---------------------------------------------------------------------
    Rectangle {
        anchors.horizontalCenter: foot.horizontalCenter
        anchors.bottom: foot.top
        anchors.bottomMargin: 8
        width: Math.min(panel.cardW - 60, toastText.implicitWidth + 32)
        height: 30
        radius: 15
        color: Style.card
        border.width: 1
        border.color: panel.noteIsError ? Qt.alpha(Colors.critical, 0.6) : Qt.alpha(Colors.accent, 0.5)
        opacity: panel.note !== "" && panel.reveal > 0.9 ? 1 : 0
        visible: opacity > 0.01

        Behavior on opacity {
            NumberAnimation {
                duration: Style.fadeMs
            }
        }

        Txt {
            id: toastText

            anchors.centerIn: parent
            width: Math.min(implicitWidth, panel.cardW - 92)
            text: panel.note
            color: panel.noteIsError ? Colors.critical : Colors.foreground
            font.pixelSize: Style.fontMd
            elide: Text.ElideRight
        }
    }
}
