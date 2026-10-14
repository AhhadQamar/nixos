// A picture, cropped to a circle (or to whatever corner radius it is given).
// Used for a notification's own image in the toasts and in the centre.

import QtQuick
import QtQuick.Effects

Item {
    id: ph

    property url source
    property real radius: 9
    // Image.Null / Loading / Ready / Error, so a caller can fall back to an
    // icon or a letter when the picture cannot be loaded
    readonly property int status: img.status

    Image {
        id: img

        anchors.fill: parent
        source: ph.source
        fillMode: Image.PreserveAspectCrop
        sourceSize.width: 128
        sourceSize.height: 128
        asynchronous: true
        visible: false
    }

    Item {
        id: mask

        anchors.fill: parent
        visible: false
        layer.enabled: true

        Rectangle {
            anchors.fill: parent
            radius: ph.radius
            color: "black"
        }
    }

    MultiEffect {
        anchors.fill: parent
        source: img
        maskEnabled: true
        maskSource: mask
    }
}
