import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

PanelWindow {
    id: clipboard

    readonly property int rowHeight: 40
    readonly property int rowGap: 2
    readonly property int maxRows: 8

    property var allEntries: [] // raw "id\tpreview" lines from cliphist
    property var filtered: []
    property int selectedIndex: 0

    // ---- Helpers --------------------------------------------------------
    function b64(str) {
        return Qt.btoa(unescape(encodeURIComponent(str)));
    }

    // cliphist lines are "<id>\t<preview>"; only the preview is shown.
    function previewOf(line) {
        return line.replace(/^\S+\s+/, "");
    }

    function isBinary(line) {
        return /^\S+\s+\[\[ binary data/.test(line);
    }

    // ---- Actions --------------------------------------------------------
    function scan() {
        scanner.running = true;
    }

    function refilter() {
        const q = searchField.text.toLowerCase().trim();
        if (q.length === 0)
            filtered = allEntries;
        else
            filtered = allEntries.filter(line => {
                return line.toLowerCase().includes(q);
            });
        selectedIndex = 0;
    }

    function move(delta) {
        if (filtered.length === 0)
            return;
        selectedIndex = Math.max(0, Math.min(filtered.length - 1, selectedIndex + delta));
    }

    function selectEntry(line) {
        if (!line)
            return;
        // Pipe the exact list line through cliphist decode, then wl-copy.
        // base64-wrapped to sidestep any shell-quoting issues in the line.
        Quickshell.execDetached(["bash", "-c", "echo " + b64(line) + " | base64 -d | cliphist decode | wl-copy"]);
        close();
    }

    function deleteEntry(line) {
        if (!line)
            return;
        Quickshell.execDetached(["bash", "-c", "echo " + b64(line) + " | base64 -d | cliphist delete"]);
        // give cliphist a moment to write, then refresh
        rescanTimer.start();
    }

    function clearAll() {
        Quickshell.execDetached(["bash", "-c", "cliphist wipe"]);
        rescanTimer.start();
    }

    function open() {
        visible = true;
        searchField.text = "";
        scan();
        searchField.forceActiveFocus();
        fadeIn.restart();
    }

    function close() {
        visible = false;
    }

    function toggle() {
        if (visible)
            close();
        else
            open();
    }

    // ---- Window ---------------------------------------------------------
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

    Timer {
        id: rescanTimer

        interval: 150
        repeat: false
        onTriggered: clipboard.scan()
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
            clipboard.clearAll();
        }

        target: "clipboard"
    }

    Process {
        id: scanner

        command: ["bash", "-c", "cliphist list"]

        stdout: StdioCollector {
            onStreamFinished: {
                clipboard.allEntries = text.split("\n").filter(l => {
                    return l.trim().length > 0;
                });
                clipboard.refilter();
            }
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

    // Keyboard hint
    component KeyCap: Rectangle {
        id: cap

        property string label: ""

        implicitWidth: Math.max(20, capText.implicitWidth + 12)
        implicitHeight: 20
        radius: 5
        color: Colors.surfaceAlt

        Text {
            id: capText

            textFormat: Text.PlainText
            anchors.centerIn: parent
            text: cap.label
            font.family: Style.fontFamily
            font.pixelSize: 10
            font.bold: true
            color: Colors.foreground
            opacity: 0.75
        }
    }

    // ---- The panel ------------------------------------------------------
    Rectangle {
        id: card

        anchors.fill: parent
        implicitHeight: content.implicitHeight + 28
        radius: Style.barRadius
        antialiasing: true
        color: Style.surface
        border.width: 1
        border.color: Style.outline

        ColumnLayout {
            id: content

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 14
            spacing: 10

            // ---- Search and clear ----------------------------------------
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 34
                    radius: height / 2
                    antialiasing: true
                    color: Style.hoverFill

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 14
                        anchors.rightMargin: 14
                        spacing: 10

                        Text {
                            textFormat: Text.PlainText
                            text: "\uf0ea"
                            color: searchField.activeFocus ? Colors.accent : Colors.muted

                            Behavior on color {
                                ColorAnimation {
                                    duration: 200
                                }
                            }

                            font {
                                family: Style.fontFamily
                                pixelSize: 14
                            }
                        }

                        TextInput {
                            id: searchField

                            Layout.fillWidth: true
                            color: Colors.foreground
                            selectionColor: Colors.accent
                            selectedTextColor: Colors.background
                            clip: true
                            onTextChanged: clipboard.refilter()
                            Keys.onEscapePressed: clipboard.close()
                            Keys.onDownPressed: clipboard.move(1)
                            Keys.onUpPressed: clipboard.move(-1)
                            Keys.onReturnPressed: clipboard.selectEntry(clipboard.filtered[clipboard.selectedIndex])
                            Keys.onEnterPressed: clipboard.selectEntry(clipboard.filtered[clipboard.selectedIndex])
                            Keys.onPressed: event => {
                                if (event.key === Qt.Key_Delete) {
                                    // Removes the highlighted entry without closing the panel
                                    clipboard.deleteEntry(clipboard.filtered[clipboard.selectedIndex]);
                                    event.accepted = true;
                                } else if (event.modifiers & Qt.ControlModifier) {
                                    if (event.key === Qt.Key_N) {
                                        clipboard.move(1);
                                        event.accepted = true;
                                    } else if (event.key === Qt.Key_P) {
                                        clipboard.move(-1);
                                        event.accepted = true;
                                    }
                                }
                            }

                            font {
                                family: Style.fontFamily
                                pixelSize: 14
                            }

                            Text {
                                visible: searchField.text.length === 0
                                anchors.verticalCenter: parent.verticalCenter
                                textFormat: Text.PlainText
                                text: "Search clipboard"
                                color: Colors.muted

                                font {
                                    family: Style.fontFamily
                                    pixelSize: 14
                                }
                            }
                        }
                    }
                }

                Rectangle {
                    implicitWidth: clearLabel.implicitWidth + 28
                    implicitHeight: 34
                    radius: height / 2
                    antialiasing: true
                    color: clearArea.containsMouse ? Style.hoverFill : "transparent"
                    scale: clearArea.pressed ? 0.94 : 1

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

                    Text {
                        id: clearLabel

                        anchors.centerIn: parent
                        textFormat: Text.PlainText
                        text: "Clear"
                        color: clearArea.containsMouse ? Colors.critical : Colors.muted

                        Behavior on color {
                            ColorAnimation {
                                duration: 200
                            }
                        }

                        font {
                            family: Style.fontFamily
                            pixelSize: 13
                        }
                    }

                    MouseArea {
                        id: clearArea

                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: clipboard.clearAll()
                    }
                }
            }

            // ---- History ---------------------------------------------------
            ListView {
                id: resultsList

                readonly property int shown: Math.min(clipboard.maxRows, clipboard.filtered.length)

                Layout.fillWidth: true
                Layout.preferredHeight: shown === 0 ? 72 : shown * clipboard.rowHeight + (shown - 1) * clipboard.rowGap
                clip: true
                spacing: clipboard.rowGap
                boundsBehavior: Flickable.StopAtBounds
                model: clipboard.filtered
                currentIndex: clipboard.selectedIndex
                onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)

                Text {
                    anchors.centerIn: parent
                    visible: clipboard.filtered.length === 0
                    textFormat: Text.PlainText
                    text: clipboard.allEntries.length === 0 ? "Nothing copied yet" : "No matches"
                    color: Colors.muted

                    font {
                        family: Style.fontFamily
                        pixelSize: 13
                    }
                }

                delegate: Rectangle {
                    id: row

                    required property int index
                    required property var modelData

                    readonly property bool current: index === clipboard.selectedIndex
                    readonly property bool binary: clipboard.isBinary(modelData)

                    width: resultsList.width
                    height: clipboard.rowHeight
                    radius: height / 2
                    antialiasing: true
                    color: current ? Style.hoverFill : "transparent"
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

                    // Selection marker: the bar's 2px accent, standing up
                    Rectangle {
                        visible: row.current
                        anchors.left: parent.left
                        anchors.leftMargin: 9
                        anchors.verticalCenter: parent.verticalCenter
                        width: 2
                        height: 16
                        radius: 1
                        color: Colors.accent
                    }

                    MouseArea {
                        id: rowArea

                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        // Position, not enter, so scrolling under a still mouse
                        // doesn't steal the keyboard selection
                        onPositionChanged: clipboard.selectedIndex = row.index
                        onClicked: clipboard.selectEntry(row.modelData)
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 22
                        anchors.rightMargin: 14
                        spacing: 12

                        Text {
                            Layout.preferredWidth: 16
                            horizontalAlignment: Text.AlignHCenter
                            textFormat: Text.PlainText
                            text: row.binary ? "\uf03e" : "\uf15c"
                            color: row.current ? Colors.accent : Colors.muted

                            Behavior on color {
                                ColorAnimation {
                                    duration: 120
                                }
                            }

                            font {
                                family: Style.fontFamily
                                pixelSize: 13
                            }
                        }

                        Text {
                            Layout.fillWidth: true
                            textFormat: Text.PlainText
                            elide: Text.ElideRight
                            maximumLineCount: 1
                            text: clipboard.previewOf(row.modelData)
                            color: Colors.foreground
                            opacity: row.current || rowArea.containsMouse ? 1 : 0.75

                            font {
                                family: Style.fontFamily
                                pixelSize: 13
                            }
                        }

                        Text {
                            id: removeGlyph

                            visible: row.current || rowArea.containsMouse
                            textFormat: Text.PlainText
                            text: "\uf00d"
                            color: removeArea.containsMouse ? Colors.critical : Colors.muted

                            Behavior on color {
                                ColorAnimation {
                                    duration: 200
                                }
                            }

                            font {
                                family: Style.fontFamily
                                pixelSize: 13
                            }

                            MouseArea {
                                id: removeArea

                                anchors.fill: parent
                                anchors.margins: -8
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: clipboard.deleteEntry(row.modelData)
                            }
                        }
                    }
                }
            }

            // ---- Hints -----------------------------------------------------
            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 4
                spacing: 6

                KeyCap {
                    label: "enter"
                }

                Text {
                    textFormat: Text.PlainText
                    text: "copy"
                    color: Colors.muted
                    rightPadding: 8

                    font {
                        family: Style.fontFamily
                        pixelSize: 11
                    }
                }

                KeyCap {
                    label: "del"
                }

                Text {
                    textFormat: Text.PlainText
                    text: "remove"
                    color: Colors.muted
                    rightPadding: 8

                    font {
                        family: Style.fontFamily
                        pixelSize: 11
                    }
                }

                KeyCap {
                    label: "esc"
                }

                Text {
                    textFormat: Text.PlainText
                    text: "close"
                    color: Colors.muted

                    font {
                        family: Style.fontFamily
                        pixelSize: 11
                    }
                }

                Item {
                    Layout.fillWidth: true
                }

                Text {
                    textFormat: Text.PlainText
                    text: searchField.text.trim() === "" ? clipboard.allEntries.length + " items" : clipboard.filtered.length + " of " + clipboard.allEntries.length

                    color: Colors.muted

                    font {
                        family: Style.fontFamily
                        pixelSize: 11
                    }
                }
            }
        }
    }
}
