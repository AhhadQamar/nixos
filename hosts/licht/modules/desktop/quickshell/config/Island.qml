// Transparent row that sizes itself around its children.

import QtQuick

Item {
    id: root

    property int padding: 4
    property alias spacing: row.spacing
    property alias layoutDirection: row.layoutDirection

    default property alias content: row.data

    implicitHeight: Style.barHeight
    implicitWidth: row.implicitWidth + padding * 2

    Row {
        id: row

        anchors.centerIn: parent
        spacing: 2
    }
}
