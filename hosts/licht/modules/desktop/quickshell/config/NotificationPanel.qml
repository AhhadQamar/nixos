import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland

// The notification centre: one glass card, a third of the way up the screen.
//
//   do not disturb, grouping, clear all, keys             what is going on
//   tabs: All / New / Urgent / Snoozed
//   ---------------------------------------------------------------------
//   the log, by app (a row per notification)  |  the selected one, in full
//                                             |  and what can be done with it
//   ---------------------------------------------------------------------
//   search                                      what the keys do
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
    property bool groupByApp: true
    property bool clearArmed: false
    property string tip: ""
    property string note: ""
    property bool noteIsError: false
    property real reveal: 0
    property var targetScreen: Focus.screen

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

    // ---- Layout -------------------------------------------------------------
    readonly property real screenW: targetScreen ? targetScreen.width : 1920
    readonly property real screenH: targetScreen ? targetScreen.height : 1080
    readonly property int cardW: Math.round(Math.min(860, screenW - 32))
    readonly property int pad: Style.cardPad
    readonly property int innerW: cardW - pad * 2
    readonly property int gap: Style.spaceMd
    readonly property bool previewOn: cardW >= 680
    readonly property int listW: previewOn ? Math.floor((innerW - 14) * 0.46) : innerW
    readonly property int previewW: innerW - listW - 14
    readonly property int topH: Style.buttonCompact + 6
    readonly property int barH: Style.buttonCompact
    readonly property int footH: Style.fieldHeight
    readonly property int maxCardH: Math.round(screenH) - Style.panelTop - 48
    readonly property int maxBody: Math.max(200, maxCardH - pad * 2 - topH - barH - 1 - footH - gap * 4)
    readonly property int bodyH: Math.min(420, maxBody)

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
        if (!groupByApp)
            return items.map(x => x.n);
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
            "d": "Group by app"
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
        keys.forceActiveFocus();
    }

    function say(text, isError) {
        note = text;
        noteIsError = !!isError;
        noteTimer.restart();
    }

    function leaveInput() {
        keys.forceActiveFocus();
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
        const once = [Qt.Key_Delete, Qt.Key_Backspace, Qt.Key_X, Qt.Key_Return, Qt.Key_Enter, Qt.Key_1, Qt.Key_2, Qt.Key_3, Qt.Key_4, Qt.Key_C, Qt.Key_D, Qt.Key_Z, Qt.Key_Space, Qt.Key_Escape, Qt.Key_O, Qt.Key_G, Qt.Key_A];
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
            searchField.forceActiveFocus();
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
            spacing: panel.gap

            // ---- What is going on, and the switches -----------------------------
            Item {
                width: parent.width
                height: panel.topH

                Txt {
                    anchors.left: parent.left
                    anchors.right: tools.left
                    anchors.rightMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    text: {
                        const u = NotificationServer.doNotDisturb ? (NotificationServer.dndUntil > 0 ? "Silent until " + Qt.formatTime(new Date(NotificationServer.dndUntil), "HH:mm") : "Silent") : "";
                        const n = panel.counts.all + (panel.counts.all === 1 ? " notification" : " notifications");
                        return u !== "" ? n + "  \u00b7  " + u : n;
                    }
                    color: NotificationServer.doNotDisturb ? Colors.accent : Colors.foreground
                    font.pixelSize: Style.fontLg
                    font.bold: true
                    elide: Text.ElideRight
                }

                Row {
                    id: tools

                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2

                    IconButton {
                        glyph: NotificationServer.doNotDisturb ? Icons.bellOff : Icons.bell
                        on: NotificationServer.doNotDisturb
                        tip: NotificationServer.doNotDisturb ? "Do not disturb is on, click to end" : "Do not disturb (Shift+D: an hour)"
                        onClicked: NotificationServer.toggleDnd()
                        onHoveredChanged: panel.tip = hovered ? tip : ""
                    }

                    IconButton {
                        glyph: Icons.group
                        on: panel.groupByApp
                        tip: panel.groupByApp ? "Grouped by app" : "In order of arrival"
                        onClicked: panel.groupByApp = !panel.groupByApp
                        onHoveredChanged: panel.tip = hovered ? tip : ""
                    }

                    IconButton {
                        glyph: Icons.trash
                        danger: panel.clearArmed
                        on: panel.clearArmed
                        tip: "Clear everything"
                        onClicked: panel.clearPressed()
                        onHoveredChanged: panel.tip = hovered ? tip : ""
                    }

                    IconButton {
                        glyph: "?"
                        on: panel.showHelp
                        tip: "Keys (?)"
                        onClicked: panel.showHelp = !panel.showHelp
                        onHoveredChanged: panel.tip = hovered ? tip : ""
                    }
                }
            }

            // ---- Tabs ---------------------------------------------------------
            Item {
                width: parent.width
                height: panel.barH

                Row {
                    id: tabRow

                    spacing: 4

                    Repeater {
                        model: panel.tabs

                        delegate: TextButton {
                            required property var modelData
                            readonly property int n: panel.counts[modelData.id] || 0

                            compact: true
                            raised: panel.tab === modelData.id
                            primary: panel.tab === modelData.id
                            text: modelData.label + (n > 0 && modelData.id !== "all" ? "  " + n : "")
                            onClicked: {
                                panel.tab = modelData.id;
                                panel.leaveInput();
                            }
                        }
                    }
                }

                Txt {
                    anchors.left: tabRow.right
                    anchors.leftMargin: 14
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    horizontalAlignment: Text.AlignRight
                    text: panel.tip !== "" ? panel.tip : (panel.tickedCount > 0 ? panel.tickedCount + " ticked" : "")
                    color: Colors.muted
                    font.pixelSize: Style.fontSm
                    elide: Text.ElideRight
                }
            }

            Rule {
                width: parent.width
            }

            // ---- The body: the log, the notification, the keys -----------------
            Item {
                id: body

                width: parent.width
                height: panel.bodyH

                // The log
                Item {
                    id: listArea

                    width: panel.listW
                    height: parent.height
                    visible: !panel.showHelp

                    ListView {
                        id: list

                        anchors.fill: parent
                        anchors.rightMargin: 6
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
                            onClicked: ctrl => panel.rowClicked(modelData.key, ctrl)
                            onCopyClicked: panel.copyEntry(modelData, false)
                            onSnoozeClicked: {
                                if (modelData.snoozeUntil > 0)
                                    NotificationServer.unsnooze([modelData]);
                                else
                                    NotificationServer.snooze([modelData], 10);
                            }
                            onDismissClicked: NotificationServer.dismissEntries([modelData])
                            onGroupClearClicked: NotificationServer.clearApp(modelData.appName)
                            onTipped: text => panel.tip = text
                        }
                    }

                    // A slim scroll indicator
                    Rectangle {
                        visible: list.visible && list.visibleArea.heightRatio < 0.999
                        x: parent.width - 3
                        y: list.visibleArea.yPosition * parent.height
                        width: 3
                        height: Math.max(20, list.visibleArea.heightRatio * parent.height)
                        radius: 1.5
                        color: Style.strongFill
                    }

                    // Nothing to show
                    Column {
                        visible: list.count === 0
                        anchors.centerIn: parent
                        spacing: 10

                        Rectangle {
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: 52
                            height: 52
                            radius: 26
                            color: Style.well
                            border.width: 1
                            border.color: NotificationServer.doNotDisturb ? Qt.alpha(Colors.accent, 0.8) : Style.outline

                            Txt {
                                anchors.centerIn: parent
                                text: panel.query.trim() !== "" ? Icons.search : (NotificationServer.doNotDisturb ? Icons.bellOff : Icons.bell)
                                color: NotificationServer.doNotDisturb ? Colors.accent : Colors.muted
                                font.pixelSize: 20
                            }
                        }

                        Txt {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: panel.query.trim() !== "" ? "Nothing matches" : (panel.tab === "snoozed" ? "Nothing snoozed" : (panel.tab === "urgent" ? "Nothing urgent" : (panel.tab === "fresh" ? "Nothing new" : "All caught up")))
                            color: Colors.foreground
                            font.pixelSize: Style.fontLg
                            font.bold: true
                        }

                        Txt {
                            anchors.horizontalCenter: parent.horizontalCenter
                            visible: panel.query.trim() === "" && panel.tab === "all"
                            text: panel.dndText
                            color: Colors.muted
                            font.pixelSize: Style.fontMd
                        }
                    }
                }

                // The selected notification, in full
                Rectangle {
                    id: pane

                    x: panel.listW + 14
                    width: panel.previewW
                    height: parent.height
                    visible: panel.previewOn && !panel.showHelp
                    radius: Style.radiusLg
                    color: Style.well
                    border.width: 1
                    border.color: panel.curCritical ? Qt.alpha(Colors.critical, 0.5) : Style.outline

                    Txt {
                        id: paneMeta

                        x: 14
                        y: 12
                        width: parent.width - 28
                        text: panel.curMeta
                        color: panel.curCritical ? Colors.critical : Colors.muted
                        font.pixelSize: Style.fontSm
                        elide: Text.ElideRight
                    }

                    // What it says
                    Flickable {
                        id: textFlick

                        x: 14
                        y: 34
                        width: parent.width - 28
                        height: parent.height - 34 - actions.height - 24
                        visible: panel.cur !== null
                        clip: true
                        contentHeight: textCol.height
                        boundsBehavior: Flickable.StopAtBounds
                        flickableDirection: Flickable.VerticalFlick

                        Connections {
                            target: panel

                            function onCursorKeyChanged() {
                                textFlick.contentY = 0;
                            }
                        }

                        Column {
                            id: textCol

                            width: textFlick.width - 4
                            spacing: 8

                            Txt {
                                width: parent.width
                                text: panel.cur !== null ? (panel.cur.summary !== "" ? panel.cur.summary : panel.cur.appName) : ""
                                textFormat: Text.PlainText
                                wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                                color: Colors.foreground
                                font.pixelSize: Style.fontLg
                                font.bold: true
                            }

                            Txt {
                                width: parent.width
                                visible: panel.cur !== null && panel.cur.body !== ""
                                text: panel.cur !== null ? panel.cur.body : ""
                                textFormat: Text.PlainText
                                wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                                color: Colors.foreground
                                opacity: 0.85
                                font.pixelSize: Style.fontBase
                            }
                        }
                    }

                    Txt {
                        anchors.centerIn: parent
                        visible: panel.cur === null
                        text: "Nothing selected"
                        color: Colors.muted
                        font.pixelSize: Style.fontMd
                    }

                    // What can be done with it
                    Flow {
                        id: actions

                        x: 14
                        y: parent.height - height - 12
                        width: parent.width - 28
                        spacing: 6
                        visible: panel.cur !== null

                        // The app's own buttons
                        Repeater {
                            model: panel.curActions

                            delegate: TextButton {
                                required property var modelData
                                required property int index

                                compact: true
                                primary: index === 0
                                text: modelData.text
                                onClicked: panel.runAction(modelData.id)
                            }
                        }

                        TextButton {
                            visible: panel.curCode !== ""
                            compact: true
                            primary: panel.curActions.length === 0
                            glyph: Icons.copy
                            text: "Copy " + panel.curCode
                            onClicked: panel.copyEntry(panel.cur, false)
                        }

                        TextButton {
                            visible: panel.curLink !== ""
                            compact: true
                            glyph: Icons.openExternal
                            text: "Open link"
                            onClicked: panel.openLink(panel.cur)
                        }

                        TextButton {
                            compact: true
                            glyph: Icons.copy
                            text: "Copy text"
                            onClicked: panel.copyEntry(panel.cur, true)
                        }

                        TextButton {
                            compact: true
                            glyph: Icons.clock
                            text: panel.curSnoozed ? "Bring back" : "10 min"
                            onClicked: panel.snoozeTargets(10)
                        }

                        TextButton {
                            visible: !panel.curSnoozed
                            compact: true
                            text: "1 hour"
                            onClicked: panel.snoozeTargets(60)
                        }

                        TextButton {
                            visible: !panel.curSnoozed
                            compact: true
                            text: "Until 8:00"
                            onClicked: panel.snoozeMorning()
                        }

                        TextButton {
                            compact: true
                            danger: true
                            glyph: Icons.close
                            text: panel.tickedCount > 1 ? "Dismiss " + panel.tickedCount : "Dismiss"
                            onClicked: panel.dismissTargets()
                        }
                    }
                }

                // ---- The keys ----------------------------------------------------
                Item {
                    id: help

                    anchors.fill: parent
                    visible: panel.showHelp

                    Grid {
                        anchors.horizontalCenter: parent.horizontalCenter
                        columns: 2
                        columnSpacing: 36
                        rowSpacing: 8
                        flow: Grid.TopToBottom
                        rows: Math.ceil(panel.keyHelp.length / 2)

                        Repeater {
                            model: panel.keyHelp

                            delegate: Item {
                                required property var modelData

                                width: (help.width - 36) / 2 - 4
                                height: 22

                                Row {
                                    spacing: 3
                                    width: 90

                                    Repeater {
                                        model: modelData.k

                                        delegate: KeyCap {
                                            required property string modelData

                                            label: modelData
                                        }
                                    }
                                }

                                Txt {
                                    x: 94
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width - 94
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

            // ---- Search, and what the keys do right now --------------------------
            Item {
                width: parent.width
                height: panel.footH

                SearchField {
                    id: searchField

                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.round(parent.width * 0.5)
                    placeholder: "Search  ( / )"
                    fontSize: Style.fontMd
                    badge: panel.query.trim() !== "" ? String(panel.entryRows.length) : ""
                    onTextChanged: panel.query = text
                    onAccepted: panel.leaveInput()
                    Keys.onEscapePressed: {
                        if (text !== "")
                            text = "";
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

                Txt {
                    anchors.left: searchField.right
                    anchors.leftMargin: 14
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    horizontalAlignment: Text.AlignRight
                    text: panel.tickedCount > 0 ? panel.tickedCount + " ticked  \u00b7  x dismisses them  \u00b7  z snoozes  \u00b7  Esc unticks" : "x dismiss  \u00b7  c copy  \u00b7  z snooze  \u00b7  d silent  \u00b7  ? keys"
                    color: Colors.muted
                    opacity: 0.8
                    font.pixelSize: Style.fontSm
                    elide: Text.ElideLeft
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
