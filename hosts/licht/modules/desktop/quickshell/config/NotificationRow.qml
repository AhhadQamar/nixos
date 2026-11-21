import QtQuick
import Quickshell.Widgets

// One notification on the right-edge ruler. Each is a glass card of its own,
// hung off a thin rail by a short hairline and a node. The card the cursor is on
// is the widest and opens: the whole text, the code in it, the app's own buttons,
// snooze, copy, dismiss. The cards around it narrow and fade with their distance
// from it, like the magnifier in the bar's ruler. A title (a day, or an app's
// group) is a small caption on the rail.
Item {
    id: row

    required property var modelData
    required property int index

    // Set by the panel
    property bool current: false
    property bool ticked: false
    property real nowMs: Date.now()
    // How many rows away from the cursor this one is
    property int dist: 1
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

    // The rail runs this far in from the right edge; cards stop short of it
    readonly property int railX: 13
    readonly property int gutter: 38
    readonly property int padX: 16
    readonly property int padY: 12
    readonly property var shrink: [0, 18, 34, 48, 60]
    readonly property var fade: [1, 1, 0.94, 0.84, 0.74]

    readonly property bool isHeader: modelData.header === true
    readonly property bool isDay: isHeader && modelData.day === true
    readonly property var e: modelData
    readonly property bool hovered: hover.hovered
    readonly property bool open: current && !isHeader
    readonly property bool fresh: !isHeader && e.time > NotificationServer.newSince
    readonly property bool critical: !isHeader && e.critical === true
    readonly property bool snoozed: !isHeader && e.snoozeUntil > 0
    readonly property color tint: critical ? Colors.critical : Colors.accent
    readonly property int step: Math.min(Math.max(dist, 0), 4)
    readonly property string iconSrc: isHeader ? "" : NotificationServer.appIconSource(e)
    readonly property bool showIcon: !isHeader && iconSrc !== "" && ico.status === Image.Ready
    readonly property string title: isHeader ? "" : (e.summary !== "" ? e.summary : e.appName)
    readonly property string body: {
        if (isHeader)
            return "";
        if (snoozed)
            return "Snoozed until " + Qt.formatTime(new Date(e.snoozeUntil), "HH:mm");
        return e.body;
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
    // Ticks stand on multiples of 8 down the whole list, so they run on across rows
    readonly property real phase: (8 - (y % 8)) % 8

    height: isHeader ? 28 : card.height + 8
    opacity: isHeader ? 1 : fade[step]

    Behavior on opacity {
        NumberAnimation {
            duration: Style.moveMs
            easing.type: Style.easeMove
        }
    }

    HoverHandler {
        id: hover
    }

    // ---- The rail: ticks beside the line the panel draws ---------------------
    Repeater {
        model: Math.ceil(row.height / 8) + 1

        delegate: Rectangle {
            required property int index

            x: row.width - row.railX - 9
            y: row.phase + index * 8
            width: index % 5 === 0 ? 8 : 4
            height: 1
            visible: y < row.height
            color: Qt.alpha(Colors.foreground, index % 5 === 0 ? 0.16 : 0.09)
        }
    }

    // ---- A title: a day, or an app's group -----------------------------------
    Item {
        visible: row.isHeader
        anchors.fill: parent

        Txt {
            anchors.right: parent.right
            anchors.rightMargin: row.gutter
            anchors.verticalCenter: parent.verticalCenter
            text: row.isHeader ? row.e.appName + (row.isDay ? "" : "  ·  " + row.e.count) : ""
            color: Colors.muted
            font.pixelSize: Style.fontXs
            font.letterSpacing: 0.8
            font.capitalization: Font.AllUppercase
        }

        IconButton {
            visible: row.hovered && !row.isDay
            anchors.left: parent.left
            anchors.leftMargin: 4
            anchors.verticalCenter: parent.verticalCenter
            size: 22
            glyph: Icons.close
            danger: true
            tip: "Clear this app"
            onClicked: row.groupClearClicked()
            onHoveredChanged: row.tipped(hovered ? tip : "")
        }
    }

    // ---- The node, and the hairline to the card --------------------------------
    Item {
        visible: !row.isHeader
        x: row.width - row.railX
        y: card.y + card.height / 2
        width: 0
        height: 0

        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            x: -(row.gutter - row.railX) + 2
            width: row.gutter - row.railX - 12
            height: 1
            color: Qt.alpha(row.open ? row.tint : Colors.foreground, row.open ? 0.4 : 0.12)
        }

        // The rail lights up round the open one
        Rectangle {
            visible: row.open
            anchors.horizontalCenter: parent.horizontalCenter
            y: -50
            width: 2
            height: 100
            gradient: Gradient {
                GradientStop {
                    position: 0
                    color: Qt.alpha(row.tint, 0)
                }
                GradientStop {
                    position: 0.5
                    color: Qt.alpha(row.tint, 0.7)
                }
                GradientStop {
                    position: 1
                    color: Qt.alpha(row.tint, 0)
                }
            }
        }

        // Soft light round a new or urgent one
        Rectangle {
            visible: (row.fresh || row.critical) && !row.open
            anchors.centerIn: parent
            width: 19
            height: 19
            radius: 9.5
            color: Qt.alpha(row.tint, 0.28)
        }

        // The open one: a dark gap, then a ring
        Rectangle {
            visible: row.open
            anchors.centerIn: parent
            width: 21
            height: 21
            radius: 10.5
            color: Style.card
            border.width: 1.5
            border.color: row.tint
        }

        Rectangle {
            anchors.centerIn: parent
            width: row.open ? 11 : (row.fresh || row.critical ? 9 : 7)
            height: width
            radius: width / 2

            Behavior on width {
                NumberAnimation {
                    duration: Style.baseMs
                    easing.type: Style.easeMove
                }
            }
            color: row.fresh || row.critical || row.open ? row.tint : Qt.alpha(Colors.foreground, 0.28)
        }

        // A ticked row
        Rectangle {
            visible: row.ticked
            x: -(row.gutter + 14)
            y: -3
            width: 6
            height: 6
            radius: 3
            color: Colors.accent
        }
    }

    // A glow under the open card
    Rectangle {
        visible: !row.isHeader
        x: card.x - 6
        y: card.y + 2
        width: card.width + 12
        height: card.height + 6
        radius: card.radius + 4
        color: Qt.alpha(row.tint, 0.16)
        opacity: row.open ? 1 : 0

        Behavior on opacity {
            NumberAnimation {
                duration: Style.baseMs
            }
        }
    }

    // ---- The card --------------------------------------------------------------
    Rectangle {
        id: card

        visible: !row.isHeader
        x: row.width - row.gutter - width
        y: 0
        width: row.width - row.gutter - row.shrink[row.open ? 0 : Math.max(row.step, 1)]
        height: info.y + info.implicitHeight + row.padY
        radius: Style.radiusXl + 2
        color: row.ticked ? Qt.tint(Style.card, Qt.alpha(Colors.accent, Style.selectedAlpha)) : ((row.fresh || row.critical) ? Qt.tint(Qt.alpha(Colors.background, 0.97), Qt.alpha(row.tint, 0.13)) : Qt.tint(Qt.alpha(Colors.background, 0.96), Qt.alpha(Colors.foreground, 0.05)))
        border.width: 1
        border.color: row.open ? Qt.alpha(row.tint, 0.7) : (row.hovered ? Qt.alpha(Colors.foreground, 0.2) : ((row.fresh || row.critical) ? Qt.alpha(row.tint, 0.4) : Qt.alpha(Colors.foreground, 0.14)))
        antialiasing: true

        Behavior on width {
            NumberAnimation {
                duration: Style.moveMs
                easing.type: Style.easeMove
            }
        }

        EdgeLight {}

        // A bar of colour down the side of a new or urgent card
        Rectangle {
            visible: row.fresh || row.critical
            x: 7
            anchors.verticalCenter: parent.verticalCenter
            width: 3
            height: Math.min(parent.height - 24, 30)
            radius: 1.5
            color: row.tint
        }

        // The open card is washed with its colour from the node side
        Rectangle {
            visible: row.open
            anchors.fill: parent
            anchors.margins: 1
            radius: parent.radius - 1
            gradient: Gradient {
                orientation: Gradient.Horizontal

                GradientStop {
                    position: 0.4
                    color: Qt.alpha(row.tint, 0)
                }
                GradientStop {
                    position: 1
                    color: Qt.alpha(row.tint, Style.tintAlpha * 1.3)
                }
            }
        }

        TapHandler {
            acceptedModifiers: Qt.NoModifier
            onTapped: if (!hoverTools.hovered)
                row.clicked(false)
        }

        TapHandler {
            acceptedModifiers: Qt.ControlModifier
            onTapped: if (!hoverTools.hovered)
                row.clicked(true)
        }

        // What it says
        Column {
            id: info

            x: row.padX
            y: row.padY
            width: parent.width - row.padX * 2
            spacing: 4

            // The app, its icon and the time
            Item {
                width: parent.width
                height: 18

                Row {
                    anchors.left: parent.left
                    anchors.right: hoverTools.left
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 7

                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 16
                        height: 16
                        radius: 5
                        color: (row.fresh || row.critical) ? Qt.alpha(row.tint, 0.2) : Qt.alpha(Colors.foreground, 0.1)

                        Image {
                            anchors.fill: parent
                            visible: row.showIcon
                            source: row.iconSrc
                            fillMode: Image.PreserveAspectFit
                            asynchronous: true
                            sourceSize.width: 32
                            sourceSize.height: 32
                        }

                        Txt {
                            anchors.centerIn: parent
                            visible: !row.showIcon
                            text: row.isHeader ? "" : NotificationServer.initial(row.e.appName)
                            color: Colors.muted
                            font.pixelSize: 9
                        }
                    }

                    Txt {
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.min(implicitWidth, parent.width - 24)
                        text: row.isHeader ? "" : row.e.appName
                        color: row.critical ? Colors.critical : (row.fresh ? Colors.accent : Qt.alpha(Colors.foreground, 0.65))
                        font.pixelSize: Style.fontSm
                        elide: Text.ElideRight
                    }
                }

                Txt {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    visible: !hoverTools.visible
                    text: row.clock
                    color: row.open || row.fresh || row.critical ? row.tint : Qt.alpha(Colors.foreground, 0.6)
                    font.pixelSize: Style.fontSm
                }

                // Under the pointer, on a card that is not open
                Row {
                    id: hoverTools

                    readonly property bool hovered: hoverToolsHover.hovered

                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    visible: row.hovered || row.open
                    spacing: 2

                    HoverHandler {
                        id: hoverToolsHover
                    }

                    IconButton {
                        size: 22
                        glyph: Icons.clock
                        on: row.snoozed
                        tip: row.snoozed ? "Bring back now" : "Snooze 10 minutes (z)"
                        onClicked: row.snoozeClicked()
                        onHoveredChanged: row.tipped(hovered ? tip : "")
                    }

                    IconButton {
                        size: 22
                        glyph: Icons.copy
                        tip: "Copy the text (Shift+C)"
                        onClicked: row.copyTextClicked()
                        onHoveredChanged: row.tipped(hovered ? tip : "")
                    }

                    IconButton {
                        size: 22
                        glyph: Icons.close
                        danger: true
                        tip: "Dismiss (x)"
                        onClicked: row.dismissClicked()
                        onHoveredChanged: row.tipped(hovered ? tip : "")
                    }
                }
            }

            Txt {
                width: parent.width
                text: row.title
                color: Colors.foreground
                font.pixelSize: Style.fontLg
                font.bold: row.fresh || row.critical
                wrapMode: Text.NoWrap
                elide: Text.ElideRight
            }

            Txt {
                width: parent.width
                visible: text !== ""
                text: row.body
                textFormat: Text.PlainText
                wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                maximumLineCount: 2
                elide: Text.ElideRight
                color: Qt.alpha(Colors.foreground, 0.7)
                font.pixelSize: Style.fontMd
                lineHeight: 1.25
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

        }
    }

    // Loaded off screen: the card shows whichever of them is ready
    Image {
        id: ico

        visible: false
        source: row.iconSrc
        asynchronous: true
    }
}
