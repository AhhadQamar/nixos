// Backend for the system updater: checks whether the flake inputs have moved,
// previews what an update would change, applies it, and keeps the small facts
// the bar icon and the panel both show. Nothing here touches the repo until
// you apply, and the periodic check never builds anything.

pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    // ---- Settings -------------------------------------------------------
    readonly property string home: Quickshell.env("HOME")
    // Same variable your `rebuild` script and nh use
    readonly property string flakeDir: {
        const e = Quickshell.env("SYS_FLAKE") || Quickshell.env("NH_FLAKE");
        return e && e.length > 0 ? e : home + "/nixos";
    }
    readonly property string host: "licht"
    readonly property int checkEveryHours: 6
    readonly property int keepDays: 14
    readonly property string work: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/sysupd"
    readonly property string newLock: work + "/flake.lock"

    // ---- State ----------------------------------------------------------
    // idle | checking | building | applying | cleaning
    property string phase: "idle"
    property string error: ""
    property string lastChecked: ""

    // [{ name, from, to, days }] flake inputs that would move
    property var changes: []
    // Filled by preview(): [{ name, change, size, kind: up|add|rem }]
    property var diff: []
    property bool previewed: false
    property int upgraded: 0
    property int added: 0
    property int removed: 0

    property bool rebootPending: false
    property int failedUnits: 0
    property int dirtyFiles: 0
    // [{ id, time, version, kernel, current }], newest first
    property var generations: []
    property var logLines: []

    property bool applyArmed: false
    property bool cleanArmed: false
    property string notifiedSig: ""

    readonly property bool busy: phase !== "idle"
    readonly property int count: changes.length
    readonly property bool available: count > 0
    readonly property string summary: {
        if (phase === "checking")
            return "Checking for updates…";
        if (phase === "building")
            return "Building…";
        if (phase === "applying")
            return "Switching…";
        if (phase === "cleaning")
            return "Cleaning up…";
        if (error !== "")
            return error;
        const parts = [];
        if (available)
            parts.push(count + (count === 1 ? " input" : " inputs") + " behind");
        if (rebootPending)
            parts.push("reboot needed");
        return parts.length > 0 ? parts.join(" · ") : "Up to date";
    }

    // ---- Actions --------------------------------------------------------
    function check() {
        if (busy)
            return;
        phase = "checking";
        error = "";
        previewed = false;
        diff = [];
        checkProc.running = true;
    }

    // Build the updated system and list what would change. Heavy, so manual.
    function preview() {
        if (busy || !available)
            return;
        phase = "building";
        error = "";
        logLines = [];
        diff = [];
        previewed = false;
        buildProc.running = true;
    }

    // Two presses: the first arms, the second does it.
    function apply() {
        if (busy)
            return;
        if (!applyArmed) {
            applyArmed = true;
            armTimer.restart();
            return;
        }
        applyArmed = false;
        phase = "applying";
        error = "";
        logLines = [];
        applyProc.running = true;
    }

    function collect() {
        if (busy)
            return;
        if (!cleanArmed) {
            cleanArmed = true;
            armTimer.restart();
            return;
        }
        cleanArmed = false;
        phase = "cleaning";
        error = "";
        logLines = [];
        gcProc.running = true;
    }

    function refreshMeta() {
        metaProc.running = true;
    }

    // ---- Helpers --------------------------------------------------------
    function pushLog(line) {
        logLines = logLines.concat([line]).slice(-300);
    }

    function notify(title, body) {
        Quickshell.execDetached(["notify-send", "-a", "System", "-i", "system-software-update", title, body]);
    }

    // Which root inputs of the flake moved between two lock files
    function lockChanges(a, b) {
        const out = [];
        const ra = a.nodes[a.root] || {};
        const rb = b.nodes[b.root] || {};
        for (const name of Object.keys(rb.inputs || {})) {
            const kb = rb.inputs[name];
            const ka = (ra.inputs || {})[name];
            // "follows" entries are arrays; the input they point at is listed itself
            if (typeof kb !== "string")
                continue;
            const nb = (b.nodes[kb] || {}).locked;
            const na = typeof ka === "string" ? (a.nodes[ka] || {}).locked : undefined;
            if (!nb || (na && na.rev === nb.rev))
                continue;
            out.push({
                name: name,
                from: na && na.rev ? na.rev.slice(0, 7) : "new",
                to: nb.rev ? nb.rev.slice(0, 7) : "?",
                days: na && na.lastModified && nb.lastModified ? Math.max(0, Math.round((nb.lastModified - na.lastModified) / 86400)) : 0
            });
        }
        return out;
    }

    // Parse `nix store diff-closures`: "name: 1.0 → 2.0, +3.5 KiB"
    function parseDiff(text) {
        const rows = [];
        let up = 0, add = 0, rem = 0;
        for (const line of text.split("\n")) {
            const i = line.indexOf(": ");
            if (i < 1)
                continue;
            let rest = line.slice(i + 2);
            let size = "";
            const m = rest.match(/,\s*([+-][\d.]+\s*[KMGT]?i?B)\s*$/);
            if (m) {
                size = m[1];
                rest = rest.slice(0, m.index);
            }
            let kind = "up";
            if (rest.startsWith("∅ →")) {
                kind = "add";
                add++;
            } else if (rest.endsWith("→ ∅")) {
                kind = "rem";
                rem++;
            } else {
                up++;
            }
            rows.push({
                name: line.slice(0, i),
                change: rest,
                size: size,
                kind: kind
            });
        }
        return {
            rows: rows,
            up: up,
            add: add,
            rem: rem
        };
    }

    function onCheck(text) {
        phase = "idle";
        lastChecked = Qt.formatDateTime(new Date(), "h:mm AP");
        const e = text.indexOf("###ERR");
        if (e >= 0) {
            error = "Check failed: " + text.slice(e + 6).trim().slice(0, 140);
            return;
        }
        const o = text.indexOf("###OLD");
        const n = text.indexOf("###NEW");
        if (o < 0 || n < 0) {
            error = "Check failed: nothing came back";
            return;
        }
        try {
            changes = lockChanges(JSON.parse(text.slice(o + 6, n)), JSON.parse(text.slice(n + 6)));
        } catch (err) {
            error = "Check failed: could not read flake.lock";
            return;
        }
        // One toast per distinct set of updates, not one per check
        const sig = changes.map(c => c.name + c.to).join(",");
        if (available && sig !== notifiedSig) {
            notifiedSig = sig;
            notify("Updates available", count + (count === 1 ? " flake input has" : " flake inputs have") + " newer versions");
        }
        refreshMeta();
    }

    function onMeta(text) {
        const gens = [];
        for (const line of text.split("\n")) {
            if (line.startsWith("reboot="))
                rebootPending = line.endsWith("1");
            else if (line.startsWith("failed="))
                failedUnits = parseInt(line.slice(7)) || 0;
            else if (line.startsWith("dirty="))
                dirtyFiles = parseInt(line.slice(6)) || 0;
            else if (line.startsWith("G|")) {
                const p = line.split("|");
                gens.push({
                    id: parseInt(p[1]),
                    time: parseInt(p[2]) * 1000,
                    version: p[3],
                    kernel: p[4],
                    current: p[5] === "1"
                });
            }
        }
        generations = gens.sort((x, y) => y.id - x.id);
    }

    function finish(ok, doneTitle, failMessage, code) {
        phase = "idle";
        if (ok) {
            notify(doneTitle, "");
        } else {
            // pkexec: 126 = dialog dismissed, 127 = not authorised
            error = code === 126 || code === 127 ? "Authentication cancelled" : failMessage;
            notify(failMessage, "Open the updater and check the Log tab.");
        }
        refreshMeta();
    }

    Component.onCompleted: refreshMeta()

    // ---- Schedule -------------------------------------------------------
    // First check a little after login so it doesn't compete with startup
    Timer {
        interval: 90000
        running: true
        onTriggered: root.check()
    }
    Timer {
        interval: root.checkEveryHours * 3600000
        running: true
        repeat: true
        onTriggered: root.check()
    }
    // A pending "press again" lapses after a few seconds
    Timer {
        id: armTimer

        interval: 4000
        onTriggered: {
            root.applyArmed = false;
            root.cleanArmed = false;
        }
    }

    // ---- Processes ------------------------------------------------------
    Process {
        id: checkProc

        command: ["bash", Quickshell.shellPath("sysupd/check.sh"), root.flakeDir, root.newLock]
        stdout: StdioCollector {
            onStreamFinished: root.onCheck(text)
        }
    }

    Process {
        id: metaProc

        command: ["bash", Quickshell.shellPath("sysupd/meta.sh"), root.flakeDir]
        stdout: StdioCollector {
            onStreamFinished: root.onMeta(text)
        }
    }

    Process {
        id: buildProc

        command: ["bash", Quickshell.shellPath("sysupd/build.sh"), root.flakeDir, root.newLock, root.work + "/preview", root.host]
        stdout: SplitParser {
            onRead: data => root.pushLog(data)
        }
        onExited: (exitCode, exitStatus) => {
            if (exitCode === 0)
                diffProc.running = true;
            else
                root.finish(false, "", "Build failed", exitCode);
        }
    }

    Process {
        id: diffProc

        command: ["nix", "store", "diff-closures", "/run/current-system", root.work + "/preview"]
        stdout: StdioCollector {
            onStreamFinished: {
                const d = root.parseDiff(text);
                root.diff = d.rows;
                root.upgraded = d.up;
                root.added = d.add;
                root.removed = d.rem;
                root.previewed = true;
                root.phase = "idle";
            }
        }
    }

    Process {
        id: applyProc

        command: ["bash", Quickshell.shellPath("sysupd/apply.sh"), root.flakeDir, root.available ? root.newLock : "", root.work, root.host]
        stdout: SplitParser {
            onRead: data => root.pushLog(data)
        }
        onExited: (exitCode, exitStatus) => {
            if (exitCode === 0) {
                root.changes = [];
                root.previewed = false;
                root.diff = [];
            }
            root.finish(exitCode === 0, "System updated", "Switch failed", exitCode);
        }
    }

    Process {
        id: gcProc

        command: ["pkexec", "/run/current-system/sw/bin/nix-collect-garbage", "--delete-older-than", root.keepDays + "d"]
        stdout: SplitParser {
            onRead: data => root.pushLog(data)
        }
        onExited: (exitCode, exitStatus) => root.finish(exitCode === 0, "Old generations removed", "Cleanup failed", exitCode)
    }
}
