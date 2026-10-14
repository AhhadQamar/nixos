// Round icon button: transparent until hovered, accent-tinted while `on`.
//   danger   turns the glyph red on hover
//   active   false dims the button and ignores clicks
//   tip      free-form label for whoever shows tooltips (read `hovered`)

import QtQuick

Rectangle {
    id: btn

    property string glyph: ""
    property string tip: ""
    property bool on: false
    property bool danger: false
    property bool active: true
    property int size: Style.itemHeight
    property int glyphSize: 14

    readonly property bool hovered: hover.hovered
    readonly property bool lit: active && hover.hovered

    signal clicked

    implicitWidth: size
    implicitHeight: size
    radius: height / 2
    antialiasing: true
    color: on ? Qt.alpha(Colors.accent, 0.2) : (lit ? Style.hoverFill : "transparent")
    opacity: active ? 1.0 : 0.3
    scale: active && tap.pressed ? 0.94 : 1

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

    Txt {
        anchors.centerIn: parent
        text: btn.glyph
        color: btn.on ? Colors.accent : (btn.danger && btn.lit ? Colors.critical : (btn.lit ? Colors.foreground : Colors.muted))
        font.pixelSize: btn.glyphSize

        Behavior on color {
            ColorAnimation {
                duration: Style.baseMs
            }
        }
    }

    HoverHandler {
        id: hover

        cursorShape: btn.active ? Qt.PointingHandCursor : Qt.ArrowCursor
    }

    TapHandler {
        id: tap

        onTapped: if (btn.active)
            btn.clicked()
    }
}
