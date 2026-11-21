import QtQuick
import Quickshell.Widgets

// One line of the notification list: a title (a day, or an app's group) or one
// notification. A notification is a squircle tile (its picture, its app's icon
// or the app's first letter), the app and the time, what it says in bold if it
// is new, and one line of the text. The row the cursor is on opens: the whole
// text, the code in it to copy, the app's own buttons, and snooze, copy, open
// link and dismiss. Urgent ones are tinted in the alert colour, new ones in the
// accent. Under the pointer a row gets a dismiss button.
Item {
    id: row

    required property var modelData
    required property int index

    // Set by the panel
    property bool current: false
    property bool ticked: false
    property real nowMs: Date.now()
    // The app's own buttons, for the open row
    property var actions: []

    signal clicked(bool ctrl)
    signal actionClicked(string id)
    signal copyClicked
    signal copyTextClicked
    signal linkClicked
    signal snoozeClicked
    signal dismissClicked
    signal groupClearClicked
    signal tipped(string text)

    readonly property bool isHeader: modelData.header === true
    readonly property bool isDay: isHeader && modelData.day === true
    readonly property var e: modelData
    readonly property bool hovered: hover.hovered
    readonly property bool open: current && !isHeader
    readonly property bool fresh: !isHeader && e.time > NotificationServer.newSince
    readonly property bool critical: !isHeader && e.critical === true
    readonly property bool snoozed: !isHeader && e.snoozeUntil > 0
    readonly property color tint: critical ? Colors.critical : Colors.accent
    readonly property string iconSrc: isHeader ? "" : NotificationServer.appIconSource(e)
    readonly property bool showPhoto: !isHeader && e.image !== "" && pic.status === Image.Ready
    readonly property bool showIcon: !isHeader && !showPhoto && iconSrc !== "" && ico.status === Image.Ready
    readonly property string title: isHeader ? "" : (e.summary !== "" ? e.summary : e.appName)
    readonly property string body: {
        if (isHeader)
            return "";
        if (open)
            return e.body;
        if (snoozed)
            return "Snoozed until " + Qt.formatTime(new Date(e.snoozeUntil), "HH:mm");
        return NotificationServer.firstLine(e);
    }
    readonly property string code: isHeader ? "" : NotificationServer.codeOf(e)
    readonly property string link: isHeader ? "" : NotificationServer.linkOf(e)
    readonly property string clock: isHeader ? "" : Qt.formatTime(new Date(e.time), "HH:mm")
    readonly property string note: {
        if (isHeader)
            return "";
        const parts = [];
        if (snoozed)
            parts.push("snoozed until " + Qt.formatTime(new Date(e.snoozeUntil), "HH:mm"));
        if (e.restored)
            parts.push("from before the restart");
        return parts.join("  ·  ");
    }

    height: isHeader ? 30 : card.implicitHeight

    HoverHandler {
        id: hover
    }

    TapHandler {
        enabled: !row.isHeader
        acceptedModifiers: Qt.NoModifier
        onTapped: if (!hoverTools.hovered && !openTools.hovered)
            row.clicked(false)
    }

    TapHandler {
        enabled: !row.isHeader
        acceptedModifiers: Qt.ControlModifier
        onTapped: if (!hoverTools.hovered && !openTools.hovered)
            row.clicked(true)
    }

    // ---- A title: a day, or an app's group -----------------------------------
    Item {
        visible: row.isHeader
        anchors.fill: parent

        Txt {
            x: 10
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 4
            text: row.isHeader ? row.e.appName : ""
            color: Colors.muted
            font.pixelSize: Style.fontXs
            font.letterSpacing: 0.8
            font.capitalization: Font.AllUppercase
        }

        Txt {
            anchors.right: parent.right
            anchors.rightMargin: 12
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 4
            visible: !row.isDay && !row.hovered
            text: row.isHeader && !row.isDay ? String(row.e.count) : ""
            color: Colors.muted
            font.pixelSize: Style.fontXs
        }

        IconButton {
            visible: row.hovered && !row.isDay
            anchors.right: parent.right
            anchors.rightMargin: 6
            anchors.verticalCenter: parent.verticalCenter
            size: 22
            glyph: Icons.close
            danger: true
            tip: "Clear this app"
            onClicked: row.groupClearClicked()
            onHoveredChanged: row.tipped(hovered ? tip : "")
        }
    }

    // ---- A notification -----------------------------------------------------
    Rectangle {
        id: card

        visible: !row.isHeader
        width: parent.width
        implicitHeight: info.y + info.implicitHeight + 10
        radius: Style.radiusLg
        antialiasing: true
        color: row.ticked ? Qt.alpha(Colors.accent, Style.selectedAlpha) : (row.open ? Qt.alpha(row.tint, Style.tintAlpha) : (row.hovered ? Style.well : "transparent"))
        border.width: 1
        border.color: row.open ? Qt.alpha(row.tint, 0.4) : "transparent"

        Behavior on color {
            ColorAnimation {
                duration: Style.fadeMs
            }
        }

        // The cursor's mark
        Rectangle {
            visible: row.open
            x: 0
            y: 14
            width: 2
            height: 20
            radius: 1
            color: row.tint
        }

        // A ticked row
        Rectangle {
            visible: row.ticked
            x: 4
            y: 46
            width: 6
            height: 6
            radius: 3
            color: Colors.accent
        }

        // The tile
        Item {
            id: tile

            x: 12
            y: 10
            width: 34
            height: 34

            // Loaded off screen: the tile shows whichever of them is ready
            Image {
                id: pic

                visible: false
                source: row.isHeader ? "" : row.e.image
                asynchronous: true
                cache: false
            }

            Image {
                id: ico

                visible: false
                source: row.iconSrc
                asynchronous: true
            }

            Rectangle {
                anchors.fill: parent
                radius: Style.radiusMd
                antialiasing: true
                color: row.critical ? Qt.alpha(Colors.critical, 0.16) : (row.fresh ? Qt.alpha(Colors.accent, 0.18) : Style.well)
                border.width: 1
                border.color: row.critical ? Qt.alpha(Colors.critical, 0.45) : (row.fresh ? Qt.alpha(Colors.accent, 0.4) : Style.outline)
            }

            ClippingRectangle {
                anchors.fill: parent
                anchors.margins: 2
                radius: Style.radiusMd - 2
                color: "transparent"
                visible: row.showPhoto

                Image {
                    anchors.fill: parent
                    source: row.isHeader ? "" : row.e.image
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    cache: false
                    sourceSize.width: 80
                    sourceSize.height: 80
                }
            }

            Image {
                anchors.centerIn: parent
                width: 20
                height: 20
                visible: row.showIcon
                source: row.iconSrc
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                sourceSize.width: 40
                sourceSize.height: 40
            }

            Txt {
                anchors.centerIn: parent
                visible: !row.showPhoto && !row.showIcon
                text: row.isHeader ? "" : NotificationServer.initial(row.e.appName)
                color: row.critical ? Colors.critical : (row.fresh ? Colors.accent : Colors.foreground)
                opacity: row.critical || row.fresh ? 1 : 0.75
                font.pixelSize: Style.fontXl
                font.weight: Font.Light
            }
        }

        // What it says
        Column {
            id: info

            x: 58
            y: 10
            width: parent.width - 58 - 12
            spacing: 3

            // The app, and when
            Item {
                width: parent.width
                height: 14

                Txt {
                    anchors.left: parent.left
                    anchors.right: stamp.left
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    text: row.isHeader ? "" : row.e.appName
                    color: row.critical ? Colors.critical : (row.fresh ? Colors.accent : Colors.muted)
                    font.pixelSize: Style.fontXs
                    elide: Text.ElideRight
                }

                Txt {
                    id: stamp

                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    visible: !(row.hovered && !row.open)
                    text: row.clock
                    color: row.open ? row.tint : Colors.muted
                    font.pixelSize: Style.fontXs
                }

                // Under the pointer, on a row that is not open
                Row {
                    id: hoverTools

                    readonly property bool hovered: hoverToolsHover.hovered

                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    visible: row.hovered && !row.open
                    spacing: 2

                    HoverHandler {
                        id: hoverToolsHover
                    }

                    IconButton {
                        size: 22
                        glyph: Icons.clock
                        on: row.snoozed
                        tip: row.snoozed ? "Bring back now" : "Snooze 10 minutes"
                        onClicked: row.snoozeClicked()
                        onHoveredChanged: row.tipped(hovered ? tip : "")
                    }

                    IconButton {
                        size: 22
                        glyph: Icons.close
                        danger: true
                        tip: "Dismiss"
                        onClicked: row.dismissClicked()
                        onHoveredChanged: row.tipped(hovered ? tip : "")
                    }
                }
            }

            Txt {
                width: parent.width
                text: row.title
                color: row.fresh || row.critical ? Colors.foreground : Qt.alpha(Colors.foreground, 0.8)
                font.pixelSize: Style.fontBase
                font.bold: row.fresh || row.critical
                elide: Text.ElideRight
            }

            Txt {
                width: parent.width
                visible: text !== ""
                text: row.body
                textFormat: Text.PlainText
                wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                maximumLineCount: row.open ? 12 : 1
                elide: Text.ElideRight
                color: Colors.muted
                font.pixelSize: Style.fontSm
                lineHeight: 1.2
            }

            Txt {
                width: parent.width
                visible: row.open && row.note !== ""
                text: row.note
                color: row.snoozed ? Colors.accent : Colors.muted
                font.pixelSize: Style.fontXs
                elide: Text.ElideRight
            }

            // The code in it, ready to copy
            Item {
                visible: row.code !== ""
                width: parent.width
                height: visible ? chip.height + 6 : 0

                Rectangle {
                    id: chip

                    y: 6
                    width: codeRow.width + 12
                    height: 32
                    radius: Style.radiusMd
                    color: Style.well

                    Row {
                        id: codeRow

                        x: 12
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 10

                        Txt {
                            anchors.verticalCenter: parent.verticalCenter
                            text: row.code
                            color: Colors.foreground
                            font.pixelSize: Style.fontXl
                            font.weight: Font.Light
                            font.letterSpacing: 2.2
                        }

                        TextButton {
                            anchors.verticalCenter: parent.verticalCenter
                            compact: true
                            raised: true
                            primary: true
                            text: "copy"
                            onClicked: row.copyClicked()
                        }
                    }
                }
            }

            // What can be done with it
            Item {
                visible: row.open
                width: parent.width
                height: visible ? Math.max(pills.height, openTools.height) + 8 : 0

                Flow {
                    id: pills

                    y: 8
                    width: parent.width - openTools.width - 8
                    spacing: 6

                    Repeater {
                        model: row.open ? row.actions : []

                        delegate: TextButton {
                            required property var modelData
                            required property int index

                            compact: true
                            raised: true
                            primary: index === 0
                            text: modelData.text
                            onClicked: row.actionClicked(modelData.id)
                        }
                    }
                }

                Row {
                    id: openTools

                    readonly property bool hovered: openToolsHover.hovered

                    anchors.right: parent.right
                    y: 8
                    spacing: 0

                    HoverHandler {
                        id: openToolsHover
                    }

                    IconButton {
                        glyph: Icons.clock
                        on: row.snoozed
                        tip: row.snoozed ? "Bring back now" : "Snooze 10 minutes (z)  ·  an hour (Shift+Z)  ·  until 8:00 (m)"
                        onClicked: row.snoozeClicked()
                        onHoveredChanged: row.tipped(hovered ? tip : "")
                    }

                    IconButton {
                        glyph: Icons.copy
                        tip: "Copy the text (Shift+C)"
                        onClicked: row.copyTextClicked()
                        onHoveredChanged: row.tipped(hovered ? tip : "")
                    }

                    IconButton {
                        visible: row.link !== ""
                        glyph: Icons.link
                        tip: "Open the link (o)"
                        onClicked: row.linkClicked()
                        onHoveredChanged: row.tipped(hovered ? tip : "")
                    }

                    IconButton {
                        glyph: Icons.close
                        danger: true
                        tip: "Dismiss (x)"
                        onClicked: row.dismissClicked()
                        onHoveredChanged: row.tipped(hovered ? tip : "")
                    }
                }
            }
        }
    }
}
