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
    signal opened(string who, var source)

    // Bar popups that are open right now (see PanelLink.barPopup). The bar
    // asks the compositor for keyboard focus only while this is true, so
    // typing and Escape reach the popup but the bar never steals focus from
    // your windows the rest of the time.
    property var barPopups: ({})
    property bool barPopupOpen: false

    function setBarPopup(name, open) {
        const m = Object.assign({}, barPopups);
        if (open)
            m[name] = true;
        else
            delete m[name];
        barPopups = m;
        barPopupOpen = Object.keys(m).length > 0;
    }
}
