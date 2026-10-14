import QtQuick

// The wash every panel puts over the screen: Screenshot's dim, so a panel
// arriving looks the same whichever one it is. The background colour with a
// breath of the accent, fading in over the first half of `reveal`.
//
// Put it in a full-screen window, under the stage. With `closes` on, a click
// on it emits `clicked` (connect that to the panel's close()); with it off
// it lets clicks through to whatever the panel already does with them.
Rectangle {
    id: dim

    property real reveal: 0
    // How dark at full strength. Screenshot uses 0.55.
    property real strength: 0.55
    property bool closes: false

    signal clicked

    anchors.fill: parent
    visible: color.a > 0.002
    color: Qt.alpha(Qt.tint(Colors.background, Qt.alpha(Colors.accent, 0.08)), strength * Math.max(0, Math.min(1, reveal * 2)))

    MouseArea {
        anchors.fill: parent
        enabled: dim.closes
        onClicked: dim.clicked()
    }
}
