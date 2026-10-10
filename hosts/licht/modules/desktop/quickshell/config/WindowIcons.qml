// Row of app icons for a window list; the last-focused window is brightest.

import QtQuick
import Quickshell.Widgets

Row {
    id: root

    property var windows: []
    property int maxIcons: 3
    property int iconSize: 16
    property int iconSpacing: 4
    property bool showNames: false
    property int nameMaxWidth: 90
    property color labelColor: Colors.foreground

    spacing: showNames ? 10 : iconSpacing

    Repeater {
        model: (root.windows ?? []).slice(0, root.maxIcons)

        delegate: Row {
            id: cell

            required property var modelData

            spacing: 5
            opacity: modelData.focused ? 1 : 0.75

            Behavior on opacity {
                NumberAnimation {
                    duration: 150
                }
            }

            Item {
                implicitWidth: root.iconSize
                implicitHeight: root.iconSize

                IconImage {
                    anchors.fill: parent
                    visible: cell.modelData.icon !== ""
                    source: cell.modelData.icon
                }

                Rectangle {
                    anchors.fill: parent
                    visible: cell.modelData.icon === ""
                    radius: 5
                    color: Qt.alpha(root.labelColor, 0.2)

                    Text {
                        anchors.centerIn: parent
                        text: {
                            const parts = cell.modelData.cls.split(".");
                            const last = parts[parts.length - 1];
                            return (last !== "" ? last : cell.modelData.cls).charAt(0).toUpperCase();
                        }
                        color: root.labelColor

                        font {
                            family: Style.fontFamily
                            pixelSize: 10
                            bold: true
                        }
                    }
                }
            }

            Text {
                visible: root.showNames
                anchors.verticalCenter: parent.verticalCenter
                text: cell.modelData.name
                textFormat: Text.PlainText
                color: root.labelColor
                elide: Text.ElideRight
                width: Math.min(implicitWidth, root.nameMaxWidth)

                font {
                    family: Style.fontFamily
                    pixelSize: 11
                    bold: cell.modelData.focused
                }
            }
        }
    }

    Text {
        visible: (root.windows ?? []).length > root.maxIcons
        anchors.verticalCenter: parent.verticalCenter
        text: "+" + ((root.windows ?? []).length - root.maxIcons)
        color: root.labelColor
        opacity: 0.8

        font {
            family: Style.fontFamily
            pixelSize: 11
            bold: true
        }
    }
}
