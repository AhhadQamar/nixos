// DownloadManager.qml
// Downloads on a dial: a borderless stage rising from the bottom edge, in the
// same language as the launcher, the clipboard and the notification centre. A
// thin front end for the aria2 user service (see Aria2.qml for the helpers).
// Finished downloads raise a toast even while the panel is closed.
//   qs ipc call downloads toggle | open | close
//   qs ipc call downloads add "<link, magnet or .torrent path>"
//
// The discs are the downloads, in order: active, then queued, failed and
// finished, with a slightly wider gap between the groups. Each disc wears a
// ring in its state's colour that fills as the download does. A fine ruler
// curves over them; the 2px accent marker and the underline stand on the
// selected one. Under the ruler the middle reads out the selected download:
// what it is (state, kind, 3/12), its name, its status line and a thin bar.
// Enter opens its details: the stage grows to make room for the info rows and
// the files of a torrent. A row of buttons sits under the readout (pause,
// retry, open, show in the file manager, copy link, move to top, remove, and
// remove + delete files, which wants a second press).
//
// Below that, a second, shorter ruler is the speed graph: 60 ticks, newest on
// the right, with the speed rolling at its left and the two speed limits at its
// right. Then the filter switch (All / Active / Queued / Done / Failed) with
// pause all, resume all, clear finished and the number of parallel downloads,
// and at the foot two pills: one to paste links into (several at once, one per
// line or separated by spaces) and the search field. Press ? for every key.
//
// Motion: the discs and ruler swing in from the left over a tight dome, washed
// with the wallpaper's palette, and unfurl into the calm dial as the colour
// drains; closing plays it in reverse. The stage glides taller or shorter as the
// readout, the details and the add pill change. A new download lands with a
// glint, a finished one lights its ring green and pops, a failed one shakes and
// flushes red, one waiting for a second shift+del shakes and gets a breathing
// red ring, a removed one shrinks away while its neighbours close the gap.
//
// Keys: left / right / up / down / h / j / k / l turn the dial (home / end,
// page up / page down jump), enter details, space pause or resume, s select
// (ctrl+a all), a add links, v add from the clipboard, del remove, shift+del
// remove and delete files (press twice), r retry (shift+r all failed), u / d
// move in the queue (shift+t to the top), o open, f show in the file manager,
// y copy the link, c clear finished, shift+p pause or resume all, shift+l cycle
// the download limit, + / - parallel downloads, / search, 1-5 and tab switch
// the filter, ? the sheet of keys, esc steps back (selection, details, search,
// close).
//
// Every timing and easing comes from the shared motion tokens in Style.qml; the
// loops (breathing, the glint along the bar) are driven by properties and only
// run while the panel is open.

import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland

