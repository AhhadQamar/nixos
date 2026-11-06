// Download chip for the bar: a place to drop links, and the downloads at a glance.
//
// Drag a link, some text with links in it, or a .torrent file onto it from the
// browser or the file manager and let go: it is added, the same as pasting it
// into the downloads panel, without the panel opening. While you drag over it,
// the capsule opens into "Drop to download" and takes the accent. A check
// flashes when it was added, a cross when there was nothing to add.
//
// Otherwise it is a small download glyph, which turns to the accent and shows the
// number running and the speed while downloads are going (video grabs count too).
// Click it to open the downloads panel. The panel answers over DownloadStatus.
//
// Like the other chips: a glass capsule, an accent outline and a breathing ring
// under the pointer or the drag, and a 2px underline. The breath only runs
// while it is hovered or dragged over.

import QtQuick

Item {
    id: root

    // 0..1..0 while hovered or dragged over
    property real breath: 0
    // What the last drop did: "" | ok | none
    property string flash: ""

    readonly property bool dragging: dropArea.containsDrag
    readonly property bool busy: DownloadStatus.active > 0
    readonly property bool lit: dragging || hover.hovered
    readonly property color tint: flash === "none" ? Colors.critical : Colors.accent
    readonly property string label: {
        if (dragging)
            return "Drop to download";
        if (flash === "ok")
            return "Added";
        if (flash === "none")
            return "Nothing to add";
        if (busy)
            return DownloadStatus.active + "  " + Aria2.rate(DownloadStatus.speed);
        return "";
    }

    implicitHeight: Style.barHeight
    implicitWidth: glass.implicitWidth + Style.spaceMd

    Behavior on implicitWidth {
        NumberAnimation {
            duration: Style.baseMs
            easing.type: Style.easeMove
        }
    }

    Timer {
        id: flashTimer

        interval: 1600
        onTriggered: root.flash = ""
    }

    Connections {
        target: DownloadStatus

        function onAdded(count) {
            root.flash = count > 0 ? "ok" : "none";
            flashTimer.restart();
        }
    }

    // Breath, only while the pointer or a drag is on the chip
    SequentialAnimation {
        running: root.lit && root.visible
        loops: Animation.Infinite

        NumberAnimation {
            target: root
            property: "breath"
            from: 0
            to: 1
            duration: Style.ambientMs * 2
            easing.type: Style.easeAmbient
        }
        NumberAnimation {
            target: root
            property: "breath"
            from: 1
            to: 0
            duration: Style.ambientMs * 2
            easing.type: Style.easeAmbient
        }
    }

    // Ring round the capsule
    Rectangle {
        anchors.centerIn: glass
        width: glass.width + 4
        height: glass.height + 4
        radius: height / 2
        color: "transparent"
        antialiasing: true
        visible: root.lit
        border.width: 1
        border.color: Qt.alpha(root.tint, 0.2 + 0.2 * root.breath)
    }

    Rectangle {
        id: glass

        x: 0
        anchors.verticalCenter: parent.verticalCenter
        implicitHeight: Style.discSize
        implicitWidth: Math.max(Style.discSize, row.implicitWidth + Style.spaceLg * 2)
        radius: height / 2
        antialiasing: true
        scale: tap.pressed ? 0.97 : 1
        color: root.lit || root.flash !== "" ? Qt.alpha(root.tint, Style.tintAlpha) : Style.well
        border.width: 1
        border.color: root.lit || root.flash !== "" ? Qt.alpha(root.tint, 0.6) : (root.busy ? Qt.alpha(Colors.accent, 0.4) : Style.outline)

        Behavior on color {
            ColorAnimation {
                duration: Style.baseMs
            }
        }
        Behavior on border.color {
            ColorAnimation {
                duration: Style.baseMs
            }
        }
        Behavior on scale {
            NumberAnimation {
                duration: Style.pressMs
                easing.type: Style.easePress
            }
        }

        EdgeLight {
            corner: glass.height
        }

        Row {
            id: row

            anchors.centerIn: parent
            spacing: Style.spaceSm

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root.flash === "ok" ? Icons.check : (root.flash === "none" ? Icons.close : Icons.download)
                textFormat: Text.PlainText
                color: root.lit || root.busy || root.flash !== "" ? root.tint : Colors.muted

                Behavior on color {
                    ColorAnimation {
                        duration: Style.baseMs
                    }
                }

                font {
                    family: Style.fontFamily
                    pixelSize: Style.fontLg
                }
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: root.label !== ""
                text: root.label
                textFormat: Text.PlainText
                color: root.lit || root.flash !== "" ? root.tint : Colors.foreground

                Behavior on color {
                    ColorAnimation {
                        duration: Style.baseMs
                    }
                }

                font {
                    family: Style.fontFamily
                    pixelSize: Style.fontMd
                    bold: true
                }
            }
        }
    }

    // Underline under the capsule
    Item {
        anchors.horizontalCenter: glass.horizontalCenter
        anchors.top: glass.bottom
        anchors.topMargin: Style.spaceXs
        width: 30
        height: 2
        opacity: root.lit ? 1 : 0
        visible: opacity > 0.01

        Behavior on opacity {
            NumberAnimation {
                duration: Style.fadeMs
            }
        }

        Rectangle {
            anchors.centerIn: parent
            width: 20 + 10 * root.breath
            height: 2
            radius: 1
            color: root.tint
            opacity: 0.55 + 0.4 * root.breath
        }
    }

    // The whole bar-high column takes the drop and the click, not just the capsule
    DropArea {
        id: dropArea

        anchors.fill: parent
        onEntered: drag => {
            drag.accepted = drag.hasUrls || drag.hasText;
        }
        onDropped: drop => {
            const text = Aria2.dropText(drop);
            drop.acceptProposedAction();
            if (text === "") {
                root.flash = "none";
                flashTimer.restart();
            } else {
                DownloadStatus.addRequested(text);
            }
        }
    }

    TapHandler {
        id: tap

        onTapped: DownloadStatus.toggleRequested()
    }
    HoverHandler {
        id: hover

        cursorShape: Qt.PointingHandCursor
    }
}
