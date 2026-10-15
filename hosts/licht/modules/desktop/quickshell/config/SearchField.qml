// The search pill every panel uses: a magnifier, the text, and a clear button.
//
//   placeholder  the text shown while empty
//   clearable    shows the clear button while there is text (default on)
//   badge        a small count beside the clear button (empty hides it)
//   busy         the magnifier breathes in the accent while something is searching
//   glyph        replaces the magnifier (use something from Icons.qml)
//   fontSize     size of the typed text and the placeholder (default fontLg)
//   text         the text; read it and set it like a TextInput's
//
// Key handling stays with the panel. Put the same handlers you would put on a
// TextInput on the SearchField itself; they run before the field handles the
// key, so a panel can claim Up, Down, Left, Right, Tab, Escape or Return:
//
//     SearchField {
//         id: search
//         placeholder: "Search clipboard"
//         onTextChanged: panel.refilter()
//         Keys.onEscapePressed: if (text !== "") text = ""; else panel.close()
//         Keys.onDownPressed: panel.move(1)
//         Keys.onPressed: event => { ... }
//     }
//
// It is a pill at Style.fieldHeight. It rests on the card's `well`, lifts to
// `hoverFill` while focused, and gets a faint accent edge while it holds text.
// Its width is the panel's to set (width, Layout.fillWidth, anchors).

import QtQuick

FocusScope {
    id: root

    property string placeholder: ""
    property string glyph: Icons.search
    property bool clearable: true
    property string badge: ""
    property bool busy: false
    property int fontSize: Style.fontLg
    property alias text: field.text
    // The TextInput, for the few things a panel needs from it (selectAll,
    // cursorPosition, inputMethodComposing, ...)
    property alias input: field

    readonly property bool filled: field.text !== ""
    readonly property bool lit: field.activeFocus || filled || busy
    property real breath: 1

    signal accepted

    function selectAll() {
        field.selectAll();
    }

    function clear() {
        field.text = "";
    }

    implicitHeight: Style.fieldHeight
    implicitWidth: 240
    activeFocusOnTab: false

    Rectangle {
        id: pill

        anchors.fill: parent
        radius: height / 2
        antialiasing: true
        color: field.activeFocus ? Style.hoverFill : Style.well
        border.width: 1
        border.color: root.filled ? Qt.alpha(Colors.accent, 0.5) : "transparent"

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

    // Clicking anywhere on the pill focuses the text
    TapHandler {
        onTapped: field.forceActiveFocus()
    }

    Txt {
        id: icon

        x: 14
        anchors.verticalCenter: parent.verticalCenter
        text: root.glyph
        color: root.lit ? Colors.accent : Colors.muted
        opacity: root.busy ? root.breath : 1
        font.pixelSize: Style.fontXl

        Behavior on color {
            ColorAnimation {
                duration: Style.baseMs
            }
        }
    }

    // The magnifier breathes while it searches
    SequentialAnimation {
        running: root.busy && root.visible
        loops: Animation.Infinite
        onRunningChanged: if (!running)
            root.breath = 1

        NumberAnimation {
            target: root
            property: "breath"
            to: 0.4
            duration: Style.ambientMs
            easing.type: Style.easeAmbient
        }
        NumberAnimation {
            target: root
            property: "breath"
            to: 1
            duration: Style.ambientMs
            easing.type: Style.easeAmbient
        }
    }

    TextInput {
        id: field

        anchors.verticalCenter: parent.verticalCenter
        x: 14 + Style.fontXl + Style.spaceMd + 4
        width: parent.width - x - (root.clearable ? 38 : 14) - (count.visible ? count.width + 4 : 0)
        focus: true
        clip: true
        color: Colors.foreground
        selectionColor: Qt.alpha(Colors.accent, 0.4)
        selectedTextColor: Colors.foreground
        // The panel's handlers sit on the SearchField; give them the first look
        Keys.forwardTo: [root]
        onAccepted: root.accepted()

        font {
            family: Style.fontFamily
            pixelSize: root.fontSize
        }

        Txt {
            anchors.fill: parent
            visible: field.text.length === 0
            verticalAlignment: Text.AlignVCenter
            text: root.placeholder
            color: Colors.muted
            font.pixelSize: root.fontSize
        }
    }

    // A count beside the clear button
    Rectangle {
        id: count

        anchors.right: parent.right
        anchors.rightMargin: root.clearable ? 36 : 12
        anchors.verticalCenter: parent.verticalCenter
        implicitWidth: Math.max(18, countText.implicitWidth + 12)
        implicitHeight: 20
        radius: height / 2
        color: Qt.alpha(Colors.muted, Style.tintAlpha)
        opacity: root.badge !== "" ? 1 : 0
        visible: opacity > 0.01

        Behavior on opacity {
            NumberAnimation {
                duration: Style.fadeMs
            }
        }

        Txt {
            id: countText

            anchors.centerIn: parent
            text: root.badge
            color: Colors.muted
            font.pixelSize: Style.fontSm
        }
    }

    // Clear the text
    Rectangle {
        anchors.right: parent.right
        anchors.rightMargin: 6
        anchors.verticalCenter: parent.verticalCenter
        width: 26
        height: 26
        radius: height / 2
        opacity: root.clearable && root.filled ? 1 : 0
        visible: opacity > 0.01
        color: xHover.hovered ? Style.hoverFill : "transparent"

        Behavior on opacity {
            NumberAnimation {
                duration: Style.fadeMs
            }
        }
        Behavior on color {
            ColorAnimation {
                duration: Style.baseMs
            }
        }

        Txt {
            anchors.centerIn: parent
            text: Icons.close
            color: Colors.muted
            font.pixelSize: Style.fontMd
        }

        HoverHandler {
            id: xHover

            cursorShape: Qt.PointingHandCursor
        }
        TapHandler {
            onTapped: {
                root.clear();
                field.forceActiveFocus();
            }
        }
    }
}
