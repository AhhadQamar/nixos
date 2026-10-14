// One system tray item. Left click activates it (or opens its menu when it
// only has a menu), right click opens its menu, middle click is the secondary
// action.
//
// It is always a small glass disc in the dial's language, in miniature: a
// hairline outline, a light catching its top edge, and, under the pointer, the
// accent: the outline, a soft tint, a ring that breathes and a 2px underline.
// In the bar the disc is Style.discSize and the item is as tall as the bar, so
// the whole column is clickable; in the folded list (inList) it is larger and
// the list reads the app's name out below the discs, so the disc has no label
// of its own. Either way it reports `hovered` (the tray's ruler and the list's
// footer follow it) and `disc`, the glass itself. An app that needs attention gets
// a red dot that breathes slowly (and only runs while it is needed).

import QtQuick
import Quickshell
import Quickshell.Widgets

Rectangle {
    id: root

    required property var item
    // The folded list's disc, instead of the bare bar icon
    property bool inList: false
    // Where a menu is drawn. The folded list points these at the bar so the
    // menu outlives the list closing.
    property var menuWindow: root.QsWindow.window
    // null = the disc itself
    property Item menuAnchor: null
    // 0 -> 1 as the list opens: the disc rises in (the list sets it)
    property real arrive: 1
    // A slow pulse (0..1) for the ring round the disc under the pointer (the
    // list sets it, so it only runs while the list is open; in the bar the
    // disc breathes on its own, only while hovered)
    property real breath: 0
    property real selfBreath: 0

    // Fired after a plain activate, so the folded list can close itself
    signal triggered

    readonly property bool hovered: hover.hovered
    // status 2 = NeedsAttention
    readonly property bool attention: item.status === 2
    readonly property int discSize: inList ? 32 : Style.discSize
    readonly property real pulse: inList ? breath : selfBreath
    readonly property Item disc: face
    // Where the disc sits: in the bar, centred in the bar's height
    readonly property real faceY: inList ? 3 : (height - discSize) / 2

    // In the list the cell is the disc plus room under it for the underline
    implicitHeight: inList ? 44 : Style.barHeight
    implicitWidth: inList ? 40 : Style.discSize
    color: "transparent"
    scale: tap.pressed ? 0.94 : 1

    // Breath in the bar, only while the pointer is on the disc
    SequentialAnimation {
        running: hover.hovered && !root.inList
        loops: Animation.Infinite

        NumberAnimation {
            target: root
            property: "selfBreath"
            from: 0
            to: 1
            duration: Style.ambientMs * 2
            easing.type: Style.easeAmbient
        }
        NumberAnimation {
            target: root
            property: "selfBreath"
            from: 1
            to: 0
            duration: Style.ambientMs * 2
            easing.type: Style.easeAmbient
        }
    }
    Behavior on scale {
        NumberAnimation {
            duration: Style.pressMs
            easing.type: Style.easePress
        }
    }

    function showMenu() {
        if (!item.hasMenu || !menuWindow)
            return;
        const anchorItem = menuAnchor ? menuAnchor : face;
        const p = anchorItem.mapToItem(null, 0, anchorItem.height + 6);
        item.display(menuWindow, p.x, p.y);
    }

    // The disc
    Item {
        id: face

        x: (root.width - width) / 2
        y: root.faceY
        width: root.discSize
        height: root.discSize
        opacity: root.arrive
        transform: Translate {
            y: (1 - root.arrive) * 8
        }

        // Ring round the disc under the pointer; it breathes
        Rectangle {
            anchors.centerIn: parent
            // Tighter in the bar, where the ruler sits just above the disc
            width: parent.width + (root.inList ? 6 : 4)
            height: width
            radius: width / 2
            color: "transparent"
            antialiasing: true
            border.width: 1
            border.color: Qt.alpha(Colors.accent, 0.2 + 0.2 * root.pulse)
            opacity: root.hovered ? 1 : 0

            Behavior on opacity {
                NumberAnimation {
                    duration: Style.fadeMs
                }
            }
        }

        // Glass: a hairline outline on the card's own `well` (the card is
        // already the glass, so the disc is lit by its edge), lit in the
        // accent under the pointer
        Rectangle {
            anchors.fill: parent
            radius: width / 2
            antialiasing: true
            color: root.hovered && root.inList ? Style.hoverFill : Style.well
            border.width: 1
            border.color: root.hovered ? Qt.alpha(Colors.accent, root.inList ? 0.9 : 0.6) : (root.inList ? Qt.alpha(Colors.foreground, 0.2) : Style.outline)

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
        }

        // The soft tint inside the glass
        Rectangle {
            anchors.fill: parent
            anchors.margins: 1
            radius: width / 2
            antialiasing: true
            color: Qt.alpha(Colors.accent, root.hovered ? Style.tintAlpha : 0)

            Behavior on color {
                ColorAnimation {
                    duration: Style.baseMs
                }
            }
        }

        // Light catching the top edge, as on the bar
        Rectangle {
            anchors.top: parent.top
            anchors.topMargin: 1
            anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width * 0.5
            height: 1

            gradient: Gradient {
                orientation: Gradient.Horizontal

                GradientStop {
                    position: 0
                    color: Qt.alpha(Colors.foreground, 0)
                }
                GradientStop {
                    position: 0.5
                    color: Qt.alpha(Colors.foreground, 0.12)
                }
                GradientStop {
                    position: 1
                    color: Qt.alpha(Colors.foreground, 0)
                }
            }
        }

        Item {
            anchors.centerIn: parent
            width: root.inList ? 18 : 14
            height: width

            IconImage {
                anchors.fill: parent
                source: root.item.icon
                opacity: hover.hovered ? 1 : 0.85
                scale: hover.hovered ? 1.1 : 1

                Behavior on opacity {
                    NumberAnimation {
                        duration: Style.fadeMs
                    }
                }
                Behavior on scale {
                    NumberAnimation {
                        duration: Style.fadeMs
                        easing.type: Style.easeMove
                    }
                }
            }

            // Attention dot
            Rectangle {
                visible: root.attention
                anchors.top: parent.top
                anchors.right: parent.right
                width: 6
                height: 6
                radius: 3
                color: Colors.critical

                SequentialAnimation on opacity {
                    running: root.attention
                    loops: Animation.Infinite

                    NumberAnimation {
                        from: 1
                        to: 0.3
                        duration: Style.ambientMs
                        easing.type: Style.easeAmbient
                    }
                    NumberAnimation {
                        from: 0.3
                        to: 1
                        duration: Style.ambientMs
                        easing.type: Style.easeAmbient
                    }
                }
            }
        }
    }

    // Accent underline under the disc under the pointer; it breathes with
    // the ring
    Rectangle {
        x: (root.width - width) / 2
        y: root.faceY + root.discSize + (root.inList ? 5 : Style.spaceXs)
        width: 12 + 8 * root.pulse
        height: 2
        radius: 1
        antialiasing: true
        color: Colors.accent
        opacity: root.hovered ? 1 : 0

        Behavior on opacity {
            NumberAnimation {
                duration: Style.fadeMs
            }
        }
    }

    TapHandler {
        id: tap

        onTapped: {
            // udiskie has a menu but no "activate" action, so open the menu
            const menuOnly = root.item.onlyMenu || /udiskie/i.test(root.item.id + " " + root.item.title);
            if (menuOnly && root.item.hasMenu) {
                root.showMenu();
            } else {
                root.item.activate();
                root.triggered();
            }
        }
    }
    TapHandler {
        acceptedButtons: Qt.RightButton
        onTapped: root.showMenu()
    }
    TapHandler {
        acceptedButtons: Qt.MiddleButton
        onTapped: root.item.secondaryActivate()
    }
    HoverHandler {
        id: hover

        cursorShape: Qt.PointingHandCursor
    }
}
