// SystemUpdater.qml
// The system updater on the launcher's dial: the same borderless stage rising
// from the bottom edge, the same fine ruler, glass discs and accent underline.
// State and actions live in Updater.qml; this file is only the interface.
//
// The three tabs are three views of the same dial, switched at the foot
// (Updates / Generations / Log):
//   Updates      the first disc is the System disc (the old header orb: its
//                colour and glyph sum up the state, and it spins while
//                something runs). Then one disc per flake input that moved,
//                ringed with how many days it was behind. After a preview a
//                small gap, and one disc per package change: up, added or
//                removed. The middle reads the selected disc out: the summary
//                and the heads-up lines (reboot needed, next boot differs, a
//                new kernel, uncommitted changes, failed units), an input's
//                from -> to, or a package's change and size.
//                Under it: Preview, Test, Boot, Apply and, when it applies,
//                Reboot.
//   Generations  one disc per generation, opening on the current one. The
//                middle reads out its date, age, version and kernel. Under it:
//                Switch to and Delete for the selected one, then Remove older
//                than N days and Delete all but current.
//   Log          the System disc alone, and the build or switch output as the
//                readout (it follows the end). Under it: Copy log.
// The ruler is the state. A bright patch scans along it while something runs
// (the head line says which stage, and whether it can still be cancelled), it
// flushes red after an error, and it fills green from the middle when a run
// ends well. Updater.qml reports a phase, not a percentage, so the ruler does
// not pretend to be a progress bar.
//   qs ipc call sysupd toggle | open | close | check | preview | apply | test | boot | cancel
// Keys: r check   p preview   a apply (press twice)   t test   b boot (press
//       twice)   c cancel   1 2 3 tabs   / help   esc close (help first)
//       ← → ↑ ↓ (h j k l, Tab, Ctrl+N / Ctrl+P) and the wheel turn the dial
//       PageUp / PageDown jump 5   Home / End first / last
//       Shift+← / Shift+→ jump between the system, the inputs and the packages
//       Enter switches to the selected generation, Delete deletes it (both
//       press twice, like their buttons)
// Holding r, p, a, t, b, c, 1 2 3, /, Enter or Delete does not repeat: one
// press, one thing (a held a would otherwise arm and then run the switch).
// Mouse: click a disc to bring it to the middle, scroll turns the dial, the
//        buttons under the readout do the rest. Switch, Boot, Apply, Reboot,
//        Delete and the two clean-ups need a second press.
//
// Like the launcher it arrives as a rainbow: the discs swing in from the left
// over a tight dome and unfurl into the calm dial. Closing plays it in
// reverse. A deleted generation shrinks away while its neighbours close the
// gap. A build or a switch still brings you to the Log by itself.
//
// Like the other dials the window has one size and the stage inside it grows
// and shrinks with what is shown, so the dial glides up and down; only the
// stage takes the mouse, the rest of the screen reaches other windows. The
// keyboard is the updater's until it closes (Esc). Only the discs near the
// middle exist, so hundreds of packages cost nothing.

import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland

