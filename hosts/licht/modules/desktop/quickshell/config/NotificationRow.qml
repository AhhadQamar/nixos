import QtQuick
import Quickshell.Widgets

// One line of the notification list: either the title of an app's group or one
// notification. A notification is a round disc (its picture, its app's icon or
// the app's first letter), what it says, and how long ago. Urgent ones are
// ringed in the alert colour and new ones carry the accent dot. Under the
// pointer: copy, snooze, dismiss.
Item {
    id: row

    required property var modelData
    required property int index

    // Set by the panel
    property bool current: false
    property bool ticked: false
    property real nowMs: Date.now()

    signal clicked(bool ctrl)
    signal copyClicked
    signal snoozeClicked
    signal dismissClicked
    signal groupClearClicked
    signal tipped(string text)

    readonly property bool isHeader: modelData.header === true
    readonly property var e: modelData
    readonly property bool hovered: hover.hovered
    readonly property bool fresh: !isHeader && e.time > NotificationServer.newSince
    readonly property bool snoozed: !isHeader && e.snoozeUntil > 0
    readonly property string iconSrc: isHeader ? "" : NotificationServer.appIconSource(e)
    readonly property bool showPhoto: !isHeader && e.image !== "" && pic.status === Image.Ready
    readonly property bool showIcon: !isHeader && !showPhoto && iconSrc !== "" && ico.status === Image.Ready
    readonly property string line1: isHeader ? "" : (e.summary !== "" ? e.summary : e.appName)
    readonly property string line2: {
        if (isHeader)
            return "";
        if (snoozed)
            return "Snoozed until " + Qt.formatTime(new Date(e.snoozeUntil), "HH:mm");
        const b = NotificationServer.firstLine(e);
        return b !== "" ? b : e.appName;
    }

    height: isHeader ? 30 : 56

    HoverHandler {
        id: hover
    }

    TapHandler {
        enabled: !row.isHeader
        acceptedModifiers: Qt.NoModifier
        onTapped: if (!actionsHover.hovered)
            row.clicked(false)
    }

    TapHandler {
        enabled: !row.isHeader
        acceptedModifiers: Qt.ControlModifier
        onTapped: if (!actionsHover.hovered)
            row.clicked(true)
    }

    // ---- A group's title ----------------------------------------------------
    Item {
        visible: row.isHeader
        anchors.fill: parent

        Txt {
            x: 14
            anchors.verticalCenter: parent.verticalCenter
            text: row.isHeader ? row.e.appName : ""
            color: Colors.muted
            font.pixelSize: Style.fontSm
            font.bold: true
            font.capitalization: Font.AllUppercase
            font.letterSpacing: 0.8
        }

        Txt {
            anchors.right: parent.right
            anchors.rightMargin: 14
            anchors.verticalCenter: parent.verticalCenter
            visible: !row.hovered
            text: row.isHeader ? String(row.e.count) : ""
            color: Colors.muted
            font.pixelSize: Style.fontSm
        }

        IconButton {
            visible: row.hovered
            anchors.right: parent.right
            anchors.rightMargin: 8
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
        visible: !row.isHeader
        anchors.fill: parent
        radius: Style.radiusLg
        color: row.ticked ? Qt.alpha(Colors.accent, Style.selectedAlpha) : (row.current ? Qt.alpha(row.e.critical ? Colors.critical : Colors.accent, Style.tintAlpha) : (row.hovered ? Style.well : "transparent"))
        border.width: 1
        border.color: row.current ? Qt.alpha(row.e.critical ? Colors.critical : Colors.accent, 0.45) : "transparent"

        Behavior on color {
            ColorAnimation {
                duration: Style.fadeMs
            }
        }
    }

    // The cursor's mark
    Rectangle {
        visible: row.current && !row.isHeader
        x: 0
        y: (row.height - height) / 2
        width: 2
        height: 22
        radius: 1
        color: row.isHeader || !row.e.critical ? Colors.accent : Colors.critical
    }

    // A ticked row
    Rectangle {
        visible: row.ticked
        x: 4
        y: (row.height - height) / 2
        width: 6
        height: 6
        radius: 3
        color: Colors.accent
    }

    // The disc
    Item {
        id: disc

        visible: !row.isHeader
        x: 14
        y: (row.height - height) / 2
        width: 34
        height: 34

        // Loaded off screen: the disc shows whichever of them is ready
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
            radius: width / 2
            color: Style.well
            border.width: row.isHeader ? 0 : (row.e.critical ? 2 : 1)
            border.color: row.isHeader ? "transparent" : (row.e.critical ? Colors.critical : Style.outline)
        }

        ClippingRectangle {
            anchors.fill: parent
            anchors.margins: 2
            radius: width / 2
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
            color: !row.isHeader && row.e.critical ? Colors.critical : Colors.foreground
            font.pixelSize: 14
            font.bold: true
        }

        // Arrived since you last looked
        Rectangle {
            x: parent.width - 9
            y: -2
            width: 11
            height: 11
            radius: 5.5
            color: Colors.accent
            border.width: 2
            border.color: Style.card
            visible: row.fresh
        }
    }

    Item {
        visible: !row.isHeader
        x: 60
        width: row.width - 60 - 12 - (row.hovered ? 3 * 26 + 6 : 44)
        height: row.height

        Txt {
            anchors.left: parent.left
            anchors.right: parent.right
            y: 10
            text: row.line1
            color: Colors.foreground
            font.pixelSize: Style.fontBase
            font.bold: row.fresh
            elide: Text.ElideRight
        }

        Txt {
            anchors.left: parent.left
            anchors.right: parent.right
            y: 29
            text: row.line2
            color: Colors.muted
            font.pixelSize: Style.fontSm
            elide: Text.ElideRight
        }
    }

    // How long ago
    Txt {
        visible: !row.isHeader && !row.hovered
        anchors.right: parent.right
        anchors.rightMargin: 14
        anchors.verticalCenter: parent.verticalCenter
        text: row.isHeader ? "" : NotificationServer.ago(row.e.time, row.nowMs)
        color: Colors.muted
        font.pixelSize: Style.fontSm
    }

    // Under the pointer
    Row {
        visible: row.hovered && !row.isHeader
        anchors.right: parent.right
        anchors.rightMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        spacing: 2

        HoverHandler {
            id: actionsHover
        }

        IconButton {
            size: 24
            glyph: Icons.copy
            tip: "Copy"
            onClicked: row.copyClicked()
            onHoveredChanged: row.tipped(hovered ? tip : "")
        }

        IconButton {
            size: 24
            glyph: Icons.clock
            on: row.snoozed
            tip: row.snoozed ? "Bring back now" : "Snooze 10 minutes"
            onClicked: row.snoozeClicked()
            onHoveredChanged: row.tipped(hovered ? tip : "")
        }

        IconButton {
            size: 24
            glyph: Icons.close
            danger: true
            tip: "Dismiss"
            onClicked: row.dismissClicked()
            onHoveredChanged: row.tipped(hovered ? tip : "")
        }
    }
}
