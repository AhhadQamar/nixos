import QtQuick

Rectangle {
    id: root

    property string icon: ""
    property string label: ""
    property color iconColor: Colors.foreground
    property color labelColor: Colors.foreground
    property bool alwaysShowLabel: false

    // A small dot in the corner, for "something new"
    property bool badge: false

    signal clicked
    signal rightClicked
    signal scrolled(real delta)

    readonly property bool open: alwaysShowLabel || hover.hovered

    implicitHeight: Style.itemHeight
    implicitWidth: Math.max(implicitHeight, content.implicitWidth + 20)
    radius: height / 2
    antialiasing: true
    color: hover.hovered ? Style.hoverFill : "transparent"
    scale: tap.pressed ? 0.94 : 1

    Behavior on color {
        ColorAnimation {
            duration: 200
        }
    }
    Behavior on scale {
        NumberAnimation {
            duration: 100
            easing.type: Easing.OutQuad
        }
    }

    Row {
        id: content

        anchors.centerIn: parent

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.icon
            color: root.iconColor

            Behavior on color {
                ColorAnimation {
                    duration: 200
                }
            }

            font {
                family: Style.fontFamily
                pixelSize: 18
            }
        }

        Item {
            anchors.verticalCenter: parent.verticalCenter
            height: labelText.implicitHeight
            width: root.open && root.label !== "" ? labelText.implicitWidth + 6 : 0
            visible: width > 0.5
            clip: true

            Behavior on width {
                NumberAnimation {
                    duration: 180
                    easing.type: Easing.OutCubic
                }
            }

            Text {
                id: labelText

                x: 6
                anchors.verticalCenter: parent.verticalCenter
                text: root.label
                textFormat: Text.PlainText
                color: root.labelColor

                font {
                    family: Style.fontFamily
                    pixelSize: 13
                    weight: Font.Medium
                }
            }
        }
    }

    Rectangle {
        visible: root.badge
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.topMargin: 4
        anchors.rightMargin: 4
        width: 8
        height: 8
        radius: 4
        color: Colors.accent
        border.width: 1.5
        border.color: Qt.alpha(Colors.background, 1)
    }

    TapHandler {
        id: tap

        onTapped: root.clicked()
    }
    TapHandler {
        acceptedButtons: Qt.RightButton
        onTapped: root.rightClicked()
    }
    HoverHandler {
        id: hover

        cursorShape: Qt.PointingHandCursor
    }
    WheelHandler {
        onWheel: event => root.scrolled(event.angleDelta.y)
    }
}
