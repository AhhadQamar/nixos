import QtQuick
import Quickshell
import Quickshell.Io

// The downloads panel's entry point: keeps the IPC commands and the bar's hooks
// alive, and builds the panel window only while it is open. Everything that does
// work is in Downloads.qml, everything on screen in DownloadPanel.qml.
//
//   qs ipc call downloads toggle | open | close
//   qs ipc call downloads add <links...>        links, magnets, .torrent paths, curl commands
//   qs ipc call downloads addx '{"url": "...", "referer": "...", "cookie": "...", "headers": [...], "out": "name", "dir": "sub/folder"}'
//   qs ipc call downloads grab <video link>     always yt-dlp
//   qs ipc call downloads schedule on|off|toggle
//   qs ipc call downloads whendone none|suspend|hibernate|poweroff|cancel   (cancelaction also works)
//   qs ipc call downloads usage                 this month's data
//   qs ipc call downloads pause | resume        everything
Scope {
    Component.onCompleted: Downloads.start()

    LazyLoader {
        active: Downloads.shown

        DownloadPanel {}
    }

    // The bar's network disc: a drop adds, a right click opens
    Connections {
        target: DownloadStatus

        function onAddRequested(text) {
            Downloads.addFromBar(text);
        }

        function onToggleRequested() {
            Downloads.toggle();
        }
    }

    IpcHandler {
        target: "downloads"

        function toggle(): void {
            Downloads.toggle();
        }

        function open(): void {
            Downloads.open();
        }

        function close(): void {
            Downloads.close();
        }

        // Adds follow the same rules as the panel's add pill: a video page goes to
        // yt-dlp, a file to aria2. Only the pill shows a preview first.
        function add(link: string): string {
            if (link.trim() === "")
                return "error: nothing to add";
            const n = Downloads.addText(link, Downloads.saveDir(), false);
            return n > 0 ? "ok: " + n : "error: " + (Downloads.note || "nothing added");
        }

        function addx(spec: string): string {
            return Downloads.addSpec(spec);
        }

        function grab(link: string): string {
            return Downloads.grabLink(link) > 0 ? "queued" : "skipped";
        }

        function schedule(state: string): string {
            if (state === "on" || state === "off" || state === "toggle")
                Downloads.setSchedule(state === "toggle" ? !Downloads.schedOn : state === "on");
            return Downloads.schedOn ? "on" : "off";
        }

        function whendone(mode: string): string {
            if (mode === "cancel") {
                Downloads.cancelAction();
                return "ok";
            }
            return Downloads.setWhenDone(mode);
        }

        function cancelaction(): void {
            Downloads.cancelAction();
        }

        function usage(): string {
            return Downloads.usageSummary();
        }

        function pause(): void {
            Downloads.pauseEverything();
        }

        function resume(): void {
            Downloads.resumeAll();
        }
    }
}
