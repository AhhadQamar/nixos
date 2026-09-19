// AppLauncher.qml
// Manual .desktop file scanner (no Quickshell.DesktopEntries dependency).
// On open, runs an embedded python3 scanner that parses all .desktop
// files under the standard XDG app dirs and returns JSON.

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets

PanelWindow {
    id: launcher

    property var allApps: []
    property var filtered: []
    property int selectedIndex: 0
    // base64-encoded python3 scanner — parses ~/.local/share/applications,
    // /usr/share/applications, /usr/local/share/applications, skipping
    // NoDisplay/Hidden entries, and prints a JSON array to stdout.
    readonly property string scannerB64: "aW1wb3J0IGpzb24sIG9zLCByZSwgZ2xvYiwgY29uZmlncGFyc2VyCgojIFRyYWRpdGlvbmFsIGRpcnMgKHdvcmtzIG9uIEFyY2gvbW9zdCBkaXN0cm9zKSBQTFVTIGV2ZXJ5IGFwcGxpY2F0aW9ucy8KIyBkaXIgdW5kZXIgJFhER19EQVRBX0RJUlMgKHdvcmtzIG9uIE5peE9TLCB3aGVyZSAuZGVza3RvcCBmaWxlcyBsaXZlCiMgdW5kZXIgL3J1bi9jdXJyZW50LXN5c3RlbS9zdy9zaGFyZS9hcHBsaWNhdGlvbnMgYW5kCiMgfi8ubml4LXByb2ZpbGUvc2hhcmUvYXBwbGljYXRpb25zIGluc3RlYWQgb2YgL3Vzci9zaGFyZSkuCmRpcnMgPSBbCiAgICAiL3Vzci9zaGFyZS9hcHBsaWNhdGlvbnMiLAogICAgIi91c3IvbG9jYWwvc2hhcmUvYXBwbGljYXRpb25zIiwKICAgIG9zLnBhdGguZXhwYW5kdXNlcigifi8ubG9jYWwvc2hhcmUvYXBwbGljYXRpb25zIiksCl0KCnhkZ19kYXRhX2RpcnMgPSBvcy5lbnZpcm9uLmdldCgiWERHX0RBVEFfRElSUyIsICIiKQpmb3IgZCBpbiB4ZGdfZGF0YV9kaXJzLnNwbGl0KCI6Iik6CiAgICBpZiBkOgogICAgICAgIGRpcnMuYXBwZW5kKG9zLnBhdGguam9pbihkLCAiYXBwbGljYXRpb25zIikpCgojIGRlLWR1cGUgd2hpbGUgcHJlc2VydmluZyBvcmRlcgpzZWVuX2RpcnMgPSBzZXQoKQpvcmRlcmVkX2RpcnMgPSBbXQpmb3IgZCBpbiBkaXJzOgogICAgaWYgZCBub3QgaW4gc2Vlbl9kaXJzOgogICAgICAgIHNlZW5fZGlycy5hZGQoZCkKICAgICAgICBvcmRlcmVkX2RpcnMuYXBwZW5kKGQpCmRpcnMgPSBvcmRlcmVkX2RpcnMKCmFwcHMgPSBbXQpzZWVuID0gc2V0KCkKZmllbGRfY29kZV9yZSA9IHJlLmNvbXBpbGUociIlW2EtekEtWiVdIikKCmZvciBkIGluIGRpcnM6CiAgICBpZiBub3Qgb3MucGF0aC5pc2RpcihkKToKICAgICAgICBjb250aW51ZQogICAgZm9yIHBhdGggaW4gZ2xvYi5nbG9iKG9zLnBhdGguam9pbihkLCAiKi5kZXNrdG9wIikpOgogICAgICAgIHRyeToKICAgICAgICAgICAgY3AgPSBjb25maWdwYXJzZXIuUmF3Q29uZmlnUGFyc2VyKHN0cmljdD1GYWxzZSkKICAgICAgICAgICAgY3AucmVhZChwYXRoLCBlbmNvZGluZz0idXRmLTgiKQogICAgICAgICAgICBpZiAiRGVza3RvcCBFbnRyeSIgbm90IGluIGNwOgogICAgICAgICAgICAgICAgY29udGludWUKICAgICAgICAgICAgZSA9IGNwWyJEZXNrdG9wIEVudHJ5Il0KICAgICAgICAgICAgaWYgZS5nZXQoIk5vRGlzcGxheSIsICJmYWxzZSIpLmxvd2VyKCkgPT0gInRydWUiOgogICAgICAgICAgICAgICAgY29udGludWUKICAgICAgICAgICAgaWYgZS5nZXQoIkhpZGRlbiIsICJmYWxzZSIpLmxvd2VyKCkgPT0gInRydWUiOgogICAgICAgICAgICAgICAgY29udGludWUKICAgICAgICAgICAgaWYgZS5nZXQoIlR5cGUiLCAiQXBwbGljYXRpb24iKSAhPSAiQXBwbGljYXRpb24iOgogICAgICAgICAgICAgICAgY29udGludWUKICAgICAgICAgICAgbmFtZSA9IGUuZ2V0KCJOYW1lIiwgIiIpCiAgICAgICAgICAgIGlmIG5vdCBuYW1lIG9yIG5hbWUgaW4gc2VlbjoKICAgICAgICAgICAgICAgIGNvbnRpbnVlCiAgICAgICAgICAgIGV4ZWNfcmF3ID0gZS5nZXQoIkV4ZWMiLCAiIikKICAgICAgICAgICAgZXhlY19jbGVhbiA9IGZpZWxkX2NvZGVfcmUuc3ViKCIiLCBleGVjX3Jhdykuc3RyaXAoKQogICAgICAgICAgICBhcHBzLmFwcGVuZCh7CiAgICAgICAgICAgICAgICAibmFtZSI6IG5hbWUsCiAgICAgICAgICAgICAgICAiZ2VuZXJpY05hbWUiOiBlLmdldCgiR2VuZXJpY05hbWUiLCAiIiksCiAgICAgICAgICAgICAgICAiY29tbWVudCI6IGUuZ2V0KCJDb21tZW50IiwgIiIpLAogICAgICAgICAgICAgICAgImljb24iOiBlLmdldCgiSWNvbiIsICIiKSwKICAgICAgICAgICAgICAgICJleGVjIjogZXhlY19jbGVhbiwKICAgICAgICAgICAgICAgICJ0ZXJtaW5hbCI6IGUuZ2V0KCJUZXJtaW5hbCIsICJmYWxzZSIpLmxvd2VyKCkgPT0gInRydWUiLAogICAgICAgICAgICB9KQogICAgICAgICAgICBzZWVuLmFkZChuYW1lKQogICAgICAgIGV4Y2VwdCBFeGNlcHRpb246CiAgICAgICAgICAgIGNvbnRpbnVlCgphcHBzLnNvcnQoa2V5PWxhbWJkYSBhOiBhWyJuYW1lIl0ubG93ZXIoKSkKcHJpbnQoanNvbi5kdW1wcyhhcHBzKSkK"

    function scanApps() {
        appScanner.running = true;
    }

    function refilter() {
        const q = searchField.text.toLowerCase().trim();
        if (q.length === 0)
            filtered = allApps;
        else
            filtered = allApps.filter((a) => {
            const name = (a.name || "").toLowerCase();
            const generic = (a.genericName || "").toLowerCase();
            const exec = (a.exec || "").toLowerCase();
            return name.includes(q) || generic.includes(q) || exec.includes(q);
        });
        selectedIndex = 0;
    }

    function launch(entry) {
        if (!entry)
            return ;

        // Terminal apps get wrapped in a terminal emulator.
        // Change "kitty -e" below to match yours (e.g. "foot", "alacritty -e").
        if (entry.terminal)
            Quickshell.execDetached(["bash", "-c", "kitty -e " + entry.exec]);
        else
            Quickshell.execDetached(["bash", "-c", entry.exec]);
        close();
    }

    function open() {
        visible = true;
        searchField.text = "";
        scanApps();
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

    IpcHandler {
        function toggle() {
            launcher.toggle();
        }

        function open() {
            launcher.open();
        }

        function close() {
            launcher.close();
        }

        target: "launcher"
    }

    Process {
        id: appScanner

        command: ["bash", "-c", "echo " + scannerB64 + " | base64 -d | python3"]

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    launcher.allApps = JSON.parse(text);
                } catch (e) {
                    console.log("AppLauncher: failed to parse scanner output:", e);
                    launcher.allApps = [];
                }
                launcher.refilter();
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
                        text: "🔍"
                        color: Colors.muted
                        font.pixelSize: 18
                    }

                    TextInput {
                        id: searchField

                        Layout.fillWidth: true
                        color: Colors.foreground
                        font.pixelSize: 18
                        font.family: "monospace"
                        clip: true
                        onTextChanged: launcher.refilter()
                        Keys.onEscapePressed: launcher.close()
                        Keys.onDownPressed: {
                            if (selectedIndex < filtered.length - 1)
                                selectedIndex++;

                        }
                        Keys.onUpPressed: {
                            if (selectedIndex > 0)
                                selectedIndex--;

                        }
                        Keys.onReturnPressed: launcher.launch(filtered[selectedIndex])
                        Keys.onEnterPressed: launcher.launch(filtered[selectedIndex])
                    }

                    Text {
                        text: filtered.length + " apps"
                        color: Colors.muted
                        font.pixelSize: 12
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
                    visible: filtered.length === 0 && allApps.length > 0
                    text: "no matches"
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

                        IconImage {
                            source: Quickshell.iconPath(modelData.icon, "application-x-executable")
                            implicitWidth: 32
                            implicitHeight: 32
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0

                            Text {
                                text: modelData.name
                                color: index === selectedIndex ? Colors.background : Colors.foreground
                                font.pixelSize: 15
                                font.bold: true
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }

                            Text {
                                text: modelData.genericName || modelData.comment || ""
                                color: index === selectedIndex ? Colors.background : Colors.muted
                                font.pixelSize: 11
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                                visible: text.length > 0
                            }

                        }

                    }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        onEntered: selectedIndex = index
                        onClicked: launcher.launch(modelData)
                    }

                }

            }

        }

    }

}

