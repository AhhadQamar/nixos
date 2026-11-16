import QtQuick
import QtQuick.Shapes

// One download in the list: a round disc (a ring that fills as it goes, a glyph
// for what it is doing), the name and what it is up to, a thin bar, and on the
// right either its speed or, under the pointer or the cursor, its actions.
// Enter or a second click opens the details under it.
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

    signal clicked(bool ctrl)
    signal pauseClicked
    signal retryClicked
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
    readonly property int baseH: 56
    readonly property bool pausable: st === "downloading" || st === "seeding" || st === "checking" || st === "queued" || st === "merging"
    readonly property bool multi: r.files.length > 1
    readonly property int fileN: multi ? Math.min(8, r.files.length) : 0
    readonly property int detailsH: 10 + r.info.length * 18 + (multi ? 8 + fileN * 16 + (r.files.length > fileN ? 16 : 0) : 0)
    readonly property bool barOn: st === "downloading" || st === "paused" || st === "queued" || st === "checking" || st === "merging"
    property real sweep: Downloads.ringOf(r)
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

    height: baseH + (expanded ? detailsH : 0)

    Behavior on height {
        NumberAnimation {
            duration: Style.moveMs
            easing.type: Style.easeMove
        }
    }

    Behavior on sweep {
        NumberAnimation {
            duration: Style.sweepMs
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

        anchors.fill: parent
        radius: Style.radiusLg
        color: row.picked ? Qt.alpha(Colors.accent, Style.selectedAlpha) : (row.current ? Qt.alpha(Colors.accent, Style.tintAlpha) : (row.hovered ? Style.well : "transparent"))
        border.width: 1
        border.color: row.armed ? Colors.critical : (row.flash > 0.01 ? Qt.alpha(row.tone, 0.2 + 0.7 * row.flash) : (row.current ? Qt.alpha(Colors.accent, 0.45) : "transparent"))

        Behavior on color {
            ColorAnimation {
                duration: Style.fadeMs
            }
        }
    }

    // The cursor's accent mark
    Rectangle {
        visible: row.current
        x: 0
        y: (row.baseH - height) / 2
        width: 2
        height: 22
        radius: 1
        color: Colors.accent
    }

    // The disc: a ring that fills with progress, a glyph for the state
    Item {
        id: disc

        x: 14
        y: (row.baseH - height) / 2
        width: 34
        height: 34

        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: Style.well
            border.width: 1
            border.color: Style.outline
        }

        Shape {
            anchors.fill: parent
            layer.enabled: true
            layer.samples: 4
            visible: row.sweep > 0.002

            ShapePath {
                strokeColor: Qt.alpha(row.tone, 0.9)
                strokeWidth: 2
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap

                PathAngleArc {
                    centerX: disc.width / 2
                    centerY: disc.height / 2
                    radiusX: disc.width / 2 - 2
                    radiusY: disc.height / 2 - 2
                    startAngle: -90
                    sweepAngle: Math.min(359.9, 360 * row.sweep)
                }
            }
        }

        Txt {
            anchors.centerIn: parent
            text: Downloads.glyphOf(row.st)
            color: row.tone
            font.pixelSize: 14
            opacity: row.st === "checking" || row.st === "merging" || row.r.metadata ? 0.5 + 0.5 * row.breath : 1
        }
    }

    // Name, what it is up to, the bar
    Item {
        id: texts

        x: 62
        y: 0
        width: row.width - 62 - 176 - 6
        height: row.baseH

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

        Rectangle {
            visible: row.barOn
            anchors.left: parent.left
            anchors.right: parent.right
            y: 46
            height: 2
            radius: 1
            color: Style.well

            Rectangle {
                width: parent.width * Math.min(1, row.r.fraction)
                height: parent.height
                radius: 1
                color: Qt.alpha(row.tone, row.st === "paused" || row.st === "queued" ? 0.5 : 0.9)

                Behavior on width {
                    NumberAnimation {
                        duration: Style.baseMs
                        easing.type: Style.easeMove
                    }
                }
            }
        }
    }

    // Speed or size, when the actions are away
    Column {
        visible: !row.showActions
        anchors.right: parent.right
        anchors.rightMargin: 14
        y: (row.baseH - height) / 2
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
        y: (row.baseH - height) / 2
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
        x: 62
        y: row.baseH
        width: row.width - 62 - 14
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
