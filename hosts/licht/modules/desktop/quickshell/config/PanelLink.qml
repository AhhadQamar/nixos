// Keeps one overlay panel open at a time. Put one inside each panel:
//   PanelLink { win: myPanel; name: "myPanel" }
// When the panel opens it tells the others (Panels.opened), and it closes
// itself when another one does.
//
// Bar popups can also close themselves when left alone:
//   PanelLink { win: pop; name: "x"; idleMs: Style.popupIdleMs; hovered: hover.hovered }
// The countdown runs while the popup is open and is held (and starts again
// from zero) while the pointer is over it (`hovered`) or it is `busy`
// (a password being typed, something being joined). idleMs 0 never closes.
// Keys and the wheel are activity too: a popup used from the keyboard calls
// `poke()` so the countdown starts again from zero.

import QtQuick
import Quickshell

Scope {
    id: link

    required property var win
    required property string name
    property int idleMs: 0
    property bool hovered: false
    property bool busy: false
    // A popup hanging from the bar: while it is open the bar takes keyboard
    // focus (see Bar.qml), so a text field in it can be typed into
    property bool barPopup: false

    readonly property bool barOpen: barPopup && win.visible
    onBarOpenChanged: Panels.setBarPopup(String(link), barOpen)
    Component.onDestruction: if (barPopup)
        Panels.setBarPopup(String(link), false)

    function poke() {
        idle.restart();
    }

    Timer {
        id: idle

        interval: link.idleMs
        running: link.idleMs > 0 && link.win.visible && !link.hovered && !link.busy
        onTriggered: link.win.close()
    }

    Connections {
        target: link.win

        function onVisibleChanged() {
            if (link.win.visible)
                Panels.opened(link.name, link);
        }
    }

    Connections {
        target: Panels

        function onOpened(who, source) {
            // Another panel, or the same popup on another screen's bar
            if ((who !== link.name || source !== link) && link.win.visible)
                link.win.close();
        }
    }
}