PanelWindow {
    id: panel

    // Opens on the monitor that has focus (set in open())
    property var targetScreen: Focus.screen

    // ---- Settings -------------------------------------------------------
    readonly property real screenW: targetScreen ? targetScreen.width : 1920
    readonly property real screenH: targetScreen ? targetScreen.height : 1080
    readonly property int stageW: Math.min(780, Math.round(screenW * 0.9))
    // The window is this tall always; the stage inside it grows and shrinks
    // with what is shown (bodyH), so the dial glides up and down instead of
    // the layer surface being resized.
    readonly property int winH: Math.min(680, Math.round(screenH * 0.9))
    readonly property int topY: 56
    readonly property int ruleDrop: 46
    readonly property int ruleY: topY + ruleDrop
    readonly property real dialR: 900
    // The dome the dial starts as when it opens (and ends as when it closes)
    readonly property real rainbowR: 360
    // Pixels between discs, and the extra gap (in discs) before the packages
    readonly property real stepPx: 76
    readonly property real groupGap: 0.45
    readonly property int discSize: 48
    readonly property int selectedSize: 68
    readonly property int tickGap: 12
    readonly property int tickN: Math.ceil(stageW / tickGap) + 24
    // Discs kept on either side of the selected one
    readonly property int windowN: 11
    // How long a deleted disc takes to shrink away, in ms
    readonly property int collapseMs: 200
    // The height of the log under the dial, and the width of the readout
    readonly property int logH: 176
    readonly property int readW: Math.min(520, stageW - 48)
    // How long the green stays on the ruler after a run ends well
    readonly property int holdMs: Style.sweepMs + Style.ambientMs

    // ---- State ----------------------------------------------------------
    // 0 = updates, 1 = generations, 2 = log
    property int tab: 0
    property bool isOpen: false
    // 0 = hidden below the edge, 1 = in place
    property real reveal: 0
    // Slots the dial is swung to the left while arriving (and right when leaving)
    property real spinIn: 0
    // 1 = tight rainbow dome, 0 = the resting dial
    property real fan: 1
    // A slow pulse (0..1) for the selected disc's ring
    property real breath: 0
    // 0 -> 1 each time the selection, tab or help changes: the readout fades up
    property real swap: 1
    // The key / action cheat sheet (the "/" button), shown instead of the readout
    property bool help: false
    // Whether the dial glides to a new selection (off while opening and for long jumps)
    property bool animateView: false
    // Wheel movement not yet turned into a step (a touchpad sends many small ones)
    property real wheelAcc: 0
    // The highlighted disc of the Updates and Generations dials, by id, so it
    // stays put while discs come and go (the Log dial only has the System disc)
    property string selUpd: "sys"
    property string selGen: ""
    // Generations that were just deleted and are shrinking away: { id, d, pos }
    property var ghosts: []
    // The generations as they were, to tell which ones just went
    property var genSnap: []
    // The phase before this one, to tell a run that ended from one that began
    property string lastPhase: "idle"
    // A run ended well: green on the ruler for a moment
    property bool succeeded: false
    // Where the scan along the ruler is (-1 = far left, 1 = far right)
    property real scan: -1

    // Radius of the dial right now: curvature eases from the dome to the dial
    readonly property real dialNow: 1 / (1 / dialR + (1 / rainbowR - 1 / dialR) * fan)

    // The one colour and glyph that sum up the state (the System disc)
    readonly property color tint: Updater.error !== "" ? Colors.critical : (Updater.busy || Updater.available ? Colors.accent : Colors.success)
    readonly property int glyph: Updater.busy ? 0xF04E6 : (Updater.error !== "" ? 0xF05D6 : (Updater.available ? 0xF06B0 : 0xF05E1))
    // The colour of the moment, for the ruler: green once a run worked, red
    // after an error, otherwise the accent
    property color tone: succeeded ? Colors.success : (Updater.error !== "" ? Colors.critical : Colors.accent)
    // 0..1 red over the whole ruler while an error stands
    property real flush: Updater.error !== "" ? 1 : 0
    // 0..1 how far the green has filled the ruler outward from the middle
    property real okFill: succeeded ? 1 : 0
    // 0..1 how visible the scan is (only while something runs)
    property real scanOn: Updater.busy ? 1 : 0
    // Longest "days behind", so the rings share a scale
    readonly property int maxDays: Updater.changes.reduce((m, c) => Math.max(m, c.days), 1)

    // ---- The dials ------------------------------------------------------
    // One entry per disc, in dial order. `pos` is where it sits along the dial
    // in disc units; a deleted one shares the spot of the next, so its
    // neighbours close the gap while it shrinks.
    readonly property var sysEntry: ({
            "id": "sys",
            "kind": "sys",
            "d": null,
            "pos": 0,
            "gone": false
        })
    readonly property var allUpd: {
        const out = [sysEntry];
        let pos = 1;
        for (const c of Updater.changes) {
            out.push({
                "id": "in:" + c.name,
                "kind": "input",
                "d": c,
                "pos": pos,
                "gone": false
            });
            pos++;
        }
        if (Updater.previewed && Updater.diff.length > 0) {
            pos += groupGap;
            for (let i = 0; i < Updater.diff.length; i++) {
                out.push({
                    "id": "pk:" + i,
                    "kind": "pkg",
                    "d": Updater.diff[i],
                    "pos": pos + i,
                    "gone": false
                });
            }
        }
        return out;
    }
    readonly property var allGen: Updater.generations.map((g, i) => ({
                "id": "g" + g.id,
                "kind": "gen",
                "d": g,
                "pos": i,
                "gone": false
            }))
    readonly property var allList: tab === 1 ? allGen : (tab === 0 ? allUpd : [sysEntry])
    readonly property string selId: tab === 1 ? selGen : (tab === 0 ? selUpd : "sys")
    readonly property int selIndex: indexOfId(allList, selId)
    readonly property var cur: selIndex >= 0 ? allList[selIndex] : null
    readonly property string curKind: cur ? cur.kind : "sys"
    readonly property real targetPos: cur ? cur.pos : 0
    // Where the dial is turned to; glides to the selected disc
    property real viewPos: targetPos

    // Only the discs near the middle are built, and only while the panel is
    // on screen
    readonly property var shown: {
        if (!visible)
            return [];
        const all = allList;
        const at = Math.max(0, selIndex);
        const lo = Math.max(0, at - windowN);
        const hi = Math.min(all.length, at + windowN + 1);
        const out = all.slice(lo, hi);
        if (tab === 1) {
            for (const g of ghosts) {
                if (g.pos >= lo - 1 && g.pos <= hi) {
                    out.push({
                        "id": g.id,
                        "kind": "gen",
                        "d": g.d,
                        "pos": g.pos,
                        "gone": true
                    });
                }
            }
        }
        return out;
    }

    // ---- What the middle says ---------------------------------------------
    readonly property int nInputs: Updater.changes.length
    readonly property string stageText: {
        if (Updater.phase === "checking")
            return "Checking  ·  can be cancelled";
        if (Updater.phase === "building")
            return "Building  ·  can be cancelled";
        if (Updater.phase === "applying") {
            if (Updater.cancellable)
                return "Building  ·  can be cancelled";
            return "Switching  ·  cannot be cancelled";
        }
        if (Updater.phase === "cleaning")
            return "Cleaning up";
        return "";
    }
    // "current" is what boots next, "running" is what runs now; they differ after a test
    readonly property string genBadge: {
        const g = curKind === "gen" ? cur.d : null;
        if (g === null)
            return "";
        return g.current ? (g.running ? "current" : "next boot") : (g.running ? "running" : "");
    }
    readonly property string headText: {
        if (help)
            return "Keys";
        if (curKind === "sys") {
            if (Updater.busy)
                return stageText;
            if (tab === 2)
                return Updater.logLines.length > 0 ? "Log  ·  " + Updater.logLines.length + " lines" : "Log";
            return "System" + (Updater.lastChecked !== "" && Updater.error === "" ? "  ·  checked " + Updater.lastChecked : "");
        }
        if (curKind === "input")
            return "Input  ·  " + selIndex + "/" + nInputs;
        if (curKind === "pkg") {
            const k = cur.d.kind;
            return (k === "add" ? "Added" : (k === "rem" ? "Removed" : "Upgraded")) + "  ·  " + (selIndex - nInputs) + "/" + Updater.diff.length;
        }
        if (curKind === "gen")
            return "Generation" + (genBadge !== "" ? "  ·  " + genBadge : "") + "  ·  " + (selIndex + 1) + "/" + allGen.length;
        return "Generations";
    }
    readonly property string titleText: {
        if (curKind === "sys")
            return Updater.summary;
        if (curKind === "input" || curKind === "pkg")
            return cur.d.name;
        if (curKind === "gen")
            return "#" + cur.d.id + "  ·  " + Qt.formatDateTime(new Date(cur.d.time), "d MMM yyyy, h:mm AP");
        return tab === 1 ? "No generations found" : "";
    }
    readonly property color titleColor: curKind === "sys" && Updater.error !== "" ? Colors.critical : Colors.foreground
    // The small lines under the title: [{ t, c }]
    readonly property var lines: {
        const out = [];
        if (curKind === "sys" && tab === 0) {
            const g = Updater.currentGen;
            if (g !== null)
                out.push({
                    "t": "Running generation #" + g.id + ", built " + Updater.age(g.time),
                    "c": Colors.muted
                });
            if (Updater.skipped !== "")
                out.push({
                    "t": "Last scheduled check skipped: " + Updater.skipped,
                    "c": Colors.muted
                });
            if (Updater.rebootPending)
                out.push({
                    "t": "Reboot needed: the running kernel differs from the installed one",
                    "c": Colors.accent
                });
            if (Updater.bootDiffers)
                out.push({
                    "t": Updater.runningGen === null ? "Running an unsaved test build. A reboot returns to generation #" + (g ? g.id : "?") : "Next boot uses generation #" + (g ? g.id : "?") + ", not the running #" + Updater.runningGen.id,
                    "c": Colors.accent
                });
            if (Updater.kernelChange)
                out.push({
                    "t": "Includes a new kernel: reboot after applying",
                    "c": Colors.accent
                });
            if (Updater.dirtyFiles > 0)
                out.push({
                    "t": Updater.dirtyFiles + " uncommitted change" + (Updater.dirtyFiles === 1 ? "" : "s") + " in " + Updater.flakeDir,
                    "c": Colors.muted
                });
            if (Updater.failedUnits > 0)
                out.push({
                    "t": Updater.failedUnits + " failed systemd unit" + (Updater.failedUnits === 1 ? "" : "s") + (Updater.failedNames.length > 0 ? ": " + Updater.failedNames.slice(0, 3).join(", ") + (Updater.failedNames.length > 3 ? ", …" : "") : ""),
                    "c": Colors.critical
                });
        } else if (curKind === "input") {
            out.push({
                "t": cur.d.from + "  →  " + cur.d.to,
                "c": Qt.alpha(Colors.foreground, 0.86)
            });
            if (cur.d.days > 0)
                out.push({
                    "t": "+" + cur.d.days + "d behind",
                    "c": Colors.accent
                });
        } else if (curKind === "pkg") {
            out.push({
                "t": cur.d.change,
                "c": Qt.alpha(Colors.foreground, 0.86)
            });
            if (cur.d.size !== "")
                out.push({
                    "t": cur.d.size,
                    "c": Colors.muted
                });
        } else if (curKind === "gen") {
            out.push({
                "t": Updater.age(cur.d.time) + (cur.d.version ? "  ·  " + cur.d.version : ""),
                "c": Qt.alpha(Colors.foreground, 0.86)
            });
            if (cur.d.kernel !== "")
                out.push({
                    "t": "linux " + cur.d.kernel,
                    "c": Colors.muted
                });
        }
        if (tab === 1 && curKind === "gen")
            out.push({
                "t": allGen.length + (allGen.length === 1 ? " generation" : " generations") + (Updater.removable > 0 ? " · " + Updater.removable + " can go" : "") + (Updater.diskAvail > 0 ? " · " + Updater.fmtBytes(Updater.diskAvail) + " free" : ""),
                "c": Colors.muted
            });
        return out;
    }
    // The generation's id for the buttons, or -1
    readonly property int selGenId: curKind === "gen" ? cur.d.id : -1
    readonly property bool selGenCurrent: curKind === "gen" && cur.d.current === true

    // ---- Layout of what is under the dial ---------------------------------
    readonly property int readoutTop: ruleY + 30
    readonly property int actionsH: Style.buttonCompact
    readonly property int footH: Style.buttonCompact
    readonly property int foot: 16
    // Heights that glide, so a longer readout lifts the dial in step with
    // everything under it instead of the window being resized
    property real readH: readCol.implicitHeight
    property real ctrlH: help ? 0 : 14 + actionsH
    readonly property real bodyH: Math.min(winH, readoutTop + readH + ctrlH + 14 + footH + foot)

    Behavior on viewPos {
        enabled: panel.animateView

        // The dial glides into place and settles, with no bounce
        NumberAnimation {
            duration: Style.enterMs
            easing.type: Style.easeEnter
        }
    }
    Behavior on readH {
        // Snaps while the panel is hidden or arriving
        enabled: panel.isOpen && panel.reveal > 0.8

        NumberAnimation {
            duration: Style.moveMs
            easing.type: Style.easeMove
        }
    }
    Behavior on ctrlH {
        enabled: panel.isOpen && panel.reveal > 0.8

        NumberAnimation {
            duration: Style.moveMs
            easing.type: Style.easeMove
        }
    }
    Behavior on tone {
        ColorAnimation {
            duration: Style.baseMs
        }
    }
    Behavior on flush {
        NumberAnimation {
            duration: Style.baseMs
            easing.type: Style.easeMove
        }
    }
    Behavior on okFill {
        NumberAnimation {
            duration: Style.sweepMs
            easing.type: Style.easeMove
        }
    }
    Behavior on scanOn {
        NumberAnimation {
            duration: Style.fadeMs
        }
    }

    // A check or a preview changed what is on the dial: if the highlighted
    // input or package is gone, the System disc is the one to land on
    onAllUpdChanged: {
        if (indexOfId(allUpd, selUpd) < 0) {
            animateView = false;
            selUpd = "sys";
            animateView = true;
        }
    }
    onSelIdChanged: if (isOpen)
        swapAnim.restart()
    onHelpChanged: swapAnim.restart()
    onTabChanged: swapAnim.restart()

    // ---- Helpers --------------------------------------------------------
    function clamp(v, a, b) {
        return Math.max(a, Math.min(b, v));
    }

    function mod(a, b) {
        return ((a % b) + b) % b;
    }

    // Ease-out with a small overshoot for the arrival of each disc (0..1 in,
    // about 1.04 at the peak): the shell's `pop`, kept gentle.
    function backOut(t) {
        const c1 = 0.8;
        const u = t - 1;
        return 1 + (c1 + 1) * u * u * u + c1 * u * u;
    }

    // Staggered arrival: 0 until `from`, 1 at `to` (in reveal units).
    function stage_(from, to) {
        return clamp((reveal - from) / (to - from), 0, 1);
    }

    // `base` washed with one of the palette's colours, chosen by screen
    // position x (colour1 on the left through colour6 on the right). The wash
    // is `fan` strong, so it only shows while the dial is arriving or leaving,
    // and it follows the wallpaper like everything else in the shell.
    function spectral(base, x, a) {
        const ramp = [Colors.color1, Colors.color2, Colors.color3, Colors.color4, Colors.color5, Colors.color6];
        const t = (clamp((x - stage.width / 2) / (stage.width * 0.34), -1, 1) * 0.5 + 0.5) * (ramp.length - 1);
        const i = Math.min(ramp.length - 2, Math.floor(t));
        const c = Qt.tint(ramp[i], Qt.alpha(ramp[i + 1], t - i));
        return Qt.alpha(Qt.tint(base, Qt.alpha(c, 0.9 * fan)), a);
    }

    function indexOfId(list, id) {
        for (let i = 0; i < list.length; i++) {
            if (list[i].id === id)
                return i;
        }
        return -1;
    }

    // ---- Selection ------------------------------------------------------
    function select(id) {
        if (tab === 0)
            selUpd = id;
        else if (tab === 1)
            selGen = id;
    }

    // Put the dial on disc number i. A long way snaps instead of spinning
    // past hundreds of packages.
    function pick(i) {
        const all = allList;
        if (i < 0 || i >= all.length)
            return;
        const far = Math.abs(all[i].pos - viewPos) > 6;
        if (far)
            animateView = false;
        select(all[i].id);
        if (far)
            animateView = true;
    }

    function step(n) {
        if (allList.length < 2)
            return;
        pick(clamp(Math.max(0, selIndex) + n, 0, allList.length - 1));
    }

    function jumpTo(last) {
        pick(last ? allList.length - 1 : 0);
    }

    // First disc of the previous (dir < 0) or next (dir > 0) group: the
    // system, the inputs, the packages
    function stepGroup(dir) {
        const all = allList;
        const at = selIndex;
        if (tab !== 0 || at < 0)
            return;
        const k = all[at].kind;
        if (dir > 0) {
            for (let i = at + 1; i < all.length; i++) {
                if (all[i].kind !== k) {
                    pick(i);
                    return;
                }
            }
            return;
        }
        let j = at;
        while (j >= 0 && all[j].kind === k)
            j--;
        if (j < 0)
            return;
        const prev = all[j].kind;
        while (j > 0 && all[j - 1].kind === prev)
            j--;
        pick(j);
    }

    function setTab(i) {
        if (i === tab)
            return;
        // The other dial is somewhere else entirely: put it there
        animateView = false;
        tab = i;
        animateView = true;
    }

    function showTab(i) {
        help = false;
        setTab(i);
    }

    function currentGenId() {
        const g = Updater.currentGen;
        if (g !== null)
            return "g" + g.id;
        return Updater.generations.length > 0 ? "g" + Updater.generations[0].id : "";
    }

    // The list of generations changed: shrink away the ones that went, and
    // keep the highlight on something. The ghost of a deleted disc sits where
    // the next one now is, so the rest close the gap while it shrinks.
    function genChanged_() {
        const now = Updater.generations;
        const ids = now.map(g => "g" + g.id);
        const old = genSnap;
        const add = [];
        let before = 0;
        let selWas = -1;
        let beforeSel = 0;
        for (let i = 0; i < old.length; i++) {
            if (old[i].id === selGen) {
                selWas = i;
                beforeSel = before;
            }
            if (ids.indexOf(old[i].id) < 0) {
                add.push({
                    "id": old[i].id,
                    "d": old[i].d,
                    "pos": before
                });
            } else {
                before++;
            }
        }
        if (ids.indexOf(selGen) < 0) {
            if (ids.length === 0)
                selGen = "";
            else if (selWas >= 0)
                selGen = ids[Math.min(beforeSel, ids.length - 1)];
            else
                selGen = currentGenId();
        }
        if (add.length > 0 && isOpen && reveal > 0.8 && tab === 1) {
            ghosts = ghosts.concat(add);
            ghostTimer.restart();
        }
        genSnap = now.map(g => ({
                    "id": "g" + g.id,
                    "d": g
                }));
    }

    // ---- Actions --------------------------------------------------------
    // Switch to the selected generation, or delete it: two presses each, like
    // the buttons (Updater keeps the count)
    function switchSel() {
        if (selGenId >= 0 && !selGenCurrent && !Updater.busy)
            Updater.rollback(selGenId);
    }

    function deleteSel() {
        if (selGenId >= 0 && !selGenCurrent && !Updater.busy)
            Updater.deleteGen(selGenId);
    }

    function open() {
        targetScreen = Focus.screen;
        if (isOpen)
            return;
        closeAnim.stop();
        ghosts = [];
        wheelAcc = 0;
        help = false;
        // The dial starts on the right disc instead of gliding there. The
        // discs are only built once the panel is on screen (see `shown`), so
        // this is settled before they exist.
        animateView = false;
        selUpd = "sys";
        selGen = currentGenId();
        animateView = true;
        // Fully hidden: start from the dome. Re-opened while it was still
        // leaving: carry on from where it is instead of snapping away first.
        if (reveal <= 0.001) {
            reveal = 0;
            spinIn = 3.2;
            fan = 1;
        }
        isOpen = true;
        openAnim.restart();
        keys.forceActiveFocus();
        Updater.refreshMeta();
    }

    function close() {
        if (!isOpen)
            return;
        isOpen = false;
        help = false;
        openAnim.stop();
        closeAnim.restart();
    }

    // When the last click outside the panel closed it. The same click can
    // land on the bar item that toggles it, which must not open it again.
    property double closedAt: 0

    function toggle() {
        if (!isOpen && Date.now() - closedAt < 250)
            return;
        if (isOpen)
            close();
        else
            open();
    }

    // Click outside the panel to close it. The window only covers the panel
    // (clicks beside it reach what is underneath), so the compositor's focus
    // grab tells us about a click anywhere else.
    HyprlandFocusGrab {
        windows: [panel]
        active: panel.isOpen && panel.visible
        onCleared: {
            panel.closedAt = Date.now();
            panel.close();
        }
    }

    // ---- Window ---------------------------------------------------------
    // Full screen, like the launcher: the shared dim goes over the whole screen and
    // the stage rises from the bottom edge, centred. A click on the dim closes.
    visible: isOpen || reveal > 0.001
    screen: targetScreen
    color: "transparent"
    exclusiveZone: 0
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "qs-updater"
    // Exclusive, like the other dials: the keys work the moment it opens,
    // without clicking it first.
    WlrLayershell.keyboardFocus: isOpen ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    IpcHandler {
        function toggle() {
            panel.toggle();
        }

        function open() {
            panel.open();
        }

        function close() {
            panel.close();
        }

        function check() {
            panel.open();
            Updater.check();
        }

        function preview() {
            panel.open();
            Updater.preview();
        }

        function apply() {
            panel.open();
            Updater.apply();
        }

        function test() {
            panel.open();
            Updater.tryOut();
        }

        function boot() {
            panel.open();
            Updater.bootNext();
        }

        function cancel() {
            Updater.cancel();
        }

        target: "sysupd"
    }

    Connections {
        target: Panels

        function onToggleUpdater() {
            panel.toggle();
        }
    }

    // Follow a build or a switch in the log. Deleting generations stays on the
    // list so you can watch it shrink. A run that ends well turns the ruler
    // green for a moment.
    Connections {
        target: Updater

        function onPhaseChanged() {
            const was = panel.lastPhase;
            panel.lastPhase = Updater.phase;
            if (Updater.phase === "building" || Updater.phase === "applying")
                panel.setTab(2);
            // The error is set just after the phase goes idle: look a moment later
            if (Updater.phase === "idle" && was !== "idle" && panel.isOpen)
                settleTimer.restart();
        }

        function onGenerationsChanged() {
            panel.genChanged_();
        }
    }

    Component.onCompleted: genChanged_()

    Timer {
        id: settleTimer

        interval: Style.pressMs
        onTriggered: {
            if (panel.isOpen && Updater.error === "" && !Updater.cancelled && !Updater.busy) {
                panel.succeeded = true;
                holdTimer.restart();
            }
        }
    }

    Timer {
        id: holdTimer

        interval: panel.holdMs
        onTriggered: panel.succeeded = false
    }

    Timer {
        id: ghostTimer

        interval: panel.collapseMs + 10
        onTriggered: panel.ghosts = []
    }

    // One overlay panel at a time
    PanelLink {
        win: panel
        name: "updater"
    }

    // Rises smoothly. The discs swing in from the left over a tight dome and
    // unfurl into the dial.
    ParallelAnimation {
        id: openAnim

        NumberAnimation {
            target: panel
            property: "reveal"
            to: 1
            duration: Style.sweepMs
            easing.type: Style.easeEnter
        }
        NumberAnimation {
            target: panel
            property: "spinIn"
            to: 0
            duration: Style.sweepMs + Style.moveMs
            easing.type: Style.easeEnter
        }
        NumberAnimation {
            target: panel
            property: "fan"
            to: 0
            duration: Style.sweepMs + Style.ambientMs / 2
            easing.type: Style.easeMove
        }
    }

    // Leaving: the dial curls back into the dome and sweeps off right.
    ParallelAnimation {
        id: closeAnim

        NumberAnimation {
            target: panel
            property: "reveal"
            to: 0
            duration: Style.moveMs + Style.fadeMs
            easing.type: Style.easeExit
        }
        NumberAnimation {
            target: panel
            property: "spinIn"
            to: -3.2
            duration: Style.moveMs + Style.fadeMs
            easing.type: Style.easeExit
        }
        NumberAnimation {
            target: panel
            property: "fan"
            to: 1
            duration: Style.moveMs + Style.fadeMs
            easing.type: Style.easeExit
        }
    }

    // Slow breath for the ring around the selected disc.
    SequentialAnimation {
        running: panel.isOpen
        loops: Animation.Infinite

        NumberAnimation {
            target: panel
            property: "breath"
            from: 0
            to: 1
            duration: Style.ambientMs * 2
            easing.type: Style.easeAmbient
        }
        NumberAnimation {
            target: panel
            property: "breath"
            from: 1
            to: 0
            duration: Style.ambientMs * 2
            easing.type: Style.easeAmbient
        }
    }

    // Something runs: a bright patch goes along the ruler and back
    SequentialAnimation {
        running: Updater.busy && panel.isOpen
        loops: Animation.Infinite

        NumberAnimation {
            target: panel
            property: "scan"
            to: 1.15
            duration: Style.sweepMs + Style.ambientMs
            easing.type: Style.easeAmbient
        }
        NumberAnimation {
            target: panel
            property: "scan"
            to: -1.15
            duration: Style.sweepMs + Style.ambientMs
            easing.type: Style.easeAmbient
        }
    }

    // A different disc, tab or view: the words fade up
    NumberAnimation {
        id: swapAnim

        target: panel
        property: "swap"
        from: 0
        to: 1
        duration: Style.baseMs
        easing.type: Style.easeMove
    }

    Item {
        id: keys

        anchors.fill: parent
        focus: panel.isOpen
        Keys.onPressed: event => {
            const k = event.key;
            const ctrl = (event.modifiers & Qt.ControlModifier) !== 0;
            const shift = (event.modifiers & Qt.ShiftModifier) !== 0;
            const plain = event.modifiers === Qt.NoModifier;
            // Turning the dial may repeat; running, arming or toggling
            // something must not
            if (event.isAutoRepeat && (k === Qt.Key_Escape || k === Qt.Key_Slash || k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Delete || k === Qt.Key_1 || k === Qt.Key_2 || k === Qt.Key_3 || (!ctrl && (k === Qt.Key_R || k === Qt.Key_P || k === Qt.Key_A || k === Qt.Key_T || k === Qt.Key_B || k === Qt.Key_C)))) {
                event.accepted = true;
                return;
            }
            if (k === Qt.Key_Escape) {
                if (panel.help)
                    panel.help = false;
                else
                    panel.close();
            } else if (k === Qt.Key_Slash)
                panel.help = !panel.help;
            else if (shift && k === Qt.Key_Right)
                panel.stepGroup(1);
            else if (shift && k === Qt.Key_Left)
                panel.stepGroup(-1);
            else if (k === Qt.Key_Right || k === Qt.Key_Down || k === Qt.Key_Tab || (plain && (k === Qt.Key_L || k === Qt.Key_J)) || (ctrl && k === Qt.Key_N))
                panel.step(1);
            else if (k === Qt.Key_Left || k === Qt.Key_Up || k === Qt.Key_Backtab || (plain && (k === Qt.Key_H || k === Qt.Key_K)) || (ctrl && k === Qt.Key_P))
                panel.step(-1);
            else if (k === Qt.Key_PageDown)
                panel.step(5);
            else if (k === Qt.Key_PageUp)
                panel.step(-5);
            else if (k === Qt.Key_Home)
                panel.jumpTo(false);
            else if (k === Qt.Key_End)
                panel.jumpTo(true);
            else if ((k === Qt.Key_Return || k === Qt.Key_Enter) && panel.tab === 1)
                panel.switchSel();
            else if (k === Qt.Key_Delete && panel.tab === 1)
                panel.deleteSel();
            else if (ctrl)
                return;
            else if (k === Qt.Key_R)
                Updater.check();
            else if (k === Qt.Key_P)
                Updater.preview();
            else if (k === Qt.Key_A)
                Updater.apply();
            else if (k === Qt.Key_T)
                Updater.tryOut();
            else if (k === Qt.Key_B)
                Updater.bootNext();
            else if (k === Qt.Key_C)
                Updater.cancel();
            else if (k === Qt.Key_1)
                panel.showTab(0);
            else if (k === Qt.Key_2)
                panel.showTab(1);
            else if (k === Qt.Key_3)
                panel.showTab(2);
            else
                return;
            event.accepted = true;
        }
    }

    // The share ring on a disc: how far behind an input was. It stays upright
    // while the disc tilts with the dial.
    component Ring: Shape {
        id: ring

        property real frac: 0
        property color tint: Colors.accent
        property real lineW: 2.5

        layer.enabled: true
        layer.samples: 4

        ShapePath {
            strokeColor: Qt.alpha(Colors.foreground, 0.14)
            strokeWidth: ring.lineW
            fillColor: "transparent"

            PathAngleArc {
                centerX: ring.width / 2
                centerY: ring.height / 2
                radiusX: ring.width / 2 - ring.lineW / 2
                radiusY: ring.height / 2 - ring.lineW / 2
                startAngle: -90
                sweepAngle: 360
            }
        }

        ShapePath {
            strokeColor: ring.frac > 0.004 ? ring.tint : "transparent"
            strokeWidth: ring.lineW
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap

            PathAngleArc {
                centerX: ring.width / 2
                centerY: ring.height / 2
                radiusX: ring.width / 2 - ring.lineW / 2
                radiusY: ring.height / 2 - ring.lineW / 2
                startAngle: -90
                sweepAngle: 359.9 * Math.min(1, Math.max(0, ring.frac))
            }
        }
    }

    // The shared dim (Dim.qml): the same wash as the screenshot tool
    Dim {
        reveal: panel.reveal
        closes: true
        onClicked: panel.close()
    }

    // ---- Stage ----------------------------------------------------------
    Item {
        id: stage

        readonly property real cx: width / 2

        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        width: panel.stageW
        height: panel.bodyH
        clip: true
        opacity: Math.min(1, panel.reveal * 3)
        transform: Translate {
            y: (1 - panel.reveal) * (stage.height + 40)
        }

        // Scroll wheel turns the dial
        MouseArea {
            anchors.fill: parent
            onWheel: wheel => {
                const d = wheel.angleDelta.y !== 0 ? wheel.angleDelta.y : -wheel.angleDelta.x;
                if (d === 0)
                    return;
                // One step per notch (120). A touchpad sends many small
                // deltas; counting them keeps one swipe from spinning the
                // dial through every package.
                if ((d < 0) !== (panel.wheelAcc < 0))
                    panel.wheelAcc = 0;
                panel.wheelAcc += d;
                while (panel.wheelAcc <= -120) {
                    panel.step(1);
                    panel.wheelAcc += 120;
                }
                while (panel.wheelAcc >= 120) {
                    panel.step(-1);
                    panel.wheelAcc -= 120;
                }
            }
        }

        // Feathered backing: a soft dark ellipse keeps the words and the scale
        // readable over any wallpaper without a visible panel edge. It grows
        // with the stage, so a tall readout stays covered.
        StageShade {
            id: scrimShape
            yScale: Math.max(0.62, stage.height * 0.95 / scrimShape.r)
        }

        // Low light on the horizon in the colour of the moment: the accent,
        // red after an error, green once a run has worked.
        Shape {
            id: horizon

            readonly property real r: stage.width * 0.46

            x: stage.cx - r
            y: stage.height - r
            width: r * 2
            height: r * 2
            layer.enabled: true
            layer.samples: 4
            transform: Scale {
                origin.x: horizon.r
                origin.y: horizon.r
                yScale: 0.42
            }

            ShapePath {
                strokeColor: "transparent"
                startX: 0
                startY: horizon.r

                fillGradient: RadialGradient {
                    centerX: horizon.r
                    centerY: horizon.r
                    centerRadius: horizon.r
                    focalX: horizon.r
                    focalY: horizon.r

                    GradientStop {
                        position: 0
                        color: Qt.alpha(panel.tone, 0.18)
                    }
                    GradientStop {
                        position: 0.5
                        color: Qt.alpha(panel.tone, 0.07)
                    }
                    GradientStop {
                        position: 1
                        color: Qt.alpha(panel.tone, 0)
                    }
                }

                PathArc {
                    x: horizon.r * 2
                    y: horizon.r
                    radiusX: horizon.r
                    radiusY: horizon.r
                }
                PathArc {
                    x: 0
                    y: horizon.r
                    radiusX: horizon.r
                    radiusY: horizon.r
                }
            }
        }

        // ---- The ruler: it turns with the dial, and the ticks by the middle
        // rise a little, like a magnifier. The rest of it shows the state: a
        // scan while something runs, red after an error, green filling
        // outward from the middle when a run ended well. ----------------------
        Repeater {
            // Not kept around while the panel is hidden
            model: panel.visible ? panel.tickN : 0

            delegate: Rectangle {
                id: tick

                required property int index

                readonly property real s: (index - panel.tickN / 2) * panel.tickGap - panel.mod(panel.viewPos * panel.stepPx - panel.spinIn * panel.stepPx * 0.5, panel.tickGap * 10)
                readonly property real a: s / panel.dialNow
                readonly property real rr: panel.dialNow - panel.ruleDrop
                readonly property bool major: index % 10 === 0
                // The magnifier by the middle, and the scan going past
                readonly property real near: Math.max(0, 1 - Math.abs(s) / 90)
                readonly property real wave: Math.max(0, 1 - Math.abs(x - stage.cx - panel.scan * stage.width / 2) / 90) * panel.scanOn
                readonly property real hot: Math.max(near, wave)
                // 1 once the green has reached this tick
                readonly property real okMix: panel.clamp((panel.okFill * 1.35 - Math.abs(x - stage.cx) / (stage.width / 2)) / 0.35, 0, 1)
                // Ticks the state is lighting get more solid
                readonly property real solid: {
                    const rest = major ? 0.46 : 0.28;
                    return rest + (1 - rest) * Math.max(0.7 * hot, 0.6 * panel.flush, 0.85 * okMix);
                }
                readonly property color hue: Qt.tint(Qt.tint(Qt.tint(Colors.foreground, Qt.alpha(Colors.accent, 0.7 * hot)), Qt.alpha(Colors.critical, 0.85 * panel.flush)), Qt.alpha(Colors.success, 0.95 * okMix))

                x: stage.cx + rr * Math.sin(a) - 0.75
                y: panel.topY + panel.dialNow - rr * Math.cos(a)
                width: 1.5
                height: (major ? 9 : 5) + 6 * hot + 4 * okMix
                radius: 0.75
                antialiasing: true
                visible: Math.abs(a) < 1.2
                transformOrigin: Item.Top
                rotation: a * 180 / Math.PI
                color: panel.spectral(hue, x, solid)
                opacity: panel.clamp((stage.cx - Math.abs(x - stage.cx)) / 90, 0, 1) * panel.clamp(panel.reveal * 2 - Math.abs(x - stage.cx) / stage.cx * 0.9, 0, 1)
            }
        }

        // The middle of the ruler: the 2px marker, in the colour of the moment
        Rectangle {
            x: stage.cx - 1
            y: panel.ruleY - 3
            width: 2
            height: 16
            radius: 1
            color: panel.tone
            opacity: panel.clamp(panel.reveal * 2 - 0.5, 0, 1)
        }

        // ---- The discs --------------------------------------------------
        Repeater {
            model: ScriptModel {
                values: panel.shown
                objectProp: "id"
            }

            delegate: Item {
                id: slot

                required property var modelData

                readonly property string kind: modelData ? modelData.kind : ""
                readonly property var d: modelData ? modelData.d : null
                // Animated, so the neighbours of a deleted disc glide closed
                property real pos: modelData ? modelData.pos : 0
                readonly property bool current: modelData ? modelData.id === panel.selId : false
                readonly property real rel: pos - panel.viewPos
                // Swung left while arriving, right while leaving
                readonly property real s: (rel - panel.spinIn) * panel.stepPx
                readonly property real a: s / panel.dialNow
                // 0 at rest, 1 when selected. Animated, so the disc swells.
                property real grow: current ? 1 : 0
                // 0 -> 1 while the disc shrinks away after being deleted
                property real gone: modelData && modelData.gone ? 1 : 0
                // 0..1 while the ring around a newly selected disc expands
                property real ping: 0
                // 0 -> 1 when the disc is built (a tab change, the window
                // sliding along a long list): it fades in
                property real intro: 0
                // The system glyph's turn while something runs
                property real spin: 0
                readonly property real sz: panel.discSize + (panel.selectedSize - panel.discSize) * grow
                readonly property real px: stage.cx + panel.dialNow * Math.sin(a)
                // The selected one also lifts a little off the dial
                readonly property real py: panel.topY + panel.dialNow * (1 - Math.cos(a)) - 5 * grow
                // Arrive in a left-to-right wave, each with a small overshoot
                readonly property real appear: panel.clamp(panel.reveal * 2.2 - (panel.clamp(rel, -6, 6) + 6) * 0.09, 0, 1)
                readonly property real edge: panel.clamp((stage.cx - Math.abs(px - stage.cx)) / 90, 0, 1)
                // The accent marks the selected disc; the System disc takes the
                // colour of the moment instead (red after an error)
                readonly property color ringColor: kind === "sys" ? panel.tone : Colors.accent
                // What is drawn on the disc takes its colour from what it is:
                // the colour is the data
                readonly property color glyphColor: {
                    if (kind === "sys")
                        return panel.tint;
                    if (kind === "pkg")
                        return d.kind === "add" ? Colors.success : (d.kind === "rem" ? Colors.critical : Colors.foreground);
                    return current ? Colors.accent : Colors.foreground;
                }
                // How far behind an input was, against the furthest one
                readonly property real frac: kind === "input" && d.days > 0 ? d.days / panel.maxDays : 0

                visible: Math.abs(rel) < 7 && opacity > 0.01
                width: sz
                height: sz
                x: px - sz / 2
                y: py - sz / 2
                z: current ? 20 : 10
                opacity: appear * edge * intro * (1 - gone)
                scale: (0.55 + 0.45 * panel.backOut(appear)) * (1 - 0.7 * gone)
                // Tilts along the dial, and rises from below as it arrives
                rotation: a * 180 / Math.PI * 0.6
                transform: Translate {
                    y: (1 - slot.appear) * 30
                }

                Component.onCompleted: intro = 1

                Behavior on intro {
                    NumberAnimation {
                        duration: Style.baseMs
                        easing.type: Style.easeMove
                    }
                }

                Behavior on pos {
                    enabled: panel.isOpen && panel.reveal > 0.8

                    NumberAnimation {
                        duration: Style.moveMs
                        easing.type: Style.easeMove
                    }
                }

                Behavior on gone {
                    NumberAnimation {
                        duration: panel.collapseMs
                        easing.type: Style.easeExit
                    }
                }

                // Swells with a little overshoot, settles back without one
                Behavior on grow {
                    NumberAnimation {
                        duration: Style.moveMs
                        easing.type: slot.current ? Style.easePop : Style.easeMove
                        easing.overshoot: 1.2
                    }
                }

                // The selection moved to this one: a ring leaves it.
                onCurrentChanged: if (current && panel.isOpen && panel.reveal > 0.8)
                    pingAnim.restart()

                NumberAnimation {
                    id: pingAnim

                    target: slot
                    property: "ping"
                    from: 0
                    to: 1
                    duration: Style.sweepMs
                    easing.type: Style.easeMove
                }

                // The System glyph turns while something runs
                NumberAnimation {
                    target: slot
                    property: "spin"
                    from: 0
                    to: 360
                    duration: Style.ambientMs * 2
                    loops: Animation.Infinite
                    running: slot.kind === "sys" && Updater.busy && panel.isOpen
                    onRunningChanged: if (!running)
                        slot.spin = 0
                }

                // Ring that leaves a newly selected disc.
                Rectangle {
                    anchors.centerIn: parent
                    width: parent.width + 14 + 34 * slot.ping
                    height: width
                    radius: width / 2
                    color: "transparent"
                    antialiasing: true
                    visible: slot.ping > 0.001 && slot.ping < 0.999
                    border.width: 1.5
                    border.color: Qt.alpha(slot.ringColor, 0.5 * (1 - slot.ping))
                }

                // Breathing ring around the selected disc.
                Rectangle {
                    anchors.centerIn: parent
                    width: parent.width + 12
                    height: width
                    radius: width / 2
                    color: "transparent"
                    antialiasing: true
                    visible: slot.grow > 0.05
                    border.width: 1
                    border.color: Qt.alpha(slot.ringColor, slot.grow * (0.25 + 0.25 * panel.breath))
                }

                // Glass, like the bar: one flat surface with a hairline
                // outline, lit once selected. It takes the palette wash while
                // the dial is arriving.
                Rectangle {
                    anchors.fill: parent
                    radius: width / 2
                    antialiasing: true
                    color: Style.card
                    border.width: 1
                    border.color: slot.current ? panel.spectral(slot.ringColor, slot.px, 0.9) : panel.spectral(Colors.foreground, slot.px, 0.32)

                    Behavior on border.color {
                        ColorAnimation {
                            duration: Style.baseMs
                        }
                    }
                }

                // The soft tint inside the glass
                Rectangle {
                    anchors.fill: parent
                    anchors.margins: 1
                    radius: width / 2
                    antialiasing: true
                    color: Qt.alpha(slot.ringColor, slot.current ? Style.tintAlpha : 0)

                    Behavior on color {
                        ColorAnimation {
                            duration: Style.baseMs
                        }
                    }
                }

                // Light catching the top edge, as on the bar
                Rectangle {
                    anchors.top: parent.top
                    anchors.topMargin: 1
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: parent.width * 0.5
                    height: 1

                    gradient: Gradient {
                        orientation: Gradient.Horizontal

                        GradientStop {
                            position: 0
                            color: Qt.alpha(Colors.foreground, 0)
                        }
                        GradientStop {
                            position: 0.5
                            color: Qt.alpha(Colors.foreground, 0.12)
                        }
                        GradientStop {
                            position: 1
                            color: Qt.alpha(Colors.foreground, 0)
                        }
                    }
                }

                // An input: how far behind it was
                Ring {
                    anchors.fill: parent
                    anchors.margins: 3
                    visible: slot.kind === "input"
                    frac: slot.frac
                    tint: Colors.accent
                    opacity: slot.current ? 1 : 0.7
                    rotation: -slot.rotation
                }

                // The glyph on the disc, upright while the disc tilts with the
                // dial: the state for the system, a letter for an input, an
                // arrow, plus or minus for a package, the number for a
                // generation
                Txt {
                    anchors.centerIn: parent
                    text: {
                        if (slot.kind === "sys")
                            return String.fromCodePoint(panel.glyph);
                        if (slot.kind === "input")
                            return slot.d.name.charAt(0).toUpperCase();
                        if (slot.kind === "pkg")
                            return slot.d.kind === "add" ? Icons.plus : (slot.d.kind === "rem" ? Icons.minus : Icons.arrowUp);
                        return slot.kind === "gen" ? "#" + slot.d.id : "";
                    }
                    color: slot.glyphColor
                    font.pixelSize: slot.kind === "gen" ? slot.sz * 0.28 : slot.sz * (slot.kind === "sys" ? 0.42 : 0.38)
                    font.bold: slot.kind !== "sys"
                    rotation: -slot.rotation + slot.spin

                    Behavior on color {
                        ColorAnimation {
                            duration: Style.fadeMs
                        }
                    }
                }

                // The generation that boots next (accent), or runs now (grey)
                Rectangle {
                    readonly property bool next: slot.kind === "gen" && slot.d.current === true
                    readonly property bool runs: slot.kind === "gen" && slot.d.running === true

                    x: parent.width * 0.72
                    y: parent.height * 0.02
                    width: 12
                    height: 12
                    radius: 6
                    antialiasing: true
                    color: next ? Colors.accent : Colors.muted
                    border.width: 2
                    border.color: Style.card
                    opacity: next || runs ? 1 : 0
                    scale: next || runs ? 1 : 0.4

                    Behavior on opacity {
                        NumberAnimation {
                            duration: Style.baseMs
                        }
                    }
                    Behavior on scale {
                        NumberAnimation {
                            duration: Style.baseMs
                            easing.type: Style.easeMove
                        }
                    }
                }

                // Click to bring it to the middle. Position, not hover, so the
                // dial never turns under a mouse you are only passing over.
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: if (slot.modelData && !slot.modelData.gone)
                        panel.select(slot.modelData.id)
                }
            }
        }

        // Accent underline under the selected disc; it breathes with the ring.
        Rectangle {
            readonly property real rel: panel.targetPos - panel.viewPos
            readonly property real a: (rel - panel.spinIn) * panel.stepPx / panel.dialNow

            visible: panel.cur !== null
            width: 20 + 10 * panel.breath
            height: 2
            radius: 1
            color: panel.tone
            x: stage.cx + panel.dialNow * Math.sin(a) - width / 2
            y: panel.topY + panel.dialNow * (1 - Math.cos(a)) - 5 + panel.selectedSize / 2 + 6
            rotation: a * 180 / Math.PI
            opacity: panel.clamp(panel.reveal * 2 - 0.6, 0, 1)
        }

        // ---- The middle: what the selected disc says ------------------------
        Item {
            id: readout

            x: stage.cx - width / 2
            y: panel.readoutTop
            width: panel.readW
            height: panel.readH
            opacity: (0.25 + 0.75 * panel.swap) * panel.stage_(0.25, 0.8)
            transform: Translate {
                y: (1 - panel.stage_(0.25, 0.8)) * 12 + (1 - panel.swap) * 6
            }

            Column {
                id: readCol

                width: parent.width
                spacing: Style.spaceXs

                // What it is, and where it is among the others. While
                // something runs: which stage, and whether it can be cancelled.
                Txt {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    visible: text !== ""
                    elide: Text.ElideRight
                    text: panel.headText
                    // Brighter than the muted grey, with a thin outline in the
                    // background colour: it stays readable over any wallpaper
                    color: panel.succeeded ? Colors.success : Qt.alpha(Colors.foreground, 0.78)
                    style: Text.Outline
                    styleColor: Qt.alpha(Colors.background, 0.85)
                    font.pixelSize: Style.fontSm
                    font.letterSpacing: 1.4
                    font.capitalization: Font.AllUppercase
                }

                // The name, the summary or the date, large
                Txt {
                    width: parent.width
                    height: visible ? implicitHeight : 0
                    horizontalAlignment: Text.AlignHCenter
                    visible: !panel.help && text !== ""
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                    text: panel.titleText
                    color: panel.titleColor
                    style: Text.Outline
                    styleColor: Qt.alpha(Colors.background, 0.8)
                    font.pixelSize: Style.fontXl
                    font.bold: true
                }

                // The small lines: the heads-up, from -> to, the kernel
                Repeater {
                    model: panel.help ? [] : panel.lines

                    delegate: Txt {
                        required property var modelData

                        width: readCol.width
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.Wrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                        text: modelData.t
                        color: modelData.c
                        style: Text.Outline
                        styleColor: Qt.alpha(Colors.background, 0.8)
                        font.pixelSize: Style.fontMd
                    }
                }

                // What a preview found, in the colours of the discs
                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    height: visible ? implicitHeight : 0
                    spacing: Style.spaceLg
                    visible: !panel.help && panel.tab === 0 && panel.curKind === "sys" && Updater.previewed

                    Txt {
                        text: "↑ " + Updater.upgraded + " upgraded"
                        color: Qt.alpha(Colors.foreground, 0.86)
                        style: Text.Outline
                        styleColor: Qt.alpha(Colors.background, 0.8)
                        font.pixelSize: Style.fontMd
                    }
                    Txt {
                        text: "+ " + Updater.added + " added"
                        color: Colors.success
                        style: Text.Outline
                        styleColor: Qt.alpha(Colors.background, 0.8)
                        font.pixelSize: Style.fontMd
                    }
                    Txt {
                        text: "− " + Updater.removed + " removed"
                        color: Colors.critical
                        style: Text.Outline
                        styleColor: Qt.alpha(Colors.background, 0.8)
                        font.pixelSize: Style.fontMd
                    }
                    Txt {
                        visible: Updater.previewTag === "local"
                        text: "your local edits only"
                        color: Colors.muted
                        style: Text.Outline
                        styleColor: Qt.alpha(Colors.background, 0.8)
                        font.pixelSize: Style.fontMd
                    }
                }

                // No package changes
                Txt {
                    width: parent.width
                    height: visible ? implicitHeight : 0
                    horizontalAlignment: Text.AlignHCenter
                    visible: !panel.help && panel.tab === 0 && panel.curKind === "sys" && Updater.previewed && Updater.diff.length === 0
                    text: "No package changes."
                    color: Colors.muted
                    style: Text.Outline
                    styleColor: Qt.alpha(Colors.background, 0.8)
                    font.pixelSize: Style.fontMd
                }

                // The log: what the build or the switch printed. A light wash
                // (Style.well, as on the discs) rather than dark glass, so the
                // wallpaper shows through; the text carries the same soft
                // outline as the other floating text here, to read on any of it.
                Item {
                    width: parent.width
                    height: visible ? panel.logH + Style.spaceMd : 0
                    visible: !panel.help && panel.tab === 2

                    Rectangle {
                        y: Style.spaceMd
                        width: parent.width
                        height: panel.logH
                        radius: Style.radiusLg
                        antialiasing: true
                        color: Style.well
                        border.width: 1
                        border.color: Style.outline
                        clip: true

                        // Light catching the top edge, as on the bar
                        Rectangle {
                            anchors.top: parent.top
                            anchors.topMargin: 1
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: parent.width - Style.radiusLg * 2
                            height: 1

                            gradient: Gradient {
                                orientation: Gradient.Horizontal

                                GradientStop {
                                    position: 0
                                    color: Qt.alpha(Colors.foreground, 0)
                                }
                                GradientStop {
                                    position: 0.5
                                    color: Qt.alpha(Colors.foreground, 0.12)
                                }
                                GradientStop {
                                    position: 1
                                    color: Qt.alpha(Colors.foreground, 0)
                                }
                            }
                        }

                        Flickable {
                            id: flick

                            anchors.fill: parent
                            anchors.margins: Style.spaceLg
                            contentHeight: logText.implicitHeight
                            clip: true
                            boundsBehavior: Flickable.StopAtBounds
                            // Follow the end while the output grows
                            onContentHeightChanged: contentY = Math.max(0, contentHeight - height)

                            Txt {
                                id: logText

                                width: flick.width
                                wrapMode: Text.WrapAnywhere
                                style: Text.Outline
                                styleColor: Qt.alpha(Colors.background, 0.8)
                                color: Updater.logLines.length > 0 ? Colors.foreground : Colors.muted
                                text: Updater.logLines.length > 0 ? Updater.logLines.join("\n") : "Nothing yet. Build and switch output shows up here."
                                font.pixelSize: Style.fontSm
                            }
                        }
                    }
                }

                // The key and action cheat sheet (the "/" button)
                Column {
                    width: parent.width
                    height: visible ? implicitHeight : 0
                    spacing: Style.spaceXs
                    visible: panel.help

                    Repeater {
                        model: [["r", "Check for updates"], ["p", "Preview what would change (your local edits too)"], ["a", "Switch: activate now and make it the boot default (u). Press twice"], ["t", "Test: activate now, a reboot undoes it (ut)"], ["b", "Boot: use it from the next reboot (ub). Press twice"], ["c", "Cancel a check or a build"], ["1 2 3", "Updates, Generations, Log"], ["← →", "Turn the dial (also h l, Tab, Ctrl+N / Ctrl+P, the wheel)"], ["Enter", "Generations: switch to the selected one. Press twice"], ["Del", "Generations: delete the selected one. Press twice"], ["/", "This help"], ["esc", "Close"]]

                        delegate: Row {
                            required property var modelData

                            spacing: Style.spaceLg

                            Txt {
                                width: 56
                                text: parent.modelData[0]
                                color: Colors.accent
                                style: Text.Outline
                                styleColor: Qt.alpha(Colors.background, 0.8)
                                font.bold: true
                                font.pixelSize: Style.fontMd
                            }
                            Txt {
                                width: readCol.width - 68
                                text: parent.modelData[1]
                                color: Colors.foreground
                                style: Text.Outline
                                styleColor: Qt.alpha(Colors.background, 0.8)
                                wrapMode: Text.WordWrap
                                font.pixelSize: Style.fontMd
                            }
                        }
                    }

                    Txt {
                        width: parent.width
                        topPadding: Style.spaceMd
                        horizontalAlignment: Text.AlignHCenter
                        text: "Delete all but current keeps the current generation, clears your old user profiles, collects garbage and rebuilds the boot menu. A running test build survives."
                        color: Colors.muted
                        style: Text.Outline
                        styleColor: Qt.alpha(Colors.background, 0.8)
                        wrapMode: Text.WordWrap
                        font.pixelSize: Style.fontSm
                    }
                }
            }
        }

        // ---- Under the readout: the few things you can do ---------------------
        Row {
            id: controls

            x: stage.cx - width / 2
            y: panel.readoutTop + panel.readH + 14
            spacing: Style.spaceMd
            visible: !panel.help
            // The second-press labels are short ("Press again"); this is the
            // net under that: if the row is still wider than the stage it
            // shrinks to fit
            scale: Math.min(1, (stage.width - 32) / Math.max(1, controls.implicitWidth))
            opacity: panel.stage_(0.35, 0.9)
            transform: Translate {
                y: (1 - panel.stage_(0.35, 0.9)) * 10
            }

            // Updates
            TextButton {
                compact: true
                visible: panel.tab === 0
                text: Updater.available ? "Preview packages" : "Preview local changes"
                enabled: !Updater.busy
                onClicked: Updater.preview()
            }
            TextButton {
                compact: true
                visible: panel.tab === 0
                text: "Test"
                enabled: !Updater.busy
                onClicked: Updater.tryOut()
            }
            TextButton {
                compact: true
                visible: panel.tab === 0
                danger: Updater.bootArmed
                armed: Updater.bootArmed
                text: Updater.bootArmed ? "Press again" : "Boot"
                enabled: !Updater.busy
                onClicked: Updater.bootNext()
            }
            TextButton {
                compact: true
                visible: panel.tab === 0
                primary: true
                armed: Updater.applyArmed
                minWidth: 120
                text: Updater.applyArmed ? "Press again" : (Updater.available ? "Apply update" : "Rebuild & switch")
                enabled: !Updater.busy
                onClicked: Updater.apply()
            }
            // The running kernel, or the boot default, is not the system on disk
            TextButton {
                compact: true
                visible: panel.tab === 0 && (Updater.rebootPending || Updater.bootDiffers)
                danger: Updater.rebootArmed
                armed: Updater.rebootArmed
                text: Updater.rebootArmed ? "Press again" : "Reboot"
                enabled: !Updater.busy
                onClicked: Updater.reboot()
            }

            // Generations: the selected one, then the two clean-ups
            TextButton {
                compact: true
                visible: panel.tab === 1 && panel.curKind === "gen"
                danger: Updater.rollbackArmed === panel.selGenId
                armed: Updater.rollbackArmed === panel.selGenId
                text: Updater.rollbackArmed === panel.selGenId ? "Press again" : "Switch to"
                enabled: !Updater.busy && !panel.selGenCurrent
                onClicked: panel.switchSel()
            }
            TextButton {
                compact: true
                visible: panel.tab === 1 && panel.curKind === "gen"
                glyph: Updater.deleteArmed === panel.selGenId ? "" : Icons.trash
                danger: Updater.deleteArmed === panel.selGenId
                armed: Updater.deleteArmed === panel.selGenId
                text: Updater.deleteArmed === panel.selGenId ? "Press again" : "Delete"
                enabled: !Updater.busy && !panel.selGenCurrent
                onClicked: panel.deleteSel()
            }
            TextButton {
                compact: true
                visible: panel.tab === 1
                danger: Updater.cleanArmed
                armed: Updater.cleanArmed
                text: Updater.cleanArmed ? "Press again" : "Remove older than " + Updater.keepDays + " days"
                enabled: !Updater.busy
                onClicked: Updater.collect()
            }
            TextButton {
                compact: true
                visible: panel.tab === 1
                danger: Updater.deleteAllArmed
                armed: Updater.deleteAllArmed
                minWidth: 92
                text: Updater.deleteAllArmed ? "Press again" : "Delete all but current"
                enabled: !Updater.busy && Updater.removable > 0
                onClicked: Updater.deleteAll()
            }

            // Log
            TextButton {
                compact: true
                visible: panel.tab === 2
                text: "Copy log"
                enabled: Updater.logLines.length > 0
                onClicked: Quickshell.execDetached(["wl-copy", Updater.logLines.join("\n")])
            }
        }

        // ---- The foot: which view, check or cancel, and the help ---------------
        Row {
            id: footRow

            x: stage.cx - width / 2
            y: stage.height - panel.foot - panel.footH
            spacing: Style.spaceMd
            scale: Math.min(1, (stage.width - 32) / Math.max(1, footRow.implicitWidth))
            opacity: panel.stage_(0.35, 0.9)

            Repeater {
                model: [
                    {
                        "label": "Updates",
                        "n": Updater.count
                    },
                    {
                        "label": "Generations",
                        "n": Updater.generations.length
                    },
                    {
                        "label": "Log",
                        "n": 0
                    }
                ]

                delegate: TextButton {
                    required property int index
                    required property var modelData

                    compact: true
                    primary: panel.tab === index && !panel.help
                    text: modelData.n > 0 ? modelData.label + "  " + modelData.n : modelData.label
                    onClicked: panel.showTab(index)
                }
            }

            // A little room between the views and the rest
            Item {
                width: Style.spaceMd
                height: 1
            }

            TextButton {
                compact: true
                text: "Check"
                visible: !Updater.cancellable
                enabled: !Updater.busy
                onClicked: Updater.check()
            }
            TextButton {
                compact: true
                text: "Cancel"
                visible: Updater.cancellable
                onClicked: Updater.cancel()
            }
            TextButton {
                compact: true
                text: "/"
                primary: panel.help
                onClicked: panel.help = !panel.help
            }
        }
    }
}
