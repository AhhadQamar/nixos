// WallpaperSwitcher.qml
// Grid picker for ~/Pictures/Wallpapers. Selecting one runs `wal -i`
// (regenerating your whole Colors palette) and sets it via awww.
// Toggle via IPC:
//   qs -p <your shell.qml path> ipc call wallpaper toggle
// Efficiency notes vs the first version:
//  - Thumbnails are generated ONCE per wallpaper into a disk cache
//    (~/.cache/quickshell/wall-thumbs) via `convert`, keyed by an md5
//    of the path. Every open after the first is near-instant because
//    it's loading tiny pre-resized PNGs instead of decoding full-res
//    source images (which for 4K/8K wallpapers is the actual cost).
//  - The directory is scanned once at startup, not on every open —
//    there's a manual refresh button instead of a filesystem rescan
//    every time you press the keybind.
//  - GridView delegates use sourceSize so QML never decodes above the
//    display size even for the (already-tiny) cached thumbs.
//  - Currently-applied wallpaper is read from pywal's own cache
//    (~/.cache/wal/wal) so the highlight survives across reopens/
//    restarts without the shell needing to track its own state.

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

PanelWindow {
    id: switcher

    // Change this if your wallpapers live elsewhere.
    readonly property string wallpaperDir: Quickshell.env("HOME") + "/Pictures/Wallpapers"
    readonly property string thumbCacheDir: Quickshell.env("HOME") + "/.cache/quickshell/wall-thumbs"
    // Each entry: { path, thumb }
    property var wallpapers: []
    property var filtered: []
    property string currentPath: ""
    property string applyingPath: ""
    property bool scanned: false
    property int selectedIndex: 0
    property string previewPath: ""

    function refilter() {
        const q = searchField.text.toLowerCase().trim();
        if (q.length === 0)
            filtered = wallpapers;
        else
            filtered = wallpapers.filter(w => {
                return w.path.toLowerCase().includes(q);
            });
        selectedIndex = 0;
    }

    function scan(force) {
        if (scanned && !force)
            return;

        scanner.running = true;
    }

    function setWallpaper(entry) {
        if (!entry)
            return;

        applyingPath = entry.path;
        Quickshell.execDetached(["bash", "-c", "wal -i \"" + entry.path + "\" -n; " + "ln -sf \"" + entry.path + "\" ~/Pictures/Wallpapers/.current_wallpaper; " + "awww img \"" + entry.path + "\" --transition-type simple --transition-fps 30; " + "hyprctl reload"]);
        currentPath = entry.path;
        appliedTimer.start();
    }

    function open() {
        visible = true;
        scan(false);
        searchField.text = "";
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
    margins.top: Screen.height / 6
    implicitWidth: 920
    implicitHeight: 560
    exclusiveZone: 0
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
    onSelectedIndexChanged: previewDebounce.restart()

    anchors {
        top: true
    }

    // Debounced so holding an arrow key doesn't trigger a full-res
    // decode on every single step — only once browsing pauses.
    Timer {
        id: previewDebounce

        interval: 120
        repeat: false
        onTriggered: {
            const entry = switcher.filtered[switcher.selectedIndex];
            switcher.previewPath = entry ? entry.path : "";
        }
    }

    Timer {
        id: appliedTimer

        interval: 1200
        repeat: false
        onTriggered: switcher.applyingPath = ""
    }

    IpcHandler {
        function toggle() {
            switcher.toggle();
        }

        function open() {
            switcher.open();
        }

        function close() {
            switcher.close();
        }

        target: "wallpaper"
    }

    // ---- Scan + thumbnail generation (one-time cost) ----
    Process {
        id: scanner

        command: ["bash", "-c", "mkdir -p \"" + switcher.thumbCacheDir + "\"; " + "shopt -s nullglob; " + "cd \"" + switcher.wallpaperDir + "\" 2>/dev/null || exit 0; " + "for f in *.jpg *.jpeg *.png *.webp *.JPG *.JPEG *.PNG *.WEBP; do " + "  full=\"" + switcher.wallpaperDir + "/$f\"; " + "  hash=$(printf '%s' \"$full\" | md5sum | cut -d' ' -f1); " + "  thumb=\"" + switcher.thumbCacheDir + "/$hash.png\"; " + "  if [ ! -f \"$thumb\" ]; then " + "    convert \"$full\" -thumbnail 320x200^ -gravity center -extent 320x200 \"$thumb\" 2>/dev/null; " + "  fi; " + "  if [ ! -s \"$thumb\" ]; then thumb=\"$full\"; fi; " + "  echo \"$full|$thumb\"; " + "done | sort; " + "cat \"$HOME/.cache/wal/wal\" 2>/dev/null || true"]

        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.split("\n").filter(l => {
                    return l.trim().length > 0;
                });
                const entries = [];
                let current = "";
                for (const line of lines) {
                    if (line.includes("|")) {
                        const parts = line.split("|");
                        entries.push({
                            "path": parts[0],
                            "thumb": parts[1]
                        });
                    } else {
                        // last non-piped line is the pywal "current wallpaper" file
                        current = line.trim();
                    }
                }
                switcher.wallpapers = entries;
                switcher.currentPath = current;
                switcher.scanned = true;
                switcher.refilter();
                previewDebounce.restart();
            }
        }
    }

    // Global keyboard nav, active while the panel is open.
    Item {
        anchors.fill: parent
        focus: switcher.visible
        Keys.onEscapePressed: switcher.close()
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
            anchors.margins: 14
            spacing: 10

            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 42
                    radius: 10
                    color: Colors.surface
                    border.width: searchField.activeFocus ? 2 : 0
                    border.color: Colors.accent

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        spacing: 8

                        Text {
                            text: "🔍"
                            font.pixelSize: 14
                        }

                        TextInput {
                            id: searchField

                            Layout.fillWidth: true
                            color: Colors.foreground
                            font.pixelSize: 14
                            font.family: "monospace"
                            clip: true
                            onTextChanged: switcher.refilter()
                            Keys.onReturnPressed: switcher.setWallpaper(filtered[selectedIndex])
                            Keys.onEnterPressed: switcher.setWallpaper(filtered[selectedIndex])
                            Keys.onRightPressed: {
                                if (selectedIndex < filtered.length - 1)
                                    selectedIndex++;
                            }
                            Keys.onLeftPressed: {
                                if (selectedIndex > 0)
                                    selectedIndex--;
                            }
                            Keys.onDownPressed: {
                                if (selectedIndex + grid.columns < filtered.length)
                                    selectedIndex += grid.columns;
                            }
                            Keys.onUpPressed: {
                                if (selectedIndex - grid.columns >= 0)
                                    selectedIndex -= grid.columns;
                            }
                            Keys.onPressed: event => {
                                if (event.key === Qt.Key_Home) {
                                    selectedIndex = 0;
                                    event.accepted = true;
                                } else if (event.key === Qt.Key_End) {
                                    selectedIndex = Math.max(0, filtered.length - 1);
                                    event.accepted = true;
                                }
                            }
                        }

                        Text {
                            text: filtered.length + " / " + wallpapers.length
                            color: Colors.muted
                            font.pixelSize: 11
                        }
                    }
                }

                Rectangle {
                    radius: 10
                    Layout.preferredWidth: 40
                    Layout.preferredHeight: 42
                    color: Colors.surface

                    Text {
                        anchors.centerIn: parent
                        text: "⟳"
                        color: Colors.muted
                        font.pixelSize: 16
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: switcher.scan(true)
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 12

                GridView {
                    id: grid

                    readonly property int columns: 3

                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    cellWidth: (width - 12) / columns
                    cellHeight: cellWidth * 0.66
                    model: switcher.filtered
                    currentIndex: switcher.selectedIndex
                    // Keep a couple extra rows decoded off-screen so
                    // scrolling stays smooth without re-decoding thumbs
                    // that just left the viewport.
                    cacheBuffer: cellHeight * 2
                    onCurrentIndexChanged: positionViewAtIndex(currentIndex, GridView.Contain)

                    Text {
                        anchors.centerIn: parent
                        visible: switcher.scanned && switcher.filtered.length === 0
                        text: switcher.wallpapers.length === 0 ? "no wallpapers found in\n" + switcher.wallpaperDir : "no matches"
                        color: Colors.muted
                        font.pixelSize: 13
                        horizontalAlignment: Text.AlignHCenter
                    }

                    Text {
                        anchors.centerIn: parent
                        visible: !switcher.scanned
                        text: "scanning + generating thumbnails…"
                        color: Colors.muted
                        font.pixelSize: 13
                    }

                    delegate: Item {
                        id: cell

                        readonly property bool isSelected: index === switcher.selectedIndex
                        readonly property bool isCurrent: switcher.currentPath === modelData.path
                        readonly property bool isApplying: switcher.applyingPath === modelData.path

                        width: grid.cellWidth - 8
                        height: grid.cellHeight - 8
                        scale: isSelected ? 1.05 : 1
                        z: isSelected ? 1 : 0

                        Rectangle {
                            anchors.fill: parent
                            radius: 10
                            color: Colors.surface
                            // Selection is the ONLY thing that draws a border —
                            // a thick accent ring, always visible when this is
                            // the keyboard/hover-highlighted cell. "Current
                            // wallpaper" gets its own separate dot marker below
                            // instead of fighting over the same border, so the
                            // two states never look identical.
                            border.width: cell.isSelected ? 3 : 0
                            border.color: Colors.accent
                            clip: true

                            Image {
                                anchors.fill: parent
                                anchors.margins: 3
                                source: "file://" + modelData.thumb
                                sourceSize.width: 320
                                sourceSize.height: 200
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                smooth: true
                                opacity: status === Image.Ready ? 1 : 0

                                Rectangle {
                                    anchors.fill: parent
                                    radius: 8
                                    color: Colors.background
                                    opacity: cell.isApplying ? 0.5 : 0

                                    Behavior on opacity {
                                        NumberAnimation {
                                            duration: 150
                                        }
                                    }
                                }

                                Text {
                                    anchors.centerIn: parent
                                    visible: cell.isApplying
                                    text: "Applying…"
                                    color: Colors.foreground
                                    font.pixelSize: 12
                                }

                                // Small dot marking the currently-applied
                                // wallpaper. Independent of selection/hover so
                                // it stays visible and unambiguous no matter
                                // which cell you're keyboard-browsing over.
                                Rectangle {
                                    visible: cell.isCurrent && !cell.isApplying
                                    anchors.top: parent.top
                                    anchors.right: parent.right
                                    anchors.margins: 6
                                    width: 10
                                    height: 10
                                    radius: 5
                                    color: Colors.accent
                                    border.width: 1.5
                                    border.color: Colors.background
                                }

                                Behavior on opacity {
                                    NumberAnimation {
                                        duration: 120
                                    }
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onEntered: switcher.selectedIndex = index
                                onClicked: switcher.setWallpaper(modelData)
                            }
                        }

                        Behavior on scale {
                            NumberAnimation {
                                duration: 100
                                easing.type: Easing.OutQuad
                            }
                        }
                    }
                }

                // ---- Preview sidebar ----
                // Shows the currently selected wallpaper at full resolution,
                // debounced so it only decodes once browsing settles rather
                // than on every arrow-key press.
                Rectangle {
                    Layout.preferredWidth: 220
                    Layout.fillHeight: true
                    radius: 10
                    color: Colors.surface
                    clip: true

                    Image {
                        id: previewImage

                        anchors.fill: parent
                        anchors.margins: 6
                        source: switcher.previewPath.length > 0 ? "file://" + switcher.previewPath : ""
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        smooth: true
                        opacity: status === Image.Ready ? 1 : 0

                        Rectangle {
                            anchors.bottom: parent.bottom
                            anchors.left: parent.left
                            anchors.right: parent.right
                            height: filenameText.implicitHeight + 16
                            color: Colors.background
                            opacity: 0.75

                            Text {
                                id: filenameText

                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.leftMargin: 10
                                anchors.rightMargin: 10
                                text: switcher.previewPath.length > 0 ? switcher.previewPath.split("/").pop() : ""
                                color: Colors.foreground
                                font.pixelSize: 11
                                elide: Text.ElideMiddle
                            }
                        }

                        Behavior on opacity {
                            NumberAnimation {
                                duration: 150
                            }
                        }
                    }

                    Text {
                        anchors.centerIn: parent
                        visible: switcher.previewPath.length === 0
                        text: "no selection"
                        color: Colors.muted
                        font.pixelSize: 12
                    }
                }
            }

            // ---- Footer hint bar ----
            RowLayout {
                Layout.fillWidth: true
                spacing: 16

                Text {
                    text: "↑↓←→ navigate"
                    color: Colors.muted
                    font.pixelSize: 11
                }

                Text {
                    text: "Enter apply"
                    color: Colors.muted
                    font.pixelSize: 11
                }

                Text {
                    text: "Esc close"
                    color: Colors.muted
                    font.pixelSize: 11
                }

                Item {
                    Layout.fillWidth: true
                }

                Text {
                    text: "⟳ to rescan"
                    color: Colors.muted
                    font.pixelSize: 11
                }
            }
        }
    }
}
