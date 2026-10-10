// Shared sizes and surface colours for the bar.

pragma Singleton
import QtQuick
import Quickshell

Singleton {
    readonly property string fontFamily: "JetBrainsMono Nerd Font"

    readonly property int barHeight: 44
    readonly property int barRadius: 16
    readonly property int barGap: 8
    readonly property int itemHeight: 28

    readonly property color surface: Qt.alpha(Colors.background, 0.92)
    readonly property color outline: Qt.alpha(Colors.foreground, 0.1)

    readonly property color hoverFill: Qt.alpha(Colors.foreground, 0.09)
}
