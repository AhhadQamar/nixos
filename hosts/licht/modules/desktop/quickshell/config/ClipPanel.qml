import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland

// The clipboard panel: one glass card, a third of the way up the screen.
//
//   search                                               private, clear, keys
//   tabs: All / Text / Links / Images / Pinned
//   ---------------------------------------------------------------------
//   the history (a row per copy)      |  the selected entry, in full
//                                     |  and what can be done with it
//   ---------------------------------------------------------------------
//   what the keys do
//
// All state lives in ClipStore.qml. This file is only what is on screen: the tab,
// the search, which row the cursor is on, which are ticked, and the keys. The
// window is created when the panel opens and dropped after it closes, so a
// closed panel costs nothing.
PanelWindow {
    id: panel

    // ---- View state ---------------------------------------------------------
    property string tab: "all"
    property string query: ""
    property string cursorId: ""
    property int lastIndex: 0
    property var ticked: ({})
    property bool showHelp: false
    property bool revealed: false
    property bool wipeArmed: false
    property string tip: ""
    property real reveal: 0
    property var targetScreen: Focus.screen

    readonly property var tabs: [
        {
            "id": "all",
            "label": "All"
        },
        {
            "id": "text",
            "label": "Text"
        },
        {
            "id": "link",
            "label": "Links"
        },
        {
            "id": "image",
            "label": "Images"
        },
        {
            "id": "pinned",
            "label": "Pinned"
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
    readonly property int topH: Style.fieldHeight
    readonly property int barH: Style.buttonCompact
    readonly property int footH: 18
    readonly property int maxCardH: Math.round(screenH) - Style.panelTop - 48
    readonly property int maxBody: Math.max(200, maxCardH - pad * 2 - topH - barH - 1 - footH - gap * 4)
    readonly property int bodyH: Math.min(396, maxBody)

    // ---- The list as shown --------------------------------------------------
    readonly property var shownEntries: {
        const base = tab === "pinned" ? ClipStore.pinEntries : ClipStore.entries;
        const q = query.trim();
        const out = [];
        for (let i = 0; i < base.length; i++) {
            const e = base[i];
            if (tab === "text" && (e.kind === "image" || e.kind === "link"))
                continue;
            if (tab === "link" && e.kind !== "link")
                continue;
            if (tab === "image" && e.kind !== "image")
                continue;
            if (q === "") {
                out.push({
                    "e": e,
                    "s": 0,
                    "i": i
                });
                continue;
            }
            const s = Fuzzy.score(e.preview + " " + e.app + " " + ClipStore.kindLabels[e.kind], q);
            if (s >= 0)
                out.push({
                    "e": e,
                    "s": s,
                    "i": i
                });
        }
        if (q !== "")
            out.sort((a, b) => b.s - a.s || a.i - b.i);
        return out.map(x => x.e);
    }
    readonly property int cursorIndex: {
        const l = shownEntries;
        for (let i = 0; i < l.length; i++) {
            if (l[i].id === cursorId)
                return i;
        }
        return -1;
    }
    readonly property var cur: cursorIndex >= 0 ? shownEntries[cursorIndex] : null
    readonly property int tickedCount: Object.keys(ticked).length
    readonly property var curActions: ClipStore.actionsFor(cur)
    // The whole text of the selected entry (its first line while it loads)
    readonly property string fullText: {
        if (cur === null || cur.binary)
            return "";
        const t = ClipStore.textOf(cur);
        return t !== "" ? t : cur.preview;
    }
    readonly property bool textLoaded: cur !== null && !cur.binary && ClipStore.textOf(cur) !== ""
    readonly property string curMeta: {
        if (cur === null)
            return "";
        const parts = [ClipStore.kindLabels[cur.kind]];
        if (cur.kind === "image") {
            if (cur.imgDims !== "")
                parts.push(cur.imgDims);
            if (cur.imgSize !== "")
                parts.push(cur.imgSize);
        } else if (textLoaded) {
            const lines = fullText.split("\n").length;
            parts.push(lines > 1 ? lines + " lines" : fullText.length + " characters");
        }
        if (cur.app !== "" && cur.pid === "")
            parts.push("from " + cur.app);
        const a = ClipStore.ago(cur.t);
        if (a !== "")
            parts.push(a === "now" ? "just now" : a + " ago");
        return parts.join("  \u00b7  ");
    }

    readonly property var keyHelp: [
        {
            "k": ["\u2191", "\u2193"],
            "d": "Move"
        },
        {
            "k": ["Tab"],
            "d": "Switch tab"
        },
        {
            "k": ["Enter"],
            "d": "Copy (or join the ticked)"
        },
        {
            "k": ["Shift", "Enter"],
            "d": "Copy and paste it"
        },
        {
            "k": ["Ctrl", "Space"],
            "d": "Tick a row"
        },
        {
            "k": ["Ctrl", "Shift", "A"],
            "d": "Tick all shown"
        },
        {
            "k": ["Del"],
            "d": "Remove"
        },
        {
            "k": ["Ctrl", "D"],
            "d": "Remove (always)"
        },
        {
            "k": ["Ctrl", "P"],
            "d": "Pin / unpin"
        },
        {
            "k": ["Alt", "1\u20134"],
            "d": "The buttons under the entry"
        },
        {
            "k": ["Ctrl", "O"],
            "d": "Open"
        },
        {
            "k": ["Ctrl", "S"],
            "d": "Save an image"
        },
        {
            "k": ["Ctrl", "E"],
            "d": "Show a hidden secret"
        },
        {
            "k": ["Ctrl", "I"],
            "d": "Private mode"
        },
        {
            "k": ["Ctrl", "Home"],
            "d": "First entry"
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
    visible: ready && (ClipStore.isOpen || reveal > 0.001)
    color: "transparent"
    exclusiveZone: 0
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "qs-clipboard"
    WlrLayershell.keyboardFocus: ClipStore.isOpen ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    // ---- Opening and closing ------------------------------------------------
    function close() {
        ClipStore.close();
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
        revealed = false;
        wipeArmed = false;
        searchField.text = "";
        searchField.forceActiveFocus();
    }

    // ---- The cursor ---------------------------------------------------------
    function jump(i) {
        const l = shownEntries;
        if (l.length === 0)
            return;
        cursorId = l[Math.max(0, Math.min(l.length - 1, i))].id;
    }

    function moveCursor(d) {
        jump((cursorIndex < 0 ? 0 : cursorIndex) + d);
    }

    // Keeps the cursor on a real row as the list changes under it
    function fixCursor() {
        const l = shownEntries;
        const t = {};
        const live = {};
        l.forEach(e => live[e.id] = true);
        Object.keys(ticked).forEach(function (id) {
            if (live[id])
                t[id] = true;
        });
        if (Object.keys(t).length !== tickedCount)
            ticked = t;
        if (l.length === 0) {
            cursorId = "";
            return;
        }
        for (let i = 0; i < l.length; i++) {
            if (l[i].id === cursorId) {
                lastIndex = i;
                return;
            }
        }
        cursorId = l[Math.min(lastIndex, l.length - 1)].id;
    }

    onShownEntriesChanged: fixCursor()
    onCursorIdChanged: {
        revealed = false;
        if (cursorIndex >= 0)
            lastIndex = cursorIndex;
        loadTimer.restart();
    }

    function targets() {
        if (tickedCount > 0)
            return shownEntries.filter(e => ticked[e.id] === true);
        return cur !== null ? [cur] : [];
    }

    function toggleTick(id) {
        const t = Object.assign({}, ticked);
        if (t[id])
            delete t[id];
        else
            t[id] = true;
        ticked = t;
    }

    function tickAll() {
        const t = {};
        shownEntries.forEach(e => t[e.id] = true);
        ticked = t;
    }

    function stepTab(d) {
        const i = tabs.findIndex(t => t.id === tab);
        tab = tabs[(i + d + tabs.length) % tabs.length].id;
    }

    // ---- Doing things -------------------------------------------------------
    function copyCurrent(paste) {
        if (tickedCount > 1 || (tickedCount === 1 && cur === null)) {
            ClipStore.copyMany(targets());
            return;
        }
        ClipStore.copyEntry(tickedCount === 1 ? targets()[0] : cur, paste);
    }

    function removeTargets() {
        const t = targets();
        if (t.length === 0)
            return;
        ClipStore.deleteEntries(t);
        ticked = {};
    }

    function openCurrent() {
        const a = curActions.find(x => x.id === "open");
        if (a)
            ClipStore.runAction("open", cur);
    }

    function wipePressed() {
        if (!wipeArmed) {
            wipeArmed = true;
            wipeTimer.restart();
            ClipStore.say("Press again to clear the history  \u00b7  pins stay", true);
            return;
        }
        wipeArmed = false;
        ClipStore.wipe();
    }

    function rowClicked(id, ctrl) {
        searchField.forceActiveFocus();
        if (ctrl) {
            cursorId = id;
            toggleTick(id);
        } else if (id === cursorId) {
            copyCurrent(false);
        } else {
            cursorId = id;
        }
    }

    // ---- Keys ---------------------------------------------------------------
    function handleKey(event) {
        const k = event.key;
        const ctrl = (event.modifiers & Qt.ControlModifier) !== 0;
        const shift = (event.modifiers & Qt.ShiftModifier) !== 0;
        const alt = (event.modifiers & Qt.AltModifier) !== 0;
        const input = searchField.input;

        if (showHelp) {
            if (k === Qt.Key_Escape || k === Qt.Key_Slash || k === Qt.Key_Return || k === Qt.Key_Enter)
                showHelp = false;
            event.accepted = true;
            return;
        }
        event.accepted = true;
        if (k === Qt.Key_Escape) {
            if (tickedCount > 0)
                ticked = {};
            else if (query !== "")
                searchField.text = "";
            else
                close();
            return;
        }
        // "/" shows the keys while the search is empty; once there is text it types
        if (k === Qt.Key_Slash && !ctrl && query === "") {
            showHelp = true;
            return;
        }
        if (k === Qt.Key_Down) {
            moveCursor(1);
            return;
        }
        if (k === Qt.Key_Up) {
            moveCursor(-1);
            return;
        }
        if (k === Qt.Key_PageDown) {
            moveCursor(6);
            return;
        }
        if (k === Qt.Key_PageUp) {
            moveCursor(-6);
            return;
        }
        if (ctrl && k === Qt.Key_Home) {
            jump(0);
            return;
        }
        if (ctrl && k === Qt.Key_End) {
            jump(shownEntries.length - 1);
            return;
        }
        if (k === Qt.Key_Tab) {
            stepTab(1);
            return;
        }
        if (k === Qt.Key_Backtab) {
            stepTab(-1);
            return;
        }
        if ((k === Qt.Key_Left || k === Qt.Key_Right) && query === "" && !ctrl) {
            stepTab(k === Qt.Key_Right ? 1 : -1);
            return;
        }
        if (k === Qt.Key_Return || k === Qt.Key_Enter) {
            copyCurrent(shift);
            return;
        }
        if (k === Qt.Key_Delete && (query === "" || input.cursorPosition >= query.length)) {
            removeTargets();
            return;
        }
        if (ctrl && k === Qt.Key_D) {
            removeTargets();
            return;
        }
        if (ctrl && k === Qt.Key_P) {
            ClipStore.togglePin(cur);
            return;
        }
        if (ctrl && k === Qt.Key_Space) {
            if (cursorId !== "")
                toggleTick(cursorId);
            return;
        }
        if (ctrl && shift && k === Qt.Key_A) {
            tickAll();
            return;
        }
        if (ctrl && k === Qt.Key_E) {
            revealed = !revealed;
            return;
        }
        if (ctrl && k === Qt.Key_O) {
            openCurrent();
            return;
        }
        if (ctrl && k === Qt.Key_S) {
            if (cur !== null && cur.kind === "image")
                ClipStore.runAction("save", cur);
            return;
        }
        if (ctrl && k === Qt.Key_I) {
            ClipStore.setPaused(!ClipStore.paused);
            return;
        }
        if (alt && k >= Qt.Key_1 && k <= Qt.Key_4) {
            const extra = curActions.filter(a => a.id !== "open" && a.id !== "save" && a.id !== "folder");
            const a = extra[k - Qt.Key_1];
            if (a)
                ClipStore.runAction(a.id, cur);
            return;
        }
        event.accepted = false;
    }

    Component.onCompleted: {
        targetScreen = Focus.screen;
        fixCursor();
        go(true);
        searchField.forceActiveFocus();
        Qt.callLater(() => ready = true);
    }

    Connections {
        target: ClipStore

        function onIsOpenChanged() {
            panel.go(ClipStore.isOpen);
            if (ClipStore.isOpen)
                panel.resetView();
        }
    }

    NumberAnimation {
        id: anim

        target: panel
        property: "reveal"
        onFinished: {
            if (!ClipStore.isOpen)
                Qt.callLater(ClipStore.panelGone);
        }
    }

    // Loads the selected entry a moment after the cursor settles on it, so
    // holding an arrow key does not decode everything it passes
    Timer {
        id: loadTimer

        interval: 80
        onTriggered: {
            ClipStore.ensureText(panel.cur);
            ClipStore.ensureImage(panel.cur);
        }
    }

    Timer {
        id: wipeTimer

        interval: 4000
        onTriggered: panel.wipeArmed = false
    }

    PanelLink {
        win: panel
        name: "clipboard"
    }

    // Like the other panels: a click that lands anywhere the compositor does not
    // consider this window closes it (and ClipStore.toggle ignores the same click
    // if it landed on whatever toggles the panel)
    HyprlandFocusGrab {
        windows: [panel]
        active: ClipStore.isOpen && panel.visible
        onCleared: {
            ClipStore.closedAt = Date.now();
            ClipStore.close();
        }
    }

    Dim {
        reveal: panel.reveal
        closes: true
        onClicked: panel.close()
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
        // back to the search) instead of falling through to the dim, which would
        // close the panel
        MouseArea {
            anchors.fill: parent
            onClicked: searchField.forceActiveFocus()
        }

        Column {
            id: col

            x: panel.pad
            y: panel.pad
            width: panel.innerW
            spacing: panel.gap

            // ---- Search and tools ---------------------------------------------
            Item {
                width: parent.width
                height: panel.topH

                Row {
                    id: tools

                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2

                    IconButton {
                        glyph: ClipStore.paused ? Icons.eyeOff : Icons.eye
                        on: ClipStore.paused
                        tip: ClipStore.paused ? "Private mode is on: new copies are not kept" : "Private mode: do not keep new copies"
                        onClicked: ClipStore.setPaused(!ClipStore.paused)
                        onHoveredChanged: panel.tip = hovered ? tip : ""
                    }

                    IconButton {
                        glyph: Icons.trash
                        danger: panel.wipeArmed
                        on: panel.wipeArmed
                        tip: "Clear the history (pins stay)"
                        onClicked: panel.wipePressed()
                        onHoveredChanged: panel.tip = hovered ? tip : ""
                    }

                    IconButton {
                        glyph: "?"
                        on: panel.showHelp
                        tip: "Keys (/ on an empty search)"
                        onClicked: panel.showHelp = !panel.showHelp
                        onHoveredChanged: panel.tip = hovered ? tip : ""
                    }
                }

                SearchField {
                    id: searchField

                    anchors.left: parent.left
                    anchors.right: tools.left
                    anchors.rightMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    placeholder: "Search the clipboard"
                    badge: panel.query.trim() !== "" ? String(panel.shownEntries.length) : ""
                    onTextChanged: panel.query = text
                    Keys.onPressed: event => panel.handleKey(event)
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
                            readonly property int n: ClipStore.counts[modelData.id] || 0

                            compact: true
                            raised: panel.tab === modelData.id
                            primary: panel.tab === modelData.id
                            text: modelData.label + (n > 0 && modelData.id !== "all" ? "  " + n : "")
                            onClicked: {
                                panel.tab = modelData.id;
                                searchField.forceActiveFocus();
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
                    text: panel.tip !== "" ? panel.tip : (ClipStore.paused ? "Private  \u00b7  new copies are not kept" : "")
                    color: ClipStore.paused && panel.tip === "" ? Colors.color3 : Colors.muted
                    font.pixelSize: Style.fontSm
                    elide: Text.ElideRight
                }
            }

            Rule {
                width: parent.width
            }

            // ---- The body: the list, the entry, the keys ----------------------
            Item {
                id: body

                width: parent.width
                height: panel.bodyH

                // The list
                Item {
                    id: listArea

                    width: panel.listW
                    height: parent.height
                    visible: !panel.showHelp

                    ListView {
                        id: list

                        anchors.fill: parent
                        anchors.rightMargin: 6
                        visible: list.count > 0
                        clip: true
                        spacing: 2
                        boundsBehavior: Flickable.StopAtBounds
                        cacheBuffer: 300
                        currentIndex: panel.cursorIndex
                        onCurrentIndexChanged: if (currentIndex >= 0)
                            positionViewAtIndex(currentIndex, ListView.Contain)

                        model: ScriptModel {
                            values: panel.shownEntries
                            objectProp: "id"
                        }

                        delegate: ClipRow {
                            width: list.width
                            current: modelData.id === panel.cursorId
                            ticked: panel.ticked[modelData.id] === true
                            onClicked: ctrl => panel.rowClicked(modelData.id, ctrl)
                            onCopyClicked: ClipStore.copyEntry(modelData, false)
                            onPinClicked: ClipStore.togglePin(modelData)
                            onDeleteClicked: ClipStore.deleteEntries([modelData])
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
                            border.color: Style.outline

                            Txt {
                                anchors.centerIn: parent
                                text: panel.tab === "pinned" ? Icons.heartOutline : (panel.query.trim() !== "" ? Icons.search : Icons.paste)
                                color: Colors.muted
                                font.pixelSize: 20
                            }
                        }

                        Txt {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: panel.query.trim() !== "" ? "Nothing matches" : (panel.tab === "pinned" ? "Nothing pinned yet" : (!ClipStore.loaded ? "Reading the history\u2026" : "The history is empty"))
                            color: Colors.foreground
                            font.pixelSize: Style.fontLg
                            font.bold: true
                        }

                        Txt {
                            anchors.horizontalCenter: parent.horizontalCenter
                            visible: panel.query.trim() === ""
                            text: panel.tab === "pinned" ? "Pin an entry with Ctrl+P to keep it for good" : "Things you copy show up here"
                            color: Colors.muted
                            font.pixelSize: Style.fontMd
                        }
                    }
                }

                // The selected entry, in full
                Rectangle {
                    id: pane

                    x: panel.listW + 14
                    width: panel.previewW
                    height: parent.height
                    visible: panel.previewOn && !panel.showHelp
                    radius: Style.radiusLg
                    color: Style.well
                    border.width: 1
                    border.color: Style.outline

                    Txt {
                        id: paneMeta

                        x: 14
                        y: 12
                        width: parent.width - 28
                        text: panel.cur !== null ? panel.curMeta : ""
                        color: Colors.muted
                        font.pixelSize: Style.fontSm
                        elide: Text.ElideRight
                    }

                    // The content
                    Item {
                        id: content

                        x: 14
                        y: 34
                        width: parent.width - 28
                        height: parent.height - 34 - actions.height - 22
                        clip: true

                        // Text, links, paths
                        Flickable {
                            id: textFlick

                            anchors.fill: parent
                            visible: panel.cur !== null && !panel.cur.binary && panel.cur.kind !== "color" && (panel.cur.kind !== "secret" || panel.revealed)
                            contentHeight: bodyText.height
                            boundsBehavior: Flickable.StopAtBounds
                            flickableDirection: Flickable.VerticalFlick

                            onVisibleChanged: if (visible)
                                contentY = 0

                            Txt {
                                id: bodyText

                                width: textFlick.width - 4
                                text: panel.fullText
                                textFormat: Text.PlainText
                                wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                                color: panel.cur !== null && panel.cur.kind === "link" ? Colors.accent : Colors.foreground
                                opacity: panel.textLoaded ? 1 : 0.6
                                font.pixelSize: Style.fontBase
                            }
                        }

                        // A hidden secret
                        Column {
                            visible: panel.cur !== null && panel.cur.kind === "secret" && !panel.revealed
                            anchors.centerIn: parent
                            spacing: 8

                            Txt {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: Icons.lock
                                color: Colors.color3
                                font.pixelSize: 26
                            }

                            Txt {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: "Looks like a secret, so it is hidden"
                                color: Colors.foreground
                                font.pixelSize: Style.fontMd
                            }

                            TextButton {
                                anchors.horizontalCenter: parent.horizontalCenter
                                compact: true
                                text: "Show it"
                                onClicked: panel.revealed = true
                            }
                        }

                        // A colour
                        Column {
                            visible: panel.cur !== null && panel.cur.kind === "color"
                            anchors.fill: parent
                            spacing: 10

                            Rectangle {
                                width: parent.width
                                height: Math.max(40, parent.height - 78)
                                radius: Style.radiusMd
                                color: panel.cur !== null && panel.cur.kind === "color" ? Qt.color(panel.cur.preview.trim()) : "transparent"
                                border.width: 1
                                border.color: Style.outline
                            }

                            Repeater {
                                model: panel.cur !== null && panel.cur.kind === "color" ? ["hex", "rgb", "hsl"] : []

                                delegate: Txt {
                                    required property string modelData

                                    text: ClipStore.colorAs(modelData, panel.cur.preview)
                                    color: Colors.foreground
                                    font.pixelSize: Style.fontMd
                                }
                            }
                        }

                        // An image
                        Image {
                            id: bigImage

                            anchors.fill: parent
                            visible: panel.cur !== null && panel.cur.binary
                            source: panel.cur !== null && panel.cur.binary ? ClipStore.thumbUrl(panel.cur) : ""
                            fillMode: Image.PreserveAspectFit
                            asynchronous: true
                            cache: false
                            sourceSize.width: 900
                            sourceSize.height: 900
                        }

                        Txt {
                            anchors.centerIn: parent
                            visible: panel.cur !== null && panel.cur.binary && bigImage.status !== Image.Ready
                            text: "Loading\u2026"
                            color: Colors.muted
                            font.pixelSize: Style.fontMd
                        }

                        Txt {
                            anchors.centerIn: parent
                            visible: panel.cur === null
                            text: "Nothing selected"
                            color: Colors.muted
                            font.pixelSize: Style.fontMd
                        }
                    }

                    // What can be done with it
                    Flow {
                        id: actions

                        x: 14
                        y: parent.height - height - 12
                        width: parent.width - 28
                        spacing: 6
                        visible: panel.cur !== null

                        TextButton {
                            compact: true
                            primary: true
                            glyph: Icons.copy
                            text: panel.tickedCount > 1 ? "Join " + panel.tickedCount : "Copy"
                            onClicked: panel.copyCurrent(false)
                        }

                        TextButton {
                            compact: true
                            glyph: Icons.paste
                            text: "Paste"
                            visible: panel.tickedCount < 2
                            onClicked: panel.copyCurrent(true)
                        }

                        TextButton {
                            compact: true
                            glyph: panel.cur !== null && panel.cur.pinned ? Icons.heart : Icons.heartOutline
                            text: panel.cur !== null && panel.cur.pinned ? "Unpin" : "Pin"
                            onClicked: ClipStore.togglePin(panel.cur)
                        }

                        Repeater {
                            model: panel.curActions

                            delegate: TextButton {
                                required property var modelData

                                compact: true
                                text: modelData.label
                                onClicked: ClipStore.runAction(modelData.id, panel.cur)
                            }
                        }

                        TextButton {
                            compact: true
                            danger: true
                            glyph: Icons.trash
                            text: panel.tickedCount > 1 ? "Remove " + panel.tickedCount : "Remove"
                            onClicked: panel.removeTargets()
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
                                    width: 140

                                    Repeater {
                                        model: modelData.k

                                        delegate: KeyCap {
                                            required property string modelData

                                            label: modelData
                                        }
                                    }
                                }

                                Txt {
                                    x: 144
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width - 144
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

            // ---- What the keys do right now --------------------------------------
            Item {
                width: parent.width
                height: panel.footH

                Txt {
                    anchors.left: parent.left
                    anchors.right: entryCount.left
                    anchors.rightMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    text: panel.tickedCount > 0 ? panel.tickedCount + " ticked  \u00b7  Enter joins them  \u00b7  Del removes  \u00b7  Esc unticks" : "Enter copy  \u00b7  Shift+Enter paste  \u00b7  Ctrl+P pin  \u00b7  Ctrl+Space tick  \u00b7  / keys"
                    color: Colors.muted
                    opacity: 0.8
                    font.pixelSize: Style.fontSm
                    elide: Text.ElideRight
                }

                Txt {
                    id: entryCount

                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: ClipStore.counts.all + (ClipStore.counts.all === 1 ? " entry" : " entries")
                    color: Colors.muted
                    font.pixelSize: Style.fontSm
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
        border.color: ClipStore.noteIsError ? Qt.alpha(Colors.critical, 0.6) : Qt.alpha(Colors.accent, 0.5)
        opacity: ClipStore.note !== "" && panel.reveal > 0.9 ? 1 : 0
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
            text: ClipStore.note
            color: ClipStore.noteIsError ? Colors.critical : Colors.foreground
            font.pixelSize: Style.fontMd
            elide: Text.ElideRight
        }
    }
}
