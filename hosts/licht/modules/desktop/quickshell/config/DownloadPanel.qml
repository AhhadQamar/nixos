import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland

// The downloads panel: one glass card, a third of the way up the screen.
//
//   speed readout + a ruler of the last minute's speed   limits, parallel
//   tabs: All / Active / Queued / Done / Failed          pause all, clear, ...
//   ---------------------------------------------------------------------
//   the list (a row per download; Enter opens its details)
//   ---------------------------------------------------------------------
//   save-to chips / clipboard offer
//   add pill (paste a link, drop one, or type)            search
//
// All state lives in Downloads.qml. This file is only what is on screen: the
// tab, the search, which row the cursor is on, which are ticked, and the keys.
// The window is created when the panel opens and dropped after it closes, so a
// closed panel costs nothing.
PanelWindow {
    id: panel

    // ---- View state ---------------------------------------------------------
    property string tab: "all"
    property string query: ""
    property string cursorGid: ""
    property int lastIndex: 0
    property var selected: ({})
    property string expandedGid: ""
    property string sortMode: "status"
    property bool showHelp: false
    property string tip: ""
    property real reveal: 0
    property real breath: 0
    property var targetScreen: Focus.screen

    readonly property var tabs: [
        {
            "id": "all",
            "label": "All"
        },
        {
            "id": "active",
            "label": "Active"
        },
        {
            "id": "queued",
            "label": "Queued"
        },
        {
            "id": "done",
            "label": "Done"
        },
        {
            "id": "failed",
            "label": "Failed"
        }
    ]
    readonly property var sortModes: ["status", "name", "size", "progress"]

    // ---- Layout -------------------------------------------------------------
    readonly property real screenW: targetScreen ? targetScreen.width : 1920
    readonly property real screenH: targetScreen ? targetScreen.height : 1080
    readonly property int cardW: Math.round(Math.min(780, screenW - 32))
    readonly property int pad: Style.cardPad
    readonly property int innerW: cardW - pad * 2
    readonly property int gap: Style.spaceMd
    readonly property int headH: 56
    readonly property int barH: Style.buttonCompact
    readonly property int footH: Math.round(Math.max(Style.fieldHeight, Math.min(104, addInput.contentHeight + 17)))
    readonly property bool extraOn: !showHelp && !Downloads.sheetOpen && (addInput.activeFocus || addInput.text.length > 0 || Downloads.clip !== "")
    property real extraH: extraOn ? 30 : 0
    readonly property int maxCardH: Math.round(screenH) - Style.panelTop - 48
    readonly property int maxBody: Math.max(150, maxCardH - pad * 2 - headH - barH - 1 - footH - gap * 5 - 30)
    readonly property int sheetMin: showHelp ? 392 : (Downloads.pickOpen ? 296 : (Downloads.confirmOpen ? 250 : 0))
    property real bodyH: Math.max(sheetMin, Math.max(150, Math.min(list.contentHeight + 4, maxBody)))

    Behavior on extraH {
        NumberAnimation {
            duration: Style.baseMs
            easing.type: Style.easeMove
        }
    }

    Behavior on bodyH {
        NumberAnimation {
            duration: Style.moveMs
            easing.type: Style.easeMove
        }
    }

    // ---- The list as shown --------------------------------------------------
    readonly property var shownRows: {
        const q = query.trim().toLowerCase();
        const order = {
            "active": 0,
            "queued": 1,
            "failed": 2,
            "done": 3
        };
        const mode = sortMode;
        const items = [];
        const src = Downloads.rows;
        for (let i = 0; i < src.length; i++) {
            const r = src[i];
            if (tab !== "all" && r.group !== tab)
                continue;
            if (q !== "" && r.name.toLowerCase().indexOf(q) < 0)
                continue;
            items.push({
                "r": r,
                "i": i
            });
        }
        items.sort(function (a, b) {
            if (mode === "name")
                return a.r.name.localeCompare(b.r.name);
            if (mode === "size")
                return b.r.total - a.r.total || a.i - b.i;
            if (mode === "progress")
                return b.r.fraction - a.r.fraction || a.i - b.i;
            return order[a.r.group] - order[b.r.group] || a.i - b.i;
        });
        return items.map(x => x.r);
    }
    readonly property int cursorIndex: {
        const l = shownRows;
        for (let i = 0; i < l.length; i++) {
            if (l[i].gid === cursorGid)
                return i;
        }
        return -1;
    }
    readonly property var cur: Downloads.rowMap[cursorGid] || null
    readonly property bool anyBreathing: Downloads.rows.some(r => r.state === "checking" || r.state === "merging" || r.metadata)
    readonly property int selectedCount: Object.keys(selected).length

    readonly property var keyHelp: [
        {
            "k": ["\u2191", "\u2193"],
            "d": "Move"
        },
        {
            "k": ["\u2190", "\u2192"],
            "d": "Switch tab"
        },
        {
            "k": ["Enter"],
            "d": "Details"
        },
        {
            "k": ["Space"],
            "d": "Pause / resume"
        },
        {
            "k": ["S"],
            "d": "Tick a row"
        },
        {
            "k": ["Ctrl", "A"],
            "d": "Tick all"
        },
        {
            "k": ["A"],
            "d": "Add a link"
        },
        {
            "k": ["V"],
            "d": "Add the clipboard"
        },
        {
            "k": ["G"],
            "d": "Grab the clipboard's video"
        },
        {
            "k": ["Del"],
            "d": "Remove from the list"
        },
        {
            "k": ["Shift", "Del"],
            "d": "Remove and delete the partial"
        },
        {
            "k": ["R"],
            "d": "Retry failed"
        },
        {
            "k": ["Shift", "R"],
            "d": "Retry all failed"
        },
        {
            "k": ["U", "D"],
            "d": "Move in the queue"
        },
        {
            "k": ["Shift", "T"],
            "d": "To the front"
        },
        {
            "k": ["M"],
            "d": "Speed limit of this one"
        },
        {
            "k": ["Shift", "L"],
            "d": "Global speed limit"
        },
        {
            "k": ["+", "-"],
            "d": "Downloads at once"
        },
        {
            "k": ["O"],
            "d": "Open the file"
        },
        {
            "k": ["F"],
            "d": "Show in folder"
        },
        {
            "k": ["Y"],
            "d": "Copy the link"
        },
        {
            "k": ["P"],
            "d": "Choose torrent files"
        },
        {
            "k": ["C"],
            "d": "Clear finished"
        },
        {
            "k": ["Shift", "P"],
            "d": "Pause / resume all"
        },
        {
            "k": ["Z"],
            "d": "Schedule"
        },
        {
            "k": ["W"],
            "d": "When finished"
        },
        {
            "k": ["Q"],
            "d": "Video quality"
        },
        {
            "k": ["X"],
            "d": "Clean up leftovers"
        },
        {
            "k": ["Shift", "S"],
            "d": "Sort"
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
    visible: Downloads.isOpen || reveal > 0.001
    color: "transparent"
    exclusiveZone: 0
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "qs-downloads"
    WlrLayershell.keyboardFocus: Downloads.isOpen ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    // ---- Opening and closing ------------------------------------------------
    function close() {
        Downloads.close();
    }

    function go(open) {
        anim.stop();
        anim.to = open ? 1 : 0;
        anim.duration = open ? Style.enterMs : Style.baseMs;
        anim.easing.type = open ? Style.easeEnter : Style.easeExit;
        anim.start();
    }

    function resetView() {
        selected = {};
        expandedGid = "";
        showHelp = false;
        leaveInput();
    }

    // ---- The cursor ---------------------------------------------------------
    function jump(i) {
        const l = shownRows;
        if (l.length === 0)
            return;
        cursorGid = l[Math.max(0, Math.min(l.length - 1, i))].gid;
    }

    function moveCursor(d) {
        jump((cursorIndex < 0 ? 0 : cursorIndex) + d);
    }

    // Keeps the cursor on a real row as the list changes under it
    function fixCursor() {
        const l = shownRows;
        const sel = {};
        Object.keys(selected).forEach(function (g) {
            if (Downloads.rowMap[g])
                sel[g] = true;
        });
        if (Object.keys(sel).length !== selectedCount)
            selected = sel;
        if (l.length === 0) {
            cursorGid = "";
            return;
        }
        for (let i = 0; i < l.length; i++) {
            if (l[i].gid === cursorGid) {
                lastIndex = i;
                return;
            }
        }
        cursorGid = l[Math.min(lastIndex, l.length - 1)].gid;
    }

    onShownRowsChanged: fixCursor()
    onCursorGidChanged: {
        if (expandedGid !== "" && expandedGid !== cursorGid)
            expandedGid = "";
        if (cursorIndex >= 0)
            lastIndex = cursorIndex;
    }

    function targets() {
        const s = Object.keys(selected);
        return s.length > 0 ? s : (cursorGid !== "" ? [cursorGid] : []);
    }

    function toggleSelect(gid) {
        const s = Object.assign({}, selected);
        if (s[gid])
            delete s[gid];
        else
            s[gid] = true;
        selected = s;
    }

    function selectAll() {
        const s = {};
        shownRows.forEach(r => s[r.gid] = true);
        selected = s;
    }

    function toggleExpand(gid) {
        expandedGid = expandedGid === gid ? "" : gid;
    }

    function rowClicked(gid, ctrl) {
        leaveInput();
        if (ctrl) {
            cursorGid = gid;
            toggleSelect(gid);
        } else if (gid === cursorGid) {
            toggleExpand(gid);
        } else {
            cursorGid = gid;
        }
    }

    function stepTab(d) {
        const i = tabs.findIndex(t => t.id === tab);
        tab = tabs[(i + d + tabs.length) % tabs.length].id;
    }

    function cycleSort() {
        sortMode = sortModes[(sortModes.indexOf(sortMode) + 1) % sortModes.length];
        Downloads.say("Sorted by " + sortMode, false);
    }

    // ---- Focus and the add pill ---------------------------------------------
    function leaveInput() {
        keys.forceActiveFocus();
    }

    function focusAdd() {
        showHelp = false;
        addInput.forceActiveFocus();
    }

    function focusSearch() {
        showHelp = false;
        searchField.input.forceActiveFocus();
    }

    function submitAdd() {
        const text = addInput.text;
        addInput.text = "";
        if (text.trim().length > 0)
            Downloads.addText(text, Downloads.saveDir(), true);
        leaveInput();
    }

    function removeKey(deleteFiles) {
        const t = targets();
        if (t.length === 0)
            return;
        if (Downloads.askRemove(t, deleteFiles))
            selected = {};
    }

    function schedulePressed() {
        Downloads.setSchedule(!Downloads.schedOn);
    }

    // ---- Keys ---------------------------------------------------------------
    function handleKey(event) {
        const k = event.key;
        const ctrl = (event.modifiers & Qt.ControlModifier) !== 0;
        const shift = (event.modifiers & Qt.ShiftModifier) !== 0;

        if (Downloads.pickOpen) {
            Downloads.pickKey(event);
            event.accepted = true;
            return;
        }
        if (Downloads.confirmOpen) {
            Downloads.confirmKey(event);
            event.accepted = true;
            return;
        }
        event.accepted = true;

        if (k === Qt.Key_Escape) {
            if (showHelp)
                showHelp = false;
            else if (Downloads.actionLeft > 0)
                Downloads.cancelAction();
            else if (selectedCount > 0)
                selected = {};
            else if (expandedGid !== "")
                expandedGid = "";
            else if (query !== "") {
                query = "";
                searchField.clear();
            } else
                close();
            return;
        }
        if (showHelp) {
            showHelp = false;
            return;
        }
        if (ctrl && k === Qt.Key_A) {
            selectAll();
            return;
        }
        if (ctrl) {
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
            jump(shownRows.length - 1);
            return;
        case Qt.Key_Right:
        case Qt.Key_Tab:
        case Qt.Key_L:
            if (shift && k === Qt.Key_L)
                Downloads.cycleLimit("max-overall-download-limit");
            else
                stepTab(1);
            return;
        case Qt.Key_Left:
        case Qt.Key_Backtab:
        case Qt.Key_H:
            stepTab(-1);
            return;
        case Qt.Key_Return:
        case Qt.Key_Enter:
            if (cursorGid !== "")
                toggleExpand(cursorGid);
            return;
        case Qt.Key_Space:
            Downloads.togglePause(targets());
            return;
        case Qt.Key_S:
            if (shift)
                cycleSort();
            else if (cursorGid !== "")
                toggleSelect(cursorGid);
            return;
        case Qt.Key_A:
            focusAdd();
            return;
        case Qt.Key_Slash:
            focusSearch();
            event.accepted = true;
            return;
        case Qt.Key_V:
            Downloads.pasteClipboard();
            return;
        case Qt.Key_G:
            Downloads.grabLink(Downloads.clip);
            return;
        case Qt.Key_Delete:
        case Qt.Key_Backspace:
            removeKey(shift);
            return;
        case Qt.Key_R:
            if (shift)
                Downloads.retryAllFailed();
            else
                Downloads.retryRows(targets());
            return;
        case Qt.Key_U:
            Downloads.moveQueue(targets(), "up");
            return;
        case Qt.Key_D:
            Downloads.moveQueue(targets(), "down");
            return;
        case Qt.Key_T:
            if (shift)
                Downloads.moveQueue(targets(), "top");
            return;
        case Qt.Key_M:
            Downloads.cycleTaskLimit(targets());
            return;
        case Qt.Key_Plus:
        case Qt.Key_Equal:
            Downloads.stepParallel(1);
            return;
        case Qt.Key_Minus:
        case Qt.Key_Underscore:
            Downloads.stepParallel(-1);
            return;
        case Qt.Key_O:
            Downloads.openRow(cur);
            return;
        case Qt.Key_F:
            Downloads.revealRow(cur);
            return;
        case Qt.Key_Y:
            Downloads.copyLink(cur);
            return;
        case Qt.Key_P:
            if (shift)
                Downloads.pauseAllToggle();
            else
                Downloads.openPicker(cursorGid);
            return;
        case Qt.Key_C:
            Downloads.clearFinished();
            return;
        case Qt.Key_Z:
            schedulePressed();
            return;
        case Qt.Key_W:
            Downloads.cycleWhenDone();
            return;
        case Qt.Key_Q:
            Downloads.cycleQuality();
            return;
        case Qt.Key_X:
            Downloads.startCleanup();
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
        leaveInput();
    }

    Connections {
        target: Downloads

        function onIsOpenChanged() {
            panel.go(Downloads.isOpen);
            if (Downloads.isOpen)
                panel.resetView();
        }

        function onNoteChanged() {
            if (Downloads.note.indexOf("Added") === 0)
                addFlash.restart();
        }
    }

    NumberAnimation {
        id: anim

        target: panel
        property: "reveal"
        onFinished: {
            if (!Downloads.isOpen)
                Qt.callLater(Downloads.panelGone);
        }
    }

    // A slow breath for the glyphs of whatever is checking or fetching metadata
    SequentialAnimation on breath {
        running: panel.visible && panel.anyBreathing
        loops: Animation.Infinite

        NumberAnimation {
            to: 1
            duration: Style.ambientMs * 1.5
            easing.type: Style.easeAmbient
        }
        NumberAnimation {
            to: 0
            duration: Style.ambientMs * 1.5
            easing.type: Style.easeAmbient
        }
    }

    PanelLink {
        win: panel
        name: "downloads"
    }

    // Like the other panels: a click that lands anywhere the compositor does not
    // consider this window closes it (and Downloads.toggle ignores the same click
    // if it landed on the bar item that toggles the panel)
    HyprlandFocusGrab {
        windows: [panel]
        active: Downloads.isOpen && panel.visible
        onCleared: {
            Downloads.closedAt = Date.now();
            Downloads.close();
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
        // back from the text fields) instead of falling through to the dim, which
        // would close the panel
        MouseArea {
            anchors.fill: parent
            onClicked: panel.leaveInput()
        }

        // Dropping a link, a file or text starts it
        DropArea {
            id: drop

            anchors.fill: parent
            keys: ["text/uri-list", "text/plain"]
            onDropped: d => Downloads.handleDrop(d)
        }

        Rectangle {
            anchors.fill: parent
            radius: card.radius
            color: Qt.alpha(Colors.accent, 0.1)
            border.width: 2
            border.color: Colors.accent
            opacity: drop.containsDrag ? 1 : 0
            z: 20

            Behavior on opacity {
                NumberAnimation {
                    duration: Style.fadeMs
                }
            }

            Txt {
                anchors.centerIn: parent
                text: "Drop to download"
                color: Colors.accent
                font.pixelSize: Style.fontXl
                font.bold: true
            }
        }

        Column {
            id: col

            x: panel.pad
            y: panel.pad
            width: panel.innerW
            spacing: panel.gap

            // ---- Header: speed, its ruler, limits -----------------------------
            Item {
                id: head

                width: parent.width
                height: panel.headH

                Column {
                    id: speedCol

                    anchors.verticalCenter: parent.verticalCenter
                    width: 214
                    spacing: 3

                    Txt {
                        text: Aria2.rate(Downloads.stat.downloadSpeed)
                        color: Downloads.stat.downloadSpeed > 0 ? Colors.foreground : Colors.muted
                        font.pixelSize: 22
                        font.bold: true
                    }

                    Txt {
                        width: parent.width
                        text: Downloads.down ? "aria2 is not running" : "\u2191 " + Aria2.rate(Downloads.stat.uploadSpeed) + "   " + Downloads.counts.active + " active   " + Downloads.counts.queued + " queued" + (Downloads.usageText !== "" ? "   " + Downloads.usageText : "")
                        color: Downloads.down ? Colors.critical : Colors.muted
                        font.pixelSize: Style.fontSm
                        elide: Text.ElideRight
                    }
                }

                // The last minute of speed, as a ruler: the newest tick is the bright one
                Item {
                    id: graph

                    anchors.left: speedCol.right
                    anchors.leftMargin: 12
                    anchors.right: limits.left
                    anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    height: 36
                    clip: true

                    readonly property real peak: Math.max(1048576, Math.max.apply(null, Downloads.speedHistory.concat([0])))
                    readonly property real step: width / Downloads.historyLength

                    Rectangle {
                        anchors.bottom: parent.bottom
                        width: parent.width
                        height: 1
                        color: Style.outline
                    }

                    Repeater {
                        model: Downloads.historyLength

                        delegate: Rectangle {
                            required property int index
                            readonly property int at: index - (Downloads.historyLength - Downloads.speedHistory.length)
                            readonly property real v: at >= 0 ? Downloads.speedHistory[at] : 0
                            readonly property bool newest: index === Downloads.historyLength - 1

                            x: index * graph.step
                            width: Math.max(1, graph.step - 1.5)
                            height: 2 + (graph.height - 4) * Math.min(1, v / graph.peak)
                            anchors.bottom: parent.bottom
                            radius: width / 2
                            color: newest ? Colors.accent : Qt.alpha(Colors.accent, 0.25 + 0.5 * (index / Downloads.historyLength))
                            opacity: at >= 0 && v > 0 ? 1 : 0.35
                        }
                    }
                }

                Row {
                    id: limits

                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 6

                    TextButton {
                        compact: true
                        glyph: Icons.arrowDown
                        text: Downloads.limitLabel(Downloads.globalOpt["max-overall-download-limit"])
                        onClicked: Downloads.cycleLimit("max-overall-download-limit")
                        onHoveredChanged: panel.tip = hovered ? "Speed limit for downloads" : ""
                    }

                    TextButton {
                        compact: true
                        glyph: Icons.arrowUp
                        text: Downloads.limitLabel(Downloads.globalOpt["max-overall-upload-limit"])
                        onClicked: Downloads.cycleLimit("max-overall-upload-limit")
                        onHoveredChanged: panel.tip = hovered ? "Speed limit for seeding" : ""
                    }

                    Row {
                        spacing: 0
                        anchors.verticalCenter: parent.verticalCenter

                        IconButton {
                            size: 24
                            glyph: Icons.minus
                            tip: "Fewer at once"
                            onClicked: Downloads.stepParallel(-1)
                            onHoveredChanged: panel.tip = hovered ? tip : ""
                        }

                        Txt {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 26
                            horizontalAlignment: Text.AlignHCenter
                            text: Downloads.parallel() + "\u00d7"
                            color: Colors.foreground
                            font.pixelSize: Style.fontMd
                            font.bold: true
                        }

                        IconButton {
                            size: 24
                            glyph: Icons.plus
                            tip: "More at once"
                            onClicked: Downloads.stepParallel(1)
                            onHoveredChanged: panel.tip = hovered ? tip : ""
                        }
                    }
                }
            }

            // ---- Tabs and tools -----------------------------------------------
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
                            readonly property int n: Downloads.counts[modelData.id] || 0

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
                    anchors.right: tools.left
                    anchors.rightMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    horizontalAlignment: Text.AlignRight
                    text: panel.tip !== "" ? panel.tip : (panel.selectedCount > 0 ? panel.selectedCount + " ticked" : (panel.sortMode !== "status" ? "Sorted by " + panel.sortMode : ""))
                    color: Colors.muted
                    font.pixelSize: Style.fontSm
                    elide: Text.ElideRight
                }

                Row {
                    id: tools

                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2

                    IconButton {
                        glyph: Downloads.counts.active > 0 || Downloads.rows.some(r => r.state === "queued") ? Icons.pause : Icons.play
                        tip: Downloads.counts.active > 0 ? "Pause all" : "Resume all"
                        onClicked: Downloads.pauseAllToggle()
                        onHoveredChanged: panel.tip = hovered ? tip : ""
                    }

                    IconButton {
                        glyph: Icons.trash
                        tip: "Clear finished"
                        onClicked: Downloads.clearFinished()
                        onHoveredChanged: panel.tip = hovered ? tip : ""
                    }

                    IconButton {
                        glyph: Icons.calendar
                        on: Downloads.schedOn
                        tip: Downloads.schedOn ? "Schedule on: " + Config.downloadSchedule.start + " \u2013 " + Config.downloadSchedule.stop : "Schedule: only download " + Config.downloadSchedule.start + " \u2013 " + Config.downloadSchedule.stop
                        onClicked: panel.schedulePressed()
                        onHoveredChanged: panel.tip = hovered ? tip : ""
                    }

                    IconButton {
                        glyph: Icons.power
                        on: Downloads.whenDone !== "none"
                        tip: Downloads.actionLeft > 0 ? Downloads.whenLabel(Downloads.whenDone) + " in " + Downloads.actionLeft + " s, click to cancel" : "When finished: " + Downloads.whenLabel(Downloads.whenDone)
                        onClicked: Downloads.cycleWhenDone()
                        onHoveredChanged: panel.tip = hovered ? tip : ""
                    }

                    IconButton {
                        glyph: Icons.refresh
                        tip: "Clean up leftovers"
                        onClicked: Downloads.startCleanup()
                        onHoveredChanged: panel.tip = hovered ? tip : ""
                    }

                    IconButton {
                        glyph: "?"
                        on: panel.showHelp
                        tip: "Keys"
                        onClicked: panel.showHelp = !panel.showHelp
                        onHoveredChanged: panel.tip = hovered ? tip : ""
                    }
                }
            }

            Rule {
                width: parent.width
            }

            // ---- The body: list, empty state, sheets --------------------------
            Item {
                id: body

                width: parent.width
                height: panel.bodyH
                clip: true

                ListView {
                    id: list

                    anchors.fill: parent
                    anchors.rightMargin: 6
                    visible: !panel.showHelp && !Downloads.sheetOpen && count > 0
                    clip: true
                    spacing: 2
                    boundsBehavior: Flickable.StopAtBounds
                    cacheBuffer: 300
                    currentIndex: panel.cursorIndex
                    onCurrentIndexChanged: if (currentIndex >= 0)
                        positionViewAtIndex(currentIndex, ListView.Contain)

                    model: ScriptModel {
                        values: panel.shownRows
                        objectProp: "gid"
                    }

                    delegate: DownloadRow {
                        width: list.width
                        current: modelData.gid === panel.cursorGid
                        picked: panel.selected[modelData.gid] === true
                        armed: Downloads.pendingDelete.indexOf(modelData.gid) >= 0
                        expanded: panel.expandedGid === modelData.gid
                        breath: panel.breath
                        onClicked: ctrl => panel.rowClicked(modelData.gid, ctrl)
                        onPauseClicked: {
                            if (!current)
                                panel.cursorGid = modelData.gid;
                            Downloads.togglePause([modelData.gid]);
                        }
                        onRetryClicked: Downloads.retryRows([modelData.gid])
                        onOpenClicked: Downloads.openRow(modelData)
                        onFolderClicked: Downloads.revealRow(modelData)
                        onCopyClicked: Downloads.copyLink(modelData)
                        onRemoveClicked: Downloads.askRemove([modelData.gid], false)
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
                    visible: !panel.showHelp && !Downloads.sheetOpen && list.count === 0
                    anchors.centerIn: parent
                    spacing: 10

                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: 52
                        height: 52
                        radius: 26
                        color: Style.well
                        border.width: 1
                        border.color: Style.outline

                        Txt {
                            anchors.centerIn: parent
                            text: Downloads.down ? Icons.warning : (Downloads.counts.all > 0 ? Icons.search : Icons.download)
                            color: Downloads.down || Downloads.message !== "" ? Colors.critical : Colors.muted
                            font.pixelSize: 20
                        }
                    }

                    Txt {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: Downloads.message !== "" ? Downloads.message : (Downloads.down ? "aria2 is not running" : (Downloads.counts.all > 0 ? "Nothing matches" : "No downloads yet"))
                        color: Colors.foreground
                        font.pixelSize: Style.fontLg
                        font.bold: true
                    }

                    Txt {
                        anchors.horizontalCenter: parent.horizontalCenter
                        visible: !Downloads.down && Downloads.message === ""
                        text: Downloads.counts.all > 0 ? "Try another tab, or clear the search" : "Paste a link below, or drop one on this card"
                        color: Colors.muted
                        font.pixelSize: Style.fontMd
                    }

                    TextButton {
                        anchors.horizontalCenter: parent.horizontalCenter
                        visible: Downloads.down
                        primary: true
                        text: "Start aria2"
                        onClicked: Downloads.startAria()
                    }
                }

                // ---- A question: a link's preview, a clean-up ------------------
                Item {
                    id: confirm

                    anchors.fill: parent
                    visible: Downloads.confirmOpen
                    opacity: visible ? 1 : 0

                    Behavior on opacity {
                        NumberAnimation {
                            duration: Style.fadeMs
                        }
                    }

                    Column {
                        anchors.centerIn: parent
                        width: parent.width - 40
                        spacing: 8

                        Txt {
                            width: parent.width
                            horizontalAlignment: Text.AlignHCenter
                            text: Downloads.confirmTitle
                            color: Colors.foreground
                            font.pixelSize: Style.fontXl
                            font.bold: true
                            elide: Text.ElideMiddle
                        }

                        Txt {
                            width: parent.width
                            horizontalAlignment: Text.AlignHCenter
                            text: Downloads.confirmSub
                            color: Colors.muted
                            font.pixelSize: Style.fontMd
                            elide: Text.ElideRight
                        }

                        Item {
                            width: 1
                            height: 6
                        }

                        Repeater {
                            model: Downloads.confirmLines

                            delegate: Item {
                                required property var modelData

                                width: parent.width
                                height: 20

                                Txt {
                                    width: 80
                                    text: modelData.label
                                    color: Colors.muted
                                    font.pixelSize: Style.fontMd
                                }

                                Txt {
                                    x: 90
                                    width: parent.width - 90
                                    text: modelData.value
                                    color: modelData.tone === "bad" ? Colors.critical : (modelData.tone === "warn" ? Colors.color3 : Colors.foreground)
                                    font.pixelSize: Style.fontMd
                                    elide: Text.ElideMiddle
                                }
                            }
                        }

                        Item {
                            width: 1
                            height: 8
                        }

                        Row {
                            anchors.horizontalCenter: parent.horizontalCenter
                            spacing: 8

                            TextButton {
                                primary: true
                                text: Downloads.confirmYes
                                onClicked: Downloads.confirmAccept()
                            }

                            TextButton {
                                text: "Cancel"
                                onClicked: Downloads.closeConfirm()
                            }
                        }

                        Txt {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: "Enter  \u00b7  Esc"
                            color: Colors.muted
                            opacity: 0.6
                            font.pixelSize: Style.fontSm
                        }
                    }
                }

                // ---- The files of a torrent ------------------------------------
                Item {
                    id: pick

                    anchors.fill: parent
                    visible: Downloads.pickOpen
                    opacity: visible ? 1 : 0

                    Behavior on opacity {
                        NumberAnimation {
                            duration: Style.fadeMs
                        }
                    }

                    Txt {
                        id: pickTitle

                        width: parent.width
                        text: Downloads.pickName
                        color: Colors.foreground
                        font.pixelSize: Style.fontLg
                        font.bold: true
                        elide: Text.ElideMiddle
                    }

                    Txt {
                        id: pickSub

                        y: 22
                        width: parent.width
                        text: Downloads.pickCount + " of " + Downloads.pickFiles.length + " files  \u00b7  " + Aria2.bytes(Downloads.pickBytes) + " of " + Aria2.bytes(Downloads.pickTotal)
                        color: Colors.muted
                        font.pixelSize: Style.fontSm
                    }

                    Column {
                        y: 48
                        width: parent.width
                        spacing: 2

                        Repeater {
                            model: Downloads.pickRows

                            delegate: Rectangle {
                                required property int index
                                readonly property int at: Downloads.pickTop + index
                                readonly property var f: Downloads.pickFiles[at]

                                visible: f !== undefined
                                width: parent.width
                                height: 24
                                radius: Style.radiusSm
                                color: at === Downloads.pickCur ? Qt.alpha(Colors.accent, Style.tintAlpha) : "transparent"

                                Txt {
                                    x: 8
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: f && f.on ? Icons.check : "\u00b7"
                                    color: f && f.on ? Colors.accent : Colors.muted
                                    font.pixelSize: Style.fontMd
                                    width: 16
                                }

                                Txt {
                                    x: 30
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width - 30 - 90
                                    text: f ? f.name : ""
                                    color: f && f.on ? Colors.foreground : Colors.muted
                                    font.pixelSize: Style.fontMd
                                    elide: Text.ElideMiddle
                                }

                                Txt {
                                    anchors.right: parent.right
                                    anchors.rightMargin: 10
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: f ? Aria2.bytes(f.length) : ""
                                    color: Colors.muted
                                    font.pixelSize: Style.fontSm
                                }

                                TapHandler {
                                    onTapped: {
                                        Downloads.pickCur = parent.at;
                                        Downloads.pickToggle(parent.at);
                                    }
                                }
                            }
                        }
                    }

                    Row {
                        anchors.bottom: parent.bottom
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: 8

                        TextButton {
                            compact: true
                            primary: true
                            text: "Download chosen"
                            onClicked: Downloads.applyPick()
                        }

                        TextButton {
                            compact: true
                            text: "All"
                            onClicked: Downloads.pickSet(f => true)
                        }

                        TextButton {
                            compact: true
                            text: "None"
                            onClicked: Downloads.pickSet(f => false)
                        }

                        TextButton {
                            compact: true
                            text: "Cancel"
                            onClicked: Downloads.cancelPicker()
                        }
                    }
                }

                // ---- Keys --------------------------------------------------------
                Item {
                    id: help

                    anchors.fill: parent
                    visible: panel.showHelp
                    opacity: visible ? 1 : 0

                    Behavior on opacity {
                        NumberAnimation {
                            duration: Style.fadeMs
                        }
                    }

                    Grid {
                        anchors.horizontalCenter: parent.horizontalCenter
                        columns: 2
                        columnSpacing: 28
                        rowSpacing: 6
                        flow: Grid.TopToBottom
                        rows: Math.ceil(panel.keyHelp.length / 2)

                        Repeater {
                            model: panel.keyHelp

                            delegate: Item {
                                required property var modelData

                                width: (help.width - 28) / 2 - 4
                                height: 20

                                Row {
                                    spacing: 3
                                    width: 96

                                    Repeater {
                                        model: modelData.k

                                        delegate: KeyCap {
                                            required property string modelData

                                            label: modelData
                                        }
                                    }
                                }

                                Txt {
                                    x: 100
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width - 100
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

            // ---- Save-to chips while typing, the clipboard offer otherwise ------
            Item {
                id: extra

                width: parent.width
                height: panel.extraH
                visible: height > 0.5
                clip: true

                Row {
                    visible: addInput.activeFocus || addInput.text.length > 0
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 4

                    Txt {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Save to"
                        color: Colors.muted
                        font.pixelSize: Style.fontSm
                        rightPadding: 4
                    }

                    Repeater {
                        model: Downloads.savePresets

                        delegate: TextButton {
                            required property var modelData
                            required property int index

                            compact: true
                            raised: Downloads.savePick === index
                            primary: Downloads.savePick === index
                            text: modelData.label !== "" ? modelData.label : "Auto"
                            onClicked: Downloads.savePick = index
                        }
                    }

                    TextButton {
                        compact: true
                        glyph: Icons.video
                        text: Downloads.qualityDef().label
                        onClicked: Downloads.cycleQuality()
                    }
                }

                Row {
                    visible: !(addInput.activeFocus || addInput.text.length > 0) && Downloads.clip !== ""
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 8

                    TextButton {
                        compact: true
                        primary: true
                        glyph: Icons.link
                        text: "Add the copied link"
                        onClicked: Downloads.pasteClipboard()
                    }

                    Txt {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 360
                        text: Downloads.clip.replace(/\s+/g, " ")
                        color: Colors.muted
                        font.pixelSize: Style.fontSm
                        elide: Text.ElideMiddle
                    }
                }
            }

            // ---- The add pill and the search -----------------------------------
            Item {
                id: foot

                width: parent.width
                height: panel.footH

                Rectangle {
                    id: addBox

                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    width: Math.round(parent.width * 0.6)
                    radius: Math.min(Style.fieldHeight / 2, height / 2)
                    color: Style.well
                    border.width: 1
                    border.color: addInput.activeFocus ? Qt.alpha(Colors.accent, 0.6) : Style.outline

                    Behavior on border.color {
                        ColorAnimation {
                            duration: Style.fadeMs
                        }
                    }

                    // A new download lights the pill once
                    Rectangle {
                        anchors.fill: parent
                        radius: parent.radius
                        color: Qt.alpha(Colors.accent, 0.2 * addFlash.v)
                    }

                    NumberAnimation {
                        id: addFlash

                        property real v: 0

                        target: addFlash
                        property: "v"
                        from: 1
                        to: 0
                        duration: Style.sweepMs
                        easing.type: Style.easeExit
                    }

                    Txt {
                        x: 14
                        anchors.verticalCenter: parent.verticalCenter
                        text: Icons.download
                        color: addInput.activeFocus ? Colors.accent : Colors.muted
                        font.pixelSize: 14
                    }

                    TextEdit {
                        id: addInput

                        x: 40
                        y: 9
                        width: parent.width - 54
                        color: Colors.foreground
                        selectionColor: Qt.alpha(Colors.accent, 0.4)
                        selectedTextColor: Colors.foreground
                        font.family: Style.fontFamily
                        font.pixelSize: Style.fontLg
                        wrapMode: TextEdit.WrapAnywhere
                        clip: true
                        onTextChanged: if (text.indexOf("\n") >= 0) {
                            // Pasted lines are separate links: keep them
                            text = text.replace(/\r?\n/g, " ");
                        }

                        Keys.onPressed: event => {
                            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                panel.submitAdd();
                                event.accepted = true;
                            } else if (event.key === Qt.Key_Escape) {
                                addInput.text = "";
                                panel.leaveInput();
                                event.accepted = true;
                            } else if (event.key === Qt.Key_Tab) {
                                Downloads.savePick = (Downloads.savePick + 1) % Downloads.savePresets.length;
                                event.accepted = true;
                            }
                        }

                        Txt {
                            visible: addInput.text.length === 0
                            text: "Paste a link, magnet or curl command"
                            color: Colors.muted
                            opacity: 0.7
                            font.pixelSize: Style.fontLg
                        }
                    }
                }

                SearchField {
                    id: searchField

                    anchors.left: addBox.right
                    anchors.leftMargin: 8
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    placeholder: "Search"
                    fontSize: Style.fontMd
                    onTextChanged: panel.query = text
                    onAccepted: panel.leaveInput()
                    badge: panel.query.trim() !== "" ? String(panel.shownRows.length) : ""
                    Keys.onEscapePressed: {
                        searchField.clear();
                        panel.leaveInput();
                    }
                }
            }
        }
    }

    // ---- Feedback, above the card -------------------------------------------
    Rectangle {
        id: toast

        anchors.horizontalCenter: card.horizontalCenter
        anchors.bottom: card.top
        anchors.bottomMargin: 10
        width: Math.min(panel.cardW, toastText.implicitWidth + 32)
        height: 30
        radius: 15
        color: Style.card
        border.width: 1
        border.color: Downloads.noteIsError ? Qt.alpha(Colors.critical, 0.6) : Qt.alpha(Colors.accent, 0.5)
        opacity: Downloads.note !== "" && panel.reveal > 0.9 ? 1 : 0
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
            text: Downloads.note
            color: Downloads.noteIsError ? Colors.critical : Colors.foreground
            font.pixelSize: Style.fontMd
            elide: Text.ElideRight
        }
    }
}
