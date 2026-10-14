// Tiny message bus between the bar and panels that live elsewhere in the shell.
// The bell in the bar asks, NotificationCenter listens.

pragma Singleton
import QtQuick
import Quickshell

Singleton {
    signal toggleNotifications
    signal toggleUpdater
    signal toggleMusic
    // The clock popup (ClockPopup.qml): the bar on the focused screen answers
    signal toggleClock
    signal openClock(string which)
    signal closeClock
    // A panel just opened; every other panel closes (see PanelLink.qml)
    signal opened(string who)
}
