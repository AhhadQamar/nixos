// What the bar's network disc (SystemStats.qml) and the downloads panel
// (DownloadManager.qml) tell each other. The panel writes what is going on; the
// disc reads it, and asks the panel to add things or to open.

pragma Singleton
import QtQuick
import Quickshell

Singleton {
    // Downloads running now (aria2 and video grabs), those waiting, and the speed
    property int active: 0
    property int waiting: 0
    property real speed: 0

    // The disc asks: add what was dropped on it, or open the panel
    signal addRequested(string text)
    signal toggleRequested

    // The panel answers an add: how many downloads it made (0 = none)
    signal added(int count)
}
