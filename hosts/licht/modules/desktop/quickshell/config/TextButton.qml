// The text button every panel uses: a pill, resting on the card's `well`.
//
//   text      the label
//   glyph     an icon from Icons.qml, before the label (alone if there is no text)
//   hint      a key shown on the button (see KeyCap)
//   primary   accent tint and a bold accent label
//   danger    red tint and a bold red label; also the second press of
//             something destructive
//   compact   the shorter height used on rows
//   raised    for a button that sits on a row that is already filled or
//             hovered: one step lighter at rest, so it still reads
//   armed     shakes once and rings the button in red, breathing, while it
//             waits for the second press
//   busy      breathes while it works (when disabled)
//   confirm() lights the edge in `flashColor` for a moment
//   minWidth  a floor for the width
//
// Height, label padding, fills and motion all come from Style.qml, so every
// button in the shell is the same size, tints the same way and moves the same
// way. Panels do not write their own.

import QtQuick

Rectangle {
    id: btn

    property string text: ""
    property string glyph: ""
    property string hint: ""
    property bool primary: false
    property bool danger: false
    property bool compact: false
    property bool raised: false
    property bool armed: false
    property bool busy: false
    property color flashColor: Colors.accent
    property int minWidth: 0
    property real breath: 0.8
    property real ringBreath: 0.2

    readonly property bool hovered: hover.hovered
    // Label colour: red for danger, accent for primary, otherwise the foreground
    readonly property color labelColor: danger ? Colors.critical : (primary ? Colors.accent : Colors.foreground)

    signal clicked

    function confirm() {
        flashAnim.restart();
    }

    implicitHeight: compact ? Style.buttonCompact : Style.buttonHeight
    implicitWidth: Math.max(minWidth, inner.implicitWidth + (text === "" && glyph !== "" ? implicitHeight : Style.buttonPad))
    radius: height / 2
    antialiasing: true
    opacity: enabled ? 1 : (busy ? breath : 0.4)
    scale: tap.pressed ? 0.97 : 1
    color: danger ? Qt.alpha(Colors.critical, hovered ? 0.32 : 0.22) : (primary ? Qt.alpha(Colors.accent, hovered ? 0.32 : 0.22) : (raised ? (hovered ? Style.strongFill : Style.hoverFill) : (hovered ? Style.hoverFill : Style.well)))
    transform: Translate {
        id: nudge
    }
    onArmedChanged: if (armed)
        nudgeAnim.restart()

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

    // A small shake when it arms, so the second press is noticed
    SequentialAnimation {
        id: nudgeAnim

        NumberAnimation {
            target: nudge
            property: "x"
            to: -4
            duration: 50
        }
        NumberAnimation {
            target: nudge
            property: "x"
            to: 4
            duration: 80
        }
        NumberAnimation {
            target: nudge
            property: "x"
            to: 0
            duration: 110
            easing.type: Style.easeMove
        }
    }

    // Breathes while busy
    SequentialAnimation {
        running: btn.busy && !btn.enabled && btn.visible
        loops: Animation.Infinite

        NumberAnimation {
            target: btn
            property: "breath"
            to: 0.4
            duration: Style.ambientMs
            easing.type: Style.easeAmbient
        }
        NumberAnimation {
            target: btn
            property: "breath"
            to: 0.8
            duration: Style.ambientMs
            easing.type: Style.easeAmbient
        }
    }

    // While armed: a red ring that breathes
    Rectangle {
        anchors.fill: parent
        anchors.margins: -4
        radius: btn.radius + 4
        color: "transparent"
        border.width: 1.5
        border.color: Colors.critical
        visible: btn.armed
        opacity: btn.ringBreath
        antialiasing: true

        SequentialAnimation on opacity {
            running: btn.armed
            loops: Animation.Infinite

            NumberAnimation {
                to: 0.75
                duration: Style.ambientMs
                easing.type: Style.easeAmbient
            }
            NumberAnimation {
                to: 0.2
                duration: Style.ambientMs
                easing.type: Style.easeAmbient
            }
        }
    }

    // Pressed: the edge lights up and fades
    Rectangle {
        id: flash

        anchors.fill: parent
        radius: btn.radius
        color: "transparent"
        border.width: 2
        border.color: btn.flashColor
        opacity: 0
        antialiasing: true
    }

    NumberAnimation {
        id: flashAnim

        target: flash
        property: "opacity"
        from: 0.95
        to: 0
        duration: Style.ambientMs
        easing.type: Style.easeMove
    }

    Row {
        id: inner

        anchors.centerIn: parent
        spacing: Style.spaceSm + 2

        Txt {
            anchors.verticalCenter: parent.verticalCenter
            visible: btn.glyph !== ""
            text: btn.glyph
            color: btn.primary || btn.danger ? btn.labelColor : (btn.hovered ? Colors.foreground : Colors.muted)
            font.pixelSize: btn.text === "" ? Style.fontXl - 1 : Style.fontBase

            Behavior on color {
                ColorAnimation {
                    duration: Style.baseMs
                }
            }
        }

        Txt {
            id: label

            anchors.verticalCenter: parent.verticalCenter
            visible: btn.text !== ""
            text: btn.text
            color: btn.labelColor
            font.pixelSize: Style.fontMd
            font.bold: btn.primary || btn.danger
            onTextChanged: labelFade.restart()
        }

        KeyCap {
            anchors.verticalCenter: parent.verticalCenter
            visible: btn.hint !== ""
            label: btn.hint
        }
    }

    // The label fades in when it changes ("Apply" to "Press again")
    NumberAnimation {
        id: labelFade

        target: label
        property: "opacity"
        from: 0.3
        to: 1
        duration: Style.fadeMs
    }

    TapHandler {
        id: tap

        onTapped: if (btn.enabled)
            btn.clicked()
    }
    HoverHandler {
        id: hover

        cursorShape: btn.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
    }
}
