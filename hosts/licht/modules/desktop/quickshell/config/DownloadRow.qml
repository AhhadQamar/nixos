import QtQuick

// One download in the list. The list hangs off a spine: a thin vertical line
// with a node per download (a pulsing dot while it downloads, a ring while it
// waits or is paused, red when it failed, a small grey dot when it is done).
// Beside the node: the name and what it is up to, a hairline of progress along
// the bottom, and on the right either its speed or, under the pointer or the
// cursor, its actions. The row under the cursor lifts into a glass card and
// swaps the hairline for a Ruler, with its lens and reading. Enter or a second
// click opens the details under it. The first row of a group also carries the
// group's caption (set by the panel).
Item {
    id: row

    required property var modelData
    required property int index

    // Set by the panel
    property bool current: false
    property bool picked: false
    property bool armed: false
    property bool expanded: false
    property real breath: 0
    // Set by the panel: the group caption this row opens (or ""), the row's place
    // on the spine
    property string caption: ""
    property int captionN: 0
    property bool first: false
    property bool last: false

    signal clicked(bool ctrl)
    signal pauseClicked
    signal retryClicked
    signal relinkClicked
    signal openClicked
    signal folderClicked
    signal copyClicked
    signal removeClicked
    signal tipped(string text)

    readonly property var r: modelData
    readonly property string st: r.state
    readonly property color tone: Downloads.toneOf(st)
    readonly property bool hovered: hover.hovered
    readonly property bool showActions: hovered || current
    // The row's top part is always topH; the row under the cursor grows below
    // it to make room for the ruler
    readonly property int topH: 54
    readonly property bool ruled: current && barOn
    readonly property int baseH: ruled ? 82 : topH
    readonly property int textX: 56
    readonly property int capH: caption !== "" ? 30 : 0
    readonly property real nodeY: capH + topH / 2
    readonly property string kind: st === "downloading" || st === "merging" || st === "checking" ? "live" : (st === "seeding" ? "seed" : (st === "paused" ? "paused" : (st === "failed" ? "failed" : (st === "done" || st === "cancelled" ? "done" : "wait"))))
    property real pulse: 0
    property Gradient liftGrad: Gradient {
        GradientStop {
            position: 0
            color: Qt.alpha(Colors.foreground, 0.075)
        }
        GradientStop {
            position: 1
            color: Qt.alpha(Colors.foreground, 0.025)
        }
    }
    readonly property bool pausable: st === "downloading" || st === "seeding" || st === "checking" || st === "queued" || st === "merging"
    readonly property bool multi: r.files.length > 1
    readonly property int fileN: multi ? Math.min(8, r.files.length) : 0
    readonly property int detailsH: 10 + r.info.length * 18 + (multi ? 8 + fileN * 16 + (r.files.length > fileN ? 16 : 0) : 0)
    readonly property bool barOn: st === "downloading" || st === "paused" || st === "queued" || st === "checking" || st === "merging"
    property real flash: 0

    // The two lines on the right while the actions are away
    readonly property string rightTop: {
        switch (st) {
        case "downloading":
            return r.metadata ? "" : Aria2.rate(r.speed);
        case "seeding":
            return "\u2191 " + Aria2.rate(r.upSpeed);
        case "done":
            return Aria2.bytes(r.total);
        case "failed":
            return "Failed";
        case "queued":
            return "#" + r.pos;
        case "paused":
            return Math.floor(r.fraction * 100) + "%";
        default:
            return "";
        }
    }
    readonly property string rightBottom: st === "downloading" && !r.metadata ? Math.floor(r.fraction * 100) + "%" : ""

    height: capH + baseH + (expanded ? detailsH : 0)

    Behavior on height {
        NumberAnimation {
            duration: Style.moveMs
            easing.type: Style.easeMove
        }
    }

    // A state change lights the row's edge once
    onStChanged: {
        if (st === "done" || st === "seeding" || st === "failed")
            flashAnim.restart();
    }

    NumberAnimation {
        id: flashAnim

        target: row
        property: "flash"
        from: 1
        to: 0
        duration: Style.sweepMs * 2
        easing.type: Style.easeExit
    }

    // ---- The spine: its segment, the group caption, the node --------------
    Rectangle {
        x: 24
        y: row.first ? row.nodeY : 0
        width: 1
        height: (row.last ? row.nodeY : row.height) - y
        color: Qt.alpha(Colors.foreground, 0.12)
    }

    Row {
        visible: row.caption !== ""
        x: row.textX
        y: row.capH - height - 6
        spacing: 8

        Txt {
            text: row.caption
            color: row.r.group === "failed" ? Colors.critical : (row.r.group === "active" ? Colors.foreground : Colors.muted)
            font.pixelSize: Style.fontSm
        }

        Txt {
            text: String(row.captionN)
            color: Colors.muted
            opacity: 0.7
            font.pixelSize: Style.fontSm
        }
    }

    // A ripple that leaves the node of whatever is downloading
    Rectangle {
        visible: row.kind === "live"
        x: 24.5 - width / 2
        y: row.nodeY - height / 2
        width: dot.width + 12 * row.pulse
        height: width
        radius: width / 2
        color: "transparent"
        border.width: 1
        border.color: Qt.alpha(Colors.accent, 0.55 * (1 - row.pulse))
    }

    SequentialAnimation on pulse {
        running: row.kind === "live" && row.visible
        loops: Animation.Infinite

        NumberAnimation {
            from: 0
            to: 1
            duration: Style.ambientMs * 2.2
            easing.type: Style.easeMove
        }
        PauseAnimation {
            duration: Style.ambientMs
        }
    }

    Rectangle {
        id: dot

        x: 24.5 - width / 2
        y: row.nodeY - height / 2
        width: row.kind === "done" ? 5 : (row.kind === "live" && row.current ? 11 : 9)
        height: width
        radius: width / 2
        color: row.kind === "live" ? Colors.accent : (row.kind === "failed" ? Colors.critical : (row.kind === "seed" ? Qt.alpha(Colors.foreground, 0.7) : (row.kind === "done" ? Qt.alpha(Colors.foreground, 0.35) : Style.card)))
        border.width: row.kind === "paused" || row.kind === "wait" ? 1.5 : 0
        border.color: row.kind === "paused" ? Qt.alpha(Colors.foreground, 0.6) : Qt.alpha(Colors.foreground, 0.28)
        opacity: row.st === "checking" || row.st === "merging" || row.r.metadata ? 0.4 + 0.6 * row.breath : 1

        Behavior on width {
            NumberAnimation {
                duration: Style.baseMs
                easing.type: Style.easeMove
            }
        }
    }

    // ---- Everything else sits below the caption ----------------------------
    Item {
        id: inner

        y: row.capH
        width: row.width
        height: row.baseH + (row.expanded ? row.detailsH : 0)

    HoverHandler {
        id: hover
    }

    TapHandler {
        acceptedModifiers: Qt.NoModifier
        onTapped: if (!actionsHover.hovered)
            row.clicked(false)
    }

    TapHandler {
        acceptedModifiers: Qt.ControlModifier
        onTapped: if (!actionsHover.hovered)
            row.clicked(true)
    }

    Rectangle {
        id: bg

        x: 42
        width: parent.width - 42
        height: parent.height
        radius: Style.radiusLg
        color: row.picked ? Qt.alpha(Colors.accent, Style.selectedAlpha) : (row.current ? "transparent" : (row.hovered ? Style.well : "transparent"))
        gradient: row.current && !row.picked ? row.liftGrad : null
        border.width: 1
        border.color: row.armed ? Colors.critical : (row.flash > 0.01 ? Qt.alpha(row.tone, 0.2 + 0.7 * row.flash) : (row.current ? Qt.alpha(Colors.foreground, 0.1) : "transparent"))

        EdgeLight {
            visible: row.current
            corner: Style.radiusLg
        }

        Behavior on color {
            ColorAnimation {
                duration: Style.fadeMs
            }
        }
    }

    // Name, what it is up to, the bar
    Item {
        id: texts

        x: row.textX
        y: 0
        width: row.width - row.textX - 176 - 6
        height: row.topH

        Txt {
            id: nameText

            anchors.left: parent.left
            anchors.right: parent.right
            y: 9
            text: row.r.name
            color: row.st === "cancelled" ? Colors.muted : Colors.foreground
            font.pixelSize: Style.fontBase
            font.bold: true
            elide: Text.ElideMiddle
        }

        Txt {
            anchors.left: parent.left
            anchors.right: parent.right
            y: 28
            text: Downloads.statusLine(row.r)
            color: row.st === "failed" ? Colors.critical : Colors.muted
            font.pixelSize: Style.fontSm
            elide: Text.ElideRight
        }
    }

    // Progress for every row but the one under the cursor: a hairline
    Item {
        visible: row.barOn && !row.ruled
        x: row.textX
        y: row.topH - 1
        width: row.width - row.textX - 16
        height: 1

        Rectangle {
            anchors.fill: parent
            color: Style.outline
        }

        Rectangle {
            width: parent.width * Math.min(1, row.r.fraction)
            height: parent.height
            color: Qt.alpha(Colors.foreground, row.st === "paused" || row.st === "queued" ? 0.28 : 0.6)

            Behavior on width {
                NumberAnimation {
                    duration: Style.baseMs
                    easing.type: Style.easeMove
                }
            }
        }
    }

    // The one under the cursor: the ruler
    Loader {
        active: row.ruled
        x: row.textX
        y: row.baseH - 6 - 20
        width: row.width - row.textX - 16
        height: 20

        sourceComponent: Ruler {
            value: row.r.fraction
            lens: 11
            reading: row.r.metadata ? "" : Math.floor(row.r.fraction * 100) + "%"
            lit: row.st === "paused" || row.st === "queued" ? Qt.alpha(Colors.foreground, 0.35) : Qt.alpha(Colors.accent, 0.85)
            markColor: row.st === "paused" || row.st === "queued" ? Qt.alpha(Colors.foreground, 0.5) : Colors.accent
        }
    }

    // Speed or size, when the actions are away
    Column {
        visible: !row.showActions
        anchors.right: parent.right
        anchors.rightMargin: 14
        y: (row.topH - height) / 2
        spacing: 2

        Txt {
            anchors.right: parent.right
            text: row.rightTop
            color: row.st === "failed" ? Colors.critical : (row.st === "downloading" ? Colors.foreground : Colors.muted)
            font.pixelSize: Style.fontMd
            font.bold: row.st === "downloading"
        }

        Txt {
            anchors.right: parent.right
            text: row.rightBottom
            color: Colors.muted
            font.pixelSize: Style.fontSm
        }
    }

    // The actions: under the pointer or the cursor
    Row {
        id: actions

        visible: row.showActions
        anchors.right: parent.right
        anchors.rightMargin: 10
        y: (row.topH - height) / 2
        spacing: 2

        HoverHandler {
            id: actionsHover
        }

        IconButton {
            visible: row.pausable || row.st === "paused"
            size: 26
            glyph: row.pausable ? Icons.pause : Icons.play
            tip: row.pausable ? "Pause" : "Resume"
            onClicked: row.pauseClicked()
            onHoveredChanged: row.tipped(hovered ? tip : "")
        }

        IconButton {
            visible: row.st === "failed"
            size: 26
            glyph: Icons.refresh
            tip: "Retry"
            onClicked: row.retryClicked()
            onHoveredChanged: row.tipped(hovered ? tip : "")
        }

        IconButton {
            visible: row.st === "failed" && !row.r.isBt && row.r.uris.length > 0 && String(row.r.gid).indexOf("yt:") !== 0
            size: 26
            glyph: Icons.link
            tip: "New link: keeps the partial file"
            onClicked: row.relinkClicked()
            onHoveredChanged: row.tipped(hovered ? tip : "")
        }

        IconButton {
            visible: row.r.complete && row.r.path !== ""
            size: 26
            glyph: Icons.openExternal
            tip: "Open"
            onClicked: row.openClicked()
            onHoveredChanged: row.tipped(hovered ? tip : "")
        }

        IconButton {
            visible: row.r.path !== ""
            size: 26
            glyph: Icons.folderOpen
            tip: "Show in " + Config.fileManager
            onClicked: row.folderClicked()
            onHoveredChanged: row.tipped(hovered ? tip : "")
        }

        IconButton {
            visible: row.r.link !== ""
            size: 26
            glyph: Icons.copy
            tip: row.r.isBt ? "Copy magnet link" : "Copy link"
            onClicked: row.copyClicked()
            onHoveredChanged: row.tipped(hovered ? tip : "")
        }

        IconButton {
            size: 26
            glyph: Icons.close
            danger: true
            tip: row.r.live ? "Cancel" : "Remove from list"
            onClicked: row.removeClicked()
            onHoveredChanged: row.tipped(hovered ? tip : "")
        }
    }

    // The details
    Loader {
        id: details

        active: row.expanded
        x: row.textX
        y: row.baseH
        width: row.width - row.textX - 14
        height: row.detailsH
        opacity: row.expanded ? 1 : 0

        Behavior on opacity {
            NumberAnimation {
                duration: Style.baseMs
            }
        }

        sourceComponent: Item {
            Column {
                id: infoCol

                width: parent.width
                spacing: 0

                Repeater {
                    model: row.r.info

                    delegate: Item {
                        required property var modelData

                        width: infoCol.width
                        height: 18

                        Txt {
                            width: 74
                            text: modelData[0]
                            color: Colors.muted
                            font.pixelSize: Style.fontSm
                        }

                        Txt {
                            x: 80
                            width: parent.width - 80
                            text: String(modelData[1])
                            color: Colors.foreground
                            opacity: 0.85
                            font.pixelSize: Style.fontSm
                            elide: Text.ElideMiddle
                        }
                    }
                }
            }

            Column {
                visible: row.multi
                y: infoCol.height + 8
                width: parent.width
                spacing: 0

                Repeater {
                    model: row.fileN

                    delegate: Item {
                        required property int index
                        readonly property var f: row.r.files[index]

                        width: parent.width
                        height: 16

                        Txt {
                            anchors.left: parent.left
                            anchors.right: sizeText.left
                            anchors.rightMargin: 8
                            text: f.name
                            color: f.len > 0 && f.done >= f.len ? Colors.success : Colors.foreground
                            opacity: 0.8
                            font.pixelSize: Style.fontSm
                            elide: Text.ElideMiddle
                        }

                        Txt {
                            id: sizeText

                            anchors.right: parent.right
                            text: Aria2.bytes(f.len)
                            color: Colors.muted
                            font.pixelSize: Style.fontSm
                        }
                    }
                }

                Txt {
                    visible: row.r.files.length > row.fileN
                    text: "and " + (row.r.files.length - row.fileN) + " more files"
                    color: Colors.muted
                    font.pixelSize: Style.fontSm
                    height: 16
                }
            }
        }
    }
    }
}
