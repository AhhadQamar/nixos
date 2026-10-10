// WallpaperSwitcher.qml
// Wallpaper picker in the clipboard / night light style: a compact card near
// the top of the screen with a search pill, and a filmstrip of thumbnails
// that always keeps the selected one in the middle and a little larger.
//   qs ipc call wallpaper toggle | open | close
// Keys: type to filter   ← → move   enter apply   ctrl+r random   esc close
// Mouse: click a thumbnail to select it, click the selected one to apply,
//        scroll wheel moves through the strip
//
// Applying runs `wal -i` (which regenerates your whole colour palette, so the
// bar, borders and everything else follow) and sets the image with awww.

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets // gives us ClippingRectangle (a Rectangle that clips its children to rounded corners)

PanelWindow {
    id: switcher

    // ---- Settings -------------------------------------------------------
    readonly property string wallpaperDir: Quickshell.env("HOME") + "/Pictures/Wallpapers"
    // Small pre-resized copies of every wallpaper live here, so opening the
    // panel doesn't decode 4K images just to draw tiny thumbnails.
    readonly property string thumbCacheDir: Quickshell.env("HOME") + "/.cache/quickshell/wall-thumbs"
    // Close the panel after applying a wallpaper?
    readonly property bool closeOnApply: false
    // Thumbnails are 320x200 on disk, so these stay at the same 8:5 ratio.
    // The selected one is drawn 20% larger (see `selectedScale` below).
    readonly property int tileWidth: 200
    readonly property int tileHeight: 125
    readonly property real selectedScale: 1.2

    // ---- State ----------------------------------------------------------
    // Each entry is { path, thumb }
    property var wallpapers: []
    property var filtered: []
    property string currentPath: ""   // the wallpaper that is applied right now
    property string applyingPath: ""  // the one being applied (for ~1s)
    property bool scanned: false
    property int selectedIndex: 0

    readonly property var selectedEntry: filtered.length > 0 ? filtered[selectedIndex] : null
    readonly property bool selectedIsCurrent: selectedEntry !== null && currentPath === selectedEntry.path
    readonly property bool selectedIsApplying: selectedEntry !== null && applyingPath === selectedEntry.path

    // ---- Actions --------------------------------------------------------
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

    // The folder is scanned once, not on every open. `force` is the refresh button.
    function scan(force) {
        if (scanned && !force)
            return;
        scanner.running = true;
    }

    function setWallpaper(entry) {
        if (!entry)
            return;
        applyingPath = entry.path;
        // The path is passed as an argument ($1), never pasted into the script,
        // so odd characters in a file name can't break the command.
        Quickshell.execDetached(["bash", "-c", "wal -i \"$1\" -n; ln -sf \"$1\" ~/Pictures/Wallpapers/.current_wallpaper; awww img \"$1\" --transition-type simple --transition-fps 30; hyprctl reload", "_", entry.path]);
        currentPath = entry.path; // move the "current" check straight away
        appliedTimer.restart();
        if (closeOnApply)
            close();
    }

    // dir: +1 = next, -1 = previous (stops at the ends)
    function step(dir) {
        if (filtered.length === 0)
            return;
        selectedIndex = Math.max(0, Math.min(filtered.length - 1, selectedIndex + dir));
    }

    function applyRandom() {
        if (filtered.length === 0)
            return;
        selectedIndex = Math.floor(Math.random() * filtered.length);
        setWallpaper(filtered[selectedIndex]);
    }

    function open() {
        visible = true;
        scan(false);
        searchField.text = "";
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
    // Same placement as the clipboard manager and night light: anchored to
    // the top edge only, exactly as big as the card.
    visible: false
    color: "transparent"
    margins.top: Screen.height / 5
    implicitWidth: 920
    implicitHeight: card.implicitHeight
    exclusiveZone: 0
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

    anchors {
        top: true
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

    Timer {
        id: appliedTimer

        interval: 1200
        onTriggered: switcher.applyingPath = ""
    }

    // ---- Scan + thumbnails ----------------------------------------------
    // Runs once. For each image it makes a small thumbnail (only if one isn't
    // cached yet) and prints "fullpath|thumbpath". The last line it prints is
    // pywal's own record of the current wallpaper, so the "current" check
    // survives restarts. $1 and $2 are the two folders, passed in below.
    Process {
        id: scanner

        command: ["bash", "-c", `
            mkdir -p "$2"
            shopt -s nullglob
            cd "$1" 2>/dev/null || exit 0
            for f in *.jpg *.jpeg *.png *.webp *.JPG *.JPEG *.PNG *.WEBP; do
                full="$1/$f"
                hash=$(printf '%s' "$full" | md5sum | cut -d' ' -f1)
                thumb="$2/$hash.png"
                if [ ! -f "$thumb" ]; then
                    convert "$full" -thumbnail 320x200^ -gravity center -extent 320x200 "$thumb" 2>/dev/null
                fi
                if [ ! -s "$thumb" ]; then thumb="$full"; fi
                echo "$full|$thumb"
            done | sort
            cat "$HOME/.cache/wal/wal" 2>/dev/null || true
        `, "bash", switcher.wallpaperDir, switcher.thumbCacheDir]

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
                        // the one line without "|" is pywal's current wallpaper
                        current = line.trim();
                    }
                }
                switcher.wallpapers = entries;
                switcher.currentPath = current;
                switcher.scanned = true;
                switcher.refilter();
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

    // ---- Small building blocks --------------------------------------------
    // Text in the shell font
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

            // ---- Search and refresh ---------------------------------------
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

                        Txt {
                            text: "\uf002"
                            color: searchField.activeFocus ? Colors.accent : Colors.muted
                            font.pixelSize: 14

                            Behavior on color {
                                ColorAnimation {
                                    duration: 200
                                }
                            }
                        }

                        TextInput {
                            id: searchField

                            Layout.fillWidth: true
                            color: Colors.foreground
                            selectionColor: Colors.accent
                            selectedTextColor: Colors.background
                            clip: true
                            onTextChanged: switcher.refilter()
                            // Left/right move through wallpapers instead of
                            // moving the text cursor
                            Keys.onLeftPressed: switcher.step(-1)
                            Keys.onRightPressed: switcher.step(1)
                            Keys.onEscapePressed: switcher.close()
                            Keys.onReturnPressed: switcher.setWallpaper(switcher.selectedEntry)
                            Keys.onEnterPressed: switcher.setWallpaper(switcher.selectedEntry)
                            Keys.onPressed: event => {
                                if (event.key === Qt.Key_Home) {
                                    switcher.selectedIndex = 0;
                                    event.accepted = true;
                                } else if (event.key === Qt.Key_End) {
                                    switcher.selectedIndex = Math.max(0, switcher.filtered.length - 1);
                                    event.accepted = true;
                                } else if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_R) {
                                    switcher.applyRandom();
                                    event.accepted = true;
                                }
                            }

                            font {
                                family: Style.fontFamily
                                pixelSize: 14
                            }

                            Txt {
                                visible: searchField.text.length === 0
                                anchors.verticalCenter: parent.verticalCenter
                                text: "Search wallpapers"
                                color: Colors.muted
                                font.pixelSize: 14
                            }
                        }

                        Txt {
                            visible: switcher.scanned
                            text: switcher.filtered.length === 0 ? "0" : (switcher.selectedIndex + 1) + " / " + switcher.filtered.length
                            color: Colors.muted
                            font.pixelSize: 12
                        }
                    }
                }

                // Rescan the folder (use after adding new wallpapers)
                Rectangle {
                    implicitWidth: 34
                    implicitHeight: 34
                    radius: width / 2
                    antialiasing: true
                    color: refreshArea.containsMouse ? Style.hoverFill : "transparent"
                    scale: refreshArea.pressed ? 0.94 : 1

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

                    Txt {
                        anchors.centerIn: parent
                        text: "\uf021"
                        color: refreshArea.containsMouse ? Colors.foreground : Colors.muted
                        font.pixelSize: 14
                    }

                    MouseArea {
                        id: refreshArea

                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: switcher.scan(true)
                    }
                }
            }

            // ---- Filmstrip --------------------------------------------------
            // StrictlyEnforceRange keeps the selected thumbnail in the middle
            // of the strip: moving the selection slides the whole strip
            // instead of moving a highlight along it.
            ListView {
                id: strip

                visible: switcher.filtered.length > 0
                Layout.fillWidth: true
                Layout.preferredHeight: Math.round(switcher.tileHeight * switcher.selectedScale) + 28
                orientation: ListView.Horizontal
                spacing: 18
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                cacheBuffer: 600
                model: switcher.filtered
                currentIndex: switcher.selectedIndex
                highlightRangeMode: ListView.StrictlyEnforceRange
                preferredHighlightBegin: (width - switcher.tileWidth) / 2
                preferredHighlightEnd: (width + switcher.tileWidth) / 2
                highlightMoveDuration: 220

                // The mouse wheel steps through wallpapers
                WheelHandler {
                    onWheel: event => switcher.step(event.angleDelta.y < 0 ? 1 : -1)
                }

                delegate: Item {
                    id: tile

                    required property int index
                    required property var modelData

                    readonly property bool current: index === switcher.selectedIndex
                    readonly property bool applied: modelData.path === switcher.currentPath

                    width: switcher.tileWidth
                    height: ListView.view.height
                    // The enlarged tile is drawn over its neighbours
                    z: current ? 1 : 0

                    ClippingRectangle {
                        id: pic

                        anchors.centerIn: parent
                        width: switcher.tileWidth
                        height: switcher.tileHeight
                        radius: 12
                        color: Colors.surface
                        // Thumbnails that aren't selected sit back, like the
                        // bar's inactive workspaces
                        opacity: tile.current || tileArea.containsMouse ? 1 : 0.6
                        scale: (tile.current ? switcher.selectedScale : 1) * (tileArea.pressed ? 0.97 : 1)

                        Behavior on opacity {
                            NumberAnimation {
                                duration: 150
                            }
                        }
                        Behavior on scale {
                            NumberAnimation {
                                duration: 160
                                easing.type: Easing.OutCubic
                            }
                        }

                        Image {
                            anchors.fill: parent
                            source: "file://" + tile.modelData.thumb
                            sourceSize.width: 320
                            sourceSize.height: 200
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            smooth: true
                        }

                        // Check on the wallpaper that is applied right now
                        Rectangle {
                            visible: tile.applied
                            anchors.top: parent.top
                            anchors.right: parent.right
                            anchors.margins: 6
                            width: 18
                            height: 18
                            radius: 9
                            antialiasing: true
                            color: Colors.accent

                            Txt {
                                anchors.centerIn: parent
                                text: "\uf00c"
                                color: Colors.background
                                font.pixelSize: 9
                            }
                        }

                        // Inside the picture, so its hit area grows with it
                        MouseArea {
                            id: tileArea

                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            // First click selects (the strip slides it into the
                            // middle), clicking the selected one applies it
                            onClicked: {
                                if (tile.current)
                                    switcher.setWallpaper(tile.modelData);
                                else
                                    switcher.selectedIndex = tile.index;
                            }
                        }
                    }

                    // The bar's 2px accent underline, under the selected tile
                    Rectangle {
                        visible: tile.current
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 2
                        width: 28
                        height: 2
                        radius: 1
                        color: Colors.accent
                    }
                }
            }

            // Message when there is nothing to show
            Txt {
                visible: switcher.selectedEntry === null
                Layout.fillWidth: true
                Layout.topMargin: 14
                Layout.bottomMargin: 14
                horizontalAlignment: Text.AlignHCenter
                color: Colors.muted
                text: !switcher.scanned ? "Scanning and making thumbnails…" : (switcher.wallpapers.length === 0 ? "No wallpapers found in\n" + switcher.wallpaperDir : "No matches")
                font.pixelSize: 13
            }

            // ---- File name and state ------------------------------------------
            RowLayout {
                visible: switcher.selectedEntry !== null
                Layout.fillWidth: true
                spacing: 8

                Item {
                    Layout.fillWidth: true
                }

                Txt {
                    Layout.maximumWidth: 520
                    text: switcher.selectedEntry ? switcher.selectedEntry.path.split("/").pop() : ""
                    elide: Text.ElideMiddle
                    color: Colors.foreground
                    font.pixelSize: 13
                    font.weight: Font.Medium
                }

                Rectangle {
                    visible: switcher.selectedIsApplying || switcher.selectedIsCurrent
                    width: 3
                    height: 3
                    radius: 1.5
                    color: Colors.muted
                }

                Txt {
                    visible: switcher.selectedIsApplying || switcher.selectedIsCurrent
                    text: switcher.selectedIsApplying ? "Applying…" : "Current"
                    color: Colors.accent
                    font.pixelSize: 13
                }

                Item {
                    Layout.fillWidth: true
                }
            }

            // ---- Shortcuts --------------------------------------------------
            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 6
                spacing: 6

                KeyCap {
                    label: "← →"
                }

                Txt {
                    text: "move"
                    color: Colors.muted
                    rightPadding: 8
                    font.pixelSize: 11
                }

                KeyCap {
                    label: "enter"
                }

                Txt {
                    text: "apply"
                    color: Colors.muted
                    rightPadding: 8
                    font.pixelSize: 11
                }

                KeyCap {
                    label: "ctrl+r"
                }

                Txt {
                    text: "random"
                    color: Colors.muted
                    rightPadding: 8
                    font.pixelSize: 11
                }

                KeyCap {
                    label: "esc"
                }

                Txt {
                    text: "close"
                    color: Colors.muted
                    font.pixelSize: 11
                }

                Item {
                    Layout.fillWidth: true
                }
            }
        }
    }
}
