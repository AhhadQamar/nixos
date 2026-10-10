// Tiny message bus between the bar and panels that live elsewhere in the shell.
// The bell in the bar asks, NotificationCenter listens.

pragma Singleton
import QtQuick
import Quickshell

Singleton {
    signal toggleNotifications
    signal toggleUpdater
    signal toggleMusic
}
