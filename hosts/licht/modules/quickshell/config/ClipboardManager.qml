// ClipboardManager.qml
// Rofi-replacement clipboard history, backed by cliphist.
// Toggle via IPC:
//   qs -p <your shell.qml path> ipc call clipboard toggle

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets

PanelWindow {
    id: clipboard

    property var allEntries: [] // raw "id\tpreview" lines from cliphist
    property var filtered: []
    property int selectedIndex: 0

    function b64(str) {
        return Qt.btoa(unescape(encodeURIComponent(str)));
    }

    function scan() {
        scanner.running = true;
    }

    function refilter() {
        const q = searchField.text.toLowerCase().trim();
        if (q.length === 0)
            filtered = allEntries;
        else
            filtered = allEntries.filter((line) => {
                return line.toLowerCase().includes(q);
            });
        selectedIndex = 0;
    }

    function selectEntry(line) {
        if (!line)
            return ;
 // Pipe the exact list line through cliphist decode, then wl-copy.
        // base64-wrapped to sidestep any shell-quoting issues in the line.
        Quickshell.execDetached(["bash", "-c", "echo " + b64(line) + " | base64 -d | cliphist decode | wl-copy"]);
        close();
    }

    function deleteEntry(line) {
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

    visible: false
    color: "transparent"
    margins.top: Screen.height / 5
    implicitWidth: 640
    implicitHeight: Math.min(480, 72 + resultsList.count * 56)
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
                clipboard.allEntries = text.split("\n").filter((l) => {
                    return l.trim().length > 0;
                });
                clipboard.refilter();
            }
        }

    }

    Rectangle {
        anchors.fill: parent
        radius: 14
        color: Colors.background
        border.width: 2
        border.color: Colors.accent
        opacity: 0.97

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 8

            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 48
                    radius: 10
                    color: Colors.surface
                    border.width: searchField.activeFocus ? 2 : 0
                    border.color: Colors.accent

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 14
                        anchors.rightMargin: 14
                        spacing: 10

                        Text {
                            text: "📋"
                            font.pixelSize: 16
                        }

                        TextInput {
                            id: searchField

                            Layout.fillWidth: true
                            color: Colors.foreground
                            font.pixelSize: 18
                            font.family: "monospace"
                            clip: true
                            onTextChanged: clipboard.refilter()
                            Keys.onEscapePressed: clipboard.close()
                            Keys.onDownPressed: {
                                if (selectedIndex < filtered.length - 1)
                                    selectedIndex++;

                            }
                            Keys.onUpPressed: {
                                if (selectedIndex > 0)
                                    selectedIndex--;

                            }
                            Keys.onReturnPressed: clipboard.selectEntry(filtered[selectedIndex])
                            Keys.onEnterPressed: clipboard.selectEntry(filtered[selectedIndex])
                            // Delete key clears the selected history entry
                            // without closing the picker.
                            Keys.onPressed: (event) => {
                                if (event.key === Qt.Key_Delete) {
                                    clipboard.deleteEntry(filtered[selectedIndex]);
                                    event.accepted = true;
                                }
                            }
                        }

                        Text {
                            text: filtered.length + " items"
                            color: Colors.muted
                            font.pixelSize: 12
                        }

                    }

                }

                Rectangle {
                    radius: 10
                    Layout.preferredWidth: 70
                    Layout.preferredHeight: 48
                    color: Colors.surface

                    Text {
                        anchors.centerIn: parent
                        text: "Clear"
                        color: Colors.muted
                        font.pixelSize: 12
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: clipboard.clearAll()
                    }

                }

            }

            ListView {
                id: resultsList

                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                model: filtered
                currentIndex: selectedIndex
                highlightMoveDuration: 80

                Text {
                    anchors.centerIn: parent
                    visible: filtered.length === 0
                    text: allEntries.length === 0 ? "no clipboard history yet" : "no matches"
                    color: Colors.muted
                    font.pixelSize: 14
                }

                delegate: Rectangle {
                    width: resultsList.width
                    height: 52
                    radius: 8
                    color: index === selectedIndex ? Colors.accent : "transparent"

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        spacing: 12

                        Text {
                            // strip the leading cliphist id so only the
                            // preview content shows
                            text: modelData.replace(/^\S+\s+/, "")
                            color: index === selectedIndex ? Colors.background : Colors.foreground
                            font.pixelSize: 14
                            font.family: "monospace"
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }

                        Text {
                            text: "✕"
                            color: index === selectedIndex ? Colors.background : Colors.muted
                            font.pixelSize: 13

                            MouseArea {
                                anchors.fill: parent
                                anchors.margins: -8
                                onClicked: clipboard.deleteEntry(modelData)
                            }

                        }

                    }

                    MouseArea {
                        anchors.fill: parent
                        z: -1
                        hoverEnabled: true
                        onEntered: selectedIndex = index
                        onClicked: clipboard.selectEntry(modelData)
                    }

                }

            }

        }

    }

}
