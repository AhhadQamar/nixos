// Music panel: a record deck. The record spins while music plays and the cover
// is its label; the ring around it is the progress (click or drag it to seek).
// Beside it: library and queue.
//   qs ipc call music toggle | open | close | playpause | next | prev | stop | rescan
//   qs ipc call music media <playpause|next|prev>   (media keys: falls back to playerctl)
// In the library: type to filter, Up / Down to move, Enter to play from there,
// Esc clears the search, then closes.
// State and mpv live in Music.qml; this file is only the interface.

import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland

PanelWindow {
    id: panel

    // 0 = library, 1 = queue
    property int tab: 0
    property string query: ""
    // Highlighted row in the library (keyboard)
    property int sel: 0
    readonly property int topGap: Math.round(Screen.height / 8)
    readonly property int deckW: 262
    readonly property int deckH: 424

    function toggle() {
        visible = !visible;
    }

    function open() {
        visible = true;
    }

    function close() {
        visible = false;
    }

    function refilter() {
        view.clear();
        const words = query.toLowerCase().split(/\s+/).filter(w => w !== "");
        for (const t of Music.library) {
            const hay = (t.artist + " " + t.album + " " + t.title).toLowerCase();
            if (words.every(w => hay.indexOf(w) >= 0))
                view.append({
                    path: t.path,
                    title: t.title,
                    artist: t.artist,
                    album: t.album,
                    track: t.track || 0,
                    group: (t.artist ? t.artist + " — " : "") + (t.album || "Unknown album")
                });
        }
        sel = 0;
    }

    // Play the shown list from row i on
    function playFrom(i) {
        const paths = [];
        for (let k = i; k < view.count; k++)
            paths.push(view.get(k).path);
        Music.playList(paths, 0);
    }

    // Play just the tracks of one group (an album)
    function playGroup(g) {
        const paths = [];
        for (let k = 0; k < view.count; k++)
            if (view.get(k).group === g)
                paths.push(view.get(k).path);
        Music.playList(paths, 0);
    }

    visible: false
    color: "transparent"
    margins.top: topGap
    implicitWidth: 800
    implicitHeight: card.implicitHeight
    exclusiveZone: 0
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
    onQueryChanged: refilter()
    onVisibleChanged: if (visible) {
        fadeIn.restart();
        if (!Music.scanned)
            Music.scan();
        Music.requestQueue();
        search.forceActiveFocus();
    }

    anchors {
        top: true
    }

    ListModel {
        id: view
    }

    Connections {
        target: Music

        function onLibraryChanged() {
            panel.refilter();
        }
    }

    Connections {
        target: Panels

        function onToggleMusic() {
            panel.toggle();
        }
    }

    IpcHandler {
        function toggle() {
            panel.toggle();
        }

        function open() {
            panel.open();
        }

        function close() {
            panel.close();
        }

        function playpause() {
            Music.playPause();
        }

        function next() {
            Music.next();
        }

        function prev() {
            Music.prev();
        }

        function stop() {
            Music.stop();
        }

        // Re-read ~/Music (the ytm download aliases call this)
        function rescan() {
            Music.scan();
        }

        // Media keys: drive this player when it has a track, otherwise leave
        // the key to whatever else is playing (VLC, a browser) via playerctl
        function media(action: string) {
            if (!Music.hasTrack) {
                Quickshell.execDetached(["playerctl", action === "playpause" ? "play-pause" : (action === "prev" ? "previous" : action)]);
                return;
            }
            if (action === "playpause")
                Music.playPause();
            else if (action === "next")
                Music.next();
            else if (action === "prev")
                Music.prev();
        }

        target: "music"
    }

    HyprlandFocusGrab {
        windows: [panel]
        active: panel.visible
        onCleared: panel.close()
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

    // ---- Small pieces ---------------------------------------------------
    component T: Text {
        color: Colors.foreground
        textFormat: Text.PlainText
        elide: Text.ElideRight

        font {
            family: Style.fontFamily
            pixelSize: 13
        }
    }

    // Round icon button. `glyph` is a Material Design Icons codepoint.
    component IconBtn: Rectangle {
        id: ib

        property int glyph: 0
        property bool active: false
        property int size: 34
        property bool filled: false

        signal clicked

        implicitWidth: size
        implicitHeight: size
        radius: size / 2
        antialiasing: true
        scale: ibTap.pressed ? 0.92 : 1
        color: filled ? Qt.alpha(Colors.accent, ibHov.hovered ? 0.34 : 0.24) : (ibHov.hovered ? Style.hoverFill : "transparent")

        Behavior on scale {
            NumberAnimation {
                duration: 90
            }
        }

        Text {
            anchors.centerIn: parent
            text: String.fromCodePoint(ib.glyph)
            color: ib.filled || ib.active ? Colors.accent : Colors.foreground
            opacity: ib.enabled ? 1 : 0.4

            font {
                family: Style.fontFamily
                pixelSize: ib.filled ? ib.size * 0.5 : ib.size * 0.55
            }
        }

        TapHandler {
            id: ibTap

            onTapped: ib.clicked()
        }
        HoverHandler {
            id: ibHov

            cursorShape: Qt.PointingHandCursor
        }
    }

    component Btn: Rectangle {
        id: btn

        property string text: ""
        property bool primary: false

        signal clicked

        implicitHeight: 30
        implicitWidth: bl.implicitWidth + 28
        radius: 15
        opacity: enabled ? 1 : 0.4
        color: primary ? Qt.alpha(Colors.accent, bh.hovered ? 0.32 : 0.22) : (bh.hovered ? Style.hoverFill : Qt.alpha(Colors.foreground, 0.06))

        T {
            id: bl

            anchors.centerIn: parent
            text: btn.text
            color: btn.primary ? Colors.accent : Colors.foreground
            font.pixelSize: 12
            font.bold: btn.primary
        }

        TapHandler {
            onTapped: btn.clicked()
        }
        HoverHandler {
            id: bh

            cursorShape: Qt.PointingHandCursor
        }
    }

    // A thin slider (volume): value 0..1, reports while dragging
    component Slide: Item {
        id: sl

        property real value: 0
        property real dragValue: 0

        signal moved(real v)

        implicitHeight: 18

        Rectangle {
            id: track

            anchors.verticalCenter: parent.verticalCenter
            width: parent.width
            height: 4
            radius: 2
            color: Qt.alpha(Colors.foreground, 0.12)

            Rectangle {
                width: parent.width * (ma.pressed ? sl.dragValue : sl.value)
                height: parent.height
                radius: 2
                color: Colors.accent
            }
            Rectangle {
                visible: ma.containsMouse || ma.pressed
                x: track.width * (ma.pressed ? sl.dragValue : sl.value) - 6
                y: -4
                width: 12
                height: 12
                radius: 6
                color: Colors.foreground
            }
        }

        MouseArea {
            id: ma

            function setFrom(mx) {
                sl.dragValue = Math.max(0, Math.min(1, mx / width));
                sl.moved(sl.dragValue);
            }

            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onPressed: mouse => setFrom(mouse.x)
            onPositionChanged: mouse => {
                if (pressed)
                    setFrom(mouse.x);
            }
        }
    }

    component Tab: Rectangle {
        id: tabItem

        required property int index
        property string text: ""
        property int count: 0

        implicitHeight: 28
        radius: 11
        color: panel.tab === index ? Qt.alpha(Colors.accent, 0.18) : (th.hovered ? Style.hoverFill : "transparent")

        Row {
            anchors.centerIn: parent
            spacing: 6

            T {
                anchors.verticalCenter: parent.verticalCenter
                text: tabItem.text
                color: panel.tab === tabItem.index ? Colors.accent : Colors.muted
                font.bold: panel.tab === tabItem.index
            }
            Rectangle {
                visible: tabItem.count > 0
                anchors.verticalCenter: parent.verticalCenter
                implicitWidth: Math.max(18, cnt.implicitWidth + 10)
                implicitHeight: 16
                radius: 8
                color: Qt.alpha(Colors.foreground, 0.1)

                T {
                    id: cnt

                    anchors.centerIn: parent
                    text: tabItem.count
                    color: Colors.muted
                    font.pixelSize: 10
                }
            }
        }

        TapHandler {
            onTapped: panel.tab = tabItem.index
        }
        HoverHandler {
            id: th

            cursorShape: Qt.PointingHandCursor
        }
    }

    // Three bars that dance while the music plays
    component Eq: Item {
        implicitWidth: 16
        implicitHeight: 14

        Row {
            anchors.bottom: parent.bottom
            spacing: 2

            Repeater {
                model: 3

                delegate: Rectangle {
                    id: bar

                    required property int index

                    width: 3
                    height: 4
                    radius: 1
                    color: Colors.accent

                    SequentialAnimation on height {
                        running: Music.playing && panel.visible
                        loops: Animation.Infinite

                        NumberAnimation {
                            to: 14
                            duration: 380 + bar.index * 120
                            easing.type: Easing.InOutSine
                        }
                        NumberAnimation {
                            to: 4
                            duration: 380 + bar.index * 120
                            easing.type: Easing.InOutSine
                        }
                    }
                }
            }
        }
    }

    // ---- Card -----------------------------------------------------------
    Rectangle {
        id: card

        anchors.fill: parent
        radius: Style.barRadius
        antialiasing: true
        color: Qt.alpha(Colors.background, 0.97)
        border.width: 1
        border.color: Style.outline
        implicitHeight: panel.deckH + 36

        Row {
            x: 18
            y: 18
            spacing: 22

            // ---- The deck ---------------------------------------------------
            Item {
                id: deck

                width: panel.deckW
                height: panel.deckH

                // Soft glow behind the record, brighter while playing
                Item {
                    id: glow

                    x: 6
                    y: 4
                    width: 250
                    height: 250
                    opacity: Music.playing ? 1 : 0.45

                    Behavior on opacity {
                        NumberAnimation {
                            duration: 600
                        }
                    }

                    Repeater {
                        model: 4

                        delegate: Rectangle {
                            required property int index

                            anchors.centerIn: parent
                            width: 250 + (3 - index) * 26
                            height: width
                            radius: width / 2
                            color: Qt.alpha(Colors.accent, 0.035 + index * 0.012)
                        }
                    }

                    // The record
                    Item {
                        id: vinyl

                        anchors.centerIn: parent
                        width: 222
                        height: 222

                        RotationAnimator {
                            target: vinyl
                            from: 0
                            to: 360
                            duration: 14000
                            loops: Animation.Infinite
                            running: panel.visible
                            paused: !Music.playing
                        }

                        Rectangle {
                            anchors.fill: parent
                            radius: width / 2
                            color: "#0b0b10"
                            antialiasing: true
                        }

                        // Grooves and a sheen that makes the spin visible
                        Canvas {
                            anchors.fill: parent
                            onPaint: {
                                const ctx = getContext("2d");
                                ctx.reset();
                                const c = width / 2;
                                ctx.lineWidth = 1;
                                for (let r = 56; r < c - 3; r += 3) {
                                    ctx.strokeStyle = (r / 3) % 2 === 0 ? "rgba(255,255,255,0.05)" : "rgba(255,255,255,0.02)";
                                    ctx.beginPath();
                                    ctx.arc(c, c, r, 0, Math.PI * 2);
                                    ctx.stroke();
                                }
                                const g = ctx.createConicalGradient(c, c, 0);
                                g.addColorStop(0.0, "rgba(255,255,255,0.10)");
                                g.addColorStop(0.12, "rgba(255,255,255,0)");
                                g.addColorStop(0.5, "rgba(255,255,255,0.07)");
                                g.addColorStop(0.62, "rgba(255,255,255,0)");
                                g.addColorStop(1.0, "rgba(255,255,255,0.10)");
                                ctx.fillStyle = g;
                                ctx.beginPath();
                                ctx.arc(c, c, c - 1, 0, Math.PI * 2);
                                ctx.fill();
                            }
                        }

                        // Label: the cover, round
                        Item {
                            id: lab

                            anchors.centerIn: parent
                            width: 104
                            height: 104

                            Rectangle {
                                anchors.fill: parent
                                radius: width / 2
                                antialiasing: true

                                gradient: Gradient {
                                    GradientStop {
                                        position: 0
                                        color: Qt.lighter(Colors.accent, 1.25)
                                    }
                                    GradientStop {
                                        position: 1
                                        color: Qt.darker(Colors.accent, 1.6)
                                    }
                                }
                            }

                            Image {
                                id: labImg

                                anchors.fill: parent
                                source: Music.cover
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                sourceSize.width: 208
                                sourceSize.height: 208
                                visible: false
                            }
                            Item {
                                id: labMask

                                anchors.fill: parent
                                visible: false
                                layer.enabled: true

                                Rectangle {
                                    anchors.fill: parent
                                    radius: width / 2
                                    color: "black"
                                }
                            }
                            MultiEffect {
                                anchors.fill: parent
                                source: labImg
                                maskEnabled: true
                                maskSource: labMask
                                visible: labImg.status === Image.Ready
                            }

                            Rectangle {
                                anchors.centerIn: parent
                                width: 12
                                height: 12
                                radius: 6
                                color: "#0b0b10"
                                border.width: 2
                                border.color: Qt.alpha("#000000", 0.4)
                            }
                        }
                    }

                    // Progress ring. Click or drag on it to seek.
                    Canvas {
                        id: ring

                        // Rounded so the ring is not redrawn for every tiny step
                        readonly property real shown: Math.round((seekArea.pressed ? seekArea.dragP : Music.progress) * 500) / 500

                        anchors.fill: parent
                        onShownChanged: requestPaint()
                        onPaint: {
                            const ctx = getContext("2d");
                            ctx.reset();
                            const c = width / 2;
                            const r = c - 4;
                            ctx.lineWidth = 3;
                            ctx.lineCap = "round";
                            ctx.strokeStyle = Qt.alpha(Colors.foreground, 0.12);
                            ctx.beginPath();
                            ctx.arc(c, c, r, 0, Math.PI * 2);
                            ctx.stroke();
                            if (shown > 0) {
                                ctx.strokeStyle = Colors.accent;
                                ctx.beginPath();
                                ctx.arc(c, c, r, -Math.PI / 2, -Math.PI / 2 + Math.PI * 2 * shown);
                                ctx.stroke();
                            }
                            // Knob at the end of the arc
                            const a = -Math.PI / 2 + Math.PI * 2 * shown;
                            ctx.fillStyle = Colors.accent;
                            ctx.beginPath();
                            ctx.arc(c + r * Math.cos(a), c + r * Math.sin(a), seekArea.pressed || seekArea.overRing ? 6 : 4, 0, Math.PI * 2);
                            ctx.fill();
                        }

                        Connections {
                            target: Colors

                            function onAccentChanged() {
                                ring.requestPaint();
                            }
                        }

                        MouseArea {
                            id: seekArea

                            property real dragP: 0
                            property bool overRing: false

                            function onRing(x, y) {
                                const c = width / 2;
                                const d = Math.hypot(x - c, y - c);
                                return d > c - 20 && d < c + 2;
                            }

                            function ratioAt(x, y) {
                                const c = width / 2;
                                let a = Math.atan2(y - c, x - c) + Math.PI / 2;
                                if (a < 0)
                                    a += Math.PI * 2;
                                return a / (Math.PI * 2);
                            }

                            anchors.fill: parent
                            hoverEnabled: true
                            enabled: Music.hasTrack
                            cursorShape: overRing ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onPositionChanged: mouse => {
                                overRing = onRing(mouse.x, mouse.y);
                                if (pressed)
                                    dragP = ratioAt(mouse.x, mouse.y);
                            }
                            onExited: overRing = false
                            onPressed: mouse => {
                                if (onRing(mouse.x, mouse.y))
                                    dragP = ratioAt(mouse.x, mouse.y);
                                else
                                    mouse.accepted = false;
                            }
                            onReleased: Music.seekTo(dragP * Music.duration)
                        }
                    }
                }

                T {
                    y: 270
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: Music.hasTrack ? Music.title : "Nothing playing"
                    font.pixelSize: 16
                    font.bold: true
                }
                T {
                    y: 294
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: Music.hasTrack ? [Music.artist, Music.album].filter(s => s !== "").join("  ·  ") : "Pick a track"
                    color: Colors.muted
                    font.pixelSize: 12
                }
                T {
                    y: 318
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: Music.fmt(Music.position) + "   —   " + Music.fmt(Music.duration)
                    color: Colors.muted
                    font.pixelSize: 11
                }

                Row {
                    y: 340
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 6

                    IconBtn {
                        anchors.verticalCenter: parent.verticalCenter
                        glyph: 0xF049F
                        active: Music.shuffle
                        onClicked: Music.toggleShuffle()
                    }
                    IconBtn {
                        anchors.verticalCenter: parent.verticalCenter
                        glyph: 0xF04AE
                        onClicked: Music.prev()
                    }
                    IconBtn {
                        anchors.verticalCenter: parent.verticalCenter
                        size: 48
                        filled: true
                        glyph: Music.playing ? 0xF03E4 : 0xF040A
                        onClicked: Music.hasTrack ? Music.playPause() : (view.count > 0 ? panel.playFrom(0) : undefined)
                    }
                    IconBtn {
                        anchors.verticalCenter: parent.verticalCenter
                        glyph: 0xF04AD
                        onClicked: Music.next()
                    }
                    IconBtn {
                        anchors.verticalCenter: parent.verticalCenter
                        glyph: Music.repeat === "one" ? 0xF0458 : 0xF0456
                        active: Music.repeat !== "off"
                        onClicked: Music.cycleRepeat()
                    }
                }

                Row {
                    y: 396
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 6

                    IconBtn {
                        anchors.verticalCenter: parent.verticalCenter
                        size: 26
                        glyph: Music.muted || Music.volume === 0 ? 0xF0581 : 0xF057E
                        onClicked: Music.toggleMute()
                    }
                    Slide {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 130
                        value: Music.volume / 130
                        onMoved: v => Music.setVolume(v * 130)
                    }
                }
            }

            // ---- Library and queue -----------------------------------------
            Column {
                id: side

                readonly property int w: card.width - 36 - panel.deckW - 22
                // What is left for the list once the other pieces are placed
                readonly property int listH: panel.deckH - 36 - 30 - (panel.tab === 0 ? 36 + 3 * 10 : 2 * 10)

                width: w
                spacing: 10

                Rectangle {
                    width: parent.width
                    height: 36
                    radius: 14
                    color: Qt.alpha(Colors.foreground, 0.05)

                    Row {
                        x: 4
                        y: 4
                        spacing: 2

                        Tab {
                            index: 0
                            width: (side.w - 8 - 2) / 2
                            text: "Library"
                            count: Music.library.length
                        }
                        Tab {
                            index: 1
                            width: (side.w - 8 - 2) / 2
                            text: "Queue"
                            count: Music.queue.length
                        }
                    }
                }

                // Search
                Rectangle {
                    width: parent.width
                    height: 36
                    radius: 12
                    visible: panel.tab === 0
                    color: Qt.alpha(Colors.foreground, 0.06)

                    Text {
                        x: 12
                        anchors.verticalCenter: parent.verticalCenter
                        text: String.fromCodePoint(0xF0349)
                        color: Colors.muted

                        font {
                            family: Style.fontFamily
                            pixelSize: 16
                        }
                    }

                    TextInput {
                        id: search

                        x: 38
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 38 - 40
                        color: Colors.foreground
                        selectionColor: Qt.alpha(Colors.accent, 0.4)
                        clip: true
                        onTextChanged: panel.query = text
                        Keys.onPressed: event => {
                            if (event.key === Qt.Key_Down) {
                                panel.sel = Math.min(view.count - 1, panel.sel + 1);
                                list.positionViewAtIndex(panel.sel, ListView.Contain);
                            } else if (event.key === Qt.Key_Up) {
                                panel.sel = Math.max(0, panel.sel - 1);
                                list.positionViewAtIndex(panel.sel, ListView.Contain);
                            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                if (view.count > 0)
                                    panel.playFrom(panel.sel);
                            } else if (event.key === Qt.Key_Escape) {
                                if (text !== "")
                                    text = "";
                                else
                                    panel.close();
                            } else {
                                return;
                            }
                            event.accepted = true;
                        }

                        font {
                            family: Style.fontFamily
                            pixelSize: 13
                        }

                        T {
                            anchors.fill: parent
                            visible: search.text === ""
                            text: "Search artist, album or track"
                            color: Colors.muted
                        }
                    }

                    IconBtn {
                        visible: search.text !== ""
                        anchors.right: parent.right
                        anchors.rightMargin: 4
                        anchors.verticalCenter: parent.verticalCenter
                        size: 28
                        glyph: 0xF0156
                        onClicked: search.text = ""
                    }
                }

                // List area (library or queue)
                Item {
                    width: parent.width
                    height: side.listH

                    ListView {
                        id: list

                        anchors.fill: parent
                        visible: panel.tab === 0
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        model: view
                        section.property: "group"
                        section.criteria: ViewSection.FullString
                        section.delegate: Item {
                            required property string section

                            width: ListView.view.width
                            height: 34

                            T {
                                x: 4
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - 44
                                text: parent.section.toUpperCase()
                                color: Colors.accent
                                font.pixelSize: 11
                                font.bold: true
                                font.letterSpacing: 0.5
                            }
                            IconBtn {
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                size: 26
                                glyph: 0xF040A
                                onClicked: panel.playGroup(parent.section)
                            }
                        }

                        delegate: Rectangle {
                            id: row

                            required property int index
                            required property string path
                            required property string title
                            required property string artist
                            required property int track

                            readonly property bool isCurrent: Music.hasTrack && Music.path === path

                            width: ListView.view.width
                            height: 38
                            radius: 10
                            color: isCurrent ? Qt.alpha(Colors.accent, 0.12) : (panel.sel === index ? Qt.alpha(Colors.foreground, 0.08) : (rh.hovered ? Qt.alpha(Colors.foreground, 0.05) : "transparent"))

                            HoverHandler {
                                id: rh
                            }

                            Eq {
                                visible: row.isCurrent
                                x: 12
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            T {
                                visible: !row.isCurrent
                                x: 8
                                anchors.verticalCenter: parent.verticalCenter
                                width: 24
                                horizontalAlignment: Text.AlignHCenter
                                text: row.track > 0 ? row.track : ""
                                color: Colors.muted
                                font.pixelSize: 12
                            }
                            T {
                                x: 38
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - 38 - 150
                                text: row.title
                                color: row.isCurrent ? Colors.accent : Colors.foreground
                                font.bold: row.isCurrent
                            }
                            T {
                                anchors.right: parent.right
                                anchors.rightMargin: rh.hovered ? 44 : 12
                                anchors.verticalCenter: parent.verticalCenter
                                width: 120
                                text: row.artist
                                color: Colors.muted
                                font.pixelSize: 12
                                horizontalAlignment: Text.AlignRight
                            }
                            IconBtn {
                                visible: rh.hovered
                                anchors.right: parent.right
                                anchors.rightMargin: 6
                                anchors.verticalCenter: parent.verticalCenter
                                size: 28
                                glyph: 0xF0415
                                onClicked: Music.enqueue(row.path)
                            }

                            TapHandler {
                                onTapped: {
                                    panel.sel = row.index;
                                    panel.playFrom(row.index);
                                }
                            }
                        }
                    }

                    ListView {
                        anchors.fill: parent
                        visible: panel.tab === 1
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        model: Music.queue

                        delegate: Rectangle {
                            id: qrow

                            required property int index
                            required property var modelData

                            readonly property var info: Music.lookup(modelData.filename)

                            width: ListView.view.width
                            height: 38
                            radius: 10
                            color: modelData.current ? Qt.alpha(Colors.accent, 0.12) : (qh.hovered ? Qt.alpha(Colors.foreground, 0.05) : "transparent")

                            HoverHandler {
                                id: qh
                            }

                            Eq {
                                visible: qrow.modelData.current
                                x: 12
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            T {
                                visible: !qrow.modelData.current
                                x: 8
                                anchors.verticalCenter: parent.verticalCenter
                                width: 24
                                horizontalAlignment: Text.AlignHCenter
                                text: qrow.index + 1
                                color: Colors.muted
                                font.pixelSize: 12
                            }
                            T {
                                x: 38
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - 38 - 150
                                text: qrow.info ? qrow.info.title : Music.baseName(qrow.modelData.filename)
                                color: qrow.modelData.current ? Colors.accent : Colors.foreground
                                font.bold: qrow.modelData.current
                            }
                            T {
                                anchors.right: parent.right
                                anchors.rightMargin: qh.hovered ? 44 : 12
                                anchors.verticalCenter: parent.verticalCenter
                                width: 120
                                text: qrow.info ? qrow.info.artist : ""
                                color: Colors.muted
                                font.pixelSize: 12
                                horizontalAlignment: Text.AlignRight
                            }
                            IconBtn {
                                visible: qh.hovered && !qrow.modelData.current
                                anchors.right: parent.right
                                anchors.rightMargin: 6
                                anchors.verticalCenter: parent.verticalCenter
                                size: 28
                                glyph: 0xF0156
                                onClicked: Music.removeFromQueue(qrow.index)
                            }

                            TapHandler {
                                onTapped: Music.jumpTo(qrow.index)
                            }
                        }
                    }

                    T {
                        anchors.centerIn: parent
                        visible: panel.tab === 0 ? view.count === 0 : Music.queue.length === 0
                        color: Colors.muted
                        text: panel.tab === 1 ? "The queue is empty" : (Music.scanning ? "Indexing ~/Music…" : (Music.library.length === 0 ? "No music found in ~/Music" : "Nothing matches"))
                    }
                }

                // Footer
                Item {
                    width: parent.width
                    height: 30

                    T {
                        anchors.verticalCenter: parent.verticalCenter
                        property int n: panel.tab === 0 ? view.count : Music.queue.length
                        text: n + (n === 1 ? " track" : " tracks")
                        color: Colors.muted
                        font.pixelSize: 12
                    }
                    Row {
                        anchors.right: parent.right
                        spacing: 8
                        visible: panel.tab === 0

                        Btn {
                            text: "Rescan"
                            enabled: !Music.scanning
                            onClicked: Music.scan()
                        }
                        Btn {
                            text: "Play all"
                            primary: true
                            enabled: view.count > 0
                            onClicked: panel.playFrom(0)
                        }
                    }
                    Btn {
                        visible: panel.tab === 1
                        anchors.right: parent.right
                        text: "Clear queue"
                        enabled: Music.queue.length > 1
                        onClicked: Music.clearQueue()
                    }
                }
            }
        }
    }
}
