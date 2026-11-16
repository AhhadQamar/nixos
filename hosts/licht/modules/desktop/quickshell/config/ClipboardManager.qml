import QtQuick
import Quickshell
import Quickshell.Io

// The clipboard panel's entry point: keeps the IPC commands alive and builds the
// panel window only while it is open. Everything that does work is in
// ClipStore.qml, everything on screen in ClipPanel.qml.
//
//   qs ipc call clipboard toggle | open | close
//   qs ipc call clipboard clear                 clears the history, pins stay
//   qs ipc call clipboard pin                   pins the newest entry
//   qs ipc call clipboard incognito on|off|toggle   stops keeping new copies
Scope {
    Component.onCompleted: ClipStore.start()

    LazyLoader {
        active: ClipStore.shown

        ClipPanel {}
    }

    IpcHandler {
        target: "clipboard"

        function toggle(): void {
            ClipStore.toggle();
        }

        function open(): void {
            ClipStore.open();
        }

        function close(): void {
            ClipStore.close();
        }

        function clear(): void {
            ClipStore.wipe();
        }

        function pin(): string {
            return ClipStore.pinNewest();
        }

        function incognito(mode: string): string {
            if (mode === "on" || mode === "off" || mode === "toggle")
                ClipStore.setPaused(mode === "toggle" ? !ClipStore.paused : mode === "on");
            return ClipStore.paused ? "on" : "off";
        }
    }
}