PanelWindow {
    id: dl

    // ---- Settings -------------------------------------------------------
    readonly property string rpcUrl: "http://localhost:6800/jsonrpc"
    readonly property int pollMs: 1500       // refresh rate while the panel is open
    readonly property int watchMs: 5000      // completion check while it is closed
    readonly property int historyLength: 60  // samples in the speed graph
    // Overall speed limits to cycle through, in bytes per second (0 = unlimited)
    readonly property var limitPresets: [0, 524288, 1048576, 2097152, 5242880, 10485760]
    // "Save to" choices, relative to $HOME (set in Config.qml). The first one means "aria2's default dir".
    readonly property var savePresets: Config.downloadFolders
    readonly property var tabs: [
        {
            "id": "all",
            "label": "All"
        },
        {
            "id": "active",
            "label": "Active"
        },
        {
            "id": "queued",
            "label": "Queued"
        },
        {
            "id": "done",
            "label": "Done"
        },
        {
            "id": "failed",
            "label": "Failed"
        }
    ]
    readonly property var keyHelp: [
        {
            "k": ["\u2190", "\u2192", "j", "k"],
            "d": "turn the dial"
        },
        {
            "k": ["home", "end"],
            "d": "first / last"
        },
        {
            "k": ["enter"],
            "d": "details"
        },
        {
            "k": ["space"],
            "d": "pause / resume"
        },
        {
            "k": ["s", "ctrl+a"],
            "d": "select / select all"
        },
        {
            "k": ["a"],
            "d": "add links"
        },
        {
            "k": ["v"],
            "d": "add from clipboard"
        },
        {
            "k": ["del"],
            "d": "remove"
        },
        {
            "k": ["shift+del"],
            "d": "remove + delete files"
        },
        {
            "k": ["r", "shift+r"],
            "d": "retry / retry all"
        },
        {
            "k": ["u", "d", "shift+t"],
            "d": "queue up / down / top"
        },
        {
            "k": ["o", "f", "y"],
            "d": "open / " + Config.fileManager + " / copy link"
        },
        {
            "k": ["c"],
            "d": "clear finished"
        },
        {
            "k": ["shift+p"],
            "d": "pause / resume all"
        },
        {
            "k": ["shift+l", "+", "\u2212"],
            "d": "speed limit / parallel"
        },
        {
            "k": ["/"],
            "d": "search"
        },
        {
            "k": ["1\u20135", "tab"],
            "d": "filter tabs"
        },
        {
            "k": ["esc"],
            "d": "step back / close"
        }
    ]
    readonly property var blankRow: ({
            "gid": "",
            "name": "",
            "state": "queued",
            "group": "queued",
            "live": false,
            "total": 0,
            "done": 0,
            "fraction": 0,
            "speed": 0,
            "upSpeed": 0,
            "up": 0,
            "ratio": 0,
            "conns": 0,
            "seeders": 0,
            "error": "",
            "dir": "",
            "path": "",
            "isBt": false,
            "complete": false,
            "metadata": false,
            "pos": 0,
            "link": "",
            "uris": [],
            "files": [],
            "info": []
        })
    readonly property string rpcKeys: "gid,status,totalLength,completedLength,uploadLength,downloadSpeed,uploadSpeed,connections,numSeeders,seeder,infoHash,dir,errorCode,errorMessage,followedBy,verifiedLength,verifyIntegrityPending,files,bittorrent"

    // ---- The dial ---------------------------------------------------------
    readonly property real dialR: 900
    readonly property real rainbowR: 360
    readonly property real stepPx: 76
    readonly property real discSize: 48
    readonly property real selectedSize: 68
    readonly property real tickGap: 12
    readonly property int windowN: 11
    // A little extra room between the groups of downloads, in disc units
    readonly property real groupGap: 0.35
    readonly property real collapseMs: 200
    readonly property real topY: 56
    readonly property real ruleDrop: 46
    readonly property real ruleY: topY + ruleDrop
    readonly property int tickN: Math.ceil(stageW / tickGap) + 24

    // ---- Layout -------------------------------------------------------------
    // The window keeps one size and the stage grows and shrinks inside it
    readonly property real screenW: targetScreen ? targetScreen.width : 1920
    readonly property real screenH: targetScreen ? targetScreen.height : 1080
    // The window is wider than the content, so the soft backing behind the
    // controls has room to fade out before it meets the edge of the window
    readonly property int stageW: Math.min(1240, Math.round(screenW * 0.96))
    readonly property real contentW: Math.min(900, stageW - 48)
    readonly property int winH: Math.min(760, Math.round(screenH) - 40)
    // The toast needs a little room above the stage
    readonly property int stageMax: winH - 56
    readonly property int readoutTop: ruleY + 30
    readonly property int actionsH: Style.buttonCompact
    readonly property int filterH: Style.buttonCompact
    readonly property int speedH: 52
    readonly property int foot: 16
    // The add pill grows with what is typed in it
    readonly property real addTarget: Math.min(100, Math.max(Style.fieldHeight, addInput.contentHeight + 17))
    property real addH: addTarget
    // The row above the add pill: where to save to, or the clipboard offer
    readonly property bool extraOn: !showHelp && (addInput.activeFocus || addInput.text.length > 0 || clip !== "")
    property real extraH: extraOn ? 38 : 0
    // Everything from the buttons down to the foot of the stage
    readonly property real belowFull: 14 + actionsH + 14 + speedH + 10 + filterH + 12 + extraH + addH + foot
    // What the details have room for, once the rest is accounted for
    readonly property real roomForDetails: Math.max(0, stageMax - readoutTop - belowFull - 100)
    // The height of the stage for what is on show right now
    property real bodyH: readoutTop + (showHelp ? sheet.height + 14 + addH + foot : readout.height + belowFull)

    // ---- State ----------------------------------------------------------
    property string secret: ""
    readonly property string home: Config.home
    property bool connected: false
    property string message: ""           // connection / auth problems (persistent)
    property string note: ""              // one-off feedback ("Added 2 downloads")
    property bool noteIsError: false
    property bool showHelp: false
    property bool primed: false           // watcher has recorded what already finished
    property var known: ({})              // gids already notified or seen finishing
    property var rows: []
    // What the rows said last time, to skip a poll that changed nothing
    property string rowsSig: ""
    property var rowMap: ({})
    property var counts: ({
            "all": 0,
            "active": 0,
            "queued": 0,
            "done": 0,
            "failed": 0
        })
    property var stat: ({
            "downloadSpeed": 0,
            "uploadSpeed": 0,
            "numActive": 0,
            "numWaiting": 0
        })
    property var speedHistory: []
    property var globalOpt: ({})
    property string tab: "all"
    property string query: ""
    property var shownGids: []
    property string cursorGid: ""
    property var selected: ({})
    property string expandedGid: ""
    property int savePick: 0
    property string clip: ""
    property string lastAdded: ""
    property var pendingDelete: []        // gids waiting for a second shift+del
    property var fileJobs: []
    // Where each shown download sits along the dial, in disc units
    property var posMap: ({})
    // Downloads that were just removed and are shrinking away
    property var ghosts: []
    // Downloads that arrived while the panel was open, and when
    property var arrived: ({})
    property bool seenThisOpen: false
    readonly property bool typing: addInput.activeFocus || searchInput.activeFocus
    readonly property int selectedCount: Object.keys(selected).length
    // Opens on the monitor that has focus (set in open())
    property var targetScreen: Focus.screen

    readonly property var cur: connected && rowMap[cursorGid] ? rowMap[cursorGid] : null
    readonly property bool hasCur: cur !== null && shownGids.length > 0
    // aria2 is not answering (and we know where to look for it)
    readonly property bool down: !connected && secret !== ""
    // Connected, but nothing to show
    readonly property bool blank: connected && shownGids.length === 0
    readonly property bool detailsOpen: hasCur && expandedGid !== "" && expandedGid === cursorGid
    readonly property bool armedCur: cursorGid !== "" && pendingDelete.indexOf(cursorGid) >= 0
    readonly property int selectedIndex: {
        const i = shownGids.indexOf(cursorGid);
        return i < 0 ? 0 : i;
    }
    readonly property real targetPos: posMap[cursorGid] !== undefined ? posMap[cursorGid] : 0

    // Open / close animation state
    property bool isOpen: false
    // 0 = hidden, 1 = shown
    property real reveal: 0
    // Slots the dial is swung to the left while arriving (and right when leaving)
    property real spinIn: 0
    // 1 = tight rainbow dome, 0 = the resting dial
    property real fan: 1
    // 0..1..0 slow breath for the rings
    property real breath: 0
    // 0..1 each time the panel opens: drives the speed graph rising in
    property real intro: 1
    // The readout fades up when another download is selected
    property real swap: 1
    // The readout and the sheet of keys swap places with a quick dip
    property real helpSwap: 1
    // The discs dip when the filter changes
    property real listSwap: 1
    property bool animateView: false
    property real wheelAcc: 0
    // The speed on show: eased towards the real one
    property real shownSpeed: stat.downloadSpeed
    property string tip: ""

    // Radius of the dial right now: curvature eases from the dome to the dial
    readonly property real dialNow: 1 / (1 / dialR + (1 / rainbowR - 1 / dialR) * fan)

    // Where the dial is turned to; glides to the selected download
    property real viewPos: targetPos

    // The discs that exist: those near the selected one, plus the ones that are
    // shrinking away. `pos` is where each sits along the dial in disc units; a
    // removed one keeps the spot it had, which the next download now takes, so
    // its neighbours close the gap while it shrinks.
    readonly property var entries: {
        if (!connected)
            return [];
        const n = shownGids.length;
        const lo = Math.max(0, selectedIndex - windowN);
        const hi = Math.min(n, selectedIndex + windowN + 1);
        const out = [];
        for (let i = lo; i < hi; i++) {
            const g = shownGids[i];
            out.push({
                "id": g,
                "row": rowMap[g] || blankRow,
                "pos": posMap[g] !== undefined ? posMap[g] : i,
                "gone": false
            });
        }
        for (const gh of ghosts) {
            if (Math.abs(gh.pos - targetPos) <= windowN + 1) {
                out.push({
                    "id": gh.gid,
                    "row": gh.row,
                    "pos": gh.pos,
                    "gone": true
                });
            }
        }
        return out;
    }

    // ---- What the readout says ----------------------------------------------
    readonly property string headText: {
        if (down)
            return "Not running";
        if (!hasCur)
            return "";
        let t = stateLabel(cur.state) + "  \u00b7  " + (cur.isBt ? (cur.metadata ? "Magnet" : "Torrent") : "Link");
        if (shownGids.length > 1)
            t += "  \u00b7  " + (selectedIndex + 1) + "/" + shownGids.length;
        if (selectedCount > 0)
            t += "  \u00b7  " + selectedCount + " selected";
        return t;
    }
    readonly property string nameText: {
        if (down)
            return "aria2 isn't running";
        if (blank)
            return rows.length === 0 ? "No downloads yet" : "Nothing matches";
        return hasCur ? cur.name : "";
    }
    readonly property string statusText: {
        if (down)
            return "The panel talks to the aria2 user service on port 6800.";
        if (blank)
            return rows.length === 0 ? "Paste a link, a magnet or a .torrent path below." : "Try another filter or search.";
        return hasCur ? statusLine(cur) : "";
    }

    Behavior on viewPos {
        enabled: dl.animateView

        // The dial glides into place and settles, with no bounce
        NumberAnimation {
            duration: Style.enterMs
            easing.type: Style.easeEnter
        }
    }

    Behavior on bodyH {
        NumberAnimation {
            duration: Style.moveMs
            easing.type: Style.easeMove
        }
    }

    Behavior on addH {
        NumberAnimation {
            duration: Style.baseMs
            easing.type: Style.easeMove
        }
    }

    Behavior on extraH {
        NumberAnimation {
            duration: Style.moveMs
            easing.type: Style.easeMove
        }
    }

    // The speed rolls to its new value instead of jumping
    Behavior on shownSpeed {
        NumberAnimation {
            duration: Style.moveMs
            easing.type: Style.easeMove
        }
    }

    onCursorGidChanged: {
        if (expandedGid !== "" && expandedGid !== cursorGid)
            expandedGid = "";
        if (isOpen)
            swapAnim.restart();
    }

    // The sheet and the readout swap places with a quick dip
    onShowHelpChanged: helpAnim.restart()

    // A link went in: the add pill lights up and its plus pops
    onNoteChanged: {
        if (note.indexOf("Added") === 0) {
            addFlashAnim.restart();
            plusPop.restart();
        }
    }

    // ---- Helpers --------------------------------------------------------
    function clamp(v, a, b) {
        return Math.max(a, Math.min(b, v));
    }

    function mod(a, b) {
        return ((a % b) + b) % b;
    }

    function ease(p) {
        return 1 - Math.pow(1 - p, 3);
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

    // `base` washed with one of the palette's colours, chosen by position x on
    // the stage (colour1 on the left through colour6 on the right). The wash is
    // `fan` strong, so it only shows while the dial is arriving or leaving, and
    // it follows the wallpaper like everything else in the shell.
    function spectral(base, x, a) {
        const ramp = [Colors.color1, Colors.color2, Colors.color3, Colors.color4, Colors.color5, Colors.color6];
        const t = (clamp((x - stageW / 2) / (stageW * 0.34), -1, 1) * 0.5 + 0.5) * (ramp.length - 1);
        const i = Math.min(ramp.length - 2, Math.floor(t));
        const c = Qt.tint(ramp[i], Qt.alpha(ramp[i + 1], t - i));
        return Qt.alpha(Qt.tint(base, Qt.alpha(c, 0.9 * fan)), a);
    }

    function stateLabel(s) {
        switch (s) {
        case "downloading":
            return "Downloading";
        case "seeding":
            return "Seeding";
        case "checking":
            return "Checking";
        case "paused":
            return "Paused";
        case "done":
            return "Finished";
        case "failed":
            return "Failed";
        case "cancelled":
            return "Cancelled";
        default:
            return "Queued";
        }
    }

    // The line under a download's name
    function statusLine(m) {
        switch (m.state) {
        case "failed":
            return m.error !== "" ? m.error : "Failed";
        case "done":
            return "Done    " + Aria2.bytes(m.total);
        case "cancelled":
            return "Cancelled";
        case "queued":
            return "Queued #" + m.pos + (m.total > 0 ? "    " + Aria2.bytes(m.total) : "");
        case "paused":
            return "Paused    " + Aria2.bytes(m.done) + (m.total > 0 ? " of " + Aria2.bytes(m.total) : "");
        case "checking":
            return "Checking files\u2026 " + Math.floor(m.fraction * 100) + "%";
        case "seeding":
            return "Seeding    \u2191 " + Aria2.rate(m.upSpeed) + "    ratio " + m.ratio.toFixed(2) + "    " + m.conns + (m.conns === 1 ? " peer" : " peers");
        default:
            if (m.metadata)
                return "Fetching magnet metadata\u2026    " + m.conns + (m.conns === 1 ? " peer" : " peers");
            let s = Aria2.bytes(m.done) + " of " + Aria2.bytes(m.total) + "    " + Aria2.rate(m.speed);
            if (m.speed > 0 && m.total > m.done)
                s += "    " + Aria2.dur((m.total - m.done) / m.speed) + " left";
            return s;
        }
    }

    // How much of the ring around a disc is lit
    function ringOf(m) {
        switch (m.state) {
        case "seeding":
        case "done":
        case "failed":
            return 1;
        case "cancelled":
            return 0;
        default:
            return m.fraction;
        }
    }

    // ---- Formatting -----------------------------------------------------
    function limitLabel(v) {
        v = Number(v || 0);
        return v === 0 ? "Unlimited" : Aria2.bytes(v) + "/s";
    }

    function toneOf(s) {
        switch (s) {
        case "downloading":
            return Colors.accent;
        case "seeding":
        case "done":
            return Colors.success;
        case "failed":
            return Colors.critical;
        case "checking":
        case "paused":
            return Colors.color3;
        default:
            return Colors.muted;
        }
    }

    function glyphOf(s) {
        switch (s) {
        case "downloading":
            return Icons.download;
        case "seeding":
            return Icons.upload;
        case "checking":
            return Icons.refresh;
        case "paused":
            return Icons.pause;
        case "done":
            return Icons.check;
        case "failed":
            return Icons.warning;
        case "cancelled":
            return Icons.close;
        default:
            return Icons.clock;
        }
    }

    // ---- RPC ------------------------------------------------------------
    // Raw JSON-RPC call; cb receives the parsed response object.
    function rpc(method, params, cb) {
        const xhr = new XMLHttpRequest();
        xhr.open("POST", rpcUrl);
        xhr.setRequestHeader("Content-Type", "application/json");
        xhr.onreadystatechange = function () {
            if (xhr.readyState !== XMLHttpRequest.DONE)
                return;
            // aria2 answers a failed call (bad gid, wrong secret) with HTTP 400
            // and the error as JSON. That is a reply, not a lost connection.
            if (xhr.status === 200 || xhr.status === 400) {
                let res = null;
                try {
                    res = JSON.parse(xhr.responseText);
                } catch (e) {
                    message = "aria2 sent a reply the panel couldn't read";
                    return;
                }
                if (cb)
                    cb(res);
            } else if (connected) {
                // Only on the way down: while aria2 stays away nothing is
                // reassigned, so the closed-panel check every few seconds
                // wakes no bindings
                connected = false;
                message = "";
                stat = {
                    "downloadSpeed": 0,
                    "uploadSpeed": 0,
                    "numActive": 0,
                    "numWaiting": 0
                };
            }
        };
        xhr.send(JSON.stringify({
            "jsonrpc": "2.0",
            "id": "qs",
            "method": method,
            "params": params
        }));
    }

    // aria2.* methods need the secret as their first parameter.
    function call(method, params, cb) {
        rpc(method, ["token:" + secret].concat(params), cb);
    }

    // Several aria2 calls in one request, executed in order.
    function batch(calls, cb) {
        if (calls.length === 0)
            return;
        rpc("system.multicall", [calls.map(function (c) {
                return {
                    "methodName": c[0],
                    "params": ["token:" + secret].concat(c[1])
                };
            })], cb);
    }

    function say(text, isError) {
        note = text;
        noteIsError = !!isError;
        noteTimer.restart();
    }

    // Run an action, report a failure, then refresh straight away.
    function act(method, params) {
        call(method, params, function (res) {
            if (res.error)
                say(res.error.message, true);
            refresh();
        });
    }

    function refresh() {
        if (secret === "")
            return;
        const t = "token:" + secret;
        const keys = rpcKeys.split(",");
        // system.multicall is exempt from the token, but every call inside it needs one.
        rpc("system.multicall", [[
                {
                    "methodName": "aria2.tellActive",
                    "params": [t, keys]
                },
                {
                    "methodName": "aria2.tellWaiting",
                    "params": [t, 0, 100, keys]
                },
                // Negative offset = newest first. (Offset 0 returns the OLDEST results,
                // so new completions would vanish once 20 downloads had finished.)
                {
                    "methodName": "aria2.tellStopped",
                    "params": [t, -1, 30, keys]
                },
                {
                    "methodName": "aria2.getGlobalStat",
                    "params": [t]
                }
            ]], function (res) {
            const r = res.result;
            if (!r) {
                message = res.error ? res.error.message : "unexpected reply from aria2";
                return;
            }
            if (r[0] && r[0].code) {
                message = r[0].message === "Unauthorized" ? "aria2 rejected the RPC secret" : r[0].message;
                return;
            }
            connected = true;
            message = "";
            ingest(r[0][0] || [], r[1][0] || [], r[2][0] || [], r[3][0] || {});
        });
    }

    function ingest(active, waiting, stopped, st) {
        const prev = rowMap;
        waiting.forEach(function (d, i) {
            d._pos = i + 1;
        });
        // Finished magnet links leave a "[METADATA]" stub that points at the real download.
        const real = stopped.filter(function (d) {
            return !(d.followedBy && d.followedBy.length > 0);
        });
        const arr = active.concat(waiting, real).map(d => Aria2.toRow(d));
        const map = {};
        const c = {
            "all": arr.length,
            "active": 0,
            "queued": 0,
            "done": 0,
            "failed": 0
        };
        arr.forEach(function (r) {
            map[r.gid] = r;
            c[r.group] += 1;
        });
        // Nothing about the downloads changed (all idle, or paused): leave rows,
        // counts and the dial alone, so a poll every 1.5 s wakes no bindings
        const sig = JSON.stringify(arr);
        const unchanged = seenThisOpen && sig === rowsSig;
        rowsSig = sig;
        if (!unchanged) {
            rowMap = map;
            rows = arr;
            counts = c;
        }
        stat = {
            "downloadSpeed": Number(st.downloadSpeed || 0),
            "uploadSpeed": Number(st.uploadSpeed || 0),
            "numActive": Number(st.numActive || 0),
            "numWaiting": Number(st.numWaiting || 0)
        };
        const h = speedHistory.slice(-(historyLength - 1));
        h.push(stat.downloadSpeed);
        speedHistory = h;

        // Downloads that turn up while the panel is open land with a glint;
        // the ones already there when it opened just arrive with the dial
        if (seenThisOpen) {
            const now = Date.now();
            const a = {};
            Object.keys(arrived).forEach(function (g) {
                if (now - arrived[g] < 4000)
                    a[g] = arrived[g];
            });
            arr.forEach(function (r) {
                if (!prev[r.gid])
                    a[r.gid] = now;
            });
            arrived = a;
        }
        seenThisOpen = true;

        // Whatever finishes while the panel is open needs no toast later.
        const k = known;
        real.forEach(function (d) {
            k[d.gid] = true;
        });
        active.forEach(function (d) {
            if (d.seeder === "true") {
                k[d.gid] = true;
                k["s:" + d.gid] = true;
            }
        });
        known = k;
        primed = true;
        if (!unchanged)
            recompute(true, prev);
    }

    // Where each download sits along the dial, in disc units: one step apart,
    // with a little more room where the group changes
    function layout(gids) {
        const m = {};
        let gap = 0;
        let before = "";
        for (let i = 0; i < gids.length; i++) {
            const r = rowMap[gids[i]];
            const g = r ? r.group : "";
            if (i > 0 && g !== before)
                gap += groupGap;
            m[gids[i]] = i + gap;
            before = g;
        }
        return m;
    }

    // Work out what is shown. `animate` is true for a refresh (a removed
    // download shrinks away where it was and the dial glides) and false when
    // the list itself changed (opening, a new filter or search): then the dial
    // snaps. `prev` is the table of rows from before the refresh.
    function recompute(animate, prev) {
        const q = query.trim().toLowerCase();
        const order = {
            "active": 0,
            "queued": 1,
            "failed": 2,
            "done": 3
        };
        const out = rows.map(function (r, i) {
            return {
                "r": r,
                "i": i
            };
        }).filter(function (x) {
            return (tab === "all" || x.r.group === tab) && (q === "" || x.r.name.toLowerCase().indexOf(q) >= 0);
        }).sort(function (x, y) {
            return (order[x.r.group] - order[y.r.group]) || (x.i - y.i);
        }).map(function (x) {
            return x.r.gid;
        });
        const oldShown = shownGids;
        const oldPos = posMap;
        const oldAt = oldShown.indexOf(cursorGid);
        if (!animate)
            animateView = false;
        shownGids = out;
        posMap = layout(out);

        // What dropped out of the list shrinks away where it was
        if (animate && isOpen) {
            const keep = ghosts.filter(function (g) {
                return out.indexOf(g.gid) < 0;
            });
            oldShown.forEach(function (g) {
                if (out.indexOf(g) >= 0 || keep.some(k => k.gid === g))
                    return;
                keep.push({
                    "gid": g,
                    "pos": oldPos[g] !== undefined ? oldPos[g] : 0,
                    "row": rowMap[g] || (prev && prev[g]) || blankRow
                });
            });
            ghosts = keep;
            if (keep.length > 0)
                ghostTimer.restart();
        } else {
            ghosts = [];
        }

        // The selection stays on its download; if that went, it moves to the
        // neighbour that took its place (or the first one after a new filter)
        if (out.indexOf(cursorGid) < 0)
            cursorGid = out.length > 0 ? out[animate ? clamp(oldAt, 0, out.length - 1) : 0] : "";
        animateView = true;
        const sel = {};
        Object.keys(selected).forEach(function (g) {
            if (rowMap[g])
                sel[g] = true;
        });
        if (Object.keys(sel).length !== Object.keys(selected).length)
            selected = sel;
        if (expandedGid !== "" && !rowMap[expandedGid])
            expandedGid = "";
    }

    function loadGlobal() {
        if (secret === "")
            return;
        call("aria2.getGlobalOption", [], function (res) {
            if (res.result)
                globalOpt = res.result;
        });
    }

    // ---- Closed-panel watcher: toast when something finishes --------------
    function watch() {
        if (secret === "")
            return;
        const t = "token:" + secret;
        rpc("system.multicall", [[
                {
                    "methodName": "aria2.tellActive",
                    "params": [t, ["gid", "seeder"]]
                },
                {
                    "methodName": "aria2.tellStopped",
                    "params": [t, -1, 15, ["gid", "status", "followedBy", "errorMessage"]]
                }
            ]], function (res) {
            const r = res.result;
            if (!r || (r[0] && r[0].code))
                return;
            connected = true;
            const k = known;
            const events = [];
            (r[0][0] || []).forEach(function (d) {
                if (d.seeder === "true" && !k["s:" + d.gid]) {
                    k["s:" + d.gid] = true;
                    k[d.gid] = true;
                    events.push({
                        "gid": d.gid,
                        "ok": true,
                        "msg": ""
                    });
                }
            });
            (r[1][0] || []).forEach(function (d) {
                if (k[d.gid])
                    return;
                k[d.gid] = true;
                if (d.followedBy && d.followedBy.length > 0)
                    return;
                if (d.status === "complete")
                    events.push({
                        "gid": d.gid,
                        "ok": true,
                        "msg": ""
                    });
                else if (d.status === "error")
                    events.push({
                        "gid": d.gid,
                        "ok": false,
                        "msg": d.errorMessage || ""
                    });
            });
            known = k;
            if (!primed) {
                primed = true;   // first pass only records what already exists
                return;
            }
            events.forEach(announce);
        });
    }

    // Notification text is rendered by whatever shows it, and filenames come from the
    // remote side, so swap angle brackets for look-alikes. A name like <img src=...>
    // then can't be read as markup anywhere.
    function defang(t) {
        return t.replace(/</g, "\u2039").replace(/>/g, "\u203a");
    }

    function announce(ev) {
        call("aria2.tellStatus", [ev.gid, ["files", "bittorrent", "infoHash"]], function (res) {
            const name = defang(res.result ? Aria2.nameOf(res.result) : ev.gid);
            const msg = defang(ev.msg);
            Quickshell.execDetached(["notify-send", "-a", "Downloads", "-i", "folder-download", ev.ok ? "Download complete" : "Download failed", msg ? name + "\n" + msg : name]);
        });
    }

    // ---- Adding downloads -------------------------------------------------
    function saveDir() {
        const p = savePresets[savePick];
        return p && p.dir !== "" && home !== "" ? home + "/" + p.dir : "";
    }

    function addTextTo(text, dir) {
        const tokens = text.split(/\s+/).filter(function (t) {
            return t.length > 0;
        });
        let added = 0;
        let bad = "";
        tokens.forEach(function (tok) {
            let t = tok;
            if (t.indexOf("file://") === 0) {
                try {
                    t = decodeURIComponent(t.slice(7));
                } catch (e) {
                    t = t.slice(7);
                }
            }
            if (t.indexOf("~/") === 0 && home !== "")
                t = home + t.slice(1);
            const opts = dir !== "" ? {
                "dir": dir
            } : {};
            if (/^(magnet:|https?:|ftp:|sftp:)/i.test(t)) {
                call("aria2.addUri", [[t], opts], function (res) {
                    if (res.error)
                        say(res.error.message, true);
                    refresh();
                });
                added++;
            } else if (t.charAt(0) === "/" && /\.torrent$/i.test(t)) {
                queueFile(t, "aria2.addTorrent", opts);
                added++;
            } else if (t.charAt(0) === "/" && /\.(metalink|meta4)$/i.test(t)) {
                queueFile(t, "aria2.addMetalink", opts);
                added++;
            } else if (bad === "") {
                bad = tok;
            }
        });
        if (added > 0)
            lastAdded = text.trim();
        if (bad !== "")
            say("Not a link or .torrent path: " + (bad.length > 40 ? bad.slice(0, 40) + "\u2026" : bad), true);
        else if (added > 0)
            say(added === 1 ? "Added 1 download" : "Added " + added + " downloads", false);
        return added;
    }

    function addText(text, dir) {
        return addTextTo(text, dir);
    }

    function submitAdd() {
        const text = addInput.text;
        addInput.text = "";
        if (text.trim().length > 0)
            addText(text, saveDir());
        leaveInput();
    }

    function queueFile(path, method, opts) {
        const jobs = fileJobs.slice();
        jobs.push({
            "path": path,
            "method": method,
            "opts": opts
        });
        fileJobs = jobs;
        pumpFiles();
    }

    function pumpFiles() {
        if (fileReader.running || fileJobs.length === 0)
            return;
        fileReader.job = fileJobs[0];
        fileReader.command = ["base64", "-w0", fileJobs[0].path];
        fileReader.running = true;
    }

    function pasteClipboard() {
        if (clip === "") {
            say("No link on the clipboard", true);
            return;
        }
        addText(clip, saveDir());
        clip = "";
    }

    function setClip(text) {
        const t = text.trim();
        const looksLikeLink = t.length > 0 && t.length < 4000 && t.split(/\s+/).some(function (x) {
            return /^(magnet:|https?:\/\/|ftp:\/\/|sftp:\/\/)/i.test(x) || /^\/.+\.(torrent|metalink|meta4)$/i.test(x);
        });
        clip = looksLikeLink && t !== lastAdded ? t : "";
    }

    // ---- Actions on downloads ----------------------------------------------
    function targets() {
        const sel = Object.keys(selected);
        if (sel.length > 0)
            return sel;
        return cursorGid !== "" ? [cursorGid] : [];
    }

    function togglePause(gids) {
        const rs = gids.map(function (g) {
            return rowMap[g];
        }).filter(function (r) {
            return !!r;
        });
        const pausable = rs.filter(function (r) {
            return r.state === "downloading" || r.state === "seeding" || r.state === "checking" || r.state === "queued";
        });
        const paused = rs.filter(function (r) {
            return r.state === "paused";
        });
        const list = pausable.length > 0 ? pausable : paused;
        const method = pausable.length > 0 ? "aria2.forcePause" : "aria2.unpause";
        batch(list.map(function (r) {
            return [method, [r.gid]];
        }), function () {
            refresh();
        });
    }

    function pauseAllToggle() {
        const anyRunning = counts.active > 0 || rows.some(function (r) {
            return r.state === "queued";
        });
        act(anyRunning ? "aria2.forcePauseAll" : "aria2.unpauseAll", []);
    }

    function removeRows(gids, deleteFiles) {
        gids.forEach(function (gid) {
            const r = rowMap[gid];
            if (!r)
                return;
            const finish = function () {
                call("aria2.removeDownloadResult", [gid], function () {
                    refresh();
                });
            };
            // Finished data is never deleted, only unfinished downloads' leftovers.
            const wipe = deleteFiles && !r.complete;
            if (r.live)
                call("aria2.forceRemove", [gid], function () {
                    if (wipe)
                        deletePartial(r);
                    finish();
                });
            else {
                if (wipe)
                    deletePartial(r);
                finish();
            }
        });
        selected = ({});
        pendingDelete = [];
    }

    // Only files aria2 itself lists for this download, plus its .aria2 control files.
    function deletePartial(r) {
        const paths = [];
        r.files.forEach(function (f) {
            if (f.path !== "" && f.path.charAt(0) === "/") {
                paths.push(f.path);
                paths.push(f.path + ".aria2");
            }
        });
        if (r.isBt && r.dir !== "")
            paths.push(r.dir + "/" + r.name + ".aria2");
        if (paths.length > 0)
            Quickshell.execDetached(["rm", "-f", "--"].concat(paths));
    }

    function askRemove(deleteFiles) {
        let gids = targets();
        if (gids.length === 0)
            return;
        if (!deleteFiles) {
            removeRows(gids, false);
            return;
        }
        gids = gids.filter(function (g) {
            return rowMap[g] && !rowMap[g].complete;
        });
        if (gids.length === 0) {
            say("Finished downloads are never deleted from disk", true);
            return;
        }
        const same = pendingDelete.length === gids.length && gids.every(function (g) {
            return pendingDelete.indexOf(g) >= 0;
        });
        if (same) {
            removeRows(gids, true);
        } else {
            pendingDelete = gids;
            confirmTimer.restart();
            say("Press shift+del again to remove and delete " + gids.length + (gids.length === 1 ? " download" : " downloads"), true);
        }
    }

    function retryRows(gids) {
        let n = 0;
        gids.forEach(function (gid) {
            const r = rowMap[gid];
            if (!r || r.state !== "failed")
                return;
            const uris = r.isBt ? (r.link !== "" ? [r.link] : []) : r.uris;
            if (uris.length === 0)
                return;
            n++;
            const opts = r.dir !== "" ? {
                "dir": r.dir
            } : {};
            call("aria2.addUri", [uris, opts], function (res) {
                if (res.error) {
                    say(res.error.message, true);
                    return;
                }
                call("aria2.removeDownloadResult", [gid], function () {
                    refresh();
                });
            });
        });
        if (n === 0)
            say("Nothing to retry", true);
    }

    function retryAllFailed() {
        retryRows(rows.filter(function (r) {
            return r.state === "failed";
        }).map(function (r) {
            return r.gid;
        }));
    }

    // how: "top" | "up" | "down"
    function moveQueue(how) {
        let gids = targets().filter(function (g) {
            const r = rowMap[g];
            return r && (r.state === "queued" || r.state === "paused");
        });
        if (gids.length === 0)
            return;
        // keep the selection's relative order
        gids.sort(function (a, b) {
            return rowMap[a].pos - rowMap[b].pos;
        });
        if (how === "top" || how === "down")
            gids = gids.reverse();
        batch(gids.map(function (g) {
            return ["aria2.changePosition", how === "top" ? [g, 0, "POS_SET"] : [g, how === "up" ? -1 : 1, "POS_CUR"]];
        }), function () {
            refresh();
        });
    }

    function openRow(r) {
        if (!r || r.path === "")
            return;
        Quickshell.execDetached(["sh", "-c", "xdg-open \"$1\" || gio open \"$1\"", "sh", r.path]);
        close();
    }

    function revealRow(r) {
        if (!r || r.path === "")
            return;
        Quickshell.execDetached([Config.terminal, "--title", Config.fileManager, "-e", Config.fileManager, r.path]);
        close();
    }

    function copyLink(r) {
        if (!r || r.link === "")
            return;
        Quickshell.execDetached(["wl-copy", r.link]);
        say(r.isBt ? "Magnet link copied" : "Link copied", false);
    }

    function setGlobal(key, value) {
        const o = {};
        o[key] = String(value);
        call("aria2.changeGlobalOption", [o], function (res) {
            if (res.error)
                say(res.error.message, true);
            loadGlobal();
        });
    }

    function cycleLimit(key) {
        const cur = Number(globalOpt[key] || 0);
        const i = limitPresets.indexOf(cur);
        setGlobal(key, limitPresets[(i + 1) % limitPresets.length]);
    }

    function parallel() {
        return Number(globalOpt["max-concurrent-downloads"] || 1);
    }

    function stepParallel(delta) {
        setGlobal("max-concurrent-downloads", Math.max(1, Math.min(16, parallel() + delta)));
    }

    // ---- Focus, selection, tabs --------------------------------------------
    function leaveInput() {
        keys.forceActiveFocus();
    }

    // Put the dial on `gid` without gliding there (opening, a new filter, a long jump)
    function snapTo(gid) {
        animateView = false;
        cursorGid = gid;
        animateView = true;
    }

    function jump(i) {
        if (shownGids.length === 0)
            return;
        const t = clamp(i, 0, shownGids.length - 1);
        // A long way: put the dial there instead of spinning it past hundreds
        if (Math.abs(t - selectedIndex) > 8)
            snapTo(shownGids[t]);
        else
            cursorGid = shownGids[t];
    }

    function moveCursor(delta) {
        jump(selectedIndex + delta);
    }

    function toggleSelect(gid) {
        const s = Object.assign({}, selected);
        if (s[gid])
            delete s[gid];
        else
            s[gid] = true;
        selected = s;
    }

    function selectAll() {
        const s = {};
        shownGids.forEach(function (g) {
            s[g] = true;
        });
        selected = s;
    }

    function toggleExpand(gid) {
        expandedGid = expandedGid === gid ? "" : gid;
        cursorGid = gid;
    }

    function setTab(id) {
        if (id === tab)
            return;
        tab = id;
        listSwapAnim.restart();
        recompute(false);
    }

    function stepTab(delta) {
        let i = 0;
        for (let k = 0; k < tabs.length; k++) {
            if (tabs[k].id === tab)
                i = k;
        }
        setTab(tabs[(i + delta + tabs.length) % tabs.length].id);
    }

    function startAria() {
        Quickshell.execDetached(["systemctl", "--user", "start", "aria2"]);
        message = "";
        retryTimer.restart();
    }

    // ---- Window ----------------------------------------------------------------
    function open() {
        if (isOpen)
            return;
        targetScreen = Focus.screen;
        closeAnim.stop();
        swapAnim.stop();
        helpAnim.stop();
        swap = 1;
        helpSwap = 1;
        showHelp = false;
        speedHistory = [];
        pendingDelete = [];
        expandedGid = "";
        wheelAcc = 0;
        ghosts = [];
        arrived = ({});
        seenThisOpen = false;
        isOpen = true;
        secretFile.reload();
        refresh();
        loadGlobal();
        clip = "";
        if (!clipProc.running)
            clipProc.running = true;
        secretCheck.restart();
        // Fill the dial from what we already know; the discs play their entrance
        recompute(false);
        // Fully hidden: start from the dome. Re-opened while it was still
        // leaving: carry on from where it is instead of snapping away first.
        if (reveal <= 0.001) {
            reveal = 0;
            spinIn = 3.2;
            fan = 1;
        }
        intro = 0;
        openAnim.restart();
        introAnim.restart();
        keys.forceActiveFocus();
    }

    function close() {
        if (!isOpen)
            return;
        isOpen = false;
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
        windows: [dl]
        active: dl.isOpen && dl.visible
        onCleared: {
            dl.closedAt = Date.now();
            dl.close();
        }
    }

    // Full screen, like the launcher: the shared dim goes over the whole screen and
    // the stage rises from the bottom edge, centred. A click on the dim closes.
    visible: isOpen || reveal > 0.001
    screen: targetScreen
    color: "transparent"
    exclusiveZone: 0
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "qs-downloads"
    // Exclusive, like the launcher and the clipboard: the keys work the moment
    // it opens, without clicking it first.
    WlrLayershell.keyboardFocus: isOpen ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    IpcHandler {
        function toggle() {
            dl.toggle();
        }

        function open() {
            dl.open();
        }

        function close() {
            dl.close();
        }

        function add(link: string): void {
            dl.addText(link, "");
        }

        target: "downloads"
    }

    FileView {
        id: secretFile

        path: Config.aria2SecretFile
        onLoaded: {
            dl.secret = secretFile.text().trim();
            if (dl.isOpen) {
                dl.refresh();
                dl.loadGlobal();
            } else {
                dl.watch();
            }
        }
    }


    // A link on the clipboard becomes a one-key "add" offer
    Process {
        id: clipProc

        command: ["wl-paste", "--no-newline", "--type", "text"]
        stdout: StdioCollector {
            onStreamFinished: dl.setClip(text)
        }
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0)
                dl.clip = "";
        }
    }

    // .torrent / .metalink files are read as base64 and handed to aria2
    Process {
        id: fileReader

        // The file being read. Held here, not looked up in fileJobs, because
        // the exit handler drops it from the queue and the output may still
        // be on its way.
        property var job: null

        stdout: StdioCollector {
            onStreamFinished: {
                const job = fileReader.job;
                if (job && text.trim().length > 0) {
                    dl.call(job.method, [text.trim(), [], job.opts], function (res) {
                        if (res.error)
                            dl.say(res.error.message, true);
                        dl.refresh();
                    });
                }
            }
        }
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0 && fileReader.job)
                dl.say("Couldn't read " + fileReader.job.path, true);
            dl.fileJobs = dl.fileJobs.slice(1);
            dl.pumpFiles();
        }
    }

    // Live updates while the panel is open
    Timer {
        interval: dl.pollMs
        repeat: true
        running: dl.isOpen
        onTriggered: dl.refresh()
    }

    // Quiet check for finished downloads while the panel is closed
    Timer {
        interval: dl.watchMs
        repeat: true
        running: !dl.isOpen && dl.secret !== ""
        onTriggered: dl.watch()
    }

    Timer {
        id: noteTimer

        interval: 4000
        onTriggered: dl.note = ""
    }

    Timer {
        id: confirmTimer

        interval: 4000
        onTriggered: {
            dl.pendingDelete = [];
            dl.note = "";
        }
    }

    Timer {
        id: retryTimer

        interval: 1500
        onTriggered: dl.refresh()
    }

    Timer {
        id: secretCheck

        interval: 1500
        onTriggered: {
            if (dl.secret === "")
                dl.message = "Can't read the RPC secret at " + Config.aria2SecretFile;
        }
    }

    Timer {
        id: ghostTimer

        interval: dl.collapseMs + 10
        onTriggered: dl.ghosts = []
    }

    PanelLink {
        win: dl
        name: "downloads"
    }

    // Rises smoothly. The discs swing in from the left over a tight dome and
    // unfurl into the dial.
    ParallelAnimation {
        id: openAnim

        NumberAnimation {
            target: dl
            property: "reveal"
            to: 1
            duration: Style.sweepMs
            easing.type: Style.easeEnter
        }
        NumberAnimation {
            target: dl
            property: "spinIn"
            to: 0
            duration: Style.sweepMs + Style.moveMs
            easing.type: Style.easeEnter
        }
        NumberAnimation {
            target: dl
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
            target: dl
            property: "reveal"
            to: 0
            duration: Style.moveMs + Style.fadeMs
            easing.type: Style.easeExit
        }
        NumberAnimation {
            target: dl
            property: "spinIn"
            to: -3.2
            duration: Style.moveMs + Style.fadeMs
            easing.type: Style.easeExit
        }
        NumberAnimation {
            target: dl
            property: "fan"
            to: 1
            duration: Style.moveMs + Style.fadeMs
            easing.type: Style.easeExit
        }
    }

    // Slow breath for the rings (only while the panel is open)
    SequentialAnimation {
        running: dl.isOpen
        loops: Animation.Infinite

        NumberAnimation {
            target: dl
            property: "breath"
            from: 0
            to: 1
            duration: Style.ambientMs * 2
            easing.type: Style.easeAmbient
        }
        NumberAnimation {
            target: dl
            property: "breath"
            from: 1
            to: 0
            duration: Style.ambientMs * 2
            easing.type: Style.easeAmbient
        }
    }

    // Drives the speed graph rising in
    NumberAnimation {
        id: introAnim

        target: dl
        property: "intro"
        from: 0
        to: 1
        duration: Style.ambientMs
        easing.type: Easing.Linear
    }

    // A different download is selected: the words fade up
    NumberAnimation {
        id: swapAnim

        target: dl
        property: "swap"
        from: 0
        to: 1
        duration: Style.baseMs
        easing.type: Style.easeMove
    }

    // The readout and the sheet of keys swap places with a quick dip
    NumberAnimation {
        id: helpAnim

        target: dl
        property: "helpSwap"
        from: 0.45
        to: 1
        duration: Style.baseMs
        easing.type: Style.easeMove
    }

    // A new filter: the discs dip and come back
    NumberAnimation {
        id: listSwapAnim

        target: dl
        property: "listSwap"
        from: 0.4
        to: 1
        duration: Style.baseMs
        easing.type: Style.easeMove
    }

    // Keyboard handling for the dial. The add and search pills handle their own keys.
    Item {
        id: keys

        anchors.fill: parent
        focus: dl.isOpen
        Keys.onPressed: event => {
            const k = event.key;
            const shift = (event.modifiers & Qt.ShiftModifier) !== 0;
            const ctrl = (event.modifiers & Qt.ControlModifier) !== 0;
            const row = dl.rowMap[dl.cursorGid];
            // Turning the dial may repeat; removing, pausing or toggling
            // something must not, or a held key would sweep the whole list
            const turn = k === Qt.Key_Down || k === Qt.Key_Up || k === Qt.Key_Left || k === Qt.Key_Right || k === Qt.Key_PageDown || k === Qt.Key_PageUp || ((k === Qt.Key_J || k === Qt.Key_K || k === Qt.Key_H || k === Qt.Key_L) && !ctrl && !shift);
            if (event.isAutoRepeat && !turn) {
                event.accepted = true;
                return;
            }
            event.accepted = true;
            if (dl.showHelp) {
                dl.showHelp = false;
            } else if (k === Qt.Key_Escape) {
                if (dl.selectedCount > 0)
                    dl.selected = ({});
                else if (dl.expandedGid !== "")
                    dl.expandedGid = "";
                else if (dl.query !== "") {
                    searchInput.text = "";
                } else
                    dl.close();
            } else if (k === Qt.Key_Question || k === Qt.Key_F1) {
                dl.showHelp = true;
            } else if (k === Qt.Key_Down || k === Qt.Key_Right || ((k === Qt.Key_J || k === Qt.Key_L) && !ctrl && !shift)) {
                dl.moveCursor(1);
            } else if (k === Qt.Key_Up || k === Qt.Key_Left || ((k === Qt.Key_K || k === Qt.Key_H) && !ctrl && !shift)) {
                dl.moveCursor(-1);
            } else if (k === Qt.Key_PageDown) {
                dl.moveCursor(5);
            } else if (k === Qt.Key_PageUp) {
                dl.moveCursor(-5);
            } else if (k === Qt.Key_Home) {
                dl.moveCursor(-9999);
            } else if (k === Qt.Key_End) {
                dl.moveCursor(9999);
            } else if (k === Qt.Key_Return || k === Qt.Key_Enter) {
                if (dl.cursorGid !== "")
                    dl.toggleExpand(dl.cursorGid);
            } else if (k === Qt.Key_Space) {
                dl.togglePause(dl.targets());
            } else if (k === Qt.Key_S && !shift) {
                if (dl.cursorGid !== "") {
                    dl.toggleSelect(dl.cursorGid);
                    dl.moveCursor(1);
                }
            } else if (k === Qt.Key_A && ctrl) {
                dl.selectAll();
            } else if (k === Qt.Key_A) {
                addInput.forceActiveFocus();
            } else if (k === Qt.Key_V) {
                dl.pasteClipboard();
            } else if (k === Qt.Key_Delete || k === Qt.Key_Backspace) {
                dl.askRemove(shift);
            } else if (k === Qt.Key_R) {
                if (shift)
                    dl.retryAllFailed();
                else
                    dl.retryRows(dl.targets());
            } else if (k === Qt.Key_U || k === Qt.Key_BracketLeft) {
                dl.moveQueue("up");
            } else if (k === Qt.Key_D || k === Qt.Key_BracketRight) {
                dl.moveQueue("down");
            } else if (k === Qt.Key_T && shift) {
                dl.moveQueue("top");
            } else if (k === Qt.Key_O) {
                dl.openRow(row);
            } else if (k === Qt.Key_F) {
                dl.revealRow(row);
            } else if (k === Qt.Key_Y) {
                dl.copyLink(row);
            } else if (k === Qt.Key_C) {
                dl.act("aria2.purgeDownloadResult", []);
            } else if (k === Qt.Key_P && shift) {
                dl.pauseAllToggle();
            } else if (k === Qt.Key_L && shift) {
                dl.cycleLimit("max-overall-download-limit");
            } else if (k === Qt.Key_Plus || k === Qt.Key_Equal) {
                dl.stepParallel(1);
            } else if (k === Qt.Key_Minus) {
                dl.stepParallel(-1);
            } else if (k === Qt.Key_Slash) {
                searchInput.forceActiveFocus();
            } else if (k >= Qt.Key_1 && k <= Qt.Key_5) {
                dl.setTab(dl.tabs[k - Qt.Key_1].id);
            } else if (k === Qt.Key_Tab) {
                dl.stepTab(1);
            } else if (k === Qt.Key_Backtab) {
                dl.stepTab(-1);
            } else {
                event.accepted = false;
            }
        }
    }

    // Text with a soft outline in the background colour, so it reads over any
    // wallpaper without a panel behind it
    component OutText: Txt {
        style: Text.Outline
        styleColor: Qt.alpha(Colors.background, 0.85)
    }

    // The shared dim (Dim.qml): the same wash as the screenshot tool
    Dim {
        reveal: dl.reveal
        closes: true
        onClicked: dl.close()
    }

    // ---- Stage ----------------------------------------------------------
    Item {
        id: stage

        readonly property real cx: width / 2
        // Where each row of the foot sits; everything is placed from the bottom
        // of the stage, so it stays put while the stage grows above it
        readonly property real footY: height - dl.foot - dl.addH
        readonly property real extraY: footY - dl.extraH
        readonly property real filterY: extraY - 12 - dl.filterH
        readonly property real speedY: filterY - 10 - dl.speedH
        readonly property real actionsY: speedY - 14 - dl.actionsH
        // The rows under the readout give way to the sheet of keys
        property real stackFade: dl.showHelp ? 0 : 1

        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        width: dl.stageW
        height: Math.min(dl.bodyH, dl.stageMax)
        clip: true
        opacity: Math.min(1, dl.reveal * 3)
        transform: Translate {
            y: (1 - dl.reveal) * (stage.height + 40)
        }

        Behavior on stackFade {
            NumberAnimation {
                duration: Style.fadeMs
            }
        }

        // Scroll wheel turns the dial. Pressing anywhere on the stage gives
        // the keyboard back to the dial.
        MouseArea {
            anchors.fill: parent
            onPressed: mouse => {
                dl.leaveInput();
                mouse.accepted = false;
            }
            onWheel: wheel => {
                const d = wheel.angleDelta.y !== 0 ? wheel.angleDelta.y : -wheel.angleDelta.x;
                if (d === 0)
                    return;
                // One step per notch (120). A touchpad sends many small
                // deltas; counting them keeps one swipe from spinning the dial
                // through the whole list.
                if ((d < 0) !== (dl.wheelAcc < 0))
                    dl.wheelAcc = 0;
                dl.wheelAcc += d;
                while (dl.wheelAcc <= -120) {
                    dl.moveCursor(1);
                    dl.wheelAcc += 120;
                }
                while (dl.wheelAcc >= 120) {
                    dl.moveCursor(-1);
                    dl.wheelAcc -= 120;
                }
            }
        }

        // Feathered backing: a soft dark ellipse keeps the words and the scale
        // readable over any wallpaper without a visible panel edge. It is as
        // tall as the stage is, so it never meets the edge of the window.
        StageShade {
            id: scrimShape
            yScale: Math.min(1.2, stage.height * 0.94 / scrimShape.r)
        }

        // A second, flatter backing under the buttons, the speed ruler and the
        // pills: they rest on the faint `well` fill, which needs something dark
        // behind it to read over a bright wallpaper
        Shape {
            id: poolShape

            readonly property real r: dl.contentW * 0.66
            readonly property real ry: Math.min(stage.height * 0.55, 190)

            x: stage.cx - r
            y: stage.height - 70 - r
            width: r * 2
            height: r * 2
            layer.enabled: true
            layer.samples: 4
            opacity: dl.stage_(0.2, 0.7)
            transform: Scale {
                origin.x: poolShape.r
                origin.y: poolShape.r
                yScale: poolShape.ry / poolShape.r
            }

            ShapePath {
                strokeColor: "transparent"
                startX: 0
                startY: poolShape.r

                fillGradient: RadialGradient {
                    centerX: poolShape.r
                    centerY: poolShape.r
                    centerRadius: poolShape.r
                    focalX: poolShape.r
                    focalY: poolShape.r

                    GradientStop {
                        position: 0
                        color: Qt.alpha(Colors.background, 0.9)
                    }
                    GradientStop {
                        position: 0.75
                        color: Qt.alpha(Colors.background, 0.75)
                    }
                    GradientStop {
                        position: 1
                        color: Qt.alpha(Colors.background, 0)
                    }
                }

                PathArc {
                    x: poolShape.r * 2
                    y: poolShape.r
                    radiusX: poolShape.r
                    radiusY: poolShape.r
                }
                PathArc {
                    x: 0
                    y: poolShape.r
                    radiusX: poolShape.r
                    radiusY: poolShape.r
                }
            }
        }

        // Low accent light on the horizon
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
                        color: Qt.alpha(Colors.accent, 0.14)
                    }
                    GradientStop {
                        position: 0.5
                        color: Qt.alpha(Colors.accent, 0.05)
                    }
                    GradientStop {
                        position: 1
                        color: Qt.alpha(Colors.accent, 0)
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
        // rise a little, like a magnifier --------------------------------
        Repeater {
            // Not kept around while the panel is hidden
            model: dl.visible ? dl.tickN : 0

            delegate: Rectangle {
                id: tick

                required property int index

                readonly property real s: (index - dl.tickN / 2) * dl.tickGap - dl.mod(dl.viewPos * dl.stepPx - dl.spinIn * dl.stepPx * 0.5, dl.tickGap * 10)
                readonly property real a: s / dl.dialNow
                readonly property real rr: dl.dialNow - dl.ruleDrop
                readonly property bool major: index % 10 === 0
                readonly property real near: Math.max(0, 1 - Math.abs(s) / 90)

                x: stage.cx + rr * Math.sin(a) - 0.75
                y: dl.topY + dl.dialNow - rr * Math.cos(a)
                width: 1.5
                height: (major ? 9 : 5) + 6 * near
                radius: 0.75
                antialiasing: true
                visible: Math.abs(a) < 1.2
                transformOrigin: Item.Top
                rotation: a * 180 / Math.PI
                // Washed with the wallpaper's palette while arriving, then the
                // accent near the middle
                color: Qt.tint(dl.spectral(Colors.foreground, x, major ? 0.46 : 0.28), Qt.alpha(Colors.accent, 0.7 * near))
                opacity: dl.clamp((stage.cx - Math.abs(x - stage.cx)) / 90, 0, 1) * dl.clamp(dl.reveal * 2 - Math.abs(x - stage.cx) / stage.cx * 0.9, 0, 1)
            }
        }

        // The middle of the ruler: the accent's 2px, standing where the
        // selected download is.
        Rectangle {
            x: stage.cx - 1
            y: dl.ruleY - 3
            width: 2
            height: 16
            radius: 1
            color: Colors.accent
            opacity: dl.clamp(dl.reveal * 2 - 0.5, 0, 1)
        }

        // ---- The discs --------------------------------------------------
        Item {
            id: dialLayer

            anchors.fill: parent
            opacity: dl.listSwap

            Repeater {
                // The discs only exist while the panel is on screen, and only
                // the ones near the middle
                model: ScriptModel {
                    values: dl.visible ? dl.entries : []
                    objectProp: "id"
                }

                delegate: Item {
                    id: slot

                    required property var modelData

                    readonly property var r: modelData ? modelData.row : dl.blankRow
                    readonly property string gid: modelData ? modelData.id : ""
                    readonly property string st: r.state
                    readonly property color tone: dl.toneOf(st)
                    // Animated, so the neighbours of a removed disc glide closed
                    property real pos: modelData ? modelData.pos : 0
                    readonly property bool current: modelData ? !modelData.gone && modelData.id === dl.cursorGid : false
                    readonly property bool picked: dl.selected[gid] === true
                    readonly property bool armed: dl.pendingDelete.indexOf(gid) >= 0
                    // Checking files, or fetching a magnet's metadata
                    readonly property bool breathing: st === "checking" || (r.metadata && st === "downloading")
                    readonly property real rel: pos - dl.viewPos
                    // Swung left while arriving, right while leaving
                    readonly property real s: (rel - dl.spinIn) * dl.stepPx
                    readonly property real a: s / dl.dialNow
                    // 0 at rest, 1 when selected. Animated, so the disc swells.
                    property real grow: current ? 1 : 0
                    // 0 -> 1 while the disc shrinks away after being removed
                    property real gone: modelData && modelData.gone ? 1 : 0
                    // 0..1 while the ring around a newly selected disc expands
                    property real ping: 0
                    // 0..1 as a new download's glint leaves it
                    property real glint: 0
                    // 1 -> 0 as a finished or failed download lights its edge
                    property real flash: 0
                    // 1 -> 0: the badge pops when a download finishes
                    property real pop: 0
                    // The disc shakes when something went wrong or needs a second press
                    property real shakeX: 0
                    // How much of the ring is lit; rolls to its new value
                    property real sweep: dl.ringOf(r)
                    // 0 at rest, 1 under the pointer: a gentle lift
                    property real hover: area.containsMouse && !current ? 1 : 0
                    readonly property real sz: dl.discSize + (dl.selectedSize - dl.discSize) * grow
                    readonly property real px: stage.cx + dl.dialNow * Math.sin(a)
                    // The selected one also lifts a little off the dial
                    readonly property real py: dl.topY + dl.dialNow * (1 - Math.cos(a)) - 5 * grow
                    // Arrive in a left-to-right wave, each with a small overshoot
                    readonly property real appear: dl.clamp(dl.reveal * 2.2 - (dl.clamp(rel, -6, 6) + 6) * 0.09, 0, 1)
                    readonly property real edge: dl.clamp((stage.cx - Math.abs(px - stage.cx)) / 90, 0, 1)

                    visible: Math.abs(rel) < 7 && opacity > 0.01
                    width: sz
                    height: sz
                    x: px - sz / 2
                    y: py - sz / 2
                    z: current ? 20 : 10
                    opacity: appear * edge * (1 - gone)
                    scale: (0.55 + 0.45 * dl.backOut(appear)) * (1 - 0.7 * gone) * (1 + 0.12 * pop)
                    // Tilts along the dial, and rises from below as it arrives
                    rotation: a * 180 / Math.PI * 0.6
                    transform: [
                        Translate {
                            y: (1 - slot.appear) * 30 - 3 * slot.hover
                        },
                        Translate {
                            x: slot.shakeX
                        }
                    ]

                    Behavior on pos {
                        enabled: dl.isOpen && dl.reveal > 0.8

                        NumberAnimation {
                            duration: Style.moveMs
                            easing.type: Style.easeMove
                        }
                    }

                    Behavior on gone {
                        NumberAnimation {
                            duration: dl.collapseMs
                            easing.type: Style.easeExit
                        }
                    }

                    Behavior on hover {
                        NumberAnimation {
                            duration: Style.baseMs
                            easing.type: Style.easeMove
                        }
                    }

                    Behavior on sweep {
                        NumberAnimation {
                            duration: Style.moveMs
                            easing.type: Style.easeMove
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

                    // A download that turned up while the panel was open lands
                    // with a glint (the ones there at the start just arrive)
                    Component.onCompleted: {
                        const t = dl.arrived[gid];
                        if (t !== undefined && Date.now() - t < 1500 && dl.reveal > 0.8)
                            glintAnim.restart();
                    }

                    // The selection moved to this one: a ring leaves it.
                    onCurrentChanged: if (current && dl.isOpen && dl.reveal > 0.8)
                        pingAnim.restart()

                    // Finished: the edge lights green and the badge pops.
                    // Failed: the disc shakes and the edge lights red.
                    onStChanged: {
                        if (!dl.isOpen || dl.reveal < 0.8 || (modelData && modelData.gone))
                            return;
                        if (st === "done" || st === "seeding") {
                            flashAnim.restart();
                            popAnim.restart();
                        } else if (st === "failed") {
                            flashAnim.restart();
                            shakeAnim.restart();
                        }
                    }

                    // Waiting for a second shift+del: shake once
                    onArmedChanged: if (armed && dl.isOpen)
                        shakeAnim.restart()

                    NumberAnimation {
                        id: pingAnim

                        target: slot
                        property: "ping"
                        from: 0
                        to: 1
                        duration: Style.sweepMs
                        easing.type: Style.easeMove
                    }

                    NumberAnimation {
                        id: glintAnim

                        target: slot
                        property: "glint"
                        from: 0
                        to: 1
                        duration: Style.sweepMs
                        easing.type: Style.easeMove
                    }

                    NumberAnimation {
                        id: flashAnim

                        target: slot
                        property: "flash"
                        from: 0.95
                        to: 0
                        duration: Style.ambientMs
                        easing.type: Style.easeMove
                    }

                    NumberAnimation {
                        id: popAnim

                        target: slot
                        property: "pop"
                        from: 1
                        to: 0
                        duration: Style.moveMs
                        easing.type: Style.easeMove
                    }

                    SequentialAnimation {
                        id: shakeAnim

                        NumberAnimation {
                            target: slot
                            property: "shakeX"
                            to: -5
                            duration: 50
                        }
                        NumberAnimation {
                            target: slot
                            property: "shakeX"
                            to: 5
                            duration: 80
                        }
                        NumberAnimation {
                            target: slot
                            property: "shakeX"
                            to: 0
                            duration: 110
                            easing.type: Style.easeMove
                        }
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
                        border.color: Qt.alpha(Colors.accent, 0.5 * (1 - slot.ping))
                    }

                    // Ring that leaves a new download.
                    Rectangle {
                        anchors.centerIn: parent
                        width: parent.width + 8 + 30 * slot.glint
                        height: width
                        radius: width / 2
                        color: "transparent"
                        antialiasing: true
                        visible: slot.glint > 0.001 && slot.glint < 0.999
                        border.width: 1.5
                        border.color: Qt.alpha(Colors.accent, 0.7 * (1 - slot.glint))
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
                        border.color: Qt.alpha(Colors.accent, slot.grow * (0.25 + 0.25 * dl.breath))
                    }

                    // Waiting for a second press: a red ring that breathes
                    Rectangle {
                        anchors.centerIn: parent
                        width: parent.width + 10
                        height: width
                        radius: width / 2
                        color: "transparent"
                        antialiasing: true
                        visible: slot.armed
                        border.width: 1.5
                        border.color: Qt.alpha(Colors.critical, 0.25 + 0.5 * dl.breath)
                    }

                    // Glass, like the bar: one flat surface with a hairline
                    // outline, lit in the accent once selected. The outline
                    // takes the palette wash while the dial is arriving.
                    Rectangle {
                        anchors.fill: parent
                        radius: width / 2
                        antialiasing: true
                        color: Style.card
                        border.width: 1
                        border.color: slot.current ? dl.spectral(Colors.accent, slot.px, 0.9) : dl.spectral(Colors.foreground, slot.px, slot.hover > 0.5 ? 0.5 : 0.32)

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
                        color: Qt.alpha(Colors.accent, slot.current ? Style.tintAlpha : 0)

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

                    // The ring inside the edge: it fills as the download does,
                    // in the state's colour (that colour is the data)
                    Shape {
                        anchors.fill: parent
                        layer.enabled: true
                        layer.samples: 4
                        // Stays upright while the disc tilts with the dial
                        rotation: -slot.rotation

                        ShapePath {
                            strokeColor: Qt.alpha(slot.tone, 0.2)
                            strokeWidth: 2
                            fillColor: "transparent"

                            PathAngleArc {
                                centerX: slot.width / 2
                                centerY: slot.height / 2
                                radiusX: slot.width / 2 - 5
                                radiusY: slot.height / 2 - 5
                                startAngle: -90
                                sweepAngle: 359.9
                            }
                        }

                        ShapePath {
                            strokeColor: slot.sweep > 0.004 ? slot.tone : "transparent"
                            strokeWidth: 2.5
                            capStyle: ShapePath.RoundCap
                            fillColor: "transparent"

                            PathAngleArc {
                                centerX: slot.width / 2
                                centerY: slot.height / 2
                                radiusX: slot.width / 2 - 5
                                radiusY: slot.height / 2 - 5
                                startAngle: -90
                                sweepAngle: Math.max(0.1, Math.min(359.9, slot.sweep * 360))
                            }
                        }
                    }

                    // Finished or failed: the edge lights up and fades
                    Rectangle {
                        anchors.fill: parent
                        radius: width / 2
                        color: "transparent"
                        antialiasing: true
                        visible: slot.flash > 0.01
                        border.width: 2
                        border.color: Qt.alpha(slot.tone, slot.flash)
                    }

                    // What state it is in; it breathes while files are checked
                    // or a magnet's metadata is fetched
                    Txt {
                        anchors.centerIn: parent
                        text: dl.glyphOf(slot.st)
                        color: slot.tone
                        opacity: slot.breathing ? 0.45 + 0.55 * dl.breath : 0.9
                        font.pixelSize: slot.sz * 0.4
                        rotation: -slot.rotation
                    }

                    // Part of a selection
                    Rectangle {
                        visible: slot.picked
                        x: parent.width - 16
                        y: -2
                        width: 16
                        height: 16
                        radius: 8
                        antialiasing: true
                        color: Colors.accent

                        Txt {
                            anchors.centerIn: parent
                            text: Icons.check
                            color: Colors.onAccent
                            font.pixelSize: Style.fontXs
                        }
                    }

                    // Click to bring it to the middle; click the one in the
                    // middle to open its details; ctrl+click to select. Position,
                    // not hover, so the dial never turns under a mouse you are
                    // only passing over.
                    MouseArea {
                        id: area

                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: mouse => {
                            if (!slot.modelData || slot.modelData.gone)
                                return;
                            dl.leaveInput();
                            const i = dl.shownGids.indexOf(slot.gid);
                            if (i < 0)
                                return;
                            if (mouse.modifiers & Qt.ControlModifier) {
                                dl.jump(i);
                                dl.toggleSelect(slot.gid);
                            } else if (slot.current) {
                                dl.toggleExpand(slot.gid);
                            } else {
                                dl.jump(i);
                            }
                        }
                    }
                }
            }
        }

        // Nothing here: one quiet disc in the middle, in place of the dial
        Item {
            id: emptyDisc

            readonly property real appear: dl.stage_(0.1, 0.6)

            x: stage.cx - width / 2
            y: dl.topY - 5 - height / 2
            width: dl.selectedSize
            height: dl.selectedSize
            opacity: dl.down || dl.blank ? appear : 0
            visible: opacity > 0.01
            scale: 0.55 + 0.45 * dl.backOut(appear)

            Behavior on opacity {
                NumberAnimation {
                    duration: Style.baseMs
                }
            }

            Rectangle {
                anchors.fill: parent
                radius: width / 2
                antialiasing: true
                color: Style.card
                border.width: 1
                border.color: dl.down ? Qt.alpha(Colors.critical, 0.5) : Qt.alpha(Colors.foreground, 0.2)
            }

            Txt {
                anchors.centerIn: parent
                text: dl.down ? Icons.warning : (dl.rows.length === 0 ? Icons.download : Icons.search)
                color: dl.down ? Colors.critical : Colors.muted
                // It breathes while it waits for aria2 to come up
                opacity: dl.down ? 0.45 + 0.55 * dl.breath : 1
                font.pixelSize: 24
            }
        }

        // Accent underline under the selected disc; it breathes with the ring.
        Rectangle {
            visible: dl.hasCur
            width: 20 + 10 * dl.breath
            height: 2
            radius: 1
            color: Colors.accent
            x: stage.cx - width / 2
            y: dl.topY - 5 + dl.selectedSize / 2 + 6
            opacity: dl.clamp(dl.reveal * 2 - 0.6, 0, 1)
        }

        // ---- The middle: what the selected download is ------------------------
        Item {
            id: readout

            // The glint along the running bar
            property real sheen: 0

            x: stage.cx - width / 2
            y: dl.readoutTop
            width: Math.min(560, dl.contentW)
            height: readCol.implicitHeight
            // Clicks pass through to the dial
            enabled: false
            opacity: (dl.showHelp ? 0 : dl.helpSwap) * (0.25 + 0.75 * dl.swap) * dl.stage_(0.25, 0.8)
            visible: opacity > 0.01
            transform: Translate {
                y: (1 - dl.stage_(0.25, 0.8)) * 12 + (1 - dl.swap) * 6
            }

            SequentialAnimation {
                running: dl.isOpen && dl.hasCur && dl.cur.state === "downloading"
                loops: Animation.Infinite

                NumberAnimation {
                    target: readout
                    property: "sheen"
                    from: 0
                    to: 1
                    duration: Style.ambientMs * 2
                    easing.type: Style.easeAmbient
                }
                PauseAnimation {
                    duration: Style.ambientMs
                }
            }

            Column {
                id: readCol

                width: parent.width
                spacing: 8

                // Connection / auth problems stay on screen until they clear
                OutText {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    visible: dl.message !== ""
                    wrapMode: Text.WordWrap
                    text: Icons.warning + "  " + dl.message
                    color: Colors.critical
                    font.pixelSize: Style.fontMd
                }

                // What it is, and where it is in the list
                OutText {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    visible: dl.headText !== ""
                    elide: Text.ElideRight
                    text: dl.headText
                    // Brighter than the muted grey, with a thin outline in the
                    // background colour: it stays readable over any wallpaper
                    color: Qt.alpha(Colors.foreground, 0.78)
                    font.pixelSize: Style.fontSm
                    font.letterSpacing: 1.4
                    font.capitalization: Font.AllUppercase
                }

                // Its name
                OutText {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    visible: dl.nameText !== ""
                    elide: Text.ElideMiddle
                    text: dl.nameText
                    color: dl.hasCur ? Qt.alpha(Colors.foreground, 0.95) : Colors.muted
                    font.pixelSize: 18
                    font.bold: true
                }

                // Its status line (or what to do next, when there is nothing)
                OutText {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    visible: dl.statusText !== ""
                    wrapMode: Text.WordWrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                    text: dl.statusText
                    color: dl.hasCur && dl.cur.state === "failed" ? Colors.critical : Qt.alpha(Colors.foreground, 0.72)
                    font.pixelSize: Style.fontMd
                }

                // A thin bar and the percent
                Item {
                    width: parent.width
                    height: 14
                    visible: dl.hasCur && dl.cur.state !== "cancelled"

                    Row {
                        anchors.centerIn: parent
                        spacing: 10

                        Item {
                            id: bar

                            readonly property real frac: dl.hasCur ? (dl.cur.state === "seeding" ? 1 : dl.cur.fraction) : 0
                            readonly property color tone: dl.hasCur ? dl.toneOf(dl.cur.state) : Colors.muted

                            width: Math.min(340, readout.width - 100)
                            height: 3
                            anchors.verticalCenter: parent.verticalCenter

                            Rectangle {
                                anchors.fill: parent
                                radius: 1.5
                                color: Qt.alpha(Colors.foreground, 0.3)
                            }

                            Rectangle {
                                id: fill

                                width: parent.width * bar.frac
                                height: parent.height
                                radius: 1.5
                                color: bar.tone
                                clip: true

                                Behavior on width {
                                    NumberAnimation {
                                        duration: Style.moveMs
                                        easing.type: Style.easeMove
                                    }
                                }

                                // A glint sweeping along a running download
                                Rectangle {
                                    visible: dl.hasCur && dl.cur.state === "downloading" && !dl.cur.metadata
                                    width: 36
                                    height: parent.height
                                    x: -width + (fill.width + width) * readout.sheen

                                    gradient: Gradient {
                                        orientation: Gradient.Horizontal

                                        GradientStop {
                                            position: 0
                                            color: Qt.alpha(Colors.foreground, 0)
                                        }
                                        GradientStop {
                                            position: 0.5
                                            color: Qt.alpha(Colors.foreground, 0.5)
                                        }
                                        GradientStop {
                                            position: 1
                                            color: Qt.alpha(Colors.foreground, 0)
                                        }
                                    }
                                }
                            }
                        }

                        OutText {
                            width: 38
                            anchors.verticalCenter: parent.verticalCenter
                            text: Math.floor(bar.frac * 100) + "%"
                            color: bar.tone
                            font.pixelSize: Style.fontMd
                            font.bold: true
                        }
                    }
                }

                // The details: the stage grows first, then these ease in
                Loader {
                    width: parent.width
                    active: dl.detailsOpen
                    visible: active
                    sourceComponent: detailsComp
                }
            }

            Component {
                id: detailsComp

                Item {
                    id: det

                    readonly property var r: dl.hasCur ? dl.cur : dl.blankRow
                    readonly property int infoH: r.info.length * 19
                    // How many lines of files there is room for
                    readonly property int lineRoom: Math.max(0, Math.floor((dl.roomForDetails - infoH - 12) / 17))
                    readonly property int showN: r.files.length <= Math.min(8, lineRoom) ? r.files.length : Math.max(0, Math.min(8, lineRoom - 1))
                    readonly property bool multi: r.files.length > 1

                    height: detCol.y + detCol.implicitHeight

                    NumberAnimation on opacity {
                        from: 0
                        to: 1
                        duration: Style.baseMs
                        easing.type: Style.easeMove
                    }

                    Column {
                        id: detCol

                        y: 6
                        width: parent.width
                        spacing: 3

                        Repeater {
                            model: det.r.info

                            delegate: Row {
                                required property var modelData

                                width: detCol.width
                                height: 16
                                spacing: 10

                                OutText {
                                    width: 84
                                    horizontalAlignment: Text.AlignRight
                                    text: modelData[0]
                                    color: Qt.alpha(Colors.foreground, 0.6)
                                    font.pixelSize: Style.fontSm
                                    anchors.verticalCenter: parent.verticalCenter
                                }

                                OutText {
                                    width: parent.width - 94
                                    text: modelData[1]
                                    color: Qt.alpha(Colors.foreground, 0.9)
                                    elide: Text.ElideMiddle
                                    font.pixelSize: Style.fontMd
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }
                        }

                        // Files inside a torrent or metalink
                        Item {
                            width: 1
                            height: 6
                            visible: det.multi && det.showN > 0
                        }

                        Repeater {
                            model: det.multi ? det.r.files.slice(0, det.showN) : []

                            delegate: Row {
                                required property var modelData

                                width: detCol.width
                                height: 14
                                spacing: 10

                                OutText {
                                    width: parent.width - 100 - 20
                                    text: modelData.name
                                    color: Qt.alpha(Colors.foreground, 0.85)
                                    elide: Text.ElideMiddle
                                    font.pixelSize: Style.fontMd
                                    anchors.verticalCenter: parent.verticalCenter
                                }

                                OutText {
                                    width: 66
                                    horizontalAlignment: Text.AlignRight
                                    text: Aria2.bytes(modelData.len)
                                    color: Qt.alpha(Colors.foreground, 0.6)
                                    font.pixelSize: Style.fontSm
                                    anchors.verticalCenter: parent.verticalCenter
                                }

                                OutText {
                                    width: 34
                                    horizontalAlignment: Text.AlignRight
                                    text: modelData.len > 0 ? Math.floor(modelData.done / modelData.len * 100) + "%" : ""
                                    color: Qt.alpha(Colors.foreground, 0.6)
                                    font.pixelSize: Style.fontSm
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }
                        }

                        OutText {
                            visible: det.multi && det.r.files.length > det.showN
                            text: "and " + (det.r.files.length - det.showN) + " more files"
                            color: Qt.alpha(Colors.foreground, 0.6)
                            font.pixelSize: Style.fontSm
                        }
                    }
                }
            }
        }

        // ---- The sheet of keys: takes the readout's place ---------------------
        Item {
            id: sheet

            x: stage.cx - width / 2
            y: dl.readoutTop
            width: Math.min(640, dl.contentW)
            height: sheetCol.implicitHeight
            opacity: dl.showHelp ? dl.helpSwap : 0
            visible: opacity > 0.01

            Behavior on opacity {
                enabled: !dl.showHelp

                NumberAnimation {
                    duration: Style.fadeMs
                }
            }

            // Any click puts it away
            MouseArea {
                anchors.fill: parent
                onClicked: dl.showHelp = false
            }

            Column {
                id: sheetCol

                width: parent.width
                spacing: 14

                OutText {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: "Shortcuts  \u00b7  any key to close"
                    color: Qt.alpha(Colors.foreground, 0.78)
                    font.pixelSize: Style.fontSm
                    font.letterSpacing: 1.4
                    font.capitalization: Font.AllUppercase
                }

                Grid {
                    columns: 2
                    columnSpacing: 40
                    rowSpacing: 8

                    Repeater {
                        model: dl.keyHelp

                        delegate: Row {
                            required property var modelData

                            height: 20
                            spacing: 8

                            Row {
                                width: 124
                                height: parent.height
                                spacing: 4

                                Repeater {
                                    model: modelData.k

                                    delegate: KeyCap {
                                        required property string modelData

                                        anchors.verticalCenter: parent.verticalCenter
                                        label: modelData
                                    }
                                }
                            }

                            OutText {
                                width: (sheet.width - 40) / 2 - 132
                                anchors.verticalCenter: parent.verticalCenter
                                text: modelData.d
                                color: Qt.alpha(Colors.foreground, 0.85)
                                elide: Text.ElideRight
                                font.pixelSize: Style.fontMd
                            }
                        }
                    }
                }
            }
        }

        // ---- Under the readout: the few things you can do ----------------------
        Row {
            id: actions

            x: stage.cx - width / 2
            y: stage.actionsY
            spacing: Style.spaceMd
            visible: stage.stackFade > 0.01 && (dl.hasCur || dl.down)
            // If the row is ever wider than the stage it shrinks to fit
            scale: Math.min(1, dl.contentW / Math.max(1, actions.implicitWidth))
            opacity: dl.stage_(0.35, 0.9) * stage.stackFade

            // aria2 is not running
            TextButton {
                compact: true
                primary: true
                visible: dl.down
                text: "Start aria2"
                onClicked: dl.startAria()
            }

            TextButton {
                compact: true
                primary: true
                visible: dl.hasCur && (dl.cur.state === "paused" || dl.cur.state === "downloading" || dl.cur.state === "seeding" || dl.cur.state === "checking" || dl.cur.state === "queued")
                text: dl.hasCur && dl.cur.state === "paused" ? "Resume" : "Pause"
                hint: "space"
                onClicked: dl.togglePause(dl.targets())
            }

            TextButton {
                compact: true
                primary: true
                visible: dl.hasCur && dl.cur.state === "failed"
                text: "Retry"
                hint: "r"
                onClicked: dl.retryRows(dl.targets())
            }

            TextButton {
                compact: true
                visible: dl.hasCur && (dl.cur.state === "done" || dl.cur.state === "seeding")
                text: "Open"
                hint: "o"
                onClicked: dl.openRow(dl.cur)
            }

            TextButton {
                compact: true
                visible: dl.hasCur && dl.cur.path !== ""
                text: "Show in " + Config.fileManager
                hint: "f"
                onClicked: dl.revealRow(dl.cur)
            }

            TextButton {
                compact: true
                visible: dl.hasCur && dl.cur.link !== ""
                text: dl.hasCur && dl.cur.isBt ? "Copy magnet" : "Copy link"
                hint: "y"
                onClicked: dl.copyLink(dl.cur)
            }

            TextButton {
                compact: true
                visible: dl.hasCur && (dl.cur.state === "queued" || dl.cur.state === "paused")
                text: "To top"
                hint: "shift+t"
                onClicked: dl.moveQueue("top")
            }

            TextButton {
                compact: true
                visible: dl.hasCur
                text: dl.selectedCount > 0 ? "Remove " + dl.selectedCount : "Remove"
                hint: "del"
                onClicked: dl.askRemove(false)
            }

            // Remove and delete what was downloaded: press twice
            TextButton {
                compact: true
                minWidth: 112
                visible: dl.hasCur && !dl.cur.complete && dl.cur.state !== "cancelled"
                danger: true
                armed: dl.armedCur
                text: dl.armedCur ? "Press again" : "Delete files"
                hint: dl.armedCur ? "" : "shift+del"
                onClicked: dl.askRemove(true)
            }
        }

        // ---- The speed: a second, shorter ruler. Each tick is a sample of the
        // download speed, the newest on the right. ------------------------------
        Item {
            id: speedBand

            x: stage.cx - width / 2
            y: stage.speedY
            width: 790
            height: dl.speedH
            visible: stage.stackFade > 0.01
            scale: Math.min(1, dl.contentW / width)
            opacity: dl.stage_(0.35, 0.9) * stage.stackFade

            Column {
                x: 0
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2

                OutText {
                    text: Aria2.rate(dl.shownSpeed)
                    color: dl.stat.downloadSpeed > 0 ? Colors.foreground : Colors.muted
                    font.pixelSize: 22
                    font.bold: true

                    Behavior on color {
                        ColorAnimation {
                            duration: Style.baseMs
                        }
                    }
                }

                OutText {
                    text: "\u2191 " + Aria2.rate(dl.stat.uploadSpeed) + "   " + dl.stat.numActive + " active   " + dl.stat.numWaiting + " queued"
                    color: Qt.alpha(Colors.foreground, 0.65)
                    font.pixelSize: Style.fontSm
                }
            }

            // Download speed over the last couple of minutes. The ticks rise
            // from the left when the panel opens, and the newest is brightest.
            Item {
                id: speedGraph

                readonly property real peak: Math.max(262144, Math.max.apply(null, dl.speedHistory.concat([0])))
                readonly property real step: width / dl.historyLength
                // The ticks stand along a gentle curve, like the dial's ruler
                readonly property real sagR: 900
                readonly property real baseY: 34
                readonly property real maxH: 30

                x: 220
                width: 330
                height: parent.height

                Repeater {
                    model: dl.visible ? dl.historyLength : 0

                    delegate: Rectangle {
                        id: stick

                        required property int index

                        readonly property int at: dl.speedHistory.length - dl.historyLength + index
                        readonly property real v: at >= 0 ? dl.speedHistory[at] : 0
                        readonly property bool latest: index === dl.historyLength - 1
                        readonly property real grow: dl.ease(dl.clamp(dl.intro * 2.4 - index * 0.012, 0, 1))
                        readonly property real dx: (index - (dl.historyLength - 1) / 2) * speedGraph.step
                        property real h: (v > 0 ? Math.max(3, speedGraph.maxH * v / speedGraph.peak) : 2) * grow

                        width: 2.5
                        height: h
                        radius: 1.25
                        antialiasing: true
                        x: speedGraph.width / 2 + dx - width / 2
                        y: speedGraph.baseY + dx * dx / (2 * speedGraph.sagR) - h
                        transformOrigin: Item.Bottom
                        rotation: Math.atan(dx / speedGraph.sagR) * 180 / Math.PI
                        color: v > 0 ? Colors.accent : Qt.alpha(Colors.foreground, 0.4)
                        opacity: v > 0 ? (latest ? 1 : 0.5 + 0.4 * (index / dl.historyLength)) : 1

                        Behavior on h {
                            enabled: dl.intro >= 1

                            NumberAnimation {
                                duration: Style.moveMs
                                easing.type: Style.easeMove
                            }
                        }
                    }
                }
            }

            // The two overall limits: press to step through the presets
            Row {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.spaceSm

                TextButton {
                    compact: true
                    primary: Number(dl.globalOpt["max-overall-download-limit"] || 0) > 0
                    glyph: Icons.arrowDown
                    text: dl.limitLabel(dl.globalOpt["max-overall-download-limit"])
                    hint: "shift+l"
                    onClicked: dl.cycleLimit("max-overall-download-limit")
                }

                TextButton {
                    compact: true
                    primary: Number(dl.globalOpt["max-overall-upload-limit"] || 0) > 0
                    glyph: Icons.arrowUp
                    text: dl.limitLabel(dl.globalOpt["max-overall-upload-limit"])
                    onClicked: dl.cycleLimit("max-overall-upload-limit")
                }
            }
        }

        // ---- The filter, and the things that act on everything ------------------
        Row {
            id: filterRow

            x: stage.cx - width / 2
            y: stage.filterY
            height: dl.filterH
            spacing: 14
            visible: stage.stackFade > 0.01
            scale: Math.min(1, dl.contentW / Math.max(1, filterRow.implicitWidth))
            opacity: dl.stage_(0.35, 0.9) * stage.stackFade

            // All / Active / Queued / Done / Failed
            Row {
                spacing: 6

                Repeater {
                    model: dl.tabs

                    delegate: TextButton {
                        required property var modelData

                        compact: true
                        primary: dl.tab === modelData.id
                        text: modelData.label + "  " + (dl.counts[modelData.id] || 0)
                        onClicked: dl.setTab(modelData.id)
                    }
                }
            }

            // What the button under the pointer does
            OutText {
                width: 96
                anchors.verticalCenter: parent.verticalCenter
                horizontalAlignment: Text.AlignRight
                text: dl.tip
                elide: Text.ElideRight
                color: Qt.alpha(Colors.foreground, 0.7)
                font.pixelSize: Style.fontSm
            }

            Row {
                spacing: 6

                TextButton {
                    compact: true
                    glyph: Icons.pause
                    onClicked: dl.act("aria2.forcePauseAll", [])
                    onHoveredChanged: dl.tip = hovered ? "Pause all" : ""
                }

                TextButton {
                    compact: true
                    glyph: Icons.play
                    onClicked: dl.act("aria2.unpauseAll", [])
                    onHoveredChanged: dl.tip = hovered ? "Resume all" : ""
                }

                TextButton {
                    compact: true
                    danger: true
                    glyph: Icons.trash
                    onClicked: dl.act("aria2.purgeDownloadResult", [])
                    onHoveredChanged: dl.tip = hovered ? "Clear finished" : ""
                }
            }

            Row {
                spacing: 4

                TextButton {
                    compact: true
                    glyph: Icons.minus
                    onClicked: dl.stepParallel(-1)
                    onHoveredChanged: dl.tip = hovered ? "Fewer at a time" : ""
                }

                OutText {
                    height: parent.height
                    verticalAlignment: Text.AlignVCenter
                    text: dl.parallel() + " at a time"
                    color: Qt.alpha(Colors.foreground, 0.8)
                    font.pixelSize: Style.fontMd
                }

                TextButton {
                    compact: true
                    glyph: Icons.plus
                    onClicked: dl.stepParallel(1)
                    onHoveredChanged: dl.tip = hovered ? "More at a time" : ""
                }
            }
        }

        // ---- Where to save to, while adding -----------------------------------
        Row {
            id: saveRow

            readonly property bool on: addInput.activeFocus || addInput.text.length > 0

            x: stage.cx - width / 2
            y: stage.extraY
            height: 28
            spacing: Style.spaceSm
            visible: opacity > 0.01
            opacity: on ? dl.clamp(dl.extraH / 38, 0, 1) : 0
            scale: Math.min(1, dl.contentW / Math.max(1, saveRow.implicitWidth))

            Behavior on opacity {
                NumberAnimation {
                    duration: Style.baseMs
                    easing.type: Style.easeMove
                }
            }

            OutText {
                anchors.verticalCenter: parent.verticalCenter
                text: "Save to"
                color: Qt.alpha(Colors.foreground, 0.7)
                rightPadding: 4
                font.pixelSize: Style.fontMd
            }

            Repeater {
                model: dl.savePresets

                delegate: TextButton {
                    required property int index
                    required property var modelData

                    anchors.verticalCenter: parent.verticalCenter
                    compact: true
                    primary: dl.savePick === index
                    text: modelData.label !== "" ? modelData.label : (dl.globalOpt["dir"] ? Aria2.basename(dl.globalOpt["dir"]) : "Default")
                    onClicked: {
                        dl.savePick = index;
                        addInput.forceActiveFocus();
                    }
                }
            }

            KeyCap {
                anchors.verticalCenter: parent.verticalCenter
                label: "enter"
            }

            OutText {
                anchors.verticalCenter: parent.verticalCenter
                text: "add"
                color: Qt.alpha(Colors.foreground, 0.7)
                rightPadding: 4
                font.pixelSize: Style.fontSm
            }

            KeyCap {
                anchors.verticalCenter: parent.verticalCenter
                label: "tab"
            }

            OutText {
                anchors.verticalCenter: parent.verticalCenter
                text: "folder"
                color: Qt.alpha(Colors.foreground, 0.7)
                font.pixelSize: Style.fontSm
            }
        }

        // ---- A link on the clipboard: one key to add it ------------------------
        Row {
            id: clipRow

            readonly property bool on: !dl.showHelp && dl.clip !== "" && !addInput.activeFocus && addInput.text.length === 0

            x: stage.cx - width / 2
            y: stage.extraY
            height: 28
            spacing: Style.spaceMd
            visible: opacity > 0.01
            opacity: on ? dl.clamp(dl.extraH / 38, 0, 1) : 0
            scale: Math.min(1, dl.contentW / Math.max(1, clipRow.implicitWidth))

            Behavior on opacity {
                NumberAnimation {
                    duration: Style.baseMs
                    easing.type: Style.easeMove
                }
            }

            TextButton {
                anchors.verticalCenter: parent.verticalCenter
                compact: true
                primary: true
                glyph: Icons.paste
                text: "Add from clipboard"
                hint: "v"
                onClicked: dl.pasteClipboard()
            }

            OutText {
                width: 300
                anchors.verticalCenter: parent.verticalCenter
                text: dl.clip.replace(/\s+/g, " ")
                elide: Text.ElideMiddle
                color: Qt.alpha(Colors.foreground, 0.8)
                font.pixelSize: Style.fontMd
            }
        }

        // ---- The foot: paste links in, and search -------------------------------
        Item {
            id: footRow

            readonly property real addW: 440
            readonly property real gap: Style.spaceMd
            readonly property real searchW: 280

            x: stage.cx - width / 2
            y: stage.footY
            width: addW + gap + searchW
            height: dl.addH
            transformOrigin: Item.Bottom
            scale: Math.min(1, dl.contentW / width)
            opacity: dl.stage_(0.35, 0.9)

            // The add pill: a pill like the search field, growing with what is typed
            Rectangle {
                id: addBox

                anchors.left: parent.left
                anchors.bottom: parent.bottom
                width: footRow.addW
                height: dl.addH
                radius: Math.min(height / 2, Style.radiusXl)
                antialiasing: true
                color: addInput.activeFocus ? Style.hoverFill : Style.well
                border.width: 1
                border.color: addInput.activeFocus || addInput.text.length > 0 ? Qt.alpha(Colors.accent, 0.5) : "transparent"

                Behavior on color {
                    ColorAnimation {
                        duration: Style.baseMs
                    }
                }
                Behavior on border.color {
                    ColorAnimation {
                        duration: Style.baseMs
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.IBeamCursor
                    onClicked: addInput.forceActiveFocus()
                }

                // Lights up and fades when a link was added
                Rectangle {
                    id: addFlash

                    anchors.fill: parent
                    radius: parent.radius
                    color: "transparent"
                    border.width: 2
                    border.color: Colors.accent
                    opacity: 0
                    antialiasing: true
                }

                NumberAnimation {
                    id: addFlashAnim

                    target: addFlash
                    property: "opacity"
                    from: 0.95
                    to: 0
                    duration: Style.ambientMs
                    easing.type: Style.easeMove
                }

                NumberAnimation {
                    id: plusPop

                    target: plusIcon
                    property: "scale"
                    from: 1.7
                    to: 1
                    duration: Style.moveMs
                    easing.type: Style.easePop
                    easing.overshoot: 2
                }

                Txt {
                    id: plusIcon

                    x: 14
                    y: (Style.fieldHeight - implicitHeight) / 2
                    text: Icons.plus
                    color: addInput.activeFocus || addInput.text.length > 0 ? Colors.accent : Colors.muted
                    font.pixelSize: Style.fontXl
                    rotation: addInput.activeFocus ? 90 : 0

                    Behavior on color {
                        ColorAnimation {
                            duration: Style.baseMs
                        }
                    }
                    Behavior on rotation {
                        NumberAnimation {
                            duration: Style.moveMs
                            easing.type: Style.easeMove
                        }
                    }
                }

                TextEdit {
                    id: addInput

                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.leftMargin: 14 + Style.fontXl + Style.spaceMd + 4
                    anchors.rightMargin: 40
                    y: 8
                    wrapMode: TextEdit.Wrap
                    color: Colors.foreground
                    selectionColor: Qt.alpha(Colors.accent, 0.4)
                    selectedTextColor: Colors.foreground
                    selectByMouse: true
                    Keys.onPressed: event => {
                        if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && !(event.modifiers & Qt.ShiftModifier)) {
                            dl.submitAdd();
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Escape) {
                            text = "";
                            dl.leaveInput();
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Tab) {
                            dl.savePick = (dl.savePick + 1) % dl.savePresets.length;
                            event.accepted = true;
                        }
                    }

                    font {
                        family: Style.fontFamily
                        pixelSize: Style.fontLg
                    }

                    Txt {
                        visible: addInput.text.length === 0
                        text: "Paste a link, magnet or .torrent path"
                        color: Colors.muted
                        font.pixelSize: Style.fontLg
                    }
                }

                KeyCap {
                    anchors.right: parent.right
                    anchors.rightMargin: 10
                    y: (Style.fieldHeight - height) / 2
                    visible: !addInput.activeFocus && addInput.text.length === 0
                    label: "a"
                }
            }

            SearchField {
                id: searchInput

                anchors.right: parent.right
                anchors.bottom: parent.bottom
                width: footRow.searchW
                placeholder: "Search downloads"
                hint: "/"
                // Number of matches while typing
                badge: dl.query.trim() !== "" ? String(dl.shownGids.length) : ""

                onTextChanged: {
                    dl.query = text;
                    dl.recompute(false);
                }
                Keys.onEscapePressed: {
                    text = "";
                    dl.leaveInput();
                }
                Keys.onReturnPressed: dl.leaveInput()
                Keys.onDownPressed: dl.leaveInput()
            }
        }
    }

    // ---- The toast: one-off feedback, above the stage -------------------------
    TextMetrics {
        id: toastMetrics

        text: dl.note
        font.family: Style.fontFamily
        font.pixelSize: Style.fontMd
    }

    Rectangle {
        id: toast

        readonly property bool shown: dl.note !== ""

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: stage.top
        anchors.bottomMargin: shown ? 14 : 4
        width: Math.min(toastMetrics.width + 40, dl.stageW - 32)
        height: 34
        radius: height / 2
        antialiasing: true
        color: Colors.raisedAlt
        border.width: 1
        border.color: dl.noteIsError ? Qt.alpha(Colors.critical, 0.6) : Qt.alpha(Colors.foreground, 0.2)
        opacity: shown ? dl.reveal : 0
        visible: opacity > 0.01

        Behavior on opacity {
            NumberAnimation {
                duration: Style.fadeMs
            }
        }
        Behavior on anchors.bottomMargin {
            NumberAnimation {
                duration: Style.baseMs
                easing.type: Style.easeMove
            }
        }

        Txt {
            anchors.fill: parent
            anchors.leftMargin: 20
            anchors.rightMargin: 20
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
            text: dl.note
            color: dl.noteIsError ? Colors.critical : Colors.foreground
            font.pixelSize: Style.fontMd
        }
    }
}
