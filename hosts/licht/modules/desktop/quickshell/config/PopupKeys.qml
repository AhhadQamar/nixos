// Escape closes a bar popup. Put one inside the popup next to its PanelLink:
//   PopupKeys { id: popupKeys; win: pop }
// It takes focus each time the popup opens, so Escape works with nothing
// else focused. A text field inside keeps its own focus and Escape handler;
// when it is done, give focus back with popupKeys.forceActiveFocus().

import QtQuick

Item {
    id: keys

    required property var win

    anchors.fill: parent
    focus: win.visible
    Keys.onEscapePressed: win.close()

    // Focus set before the window is shown can be lost; ask again once it is
    Connections {
        target: keys.win

        function onVisibleChanged() {
            if (keys.win.visible)
                Qt.callLater(keys.forceActiveFocus);
        }
    }
}
