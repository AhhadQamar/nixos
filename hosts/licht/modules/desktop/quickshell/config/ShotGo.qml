// The one button that does the thing: Capture. Copy and Save beside it are
// quiet toggles that tint when they are on; this one is the accent itself, a
// solid pill, so there is never any doubt what Enter will do. A faint ring
// around it breathes with the dial's ring (pass `breath`).
//
//   text / glyph   as on TextButton
//   breath         0..1, the shell's slow pulse
//   enabled        false dims it and ignores clicks

import QtQuick

Rectangle {
    id: btn

    property string text: ""
    property string glyph: ""
    property real breath: 0

    readonly property bool hovered: hover.hovered

    signal clicked

    implicitHeight: Style.buttonHeight
    implicitWidth: inner.implicitWidth + Style.buttonPad
    radius: height / 2
    antialiasing: true
    color: hovered && enabled ? Qt.lighter(Colors.accent, 1.12) : Colors.accent
    opacity: enabled ? 1 : 0.4
    scale: tap.pressed ? 0.97 : 1

    Behavior on color {
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

    // A breath of accent just outside the pill
    Rectangle {
        anchors.fill: parent
        anchors.margins: -3
        radius: btn.radius + 3
        color: "transparent"
        antialiasing: true
        border.width: 1
        border.color: Qt.alpha(Colors.accent, btn.enabled ? 0.15 + 0.2 * btn.breath : 0)
    }

    EdgeLight {
        corner: btn.height / 2
    }

    Row {
        id: inner

        anchors.centerIn: parent
        spacing: Style.spaceSm + 2

        Txt {
            anchors.verticalCenter: parent.verticalCenter
            visible: btn.glyph !== ""
            text: btn.glyph
            color: Colors.background
            font.pixelSize: Style.fontBase
        }

        Txt {
            anchors.verticalCenter: parent.verticalCenter
            visible: btn.text !== ""
            text: btn.text
            color: Colors.background
            font.pixelSize: Style.fontMd
            font.bold: true
        }
    }

    HoverHandler {
        id: hover

        cursorShape: btn.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
    }

    TapHandler {
        id: tap

        onTapped: if (btn.enabled)
            btn.clicked()
    }
}
