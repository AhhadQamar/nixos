// Backend for the system updater: checks whether the flake inputs have moved,
// previews what an update would change, applies it, and keeps the small facts
// the bar icon and the panel both show. Nothing here touches the repo until
// you apply, and the periodic check never builds anything.

pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower

Singleton {
    id: root

    // ---- Settings -------------------------------------------------------
    readonly property string home: Quickshell.env("HOME")
    // Same variable your `rebuild` script and nh use
    readonly property string flakeDir: {
        const e = Quickshell.env("SYS_FLAKE") || Quickshell.env("NH_FLAKE");
        return e && e.length > 0 ? e : home + "/nixos";
    }
    // Name of the nixosConfigurations entry to build. Starts as a fallback and
    // is replaced by this machine's hostname once `hostname` answers.
    property string host: "licht"
    // Commit the new flake.lock (that file only, never pushed) after a good switch
    readonly property bool commitLock: true
    readonly property int checkEveryHours: 6
    readonly property int keepDays: 14
    // Scheduled checks are skipped on battery below this, and on metered
    // connections. A check you start yourself always runs.
    readonly property int minBatteryForCheck: 30
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
    // The next boot would not come up in the system that is running now
    // (after a test, or a boot-only switch)
    property bool bootDiffers: false
    property string kernelRunning: ""
    property int failedUnits: 0
    property var failedNames: []
    property double diskAvail: 0
    // Why the last scheduled check did not run, or ""
    property string skipped: ""
    property int dirtyFiles: 0
    // [{ id, time, version, kernel, current, running }], newest first
    property var generations: []
    property var logLines: []

    property bool applyArmed: false
    property bool cleanArmed: false
    // Deleting generations: one id waiting for its second press (or -1), the
    // "delete all but current" button, and what the running delete is for
    property int deleteArmed: -1
    property bool deleteAllArmed: false
    property string deleteKind: "all"
    // What the running apply does: switch | test | boot | rollback
    property string runMode: "switch"
    // While applying: "build" (can be cancelled) then "switch" (cannot)
    property string applyStage: "build"
    property bool bootArmed: false
    property bool rebootArmed: false
    // Free disk before a cleanup, to report how much it freed; -1 when idle
    property double freedFrom: -1
    // Generation number waiting for its second press, or -1
    property int rollbackArmed: -1
    property int rollbackTarget: 0
    // Set by cancel(); tells the exit handlers that a stop was asked for
    property bool cancelled: false
    // sha256 of the candidate lock the panel is showing, and what the package
    // preview was built from: that hash, or "local" for the repo as it is
    property string candidateHash: ""
    property string previewTag: ""
    property bool meteredAnswered: false
    property string notifiedSig: ""

    readonly property bool busy: phase !== "idle"
    // Checking and building only read; stopping them is safe. Once the root
    // step starts, switching is not.
    readonly property bool cancellable: phase === "checking" || phase === "building" || (phase === "applying" && applyStage === "build")
    readonly property var currentGen: generations.find(g => g.current) ?? null
    readonly property var runningGen: generations.find(g => g.running) ?? null
    // Everything but the current generation can go
    readonly property int removable: generations.filter(g => !g.current).length
    // Matches what preview() would build right now
    readonly property string currentTag: available ? candidateHash : "local"
    // A new kernel in the preview means the next boot differs from this one
    readonly property bool kernelChange: previewed && diff.some(r => /^linux(-\d|$)/.test(r.name))
    readonly property int count: changes.length
    readonly property bool available: count > 0
    readonly property string summary: {
        if (phase === "checking")
            return "Checking for updates…";
        if (phase === "building")
            return "Building…";
        if (phase === "applying") {
            if (runMode === "rollback")
                return "Switching to #" + rollbackTarget + "…";
            if (applyStage === "build")
                return "Building…";
            return runMode === "test" ? "Activating test build…" : (runMode === "boot" ? "Writing boot entry…" : "Switching…");
        }
        if (phase === "cleaning")
            return "Cleaning up…";
        if (error !== "")
            return error;
        const parts = [];
        if (available)
            parts.push(count + (count === 1 ? " input" : " inputs") + " behind");
        if (rebootPending)
            parts.push("reboot needed");
        else if (bootDiffers)
            parts.push("next boot differs");
        return parts.length > 0 ? parts.join(" · ") : "Up to date";
    }

    // ---- Actions --------------------------------------------------------
    function check() {
        if (busy)
            return;
        phase = "checking";
        error = "";
        skipped = "";
        cancelled = false;
        checkProc.running = true;
    }

    // The timer's version of check(): stays quiet when the machine is on a low
    // battery or a metered connection (a check can download changed inputs).
    function scheduledCheck() {
        if (busy)
            return;
        meteredAnswered = false;
        meteredProc.running = true;
    }

    function scheduledGo(metered) {
        if (busy)
            return;
        const bat = UPower.displayDevice;
        const onBattery = bat && bat.isPresent && bat.state === UPowerDeviceState.Discharging;
        const raw = bat ? bat.percentage : 1;
        const pct = Math.round(raw > 1 ? raw : raw * 100);
        if (onBattery && pct < minBatteryForCheck) {
            skipped = "battery at " + pct + "%";
            return;
        }
        if (metered) {
            skipped = "metered connection";
            return;
        }
        check();
    }

    // Stop a check or a build. Never applies to the switch itself.
    function cancel() {
        if (!cancellable)
            return;
        cancelled = true;
        if (phase === "checking")
            checkProc.running = false;
        else if (phase === "building")
            buildProc.running = false;
        else
            applyProc.running = false;
    }

    // Build the system and list what would change against the running one:
    // with the pending updates if there are any, otherwise with just your local
    // edits. Heavy, so manual.
    function preview() {
        if (busy)
            return;
        phase = "building";
        error = "";
        cancelled = false;
        logLines = [];
        diff = [];
        previewed = false;
        previewTag = currentTag;
        buildProc.running = true;
    }

    // Start building and activating. switch and boot take two presses, test one.
    function startRun(mode) {
        runMode = mode;
        applyStage = "build";
        applyArmed = false;
        bootArmed = false;
        phase = "applying";
        error = "";
        cancelled = false;
        logLines = [];
        applyProc.running = true;
    }

    // Two presses: the first arms, the second does it.
    function apply() {
        if (busy)
            return;
        if (!applyArmed) {
            applyArmed = true;
            bootArmed = false;
            armTimer.restart();
            return;
        }
        startRun("switch");
    }

    // Activate the new system without making it the boot default, like the
    // `ut` alias (nh os test). A reboot returns to the previous generation.
    function tryOut() {
        if (busy)
            return;
        startRun("test");
    }

    // Make it the boot default without activating it, like `ub` (nh os boot).
    function bootNext() {
        if (busy)
            return;
        if (!bootArmed) {
            bootArmed = true;
            applyArmed = false;
            armTimer.restart();
            return;
        }
        startRun("boot");
    }

    // Restart the machine. Two presses.
    function reboot() {
        if (busy)
            return;
        if (!rebootArmed) {
            rebootArmed = true;
            armTimer.restart();
            return;
        }
        rebootArmed = false;
        Quickshell.execDetached(["systemctl", "reboot"]);
    }

    // Delete one generation. Two presses.
    function deleteGen(id) {
        if (busy)
            return;
        if (deleteArmed !== id) {
            deleteArmed = id;
            armTimer.restart();
            return;
        }
        deleteArmed = -1;
        startClean(String(id));
    }

    // Delete every generation except the current one, then collect garbage.
    function deleteAll() {
        if (busy)
            return;
        if (!deleteAllArmed) {
            deleteAllArmed = true;
            armTimer.restart();
            return;
        }
        deleteAllArmed = false;
        startClean("all");
    }

    function startClean(kind) {
        deleteKind = kind;
        freedFrom = diskAvail;
        phase = "cleaning";
        error = "";
        logLines = [];
        cleanProc.running = true;
    }

    // Switch to an older generation. Two presses, like apply.
    function rollback(id) {
        if (busy)
            return;
        if (rollbackArmed !== id) {
            rollbackArmed = id;
            armTimer.restart();
            return;
        }
        rollbackArmed = -1;
        rollbackTarget = id;
        runMode = "rollback";
        applyStage = "switch";
        phase = "applying";
        error = "";
        logLines = [];
        rollbackProc.running = true;
    }

    // "today", "yesterday", "5 days ago"
    function age(ms) {
        const d = Math.floor((Date.now() - ms) / 86400000);
        if (d <= 0)
            return "today";
        return d === 1 ? "yesterday" : d + " days ago";
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
        startClean("old");
    }

    // "1.4 GB"
    function fmtBytes(n) {
        const u = ["B", "KB", "MB", "GB", "TB"];
        let i = 0;
        let v = n;
        while (v >= 1024 && i < u.length - 1) {
            v /= 1024;
            i++;
        }
        return (i === 0 ? Math.round(v) : v.toFixed(v < 10 ? 1 : 0)) + " " + u[i];
    }

    function refreshMeta() {
        metaProc.running = true;
    }

    // ---- Helpers --------------------------------------------------------
    function pushLog(line) {
        if (phase === "applying" && line.startsWith("==> activating"))
            applyStage = "switch";
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
        if (cancelled) {
            cancelled = false;
            return;
        }
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
        const h = text.match(/###HASH ([0-9a-f]{64})/);
        candidateHash = h ? h[1] : "";
        // A preview stays while it is still of what would be built now, so a
        // background check cannot wipe what you are reading.
        if (previewTag !== currentTag) {
            previewed = false;
            diff = [];
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
        const names = [];
        for (const line of text.split("\n")) {
            if (line.startsWith("reboot="))
                rebootPending = line.endsWith("1");
            else if (line.startsWith("bootdiff="))
                bootDiffers = line.endsWith("1");
            else if (line.startsWith("kernel="))
                kernelRunning = line.slice(7).trim();
            else if (line.startsWith("disk="))
                diskAvail = parseFloat(line.slice(5).split("|")[1]) || 0;
            else if (line.startsWith("U|"))
                names.push(line.slice(2).trim());
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
                    current: p[5] === "1",
                    running: p[6] === "1"
                });
            }
        }
        failedNames = names;
        generations = gens.sort((x, y) => y.id - x.id);
        // A cleanup just finished: say how much room it made
        if (freedFrom >= 0) {
            const d = diskAvail - freedFrom;
            freedFrom = -1;
            const msg = d > 0 ? "Freed " + fmtBytes(d) : "Nothing to free";
            pushLog("==> " + msg);
            notify("Cleanup finished", msg);
        }
    }

    function finish(ok, doneTitle, failMessage, code) {
        const cleaning = phase === "cleaning";
        phase = "idle";
        if (ok) {
            // A finished cleanup reports once meta knows how much it freed
            if (!cleaning)
                notify(doneTitle, "");
        } else {
            freedFrom = -1;
            // pkexec: 126 = dialog dismissed, 127 = not authorised
            if (code === 126 || code === 127) {
                error = "Authentication cancelled";
            } else {
                error = code === 3 ? "The update changed since the check; check again" : (code === 4 ? "Root helper not installed; see the Log tab" : failMessage);
                notify(failMessage, "Open the updater and check the Log tab.");
            }
        }
        refreshMeta();
    }

    Component.onCompleted: {
        hostProc.running = true;
        refreshMeta();
    }

    // ---- Schedule -------------------------------------------------------
    // First check a little after login so it doesn't compete with startup
    Timer {
        interval: 90000
        running: true
        onTriggered: root.scheduledCheck()
    }
    Timer {
        interval: root.checkEveryHours * 3600000
        running: true
        repeat: true
        onTriggered: root.scheduledCheck()
    }
    // A pending "press again" lapses after a few seconds
    Timer {
        id: armTimer

        interval: 4000
        onTriggered: {
            root.applyArmed = false;
            root.bootArmed = false;
            root.rebootArmed = false;
            root.cleanArmed = false;
            root.rollbackArmed = -1;
            root.deleteArmed = -1;
            root.deleteAllArmed = false;
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
        id: hostProc

        command: ["hostname"]
        stdout: StdioCollector {
            onStreamFinished: {
                const h = text.trim();
                if (h !== "")
                    root.host = h;
            }
        }
    }

    // NetworkManager's own verdict: 1 = metered, 3 = probably metered
    Process {
        id: meteredProc

        command: ["busctl", "get-property", "org.freedesktop.NetworkManager", "/org/freedesktop/NetworkManager", "org.freedesktop.NetworkManager", "Metered"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.meteredAnswered = true;
                const m = text.match(/u\s+(\d)/);
                root.scheduledGo(m !== null && (m[1] === "1" || m[1] === "3"));
            }
        }
        // No busctl or no NetworkManager: treat the connection as unmetered
        onExited: if (!root.meteredAnswered) {
            root.meteredAnswered = true;
            root.scheduledGo(false);
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

        command: ["bash", Quickshell.shellPath("sysupd/build.sh"), root.flakeDir, root.available ? root.newLock : "", root.work + "/preview", root.host]
        stdout: SplitParser {
            onRead: data => root.pushLog(data)
        }
        onExited: (exitCode, exitStatus) => {
            if (root.cancelled) {
                root.cancelled = false;
                root.phase = "idle";
                root.pushLog("Cancelled.");
                return;
            }
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

        command: ["bash", Quickshell.shellPath("sysupd/apply.sh"), root.flakeDir, root.available ? root.newLock : "", root.work, root.host, root.commitLock ? "1" : "0", root.changes.map(c => c.name + " " + c.from + " -> " + c.to).join("\n"), root.available ? root.candidateHash : "", root.runMode]
        stdout: SplitParser {
            onRead: data => root.pushLog(data)
        }
        onExited: (exitCode, exitStatus) => {
            if (root.cancelled) {
                root.cancelled = false;
                // A Cancel that arrived after the build is ignored by the
                // script, which then finishes the switch: report it normally
                if (root.applyStage === "build") {
                    root.phase = "idle";
                    root.pushLog("Cancelled.");
                    return;
                }
            }
            // A test leaves flake.lock alone, so the update is still pending
            if (exitCode === 0 && root.runMode !== "test") {
                root.changes = [];
                root.previewed = false;
                root.diff = [];
            }
            const m = root.runMode;
            root.finish(exitCode === 0, m === "test" ? "System activated for testing" : (m === "boot" ? "Boot entry updated, reboot to use it" : "System updated"), m === "test" ? "Test failed" : (m === "boot" ? "Boot setup failed" : "Switch failed"), exitCode);
        }
    }

    Process {
        id: rollbackProc

        command: ["bash", Quickshell.shellPath("sysupd/rollback.sh"), String(root.rollbackTarget)]
        stdout: SplitParser {
            onRead: data => root.pushLog(data)
        }
        onExited: (exitCode, exitStatus) => root.finish(exitCode === 0, "Switched to generation " + root.rollbackTarget, "Rollback failed", exitCode)
    }

    Process {
        id: cleanProc

        command: ["bash", Quickshell.shellPath("sysupd/clean.sh"), root.deleteKind, String(root.keepDays)]
        stdout: SplitParser {
            onRead: data => root.pushLog(data)
        }
        onExited: (exitCode, exitStatus) => root.finish(exitCode === 0, "", "Delete failed", exitCode)
    }
}
