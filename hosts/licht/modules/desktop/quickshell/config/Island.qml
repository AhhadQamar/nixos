// Transparent row that sizes itself around its children.

import QtQuick

Item {
    id: root

    property int padding: 4
    property alias spacing: row.spacing
    property alias layoutDirection: row.layoutDirection

    default property alias content: row.data
    // The row the children sit in, for a parent that draws something across
    // all of them (Workspaces.qml's ruler)
    readonly property Item track: row

    implicitHeight: Style.barHeight
    implicitWidth: row.implicitWidth + padding * 2

    Row {
        id: row

        anchors.centerIn: parent
        spacing: 2
    }
}
