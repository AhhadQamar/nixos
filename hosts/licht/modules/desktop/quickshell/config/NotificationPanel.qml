import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland

// The notification centre: one glass card, an eighth of the way down the screen.
//
//   7  new          the count of what arrived since you last looked, big;
//                   do not disturb and clear all beside it
//   the day         a ruler from 00 to 24: a tick every quarter hour, lit up to
//                   now, a dot where each notification arrived
//   tabs            All / Urgent / Snoozed, and search
//   the log         a row per notification, newest first, by day; the one the
//                   cursor is on opens with its buttons
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
    readonly property int cardW: Math.round(Math.min(520, screenW - 32))
    readonly property int pad: Style.cardPad
    readonly property int innerW: cardW - pad * 2
    readonly property int headH: 58
    readonly property int dayH: 74
    readonly property int tabsH: Style.fieldHeight
    readonly property int footH: 36
    readonly property int maxCardH: Math.round(screenH) - Style.panelTop - 48
    readonly property int maxBody: Math.max(200, maxCardH - pad * 2 - headH - 14 - dayH - tabsH - 4 - footH)
    readonly property int bodyH: Math.min(400, maxBody)

    // ---- The day --------------------------------------------------------------
    readonly property double dayStart: {
        const d = new Date(clock.date.getTime());
        d.setHours(0, 0, 0, 0);
        return d.getTime();
    }
    readonly property real nowMin: (clock.date.getTime() - dayStart) / 60000
    // A dot for every notification shown that arrived today
    readonly property var pips: entryRows.filter(e => e.time >= dayStart).map(e => ({
                "key": e.key,
                "m": (e.time - dayStart) / 60000,
                "fresh": e.time > NotificationServer.newSince,
                "crit": e.critical === true
            }))

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

    // ---- The card -----------------------------------------------------------
    Rectangle {
        id: card

        x: Math.round((panel.width - width) / 2)
        y: Style.panelTop
        width: panel.cardW
        height: Math.min(col.implicitHeight + panel.pad * 2, panel.maxCardH)
        radius: Style.radiusXl
        color: Style.card
        border.width: 1
        border.color: Style.outline
        opacity: panel.reveal
        scale: 0.97 + 0.03 * panel.reveal
        transformOrigin: Item.Top

        EdgeLight {}

        // A click on the gaps between things stays on the card (and takes the keys
        // back from the search) instead of falling through to the dim, which would
        // close the panel
        MouseArea {
            anchors.fill: parent
            onClicked: panel.leaveInput()
        }

        Column {
            id: col

            x: panel.pad
            y: panel.pad
            width: panel.innerW
            spacing: 0

            // ---- What is new, and the switches ---------------------------------
            Item {
                width: parent.width
                height: panel.headH

                Row {
                    id: tally

                    anchors.left: parent.left
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 6
                    spacing: 12

                    Txt {
                        id: numeral

                        text: String(panel.counts.fresh)
                        color: panel.counts.fresh > 0 ? Colors.foreground : Colors.muted
                        font.pixelSize: 52
                        font.weight: Font.Light
                        font.letterSpacing: -2
                        lineHeight: 0.9
                    }

                    Column {
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 4
                        spacing: 2

                        Txt {
                            text: panel.counts.fresh > 0 ? "new" : "all quiet"
                            color: panel.counts.fresh > 0 ? Colors.accent : Colors.muted
                            font.pixelSize: Style.fontMd
                        }

                        Txt {
                            text: panel.counts.fresh > 0 ? (NotificationServer.newSince > 0 ? "since " + Qt.formatTime(new Date(NotificationServer.newSince), "HH:mm") : "") : "nothing new"
                            visible: text !== ""
                            color: Colors.muted
                            font.pixelSize: Style.fontSm
                        }
                    }
                }

                // Click the count to see only the new ones
                MouseArea {
                    x: 0
                    y: 0
                    width: tally.width
                    height: parent.height
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        panel.tab = panel.tab === "fresh" ? "all" : "fresh";
                        panel.leaveInput();
                    }
                    onContainsMouseChanged: panel.tip = containsMouse ? (panel.tab === "fresh" ? "Show everything" : "Show only the new ones") : ""
                }

                Rectangle {
                    visible: panel.tab === "fresh"
                    x: 0
                    y: parent.height - 2
                    width: tally.width
                    height: 2
                    radius: 1
                    color: Colors.accent
                }

                Row {
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 4
                    spacing: 4

                    TextButton {
                        compact: true
                        raised: NotificationServer.doNotDisturb
                        primary: NotificationServer.doNotDisturb
                        glyph: NotificationServer.doNotDisturb ? Icons.bellOff : Icons.bell
                        text: NotificationServer.doNotDisturb ? (NotificationServer.dndUntil > 0 ? "silent until " + Qt.formatTime(new Date(NotificationServer.dndUntil), "HH:mm") : "silent") : "do not disturb"
                        onClicked: NotificationServer.toggleDnd()
                        onHoveredChanged: panel.tip = hovered ? "Do not disturb (d)  ·  an hour (Shift+D)" : ""
                    }

                    TextButton {
                        visible: NotificationServer.history.length > 0
                        compact: true
                        danger: panel.clearArmed
                        armed: panel.clearArmed
                        text: panel.clearArmed ? "press again" : "clear all"
                        onClicked: panel.clearPressed()
                        onHoveredChanged: panel.tip = hovered ? "Clear everything" : ""
                    }
                }
            }

            // ---- The day, as a ruler ------------------------------------------
            Item {
                id: day

                width: parent.width
                height: panel.dayH + 14

                // Where the notifications arrived
                Item {
                    y: 14
                    width: parent.width
                    height: 44

                    Repeater {
                        model: panel.pips

                        delegate: Item {
                            id: pip

                            required property var modelData
                            readonly property bool sel: modelData.key === panel.cursorKey
                            readonly property color dot: modelData.crit ? Colors.critical : (modelData.fresh ? Colors.accent : Qt.alpha(Colors.foreground, 0.3))

                            x: modelData.m / 1440 * day.width
                            y: 22
                            width: 0
                            height: 0

                            Rectangle {
                                visible: pip.sel || pip.modelData.crit
                                anchors.centerIn: parent
                                width: pip.sel ? 24 : 18
                                height: width
                                radius: width / 2
                                color: Qt.alpha(pip.modelData.crit ? Colors.critical : Colors.accent, pip.sel ? 0.18 : 0.12)
                            }

                            Rectangle {
                                anchors.centerIn: parent
                                width: pip.sel ? 11 : 6
                                height: width
                                radius: width / 2
                                color: pip.dot
                                z: pip.sel ? 1 : 0

                                Behavior on width {
                                    NumberAnimation {
                                        duration: Style.baseMs
                                        easing.type: Style.easeMove
                                    }
                                }
                            }

                            // A click on a dot goes to that notification
                            MouseArea {
                                x: -8
                                y: -8
                                width: 16
                                height: 16
                                cursorShape: Qt.PointingHandCursor
                                onClicked: panel.rowClicked(pip.modelData.key, false)
                            }
                        }
                    }
                }

                // A tick every quarter hour, long by the hour and the six hours,
                // lit up to now
                Repeater {
                    model: 97

                    delegate: Rectangle {
                        required property int index
                        readonly property bool six: index % 24 === 0
                        readonly property bool hour: index % 4 === 0
                        readonly property bool past: index * 15 <= panel.nowMin

                        x: index * 15 / 1440 * day.width
                        y: 14 + 46 - height
                        width: 1
                        height: six ? 13 : (hour ? 7 : 4)
                        color: past ? Qt.alpha(Colors.accent, six || hour ? 0.55 : 0.4) : Qt.alpha(Colors.foreground, 0.12)
                    }
                }

                // Now
                Rectangle {
                    x: panel.nowMin / 1440 * day.width - 5
                    y: 14 + 30 - 4
                    width: 11
                    height: 24
                    radius: 5.5
                    color: Qt.alpha(Colors.accent, 0.14)
                }
                Rectangle {
                    x: panel.nowMin / 1440 * day.width - 1
                    y: 14 + 30
                    width: 2
                    height: 16
                    radius: 1
                    color: Colors.accent
                }

                Repeater {
                    model: ["00", "06", "12", "18", "24"]

                    delegate: Txt {
                        required property string modelData
                        required property int index

                        x: index * 6 / 24 * day.width - width / 2
                        y: 14 + 52
                        text: modelData
                        color: Colors.muted
                        opacity: 0.7
                        font.pixelSize: 9
                    }
                }
            }

            // ---- Tabs, and search ---------------------------------------------
            Item {
                width: parent.width
                height: panel.tabsH + 4

                Row {
                    id: tabRow

                    anchors.left: parent.left
                    anchors.bottom: parent.bottom
                    spacing: 18

                    Repeater {
                        model: panel.shownTabs

                        delegate: Item {
                            id: tabItem

                            required property var modelData
                            readonly property int n: panel.counts[modelData.id] || 0
                            readonly property bool on: panel.tab === modelData.id

                            width: tabLabel.width
                            height: 30

                            Row {
                                id: tabLabel

                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 6

                                Txt {
                                    text: tabItem.modelData.label
                                    color: tabItem.on ? Colors.foreground : Colors.muted
                                    font.pixelSize: Style.fontMd
                                }

                                Txt {
                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.verticalCenterOffset: 1
                                    text: String(tabItem.n)
                                    color: Colors.muted
                                    opacity: 0.8
                                    font.pixelSize: Style.fontXs
                                }
                            }

                            Rectangle {
                                anchors.bottom: parent.bottom
                                width: parent.width
                                height: 1
                                color: tabItem.on ? Colors.foreground : "transparent"
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    panel.tab = tabItem.modelData.id;
                                    panel.leaveInput();
                                }
                            }
                        }
                    }
                }

                // The hairline under the tabs
                Rectangle {
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 0
                    width: parent.width
                    height: 1
                    z: -1
                    color: Qt.alpha(Colors.foreground, 0.07)
                }

                // Search: a quiet label until you use it
                Item {
                    id: searchSlot

                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    width: 210
                    height: panel.tabsH

                    Row {
                        visible: !(panel.searching || panel.query !== "")
                        anchors.right: parent.right
                        anchors.rightMargin: 6
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.verticalCenterOffset: -3
                        spacing: 6

                        Txt {
                            text: Icons.search
                            color: Colors.muted
                            font.pixelSize: Style.fontMd
                        }

                        Txt {
                            text: "search"
                            color: Colors.muted
                            font.pixelSize: Style.fontSm
                        }

                        HoverHandler {
                            cursorShape: Qt.PointingHandCursor
                        }
                        TapHandler {
                            onTapped: panel.openSearch()
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
            }

            // ---- The log, or the keys --------------------------------------------
            Item {
                id: body

                width: parent.width
                height: panel.bodyH + 8

                Item {
                    id: listArea

                    y: 8
                    width: parent.width
                    height: panel.bodyH
                    visible: !panel.showHelp

                    ListView {
                        id: list

                        anchors.fill: parent
                        visible: count > 0
                        clip: true
                        spacing: 2
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
                        height: 34

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

                // ---- The keys ----------------------------------------------------
                Item {
                    id: help

                    y: 8
                    width: parent.width
                    height: panel.bodyH
                    visible: panel.showHelp

                    Grid {
                        anchors.horizontalCenter: parent.horizontalCenter
                        columns: 2
                        columnSpacing: 28
                        rowSpacing: 7
                        flow: Grid.TopToBottom
                        rows: Math.ceil(panel.keyHelp.length / 2)

                        Repeater {
                            model: panel.keyHelp

                            delegate: Item {
                                required property var modelData

                                width: (help.width - 28) / 2
                                height: 22

                                Row {
                                    spacing: 3
                                    width: 80

                                    Repeater {
                                        model: modelData.k

                                        delegate: KeyCap {
                                            required property string modelData

                                            label: modelData
                                        }
                                    }
                                }

                                Txt {
                                    x: 84
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width - 84
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
            }

            // ---- What the keys do right now ----------------------------------------
            Item {
                width: parent.width
                height: panel.footH

                Row {
                    id: hints

                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 16
                    visible: panel.tip === "" && panel.tickedCount === 0

                    Repeater {
                        model: [["j k", "move"], ["x", "dismiss"], ["z", "snooze"], ["/", "search"]]

                        delegate: Row {
                            required property var modelData

                            spacing: 6

                            KeyCap {
                                anchors.verticalCenter: parent.verticalCenter
                                label: parent.modelData[0]
                            }

                            Txt {
                                anchors.verticalCenter: parent.verticalCenter
                                text: parent.modelData[1]
                                color: Colors.muted
                                font.pixelSize: Style.fontSm
                            }
                        }
                    }
                }

                // The tip for what the pointer is over, or what is ticked
                Txt {
                    anchors.left: parent.left
                    anchors.right: more.left
                    anchors.rightMargin: 14
                    anchors.verticalCenter: parent.verticalCenter
                    visible: !hints.visible
                    text: panel.tip !== "" ? panel.tip : panel.tickedCount + " ticked  ·  x dismisses them  ·  z snoozes  ·  Esc unticks"
                    color: Colors.muted
                    font.pixelSize: Style.fontSm
                    elide: Text.ElideRight
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
                        text: panel.showHelp ? "back" : "all keys"
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
        }
    }

    // ---- Feedback, above the card -------------------------------------------
    Rectangle {
        anchors.horizontalCenter: card.horizontalCenter
        anchors.bottom: card.top
        anchors.bottomMargin: 10
        width: Math.min(panel.cardW, toastText.implicitWidth + 32)
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
            width: Math.min(implicitWidth, panel.cardW - 40)
            text: panel.note
            color: panel.noteIsError ? Colors.critical : Colors.foreground
            font.pixelSize: Style.fontMd
            elide: Text.ElideRight
        }
    }
}
