import QtQuick
import Quickshell
import Quickshell.Io

// The notification centre's entry point: keeps the IPC commands and the bell's
// request alive and builds the panel window only while it is open. The log, do
// not disturb and snooze are in NotificationServer.qml, everything on screen in
// NotificationPanel.qml.
//
//   qs ipc call notifications toggle | open | close
//   qs ipc call notifications clear              empties the log
//   qs ipc call notifications dnd                do not disturb on / off
//   qs ipc call notifications dndfor <minutes>   silent for a while
//   qs ipc call notifications unread             how many arrived since it was last opened
Scope {
    LazyLoader {
        active: NotificationServer.shown

        NotificationPanel {}
    }

    // The bell in the bar, and a click on a "+N more" toast
    Connections {
        target: Panels

        function onToggleNotifications() {
            NotificationServer.toggleCenter();
        }
    }

    IpcHandler {
        target: "notifications"

        function toggle(): void {
            NotificationServer.toggleCenter();
        }

        function open(): void {
            NotificationServer.openCenter();
        }

        function close(): void {
            NotificationServer.closeCenter();
        }

        function clear(): void {
            NotificationServer.clearHistory();
        }

        function dnd(): void {
            NotificationServer.toggleDnd();
        }

        function dndfor(minutes: int): void {
            NotificationServer.dndFor(minutes);
        }

        function unread(): string {
            return String(NotificationServer.unread);
        }
    }
}
