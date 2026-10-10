// Inbox.qml
// Obsidian quick capture. Type a thought and it lands in your vault.
//
//   qs ipc call capture toggle | open | close
//   qs ipc call capture show daily          open straight into a mode (note | daily | task)
//   qs ipc call capture add "<text>"        save a note without opening the panel
//   qs ipc call capture daily "<text>"      append to today's daily note
//   qs ipc call capture task "<text>"       append a - [ ] task
//
// Modes:  Note   new note in the Inbox folder (title = first line)
//         Daily  "- 14:32 text" appended to today's daily note
//         Task   "- [ ] text" appended to your task file (or today's daily note)
//
// Keys:  enter save   shift+enter new line   tab / shift+tab switch mode (ctrl+1-3 jump)
//        ctrl+enter save and open in Obsidian   esc close

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

PanelWindow {
    id: capture

    // ---- Settings -------------------------------------------------------
    // Your vault. Change this if it isn't at ~/Life.
    readonly property string vaultDir: Quickshell.env("HOME") + "/Documents/Vault"
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
            "glyph": "\uf15c",
            "hint": "Capture a thought…"
        },
        {
            "id": "daily",
            "label": "Daily",
            "glyph": "\uf073",
            "hint": "Add to today's daily note…"
        },
        {
            "id": "task",
            "label": "Task",
            "glyph": "\uf046",
            "hint": "Add a task…"
        }
    ]
    readonly property var keyHints: [
        {
            "k": "enter",
            "d": "save"
        },
        {
            "k": "shift+enter",
            "d": "new line"
        },
        {
            "k": "tab",
            "d": "mode"
        },
        {
            "k": "ctrl+enter",
            "d": "save & open"
        },
        {
            "k": "esc",
            "d": "close"
        }
    ]
    // Runs as: sh -c <script> sh <text> <file> <append|create> <stamp>
    // The text and paths are arguments, never pasted into the script, so
    // quotes or $ in a note can't break it. Prints the file it wrote.
    readonly property var writeLines: ['mkdir -p "$(dirname "$2")" || exit 1', 'f="$2"', 'if [ "$3" = append ]; then', '  if [ -s "$f" ] && [ -n "$(tail -c1 "$f")" ]; then printf "\\n" >> "$f"; fi', '  printf "%s\\n" "$1" >> "$f"', 'else', '  if [ -e "$f" ]; then f="${2%.md} $4.md"; fi', '  set -C', '  printf "%s\\n" "$1" > "$f" || exit 1', 'fi', 'printf "%s" "$f"']

    // ---- State ----------------------------------------------------------
    property int mode: 0
    property bool openAfter: false
    property int lastMode: 0
    property string pendingText: ""
    property var inboxNotes: []   // file names in the Inbox folder, newest first

    // ---- Derived --------------------------------------------------------
    readonly property var current: modes[mode]
    readonly property string vaultName: vaultDir.split("/").pop()
    readonly property string destLabel: {
        const t = input.text.trim();
        if (mode === 0 && t === "")
            return inboxFolder + "/";
        return destinationOf(mode, t);
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

    function scanInbox() {
        lister.running = true;
    }

    function cycleMode(step) {
        mode = (mode + step + modes.length) % modes.length;
    }

    // ---- Window ---------------------------------------------------------
    function open(name) {
        mode = Math.max(0, modes.findIndex(m => {
            return m.id === name;
        }));
        visible = true;
        scanInbox();
        input.forceActiveFocus();
        if (input.text !== "")
            input.selectAll();
        fadeIn.restart();
    }

    function close() {
        visible = false;
        if (!keepDraft)
            input.text = "";
    }

    function toggle() {
        if (visible)
            close();
        else
            open();
    }

    // ---- Window ---------------------------------------------------------
    // Same placement as the clipboard manager and night light: anchored to
    // the top edge only, exactly as big as the card.
    visible: false
    color: "transparent"
    margins.top: Screen.height / 5
    implicitWidth: 640
    implicitHeight: card.implicitHeight
    exclusiveZone: 0
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

    anchors {
        top: true
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

    // File names in the Inbox folder, newest first
    Process {
        id: lister

        command: ["sh", "-c", 'd="$1"; [ -d "$d" ] && find "$d" -maxdepth 1 -type f -name "*.md" -printf "%T@ %f\\n" | sort -rn | cut -d" " -f2-', "sh", capture.vaultDir + "/" + capture.inboxFolder]
        stdout: StdioCollector {
            onStreamFinished: {
                capture.inboxNotes = text.split("\n").filter(l => {
                    return l.trim() !== "";
                });
            }
        }
    }

    // ---- Small building blocks --------------------------------------------
    // Text in the shell font. Every label below uses this, so none of them
    // can fall back to the system default font.
    component Txt: Text {
        textFormat: Text.PlainText
        font.family: Style.fontFamily
    }

    // Keyboard hint
    component KeyCap: Rectangle {
        id: cap

        property string label: ""

        implicitWidth: Math.max(20, capText.implicitWidth + 12)
        implicitHeight: 20
        radius: 5
        color: Colors.surfaceAlt

        Txt {
            id: capText

            anchors.centerIn: parent
            text: cap.label
            color: Colors.foreground
            opacity: 0.75
            font.pixelSize: 10
            font.bold: true
        }
    }

    // Mode button: a pill that is transparent until hovered, accent-tinted
    // while it is the selected mode (same as the night light's power button).
    component PillButton: Rectangle {
        id: pill

        property string glyph: ""
        property string label: ""
        property bool on: false

        signal clicked

        implicitWidth: pillRow.implicitWidth + 24
        implicitHeight: Style.itemHeight
        radius: height / 2
        antialiasing: true
        color: on ? Qt.alpha(Colors.accent, 0.2) : (pillHover.hovered ? Style.hoverFill : "transparent")
        scale: pillTap.pressed ? 0.94 : 1

        Behavior on color {
            ColorAnimation {
                duration: 200
            }
        }
        Behavior on scale {
            NumberAnimation {
                duration: 100
                easing.type: Easing.OutQuad
            }
        }

        Row {
            id: pillRow

            anchors.centerIn: parent
            spacing: 6

            Txt {
                anchors.verticalCenter: parent.verticalCenter
                visible: pill.glyph !== ""
                text: pill.glyph
                color: pill.on ? Colors.accent : (pillHover.hovered ? Colors.foreground : Colors.muted)
                font.pixelSize: 13

                Behavior on color {
                    ColorAnimation {
                        duration: 200
                    }
                }
            }

            Txt {
                anchors.verticalCenter: parent.verticalCenter
                text: pill.label
                color: pill.on ? Colors.accent : Colors.foreground
                opacity: pill.on || pillHover.hovered ? 1 : 0.75
                font.pixelSize: 13

                Behavior on color {
                    ColorAnimation {
                        duration: 200
                    }
                }
            }
        }

        HoverHandler {
            id: pillHover

            cursorShape: Qt.PointingHandCursor
        }

        TapHandler {
            id: pillTap

            onTapped: pill.clicked()
        }
    }

    ParallelAnimation {
        id: fadeIn

        NumberAnimation {
            target: card
            property: "opacity"
            from: 0
            to: 1
            duration: 140
            easing.type: Easing.OutCubic
        }

        NumberAnimation {
            target: card
            property: "scale"
            from: 0.97
            to: 1
            duration: 140
            easing.type: Easing.OutCubic
        }
    }

    // ---- The card -------------------------------------------------------
    Rectangle {
        id: card

        anchors.fill: parent
        implicitHeight: content.implicitHeight + 28
        radius: Style.barRadius
        antialiasing: true
        // More solid than the bar: this card sits over other windows' text
        color: Qt.alpha(Colors.background, 0.97)
        border.width: 1
        border.color: Style.outline

        ColumnLayout {
            id: content

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 14
            spacing: 10

            // ---- Header ---------------------------------------------------
            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 6
                spacing: 8

                Txt {
                    text: "Capture"
                    color: Colors.foreground
                    font.pixelSize: 14
                    font.bold: true
                }

                Rectangle {
                    width: 3
                    height: 3
                    radius: 1.5
                    color: Colors.muted
                }

                Txt {
                    text: capture.inboxNotes.length + " in " + capture.inboxFolder
                    color: Colors.muted
                    font.pixelSize: 13
                }

                Item {
                    Layout.fillWidth: true
                }
            }

            // ---- Mode and destination -------------------------------------
            RowLayout {
                Layout.fillWidth: true
                spacing: 4

                Repeater {
                    model: capture.modes

                    delegate: PillButton {
                        required property int index
                        required property var modelData

                        on: capture.mode === index
                        glyph: modelData.glyph
                        label: modelData.label
                        onClicked: {
                            capture.mode = index;
                            input.forceActiveFocus();
                        }
                    }
                }

                Txt {
                    Layout.fillWidth: true
                    Layout.leftMargin: 10
                    Layout.rightMargin: 6
                    horizontalAlignment: Text.AlignRight
                    elide: Text.ElideMiddle
                    text: "\u2192 " + capture.destLabel
                    color: Colors.muted
                    font.pixelSize: 12
                }
            }

            // ---- Input ----------------------------------------------------
            // Same field as the clipboard search: a soft fill, no hard border.
            // Focus only tints the icon and adds a faint accent edge.
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(200, Math.max(40, input.contentHeight + 24))
                radius: 18
                antialiasing: true
                color: Style.hoverFill
                border.width: 1
                border.color: input.activeFocus ? Qt.alpha(Colors.accent, 0.5) : "transparent"

                Behavior on border.color {
                    ColorAnimation {
                        duration: 200
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.IBeamCursor
                    onClicked: input.forceActiveFocus()
                }

                Txt {
                    x: 16
                    y: 12
                    text: capture.current.glyph
                    color: input.activeFocus ? Colors.accent : Colors.muted
                    font.pixelSize: 14

                    Behavior on color {
                        ColorAnimation {
                            duration: 200
                        }
                    }
                }

                TextEdit {
                    id: input

                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.leftMargin: 44
                    anchors.rightMargin: 16
                    y: 12
                    wrapMode: TextEdit.Wrap
                    color: Colors.foreground
                    selectionColor: Colors.accent
                    selectedTextColor: Colors.background
                    selectByMouse: true
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
                        }
                    }

                    font {
                        family: Style.fontFamily
                        pixelSize: 14
                    }

                    Txt {
                        visible: input.text.length === 0
                        text: capture.current.hint
                        color: Colors.muted
                        font.pixelSize: 14
                    }
                }
            }

            // ---- Recent captures ------------------------------------------
            ColumnLayout {
                visible: capture.inboxNotes.length > 0
                Layout.fillWidth: true
                spacing: 2

                Txt {
                    Layout.leftMargin: 6
                    Layout.bottomMargin: 4
                    text: "Recent in " + capture.inboxFolder
                    color: Colors.muted
                    font.pixelSize: 11
                }

                Repeater {
                    model: capture.inboxNotes.slice(0, capture.recentCount)

                    delegate: Rectangle {
                        id: row

                        required property string modelData

                        Layout.fillWidth: true
                        implicitHeight: 34
                        radius: height / 2
                        antialiasing: true
                        color: rowArea.containsMouse ? Style.hoverFill : "transparent"
                        scale: rowArea.pressed ? 0.985 : 1

                        Behavior on color {
                            ColorAnimation {
                                duration: 120
                            }
                        }
                        Behavior on scale {
                            NumberAnimation {
                                duration: 100
                                easing.type: Easing.OutQuad
                            }
                        }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 16
                            anchors.rightMargin: 16
                            spacing: 10

                            Txt {
                                text: "\uf15c"
                                color: rowArea.containsMouse ? Colors.accent : Colors.muted
                                font.pixelSize: 12

                                Behavior on color {
                                    ColorAnimation {
                                        duration: 200
                                    }
                                }
                            }

                            Txt {
                                Layout.fillWidth: true
                                text: row.modelData.replace(/\.md$/, "")
                                elide: Text.ElideRight
                                color: Colors.foreground
                                opacity: rowArea.containsMouse ? 1 : 0.75
                                font.pixelSize: 13
                            }

                            Txt {
                                visible: rowArea.containsMouse
                                text: "\uf08e"
                                color: Colors.accent
                                font.pixelSize: 12
                            }
                        }

                        MouseArea {
                            id: rowArea

                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                capture.openNote(capture.inboxFolder + "/" + row.modelData);
                                capture.close();
                            }
                        }
                    }
                }
            }

            // ---- Shortcuts ------------------------------------------------
            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 6
                spacing: 6

                Repeater {
                    model: capture.keyHints

                    delegate: RowLayout {
                        id: hint

                        required property var modelData

                        spacing: 6

                        KeyCap {
                            label: hint.modelData.k
                        }

                        Txt {
                            text: hint.modelData.d
                            color: Colors.muted
                            rightPadding: 8
                            font.pixelSize: 11
                        }
                    }
                }

                Item {
                    Layout.fillWidth: true
                }
            }
        }
    }
}
