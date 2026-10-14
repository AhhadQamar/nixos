// The fade-and-grow every panel plays when it opens. Call restart() on it.
// Uses the shared motion tokens (see Style.qml), so it moves like everything else.

import QtQuick

ParallelAnimation {
    id: root

    property Item target
    property real fromScale: 0.97

    NumberAnimation {
        target: root.target
        property: "opacity"
        from: 0
        to: 1
        duration: Style.fadeMs
        easing.type: Style.easeMove
    }

    NumberAnimation {
        target: root.target
        property: "scale"
        from: root.fromScale
        to: 1
        duration: Style.fadeMs
        easing.type: Style.easeMove
    }
}
