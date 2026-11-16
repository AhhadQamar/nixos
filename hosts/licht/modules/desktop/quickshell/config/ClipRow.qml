import QtQuick
import Quickshell.Widgets

// One entry in the list: a round disc (a thumbnail for an image, the colour for
// a colour, a glyph for the rest), the first line of it, and under that what it
// is, where it came from and how long ago. Under the pointer: copy, pin, remove.
Item {
    id: row

    required property var modelData
    required property int index

    // Set by the panel
    property bool current: false
    property bool ticked: false

    signal clicked(bool ctrl)
    signal copyClicked
    signal pinClicked
    signal deleteClicked
    signal tipped(string text)

    readonly property var e: modelData
    readonly property string kind: e.kind
    readonly property bool hovered: hover.hovered
    readonly property string thumb: kind === "image" ? ClipStore.thumbUrl(e) : ""
    readonly property string glyph: {
        switch (kind) {
        case "link":
            return Icons.link;
        case "path":
            return Icons.folder;
        case "image":
            return Icons.image;
        case "secret":
            return Icons.lock;
        default:
            return Icons.file;
        }
    }
    readonly property string metaLine: {
        const parts = [ClipStore.kindLabels[kind]];
        if (kind === "image") {
            if (e.imgDims !== "")
                parts.push(e.imgDims);
            if (e.imgSize !== "")
                parts.push(e.imgSize);
        }
        if (e.app !== "" && e.pid === "")
            parts.push(e.app);
        const t = ClipStore.ago(e.t);
        if (t !== "")
            parts.push(t);
        return parts.join("  \u00b7  ");
    }

    height: 46

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
        anchors.fill: parent
        radius: Style.radiusLg
        color: row.ticked ? Qt.alpha(Colors.accent, Style.selectedAlpha) : (row.current ? Qt.alpha(Colors.accent, Style.tintAlpha) : (row.hovered ? Style.well : "transparent"))
        border.width: 1
        border.color: row.current ? Qt.alpha(Colors.accent, 0.45) : "transparent"

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
        y: (row.height - height) / 2
        width: 2
        height: 20
        radius: 1
        color: Colors.accent
    }

    // The disc
    Item {
        id: disc

        x: 12
        y: (row.height - height) / 2
        width: 30
        height: 30

        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: row.kind === "color" ? Qt.color(row.e.preview.trim()) : Style.well
            border.width: 1
            border.color: Style.outline
        }

        ClippingRectangle {
            anchors.fill: parent
            radius: width / 2
            color: "transparent"
            visible: row.thumb !== ""

            Image {
                anchors.fill: parent
                source: row.thumb
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: false
                sourceSize.width: 64
                sourceSize.height: 64
            }
        }

        Txt {
            anchors.centerIn: parent
            visible: row.kind !== "color" && row.thumb === ""
            text: row.glyph
            color: row.kind === "secret" ? Colors.color3 : Colors.muted
            font.pixelSize: 13
        }
    }

    Item {
        x: 54
        width: row.width - 54 - 12 - (row.hovered ? 3 * 26 + 6 : (row.e.pinned ? 22 : 0))
        height: row.height

        Txt {
            anchors.left: parent.left
            anchors.right: parent.right
            y: 7
            text: row.kind === "secret" ? "\u2022\u2022\u2022\u2022\u2022\u2022\u2022\u2022\u2022\u2022\u2022\u2022" : (row.kind === "image" ? "Image" : row.e.preview)
            color: Colors.foreground
            font.pixelSize: Style.fontBase
            elide: Text.ElideRight
        }

        Txt {
            anchors.left: parent.left
            anchors.right: parent.right
            y: 25
            text: row.metaLine
            color: Colors.muted
            font.pixelSize: Style.fontSm
            elide: Text.ElideRight
        }
    }

    // Pinned
    Txt {
        visible: row.e.pinned && !row.hovered
        anchors.right: parent.right
        anchors.rightMargin: 14
        anchors.verticalCenter: parent.verticalCenter
        text: Icons.heart
        color: Colors.accent
        font.pixelSize: 12
    }

    // Ticked
    Rectangle {
        visible: row.ticked
        x: 4
        y: (row.height - height) / 2
        width: 6
        height: 6
        radius: 3
        color: Colors.accent
    }

    // Under the pointer
    Row {
        visible: row.hovered
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
            glyph: row.e.pinned ? Icons.heart : Icons.heartOutline
            on: row.e.pinned
            tip: row.e.pinned ? "Unpin" : "Pin"
            onClicked: row.pinClicked()
            onHoveredChanged: row.tipped(hovered ? tip : "")
        }

        IconButton {
            size: 24
            glyph: Icons.close
            danger: true
            tip: "Remove"
            onClicked: row.deleteClicked()
            onHoveredChanged: row.tipped(hovered ? tip : "")
        }
    }
}
