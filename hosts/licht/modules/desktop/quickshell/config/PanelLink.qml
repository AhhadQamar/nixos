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

import QtQuick
import Quickshell

Scope {
    id: link

    required property var win
    required property string name
    property int idleMs: 0
    property bool hovered: false
    property bool busy: false

    Timer {
        interval: link.idleMs
        running: link.idleMs > 0 && link.win.visible && !link.hovered && !link.busy
        onTriggered: link.win.close()
    }

    Connections {
        target: link.win

        function onVisibleChanged() {
            if (link.win.visible)
                Panels.opened(link.name);
        }
    }

    Connections {
        target: Panels

        function onOpened(who) {
            if (who !== link.name && link.win.visible)
                link.win.close();
        }
    }
}
