pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Downloads.qml
// The brain of the downloads panel. No UI in here: DownloadPanel.qml draws, this
// file keeps the state, talks to aria2 over JSON-RPC and runs yt-dlp. It lives
// outside the panel so downloads keep being watched (toasts, the schedule, the
// monthly counter, the bar's network disc) while the panel is closed, and the
// panel itself is only built while it is on screen.
//
// aria2 (user service on :6800) does files, torrents and metalinks. yt-dlp does
// video pages, in up to two slots; those jobs are rows in the same list with ids
// "yt:N" and are remembered across restarts (paused).
//
// What it understands when something is added (the panel's add pill, `dl`, the
// bar's network disc and `qs ipc call downloads add`, all the same):
//   links, magnets, .torrent and .metalink paths
//   https://x.org/img[001-100].jpg        a batch ([1-99:2] steps, [a-e] letters)
//   https://a.org/f.iso|https://b.org/f.iso    mirrors of one file
//   https://a.org/f.iso#sha256=<hex>      checked when done (sha-1, sha-512, md5)
//   curl 'https://...' -H 'Cookie: ...'   "Copy as cURL": cookies, referer, login
//   video:link  or  grab:link             force yt-dlp
//   playlist:link                         yt-dlp, the whole playlist
//   direct:link                           force aria2
// A link that is a video page (known site, .html) goes to yt-dlp, one that ends in
// a file type goes to aria2, anything else is asked about first (probe.sh).
// Every way of adding follows these rules; only the add pill (panel open) shows
// the preview sheet first.
//
// Things this fixes against the old DownloadManager.qml:
//   - links added from outside the panel were never sent to yt-dlp
//   - retry kept only the link and folder; now the headers, cookies, referer,
//     login, output name and limit come along
//   - resume (and the end of the schedule's quiet hours) restarted everything,
//     including what you paused by hand and torrents waiting for you to choose
//     their files; now only what the shell itself paused is let go
//   - a paused video grab stopped "when finished" from ever firing
//   - the usage table is pruned, preview.py no longer needs the music python

Singleton {
    id: dl

    // ---- Settings -----------------------------------------------------------
    readonly property string rpcUrl: "http://localhost:6800/jsonrpc"
    readonly property int pollMs: 1000
    readonly property int watchMs: 5000
    readonly property int historyLength: 60
    // Speed limits to cycle through, in bytes per second (0 = unlimited)
    readonly property var limitPresets: [0, 524288, 1048576, 2097152, 5242880, 10485760]
    readonly property var savePresets: Config.downloadFolders
    readonly property string home: Config.home
    readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || home + "/.local/state") + "/quickshell"
    readonly property string rpcKeys: "gid,status,totalLength,completedLength,uploadLength,downloadSpeed,uploadSpeed,connections,numSeeders,seeder,infoHash,dir,errorCode,errorMessage,followedBy,verifiedLength,verifyIntegrityPending,files,bittorrent"
    // The options a retry carries over from the failed download
    readonly property var retryKeep: ["dir", "header", "referer", "user-agent", "http-user", "http-passwd", "ftp-user", "ftp-passwd", "out", "checksum", "max-download-limit"]
    // Runs a bundled python script with whatever python there is (the music
    // module's one first, any python3 otherwise). Arguments follow.
    readonly property string pyLauncher: "p=$(command -v qs-music-py || command -v python3) || { echo '{\"ok\":false,\"error\":\"no python found\"}'; exit 0; }; exec \"$p\" \"$@\""

    // ---- State --------------------------------------------------------------
    property string secret: ""
    property bool connected: false
    // Connection or auth problems (stay until they clear)
    property string message: ""
    // One-off feedback ("Added 2 downloads")
    property string note: ""
    property bool noteIsError: false
    // The panel is wanted / its window exists (it stays until the close animation ends)
    property bool isOpen: false
    property bool shown: false

    property bool primed: false
    property var known: ({})
    property var rows: []
    property string rowsSig: ""
    property bool seenOnce: false
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
    property var lastStat: ({})
    property string clip: ""
    property string lastAdded: ""
    property int savePick: 0
    property var pendingDelete: []
    property var fileJobs: []

    // What the shell itself paused (schedule, monthly cap, "pause all"): only
    // these are let go again by the schedule. Torrents waiting for you to choose
    // their files are never restarted by anything but your choice.
    property var held: ({})
    property var awaiting: ({})
    property bool holding: false

    // Scheduler: downloads run inside Config.downloadSchedule and wait outside it
    property bool schedOn: false
    property bool windowOpen: true
    property var windowLast: null
    readonly property bool holdNew: schedOn && !windowOpen
    // What to do when the last download ends: none | suspend | hibernate | poweroff
    property string whenDone: "none"
    property bool seenBusy: false
    property int actionLeft: 0
    property bool clipSeeded: false

    // Video grabs (yt-dlp)
    property var grabs: []
    property int grabSeq: 0
    property int videoQuality: 0
    property var probeQueue: []

    // Data used this month
    property var usage: ({
            "month": "",
            "down": 0,
            "up": 0,
            "history": {},
            "warn": 0,
            "capPaused": false
        })
    property var usageLast: ({})
    property var usageFresh: ({})
    property bool usageReady: false
    readonly property string usageText: usage.month === "" ? "" : Aria2.bytes(usage.down) + (Config.downloadMonthlyCapGB > 0 ? " of " + Config.downloadMonthlyCapGB + " GB" : "") + " this month"

    // Sheets that take the list's place: a question, and the files of a torrent
    property bool confirmOpen: false
    property string confirmKind: ""
    property string confirmTitle: ""
    property string confirmSub: ""
    property var confirmLines: []
    property string confirmYes: ""
    property var confirmData: null
    property bool pickOpen: false
    property string pickGid: ""
    property string pickName: ""
    property var pickFiles: []
    property int pickCur: 0
    property bool pickWePaused: false
    property var pickQueue: []
    property var pickAsked: ({})
    property double lastTorrentAdd: 0
    readonly property int pickRows: 9
    readonly property int pickTop: Math.max(0, Math.min(pickFiles.length - pickRows, pickCur - 4))
    readonly property int pickCount: pickFiles.filter(f => f.on).length
    readonly property real pickBytes: pickFiles.reduce((a, f) => a + (f.on ? f.length : 0), 0)
    readonly property real pickTotal: pickFiles.reduce((a, f) => a + f.length, 0)
    readonly property bool sheetOpen: confirmOpen || pickOpen

    // Looking at a link first, and sweeping up leftovers
    property bool previewBusy: false
    property string previewBuf: ""
    property var previewReq: null
    property bool cleanBusy: false
    property string cleanBuf: ""
    property var cleanReq: null
    property string cleanMode: ""

    // The bar's ring: every download seen running since things were last idle
    property var burst: ({})

    readonly property bool down: !connected && secret !== ""

    onGrabsChanged: if (!saveTimer.running)
        saveTimer.start()

    function start() {
        return true;
    }

    // ---- How things look ----------------------------------------------------
    function stateLabel(s) {
        switch (s) {
        case "downloading":
            return "Downloading";
        case "seeding":
            return "Seeding";
        case "checking":
            return "Checking";
        case "merging":
            return "Finishing";
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

    function toneOf(s) {
        switch (s) {
        case "downloading":
        case "merging":
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
        case "merging":
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

    // How much of a disc's ring is lit
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

    function statusLine(m) {
        if (m.statusText)
            return m.statusText;
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
            let s = Aria2.bytes(m.done) + " of " + Aria2.bytes(m.total);
            if (m.speed > 0 && m.total > m.done)
                s += "    " + Aria2.dur((m.total - m.done) / m.speed) + " left";
            return s;
        }
    }

    function limitLabel(v) {
        v = Number(v || 0);
        return v === 0 ? "Unlimited" : Aria2.bytes(v) + "/s";
    }

    function whenLabel(m) {
        return ({
                "none": "Nothing",
                "suspend": "Sleep",
                "hibernate": "Hibernate",
                "poweroff": "Shut down"
            })[m] || "Nothing";
    }

    function tidy(path) {
        return home !== "" && path.indexOf(home) === 0 ? "~" + path.slice(home.length) : path;
    }

    // Notification text is rendered by whatever shows it, and filenames come from
    // the remote side, so swap angle brackets for look-alikes
    function defang(t) {
        return String(t).replace(/</g, "\u2039").replace(/>/g, "\u203a");
    }

    function say(text, isError) {
        note = text;
        noteIsError = !!isError;
        noteTimer.restart();
    }

    function notify(title, body, urgent) {
        const cmd = ["notify-send", "-a", "Downloads", "-i", "folder-download"];
        if (urgent)
            cmd.push("-u", "critical");
        Quickshell.execDetached(cmd.concat([title, body]));
    }

    // ---- RPC ----------------------------------------------------------------
    function rpc(method, params, cb) {
        const xhr = new XMLHttpRequest();
        xhr.open("POST", rpcUrl);
        xhr.setRequestHeader("Content-Type", "application/json");
        xhr.onreadystatechange = function () {
            if (xhr.readyState !== XMLHttpRequest.DONE)
                return;
            // aria2 answers a failed call (bad gid, wrong secret) with HTTP 400
            // and the error as JSON: that is a reply, not a lost connection
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
                connected = false;
                message = "";
                stat = {
                    "downloadSpeed": 0,
                    "uploadSpeed": 0,
                    "numActive": 0,
                    "numWaiting": 0
                };
                pushStatus(stat);
            }
        };
        xhr.send(JSON.stringify({
            "jsonrpc": "2.0",
            "id": "qs",
            "method": method,
            "params": params
        }));
    }

    // aria2.* methods take the secret as their first parameter
    function call(method, params, cb) {
        const adds = method.indexOf("aria2.add") === 0;
        const hold = holdNew;
        rpc(method, ["token:" + secret].concat(params), adds ? function (res) {
            if (res.result && typeof res.result === "string") {
                usageFresh[res.result] = true;
                if (hold)
                    held[res.result] = true;
            }
            if (cb)
                cb(res);
        } : cb);
    }

    // Several calls in one request, executed in order: [[method, params], ...]
    function batch(calls, cb) {
        if (calls.length === 0)
            return;
        const hold = holdNew;
        rpc("system.multicall", [calls.map(function (c) {
                return {
                    "methodName": c[0],
                    "params": ["token:" + secret].concat(c[1])
                };
            })], function (res) {
            const list = res.result || [];
            calls.forEach(function (c, i) {
                if (c[0].indexOf("aria2.add") === 0 && Array.isArray(list[i]) && typeof list[i][0] === "string") {
                    usageFresh[list[i][0]] = true;
                    if (hold)
                        held[list[i][0]] = true;
                }
            });
            if (cb)
                cb(res);
        });
    }

    // Run an action, report a failure, refresh straight away
    function act(method, params) {
        call(method, params, function (res) {
            if (res.error)
                say(res.error.message, true);
            refresh();
        });
    }

    function firstError(res) {
        if (res.error)
            return res.error.message;
        const list = res.result || [];
        for (let i = 0; i < list.length; i++) {
            if (list[i] && list[i].code)
                return list[i].message;
        }
        return "";
    }

    function loadGlobal() {
        if (secret === "")
            return;
        call("aria2.getGlobalOption", [], function (res) {
            if (res.result)
                globalOpt = res.result;
        });
    }

    // ---- Reading aria2 ------------------------------------------------------
    function refresh() {
        if (secret === "")
            return;
        const t = "token:" + secret;
        const keys = rpcKeys.split(",");
        rpc("system.multicall", [[
                {
                    "methodName": "aria2.tellActive",
                    "params": [t, keys]
                },
                {
                    "methodName": "aria2.tellWaiting",
                    "params": [t, 0, 100, keys]
                },
                // A negative offset is newest first (offset 0 would be the oldest)
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
            if (!connected)
                windowLast = null;
            connected = true;
            message = "";
            const active = r[0][0] || [];
            const waiting = r[1][0] || [];
            const stopped = r[2][0] || [];
            const st = r[3][0] || {};
            ingest(active, waiting, stopped, st);
            checkIdle(st, active, waiting);
            usageSee(active, false);
            usageSee(stopped, true);
            usageReady = true;
            progressSee(active, stopped);
            pickScan(waiting);
        });
    }

    function ingest(active, waiting, stopped, st) {
        const prev = rowMap;
        waiting.forEach(function (d, i) {
            d._pos = i + 1;
        });
        // A finished magnet link leaves a "[METADATA]" stub pointing at the real download
        const real = stopped.filter(function (d) {
            return !(d.followedBy && d.followedBy.length > 0);
        });
        const arr = active.concat(waiting, real).map(d => Aria2.toRow(d)).concat(grabRows());
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
        // counts and the list alone, so a poll wakes no bindings
        const sig = arr.map(r => r.gid + "|" + r.state + "|" + r.done + "|" + r.speed + "|" + r.up + "|" + r.conns + "|" + r.total + "|" + r.error + "|" + (r.statusText || "")).join("\n");
        const unchanged = seenOnce && sig === rowsSig;
        rowsSig = sig;
        seenOnce = true;
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

        // Whatever finishes while the panel is open needs no toast later
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
        // Forget what no longer exists
        Object.keys(held).forEach(function (g) {
            if (!map[g])
                delete held[g];
        });
        Object.keys(awaiting).forEach(function (g) {
            if (!map[g])
                delete awaiting[g];
        });
    }

    // ---- Closed-panel watcher: toast when something finishes ----------------
    function watch() {
        if (secret === "")
            return;
        const t = "token:" + secret;
        rpc("system.multicall", [[
                {
                    "methodName": "aria2.tellActive",
                    "params": [t, ["gid", "seeder", "completedLength", "totalLength", "uploadLength", "downloadSpeed", "followedBy"]]
                },
                {
                    "methodName": "aria2.tellStopped",
                    "params": [t, -1, 15, ["gid", "status", "followedBy", "errorMessage", "completedLength", "totalLength", "uploadLength"]]
                },
                {
                    "methodName": "aria2.getGlobalStat",
                    "params": [t]
                },
                {
                    "methodName": "aria2.tellWaiting",
                    "params": [t, 0, 50, ["gid", "status", "completedLength", "infoHash"]]
                }
            ]], function (res) {
            const r = res.result;
            if (!r || (r[0] && r[0].code))
                return;
            if (!connected)
                windowLast = null;
            connected = true;
            const active = (r[0] && r[0][0]) || [];
            const stopped = (r[1] && r[1][0]) || [];
            const waiting = (r[3] && r[3][0]) || [];
            checkIdle((r[2] && r[2][0]) || {}, active, waiting);
            usageSee(active, false);
            usageSee(stopped, true);
            usageReady = true;
            progressSee(active, stopped);
            pickScan(waiting);
            const k = known;
            const events = [];
            active.forEach(function (d) {
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
            stopped.forEach(function (d) {
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
                primed = true;   // the first pass only records what already exists
                return;
            }
            events.forEach(announce);
        });
    }

    function announce(ev) {
        call("aria2.tellStatus", [ev.gid, ["files", "bittorrent", "infoHash"]], function (res) {
            const name = defang(res.result ? Aria2.nameOf(res.result) : ev.gid);
            const msg = defang(ev.msg);
            notify(ev.ok ? "Download complete" : "Download failed", msg ? name + "\n" + msg : name, false);
        });
    }

    // ---- Adding downloads ---------------------------------------------------
    function saveDir() {
        const p = savePresets[savePick];
        return p && p.dir !== "" && home !== "" ? home + "/" + p.dir : "";
    }

    // Where a new download goes and how it starts: a folder by file type (when no
    // folder was picked), and paused while the schedule is holding things back
    function baseOpts(name, dir) {
        const o = {};
        let d = dir;
        if (d === "" && Config.downloadAutoCategory && home !== "") {
            const c = Aria2.categoryDir(name, Config.downloadCategories);
            if (c !== "")
                d = home + "/" + c;
        }
        if (d !== "")
            o["dir"] = d;
        if (holdNew)
            o["pause"] = "true";
        return o;
    }

    function isDuplicate(url) {
        const gids = Object.keys(rowMap);
        for (let i = 0; i < gids.length; i++) {
            const r = rowMap[gids[i]];
            if (r.live && r.uris.indexOf(url) >= 0)
                return true;
        }
        return false;
    }

    // One download with its own headers: what a "Copy as cURL" holds, or addx
    function addRich(o, dir) {
        if (isDuplicate(o.url)) {
            say("Already in the list", true);
            return 0;
        }
        const uris = [o.url].concat(o.mirrors || []);
        const opts = baseOpts(o.out && o.out !== "" ? o.out : o.url, dir);
        const headers = (o.headers || []).slice();
        if (o.cookie && o.cookie !== "")
            headers.push("Cookie: " + o.cookie);
        if (headers.length > 0)
            opts["header"] = headers;
        if (o.referer && o.referer !== "")
            opts["referer"] = o.referer;
        if (o.ua && o.ua !== "")
            opts["user-agent"] = o.ua;
        if (o.user && o.user !== "") {
            opts["http-user"] = o.user;
            opts["http-passwd"] = o.pass || "";
            opts["ftp-user"] = o.user;
            opts["ftp-passwd"] = o.pass || "";
        }
        if (o.out && o.out !== "")
            opts["out"] = o.out;
        call("aria2.addUri", [uris, opts], function (res) {
            if (res.error)
                say(res.error.message, true);
            else
                say(holdNew ? "Added  \u00b7  waits for " + Config.downloadSchedule.start : "Added 1 download", false);
            refresh();
        });
        return 1;
    }

    // qs ipc call downloads addx '{...}'
    function addSpec(spec) {
        let o = null;
        try {
            o = JSON.parse(spec);
        } catch (e) {
            return "error: not JSON";
        }
        if (!o || typeof o.url !== "string" || !/^(https?|ftp|sftp):\/\//i.test(o.url))
            return "error: needs a \"url\"";
        let dir = typeof o.dir === "string" ? o.dir : "";
        if (dir !== "" && dir.charAt(0) !== "/" && home !== "")
            dir = home + "/" + dir;
        const n = addRich({
            "url": o.url,
            "mirrors": Array.isArray(o.mirrors) ? o.mirrors : [],
            "headers": Array.isArray(o.headers) ? o.headers : [],
            "cookie": o.cookie || "",
            "referer": o.referer || "",
            "ua": o.userAgent || "",
            "user": o.user || "",
            "pass": o.pass || "",
            "out": o.out || ""
        }, dir);
        return n > 0 ? "ok" : "skipped";
    }

    // Add whatever text holds. `preview`: with the panel open, a single plain link
    // is looked at first (the add pill). Returns how many downloads it made.
    function addText(text, dir, preview) {
        if (preview && maybePreview(text, dir))
            return 0;
        if (/^\s*curl\s/.test(text)) {
            const c = Aria2.parseCurl(text);
            if (c.error) {
                say(c.error, true);
                return 0;
            }
            const n = addRich(c, dir);
            if (n > 0)
                lastAdded = text.trim();
            return n;
        }
        const tokens = text.split(/\s+/).filter(t => t.length > 0);
        const calls = [];
        const seen = {};
        let added = 0;
        let dups = 0;
        let probing = 0;
        let cut = false;
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
            let force = "";
            const pm = /^(video|grab|playlist|direct):/i.exec(t);
            if (pm) {
                force = pm[1].toLowerCase();
                t = t.slice(pm[0].length);
            }
            if (/^https?:\/\//i.test(t) && force !== "direct") {
                const route = force !== "" ? "video" : Aria2.routeOf(t, Config.downloadVideoSites);
                if (route === "video") {
                    if (addGrab(t, force === "playlist"))
                        added++;
                    else
                        dups++;
                    return;
                }
                if (route === "probe") {
                    if (isDuplicate(t) || probeQueue.some(q => q.url === t)) {
                        dups++;
                    } else {
                        probeLink(t, dir);
                        added++;
                        probing++;
                    }
                    return;
                }
            }
            if (/^(magnet:|https?:|ftp:|sftp:)/i.test(t)) {
                const p = Aria2.parseToken(t, 1000);
                cut = cut || p.cut;
                p.groups.forEach(function (uris) {
                    if (seen[uris[0]] || isDuplicate(uris[0])) {
                        dups++;
                        return;
                    }
                    seen[uris[0]] = true;
                    const opts = metaOpts(uris[0], baseOpts(uris[0], dir));
                    if (p.checksum !== "")
                        opts["checksum"] = p.checksum;
                    calls.push(["aria2.addUri", [uris, opts]]);
                    added++;
                });
            } else if (t.charAt(0) === "/" && /\.torrent$/i.test(t)) {
                queueFile(t, "aria2.addTorrent", pickOpts(baseOpts(t, dir)));
                added++;
            } else if (t.charAt(0) === "/" && /\.(metalink|meta4)$/i.test(t)) {
                queueFile(t, "aria2.addMetalink", baseOpts(t, dir));
                added++;
            } else if (bad === "") {
                bad = tok;
            }
        });
        if (calls.length > 0)
            batch(calls, function (res) {
                const err = firstError(res);
                if (err !== "")
                    say(err, true);
                refresh();
            });
        if (added > 0)
            lastAdded = text.trim();
        if (bad !== "") {
            say("Not a link or .torrent path: " + (bad.length > 40 ? bad.slice(0, 40) + "\u2026" : bad), true);
        } else if (added > 0 && probing === added) {
            say(probing === 1 ? "Checking the link\u2026" : "Checking " + probing + " links\u2026", false);
        } else if (added > 0) {
            let msg = added === 1 ? "Added 1 download" : "Added " + added + " downloads";
            if (holdNew)
                msg += "  \u00b7  waits for " + Config.downloadSchedule.start;
            if (dups > 0)
                msg += "  \u00b7  " + dups + " already in the list";
            if (cut)
                msg += "  \u00b7  batch cut at 1000";
            say(msg, false);
        } else if (dups > 0) {
            say(dups === 1 ? "Already in the list" : dups + " already in the list", true);
        }
        return added;
    }

    // Forced to aria2, no questions asked (a link already known to be a file)
    function addFile(url, dir) {
        return addText("direct:" + url, dir, false);
    }

    // Something was dropped on the bar's network disc while the panel may be
    // closed: the disc is told how many downloads that made, and a no is also said
    // out loud, since the panel's own note is not on screen
    function addFromBar(text) {
        const n = addText(text, saveDir(), false);
        DownloadStatus.added(n);
        if (n === 0 && note !== "")
            notify("Not added", note, false);
    }

    function handleDrop(drop) {
        const text = Aria2.dropText(drop);
        drop.acceptProposedAction();
        if (text === "")
            say("Nothing to download in that", true);
        else
            addText(text, saveDir(), true);
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

    // ---- The clipboard ------------------------------------------------------
    function readClip() {
        clip = "";
        if (!clipProc.running)
            clipProc.running = true;
    }

    function setClip(text) {
        const t = text.trim();
        const looksLikeLink = t.length > 0 && t.length < 4000 && t.split(/\s+/).some(function (x) {
            return /^(magnet:|https?:\/\/|ftp:\/\/|sftp:\/\/)/i.test(x) || /^\/.+\.(torrent|metalink|meta4)$/i.test(x);
        });
        clip = looksLikeLink && t !== lastAdded ? t : "";
    }

    function pasteClipboard() {
        if (clip === "") {
            say("No link on the clipboard", true);
            return;
        }
        addText(clip, saveDir(), true);
        clip = "";
    }

    // Links copied while Config.downloadClipboardAdd is on are added at once
    function captureClip(line) {
        if (!clipSeeded) {
            clipSeeded = true;   // the first answer is what was already there
            return;
        }
        const t = line.trim();
        if (t === "" || t === lastAdded || !Aria2.isFileLink(t, Config.downloadCategories))
            return;
        if (addText(t, "", false) > 0)
            notify("Download started", defang(t.length > 90 ? t.slice(0, 90) + "\u2026" : t), false);
    }

    // ---- Actions on downloads -----------------------------------------------
    function isGrab(gid) {
        return String(gid).indexOf("yt:") === 0;
    }

    function togglePause(gids) {
        gids.filter(g => isGrab(g)).forEach(g => toggleGrabPause(g));
        const rs = gids.filter(g => !isGrab(g)).map(g => rowMap[g]).filter(r => !!r);
        const pausable = rs.filter(r => r.state === "downloading" || r.state === "seeding" || r.state === "checking" || r.state === "queued");
        const paused = rs.filter(r => r.state === "paused");
        const list = pausable.length > 0 ? pausable : paused;
        const method = pausable.length > 0 ? "aria2.forcePause" : "aria2.unpause";
        // Your own choice: the schedule and the cap no longer own these
        list.forEach(function (r) {
            delete held[r.gid];
            delete awaiting[r.gid];
        });
        batch(list.map(r => [method, [r.gid]]), function () {
            refresh();
        });
    }

    // Everything that is running or waiting is paused, and remembered as ours.
    // Asks aria2 rather than trusting the list on screen, which is not kept
    // current while the panel is closed.
    function pauseEverything() {
        batch([["aria2.tellActive", [["gid"]]], ["aria2.tellWaiting", [0, 1000, ["gid", "status"]]]], function (res) {
            const parts = res.result || [];
            if (parts.length !== 2 || !Array.isArray(parts[0]) || !Array.isArray(parts[1]))
                return;
            const calls = [];
            (parts[0][0] || []).forEach(function (d) {
                calls.push(["aria2.forcePause", [d.gid]]);
                held[d.gid] = true;
            });
            (parts[1][0] || []).forEach(function (d) {
                if (d.status === "waiting") {
                    calls.push(["aria2.forcePause", [d.gid]]);
                    held[d.gid] = true;
                }
            });
            batch(calls, function () {
                refresh();
            });
        });
        grabs.forEach(function (j) {
            if (j.state === "downloading" || j.state === "merging" || j.state === "queued") {
                held[j.id] = true;
                pauseGrab(j.id);
            }
        });
        holding = true;
    }

    // Let go of what the shell paused, and nothing else
    function releaseHeld() {
        const ids = Object.keys(held);
        const mine = ids.filter(g => !isGrab(g) && !awaiting[g]);
        const vids = ids.filter(g => isGrab(g));
        const lost = ids.length === 0 && holding;
        held = {};
        holding = false;
        if (lost) {
            // After a restart the gids are new: all that waits, minus the torrents
            // that wait for a choice, was ours
            resumeAll();
            return;
        }
        batch(mine.map(g => ["aria2.unpause", [g]]), function () {
            refresh();
        });
        vids.forEach(g => resumeGrab(g));
    }

    // The button: resume everything that is paused, except the torrents that are
    // waiting for you to choose their files
    function resumeAll() {
        held = {};
        holding = false;
        batch([["aria2.tellWaiting", [0, 1000, ["gid", "status"]]]], function (res) {
            const parts = res.result || [];
            if (parts.length !== 1 || !Array.isArray(parts[0]))
                return;
            const calls = [];
            (parts[0][0] || []).forEach(function (d) {
                if (d.status === "paused" && !awaiting[d.gid])
                    calls.push(["aria2.unpause", [d.gid]]);
            });
            batch(calls, function () {
                refresh();
            });
        });
        grabs.forEach(j => resumeGrab(j.id));
    }

    function pauseAllToggle() {
        const running = counts.active > 0 || rows.some(r => r.state === "queued");
        if (running)
            pauseEverything();
        else
            resumeAll();
    }

    function removeRows(gids, deleteFiles) {
        gids.forEach(function (gid) {
            const r = rowMap[gid];
            if (!r)
                return;
            delete held[gid];
            delete awaiting[gid];
            if (isGrab(gid)) {
                removeGrab(gid, deleteFiles && !r.complete);
                return;
            }
            const finish = function () {
                call("aria2.removeDownloadResult", [gid], function () {
                    refresh();
                });
            };
            // Finished data is never deleted, only an unfinished download's leftovers
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
        pendingDelete = [];
    }

    // Only files aria2 itself lists for this download, plus its .aria2 control files
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

    // Plain remove goes straight through; remove + delete asks for a second press.
    // Returns true when something was removed.
    function askRemove(gids, deleteFiles) {
        if (gids.length === 0)
            return false;
        if (!deleteFiles) {
            removeRows(gids, false);
            return true;
        }
        const list = gids.filter(g => rowMap[g] && !rowMap[g].complete);
        if (list.length === 0) {
            say("Finished downloads are never deleted from disk", true);
            return false;
        }
        const same = pendingDelete.length === list.length && list.every(g => pendingDelete.indexOf(g) >= 0);
        if (same) {
            removeRows(list, true);
            return true;
        }
        pendingDelete = list;
        confirmTimer.restart();
        say("Press shift+del again to remove and delete " + list.length + (list.length === 1 ? " download" : " downloads"), true);
        return false;
    }

    // Retry keeps what made the first try work: the headers and cookies, the
    // referer, the login, the file name, the checksum and the speed limit
    function retryRows(gids) {
        let n = 0;
        gids.forEach(function (gid) {
            const r = rowMap[gid];
            if (!r || r.state !== "failed")
                return;
            if (isGrab(gid)) {
                retryGrab(gid);
                n++;
                return;
            }
            const uris = r.isBt ? (r.link !== "" ? [r.link] : []) : r.uris;
            if (uris.length === 0)
                return;
            n++;
            call("aria2.getOption", [gid], function (res) {
                const src = res.result || {};
                const o = {};
                (r.isBt ? ["dir"] : retryKeep).forEach(function (k) {
                    if (src[k] !== undefined && src[k] !== "")
                        o[k] = src[k];
                });
                if (o["dir"] === undefined && r.dir !== "")
                    o["dir"] = r.dir;
                if (holdNew)
                    o["pause"] = "true";
                call("aria2.addUri", [uris, o], function (add) {
                    if (add.error) {
                        say(add.error.message, true);
                        return;
                    }
                    call("aria2.removeDownloadResult", [gid], function () {
                        refresh();
                    });
                });
            });
        });
        if (n === 0)
            say("Nothing to retry", true);
    }

    function retryAllFailed() {
        retryRows(rows.filter(r => r.state === "failed").map(r => r.gid));
    }

    // how: "top" | "up" | "down"
    function moveQueue(gids, how) {
        let list = gids.filter(function (g) {
            const r = rowMap[g];
            return r && !isGrab(g) && (r.state === "queued" || r.state === "paused");
        });
        if (list.length === 0)
            return;
        list.sort((a, b) => rowMap[a].pos - rowMap[b].pos);
        if (how === "top" || how === "down")
            list = list.reverse();
        batch(list.map(g => ["aria2.changePosition", how === "top" ? [g, 0, "POS_SET"] : [g, how === "up" ? -1 : 1, "POS_CUR"]]), function () {
            refresh();
        });
    }

    // One download's own speed limit: steps through the presets
    function cycleTaskLimit(gids) {
        const list = gids.filter(g => !isGrab(g) && rowMap[g] && rowMap[g].live);
        if (list.length === 0) {
            say("Nothing here to limit", true);
            return;
        }
        call("aria2.getOption", [list[0]], function (res) {
            const cur = Number((res.result || {})["max-download-limit"] || 0);
            const next = limitPresets[(limitPresets.indexOf(cur) + 1) % limitPresets.length];
            batch(list.map(g => ["aria2.changeOption", [g, {
                        "max-download-limit": String(next)
                    }]]), function (r2) {
                const err = firstError(r2);
                say(err !== "" ? err : "Limit for " + (list.length === 1 ? "this download" : list.length + " downloads") + ": " + limitLabel(next), err !== "");
                refresh();
            });
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

    function clearFinished() {
        act("aria2.purgeDownloadResult", []);
        grabs = grabs.filter(j => j.state !== "done" && j.state !== "failed");
    }

    function startAria() {
        Quickshell.execDetached(["systemctl", "--user", "start", "aria2"]);
        message = "";
        retryTimer.restart();
    }

    // ---- Look at a link before it starts ------------------------------------
    // A single plain link added with the panel open is asked about first
    // (downloads/preview.py): its name, size, where it would go, the room there and
    // whether it can be resumed. Config.downloadPreview: "ask" waits for Enter,
    // "note" says it and starts, "off" skips it.
    function previewUrl(text) {
        const t = text.trim();
        if (/\s/.test(t) || !/^https?:\/\//i.test(t) || t.indexOf("|") >= 0 || /#(sha|md5)/i.test(t))
            return "";
        return Aria2.routeOf(t, Config.downloadVideoSites) === "video" ? "" : t;
    }

    function previewDir(url, dir) {
        const o = baseOpts(url, dir);
        return o["dir"] || globalOpt["dir"] || (home !== "" ? home + "/Downloads" : "");
    }

    function maybePreview(text, dir) {
        if (Config.downloadPreview === "off" || !isOpen || confirmOpen || pickOpen)
            return false;
        const url = previewUrl(text);
        if (url === "" || isDuplicate(url))
            return false;
        if (previewBusy) {
            say("Still looking at the last link", true);
            return true;
        }
        previewBusy = true;
        previewBuf = "";
        previewReq = {
            "url": url,
            "dir": dir,
            "target": previewDir(url, dir)
        };
        say("Looking at the link\u2026", false);
        previewProc.command = ["sh", "-c", pyLauncher, "sh", Quickshell.shellPath("downloads/preview.py"), url, previewReq.target];
        previewProc.running = true;
        return true;
    }

    function onPreviewDone() {
        const req = previewReq;
        previewBusy = false;
        previewReq = null;
        if (req === null)
            return;
        let d = null;
        try {
            d = JSON.parse(previewBuf);
        } catch (e) {
            d = null;
        }
        // The panel was put away while it looked: add it as it was asked
        if (!isOpen) {
            if (d && d.ok && d.page && d.status < 400 && Aria2.routeOf(req.url, Config.downloadVideoSites) === "probe")
                addGrab(req.url, false);
            else
                addFile(req.url, req.dir);
            return;
        }
        // A web page behind a link that did not say so: a video's job
        if (d && d.ok && d.page && d.status < 400 && Aria2.routeOf(req.url, Config.downloadVideoSites) === "probe") {
            if (addGrab(req.url, false))
                say("It is a web page  \u00b7  looking for a video", false);
            return;
        }
        if (Config.downloadPreview === "note" && d && d.ok && d.status < 400) {
            addFile(req.url, req.dir);
            say(d.name + "  \u00b7  " + (d.size !== null ? Aria2.bytes(d.size) : "size not given"), false);
            return;
        }
        openPreview(req, d);
    }

    function openPreview(req, d) {
        const lines = [];
        let yes = "Download";
        if (d === null || !d.ok) {
            confirmTitle = req.url.length > 70 ? req.url.slice(0, 70) + "\u2026" : req.url;
            confirmSub = "No answer from the server";
            lines.push({
                "label": "Error",
                "value": d && d.error ? d.error : "it did not reply",
                "tone": "bad"
            });
            yes = "Try anyway";
        } else {
            const short = d.size !== null && d.free !== null && d.size > d.free;
            confirmTitle = d.name;
            confirmSub = (d.size !== null ? Aria2.bytes(d.size) : "Size not given") + (d.type !== "" ? "  \u00b7  " + d.type : "");
            if (d.status >= 400) {
                lines.push({
                    "label": "Server",
                    "value": "answered " + d.status,
                    "tone": "bad"
                });
                yes = "Try anyway";
            }
            lines.push({
                "label": "From",
                "value": d.host,
                "tone": ""
            });
            lines.push({
                "label": "Save to",
                "value": tidy(req.target) + (d.free !== null ? "  \u00b7  " + Aria2.bytes(d.free) + " free" : ""),
                "tone": short ? "bad" : ""
            });
            if (short)
                lines.push({
                    "label": "",
                    "value": "There is not enough room for it",
                    "tone": "bad"
                });
            lines.push({
                "label": "Resume",
                "value": d.resume === true ? "can be resumed" : (d.resume === false ? "must finish in one go" : "not said"),
                "tone": d.resume === false ? "warn" : ""
            });
        }
        confirmKind = "preview";
        confirmLines = lines;
        confirmYes = yes;
        confirmData = {
            "url": req.url,
            "dir": req.dir
        };
        confirmOpen = true;
    }

    function closeConfirm() {
        confirmOpen = false;
        confirmLines = [];
        confirmData = null;
    }

    function confirmAccept() {
        if (!confirmOpen)
            return;
        const kind = confirmKind;
        const data = confirmData;
        closeConfirm();
        if (kind === "preview")
            addFile(data.url, data.dir);
        else if (kind === "cleanup")
            deleteLeftovers(data);
    }

    function confirmKey(event) {
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
            confirmAccept();
        else if (event.key === Qt.Key_Escape)
            closeConfirm();
    }

    // ---- Sweeping up what failed downloads left behind ----------------------
    // downloads/leftovers.py finds them, and later removes exactly the ones you
    // agreed to. What aria2 and the video grabs use right now is left alone.
    function cleanupRequest(active) {
        const dirs = [];
        const add = function (d) {
            if (d !== "" && dirs.indexOf(d) < 0)
                dirs.push(d);
        };
        add(globalOpt["dir"] || (home !== "" ? home + "/Downloads" : ""));
        Config.downloadCategories.forEach(c => add(home + "/" + c.dir));
        grabs.forEach(j => (j.parts || []).forEach(p => active.push(p)));
        return {
            "aria_dirs": dirs,
            "video_dirs": Config.downloadCleanupVideoDirs.map(d => home + "/" + d),
            "active": active,
            "min_age_min": 10,
            "video_age_h": 24
        };
    }

    function runCleanup(mode, req) {
        cleanMode = mode;
        cleanBuf = "";
        cleanProc.command = ["sh", "-c", pyLauncher, "sh", Quickshell.shellPath("downloads/leftovers.py"), mode, JSON.stringify(req)];
        cleanProc.running = true;
    }

    function startCleanup() {
        if (cleanBusy || confirmOpen || pickOpen)
            return;
        cleanBusy = true;
        say("Looking for leftovers\u2026", false);
        batch([["aria2.tellActive", [["files"]]], ["aria2.tellWaiting", [0, 1000, ["files"]]]], function (res) {
            const parts = res.result || [];
            // If aria2 did not answer, everything would look abandoned: stop here
            if (parts.length !== 2 || !Array.isArray(parts[0]) || !Array.isArray(parts[1])) {
                cleanBusy = false;
                say("aria2 did not answer, so nothing was touched", true);
                return;
            }
            const active = [];
            parts.forEach(function (part) {
                (part[0] || []).forEach(function (d) {
                    (d.files || []).forEach(function (f) {
                        if (f.path) {
                            active.push(f.path);
                            active.push(f.path + ".aria2");
                        }
                    });
                });
            });
            cleanReq = cleanupRequest(active);
            runCleanup("scan", cleanReq);
        });
    }

    function onCleanDone() {
        cleanBusy = false;
        let d = null;
        try {
            d = JSON.parse(cleanBuf);
        } catch (e) {
            d = null;
        }
        if (d === null || d.ok !== true) {
            say("The clean-up did not answer", true);
            return;
        }
        if (cleanMode === "delete") {
            say(d.removed === 0 ? "Nothing was removed" : "Removed " + d.removed + (d.removed === 1 ? " file" : " files") + "  \u00b7  freed " + Aria2.bytes(d.freed) + (d.failed > 0 ? "  \u00b7  " + d.failed + " could not be removed" : ""), d.failed > 0);
            return;
        }
        if (d.count === 0) {
            say("Nothing to clean up", false);
            return;
        }
        const lines = d.items.slice(0, 6).map(function (i) {
            return {
                "label": i.kind === "aria2" ? "download" : "video",
                "value": i.name + "  \u00b7  " + Aria2.bytes(i.size),
                "tone": ""
            };
        });
        if (d.items.length > 6)
            lines.push({
                "label": "",
                "value": "and " + (d.items.length - 6) + " more",
                "tone": ""
            });
        confirmKind = "cleanup";
        confirmTitle = "Clean up leftovers";
        confirmSub = d.count + (d.count === 1 ? " leftover" : " leftovers") + "  \u00b7  " + Aria2.bytes(d.total);
        confirmLines = lines;
        confirmYes = "Delete";
        confirmData = {
            "paths": d.items.reduce((a, i) => a.concat(i.paths), [])
        };
        confirmOpen = true;
    }

    function deleteLeftovers(data) {
        cleanBusy = true;
        runCleanup("delete", Object.assign({}, cleanReq, {
            "paths": data.paths
        }));
    }

    // ---- Choosing the files inside a torrent --------------------------------
    // With Config.downloadTorrentPick a torrent file is added paused, and a magnet
    // link (or a link to a .torrent) pauses the torrent it turns into. pickScan
    // finds those once their files are known and offers the list.
    function pickOpts(o) {
        if (Config.downloadTorrentPick) {
            o["pause"] = "true";
            lastTorrentAdd = Date.now();
        }
        return o;
    }

    function metaOpts(url, o) {
        const e = Aria2.extOf(url);
        if (Config.downloadTorrentPick && (/^magnet:/i.test(url) || e === "torrent" || e === "metalink" || e === "meta4")) {
            o["pause-metadata"] = "true";
            lastTorrentAdd = Date.now();
        }
        return o;
    }

    // Raw aria2 statuses of waiting downloads: any paused torrent that has done
    // nothing yet, after one was added in the last quarter hour, is for choosing
    function pickScan(list) {
        if (!Config.downloadTorrentPick || Date.now() - lastTorrentAdd > 900000)
            return;
        list.forEach(function (d) {
            if (d.status !== "paused" || !d.infoHash || Number(d.completedLength || 0) > 0 || pickAsked[d.gid])
                return;
            pickAsked[d.gid] = true;
            call("aria2.tellStatus", [d.gid, ["files", "bittorrent", "infoHash", "dir"]], function (res) {
                const st = res.result;
                if (!st || !st.files || st.files.length === 0)
                    return;
                // The stub of a magnet link that is still looking for its metadata
                if (/^\[METADATA\]/.test(st.files[0].path || ""))
                    return;
                if (st.files.length === 1) {
                    // Nothing to choose; the schedule may still want it to wait
                    if (!holdNew)
                        act("aria2.unpause", [d.gid]);
                    return;
                }
                awaiting[d.gid] = true;
                delete held[d.gid];
                const name = defang(Aria2.nameOf(st));
                pickQueue = pickQueue.concat([
                    {
                        "gid": d.gid,
                        "name": name
                    }
                ]);
                if (isOpen)
                    nextPick();
                else
                    notify("Torrent ready", name + "\n" + st.files.length + " files to choose from", false);
            });
        });
    }

    function nextPick() {
        if (pickOpen || pickQueue.length === 0)
            return;
        const it = pickQueue[0];
        pickQueue = pickQueue.slice(1);
        openPicker(it.gid);
    }

    function openPicker(gid) {
        if (!gid) {
            say("Pick a torrent first", true);
            return;
        }
        const r = rowMap[gid];
        if (r && (!r.isBt || r.metadata)) {
            say("Only a torrent has files to choose", true);
            return;
        }
        call("aria2.tellStatus", [gid, ["files", "bittorrent", "infoHash", "status", "dir"]], function (res) {
            const st = res.result;
            // The panel was put away meanwhile: it is offered again when it opens
            if (!isOpen) {
                pickQueue = [
                    {
                        "gid": gid,
                        "name": ""
                    }
                ].concat(pickQueue);
                return;
            }
            if (!st || !st.files || st.files.length === 0 || /^\[METADATA\]/.test(st.files[0].path || "")) {
                say("No files to choose yet", true);
                return;
            }
            if (st.status === "complete" || st.status === "error" || st.status === "removed") {
                say("A finished torrent can't be changed", true);
                return;
            }
            pickFiles = Aria2.torrentFiles(st.files, st.dir);
            pickGid = gid;
            pickName = defang(Aria2.nameOf(st));
            pickCur = 0;
            pickWePaused = false;
            // Choosing changes what it will fetch: hold it while you do
            if (st.status === "active" || st.status === "waiting") {
                act("aria2.forcePause", [gid]);
                pickWePaused = true;
            }
            awaiting[gid] = true;
            pickOpen = true;
        });
    }

    function closePicker() {
        pickOpen = false;
        pickFiles = [];
        if (isOpen)
            nextPick();
    }

    // Esc: leave it as it was (a torrent that was waiting for you stays paused)
    function cancelPicker() {
        if (pickWePaused) {
            delete awaiting[pickGid];
            if (!holdNew)
                act("aria2.unpause", [pickGid]);
            else
                held[pickGid] = true;
        }
        closePicker();
    }

    function applyPick() {
        const on = pickFiles.filter(f => f.on).map(f => f.index);
        if (on.length === 0) {
            say("Tick at least one file", true);
            return;
        }
        const gid = pickGid;
        const n = pickFiles.length;
        call("aria2.changeOption", [gid, {
                "select-file": Aria2.fileRanges(on)
            }], function (res) {
            if (res.error) {
                say(res.error.message, true);
                return;
            }
            delete awaiting[gid];
            if (holdNew) {
                held[gid] = true;
                say("Chosen  \u00b7  waits for " + Config.downloadSchedule.start, false);
            } else {
                act("aria2.unpause", [gid]);
                say(on.length === n ? "Downloading all " + n + " files" : "Downloading " + on.length + " of " + n + " files", false);
            }
            refresh();
        });
        closePicker();
    }

    function pickToggle(i) {
        pickFiles = pickFiles.map((f, k) => k === i ? Object.assign({}, f, {
                "on": !f.on
            }) : f);
    }

    function pickSet(fn) {
        pickFiles = pickFiles.map(f => Object.assign({}, f, {
                "on": fn(f)
            }));
    }

    function pickMove(d) {
        pickCur = Math.max(0, Math.min(pickFiles.length - 1, pickCur + d));
    }

    function pickKey(event) {
        const k = event.key;
        if (k === Qt.Key_Escape)
            cancelPicker();
        else if (k === Qt.Key_Return || k === Qt.Key_Enter)
            applyPick();
        else if (k === Qt.Key_Space)
            pickToggle(pickCur);
        else if (k === Qt.Key_Down || k === Qt.Key_J)
            pickMove(1);
        else if (k === Qt.Key_Up || k === Qt.Key_K)
            pickMove(-1);
        else if (k === Qt.Key_PageDown)
            pickMove(pickRows - 1);
        else if (k === Qt.Key_PageUp)
            pickMove(-(pickRows - 1));
        else if (k === Qt.Key_A)
            pickSet(f => true);
        else if (k === Qt.Key_N)
            pickSet(f => false);
        else if (k === Qt.Key_I)
            pickSet(f => !f.on);
    }

    // ---- Data used this month -----------------------------------------------
    // aria2 keeps no total, so this adds up how far each download has got between
    // looks. A download added here counts from zero; one that was already running
    // when first seen counts what it does from then on, unless it plainly began
    // just now.
    function rollMonth(m) {
        const old = usage;
        const h = Object.assign({}, old.history || {});
        if (old.month !== "")
            h[old.month] = {
                "down": old.down,
                "up": old.up
            };
        const keys = Object.keys(h).sort();
        while (keys.length > 12)
            delete h[keys.shift()];
        // The limit starts over, and so does anything it paused
        if (old.capPaused)
            releaseHeld();
        return {
            "month": m,
            "down": 0,
            "up": 0,
            "history": h,
            "warn": 0,
            "capPaused": false
        };
    }

    function usageAdd(down, up) {
        if (down <= 0 && up <= 0)
            return;
        const m = Aria2.monthKey(new Date());
        const u = usage.month === m ? usage : rollMonth(m);
        usage = Object.assign({}, u, {
            "down": u.down + down,
            "up": u.up + up
        });
        usageCheckCap();
        if (!saveTimer.running)
            saveTimer.start();
    }

    function usageSee(list, stopped) {
        let dd = 0;
        let uu = 0;
        const last = usageLast;
        const secs = (isOpen ? pollMs : watchMs) / 1000;
        list.forEach(function (d) {
            const done = Number(d.completedLength || 0);
            const up = Number(d.uploadLength || 0);
            // The torrent a magnet link turns into starts from nothing too
            if (d.followedBy && usageFresh[d.gid])
                d.followedBy.forEach(g => usageFresh[g] = true);
            const prev = last[d.gid];
            if (prev === undefined) {
                const speed = Number(d.downloadSpeed || 0);
                const mine = usageReady && (usageFresh[d.gid] || (!stopped && done <= speed * secs * 1.5 + 65536));
                if (mine) {
                    dd += done;
                    uu += up;
                }
            } else {
                if (done > prev[0])
                    dd += done - prev[0];
                if (up > prev[1])
                    uu += up - prev[1];
            }
            last[d.gid] = [done, up];
        });
        // Old entries are dropped, oldest first, so the table cannot grow for ever
        const ks = Object.keys(last);
        if (ks.length > 600)
            ks.slice(0, 200).forEach(k => delete last[k]);
        usageAdd(dd, uu);
    }

    // A video grab's stream: bytes so far (the first look counts what is there if
    // it is small enough to have come in the last moment)
    function usageGrab(key, done) {
        const prev = usageLast[key];
        usageLast[key] = [done, 0];
        if (prev === undefined) {
            if (done < 2097152)
                usageAdd(done, 0);
        } else if (done > prev[0]) {
            usageAdd(done - prev[0], 0);
        }
    }

    function usageCheckCap() {
        const cap = Number(Config.downloadMonthlyCapGB) * 1e9;
        if (cap <= 0)
            return;
        const frac = usage.down / cap;
        const w = frac >= 1 ? 2 : (frac >= 0.8 ? 1 : 0);
        if (w <= usage.warn)
            return;
        usage = Object.assign({}, usage, {
            "warn": w,
            "capPaused": w === 2 && Config.downloadPauseAtCap
        });
        notify(w === 2 ? "Monthly limit reached" : "80% of the monthly limit used", Aria2.bytes(usage.down) + " of " + Config.downloadMonthlyCapGB + " GB" + (w === 2 && Config.downloadPauseAtCap ? "\nDownloads are paused until next month" : ""), w === 2);
        if (w === 2 && Config.downloadPauseAtCap)
            pauseEverything();
        saveSettings();
    }

    function usageSummary() {
        const m = usage.month === "" ? Aria2.monthKey(new Date()) : usage.month;
        return m + ": " + Aria2.bytes(usage.down) + " downloaded, " + Aria2.bytes(usage.up) + " uploaded" + (Config.downloadMonthlyCapGB > 0 ? " (limit " + Config.downloadMonthlyCapGB + " GB)" : "");
    }

    // ---- What the bar's network disc shows ----------------------------------
    // How many are running (video grabs too), how many wait, and how fast
    function pushStatus(st) {
        let active = Number(st.numActive || 0);
        let waiting = Number(st.numWaiting || 0);
        let speed = Number(st.downloadSpeed || 0);
        grabs.forEach(function (j) {
            if (j.state === "downloading" || j.state === "merging") {
                active++;
                speed += j.speed;
            } else if (j.state === "queued") {
                waiting++;
            }
        });
        lastStat = st;
        DownloadStatus.active = active;
        DownloadStatus.waiting = waiting;
        DownloadStatus.speed = speed;
        // Nothing running and nothing waiting: the burst is over
        if (active === 0 && waiting === 0) {
            burst = {};
            DownloadStatus.progress = -1;
        }
    }

    // How far the running downloads have got, for the bar's ring. Every download
    // seen running since things were last idle counts, byte for byte, and the
    // ones that finished count whole, so the ring does not fall back when one of
    // several completes. A video grab counts as 200 MB, filled by its own progress.
    function progressSee(active, stopped) {
        const b = burst;
        const grabSize = 209715200;
        const running = {};
        active.forEach(function (d) {
            running[d.gid] = true;
            const total = Number(d.totalLength || 0);
            if (total > 0)
                b[d.gid] = [Number(d.completedLength || 0), total];
        });
        (stopped || []).forEach(function (d) {
            if (running[d.gid] || b[d.gid] === undefined)
                return;
            if (d.status === "complete")
                b[d.gid] = [b[d.gid][1], b[d.gid][1]];
            else if (d.status === "error" || d.status === "removed")
                delete b[d.gid];
        });
        grabs.forEach(function (j) {
            if (j.state === "done")
                b[j.id] = b[j.id] !== undefined ? [grabSize, grabSize] : undefined;
            else if (j.state === "failed")
                delete b[j.id];
            else
                b[j.id] = [Math.min(1, j.pct) * grabSize, grabSize];
            if (b[j.id] === undefined)
                delete b[j.id];
        });
        let done = 0;
        let total = 0;
        Object.keys(b).forEach(function (g) {
            done += b[g][0];
            total += b[g][1];
        });
        DownloadStatus.progress = total > 0 ? Math.min(1, done / total) : 0;
    }

    // ---- Page or file? ------------------------------------------------------
    // A link that could be either is asked about first: downloads/probe.sh looks
    // at what the server sends. A web page is a video's job (yt-dlp), anything
    // else is a file (aria2). Four at a time.
    function probeLink(url, dir) {
        probeQueue.push({
            "url": url,
            "dir": dir
        });
        pumpProbes();
    }

    function pumpProbes() {
        const slots = [probeA, probeB, probeC, probeD];
        for (let i = 0; i < slots.length && probeQueue.length > 0; i++) {
            if (slots[i].running)
                continue;
            const q = probeQueue.shift();
            slots[i].url = q.url;
            slots[i].dir = q.dir;
            slots[i].verdict = "";
            slots[i].command = ["sh", Quickshell.shellPath("downloads/probe.sh"), q.url];
            slots[i].running = true;
        }
    }

    function onProbed(url, dir, verdict) {
        if (verdict === "page") {
            if (addGrab(url, false))
                say("It is a web page  \u00b7  looking for a video", false);
        } else {
            addFile(url, dir);
        }
        pumpProbes();
    }

    // ---- Video grabber ------------------------------------------------------
    // yt-dlp does the work (merging, tags, your own config for the folder). The
    // jobs are rows in the same list as aria2's downloads.
    function grabOf(id) {
        for (let i = 0; i < grabs.length; i++) {
            if (grabs[i].id === id)
                return grabs[i];
        }
        return null;
    }

    function patchGrab(id, patch) {
        grabs = grabs.map(j => j.id === id ? Object.assign({}, j, patch) : j);
    }

    function qualityDef() {
        const q = Config.downloadVideoQualities;
        return q[Math.max(0, Math.min(q.length - 1, videoQuality))];
    }

    function cycleQuality() {
        videoQuality = (videoQuality + 1) % Config.downloadVideoQualities.length;
        say("Video quality: " + qualityDef().label, false);
        saveSettings();
    }

    function makeGrab(o) {
        grabSeq++;
        return {
            "id": "yt:" + grabSeq,
            "url": o.url,
            "title": o.title || o.url,
            "state": o.state,
            "pct": 0,
            "done": 0,
            "total": 0,
            "speed": 0,
            "eta": 0,
            "error": o.error || "",
            "path": "",
            "part": "",
            "parts": [],
            "quality": o.quality,
            "args": o.args || [],
            "audioOnly": o.audioOnly === true,
            "playlist": o.playlist === true,
            "sawVideo": false,
            "stopReq": "",
            "archived": false
        };
    }

    function addGrab(url, playlist) {
        for (let i = 0; i < grabs.length; i++) {
            if (grabs[i].url === url && grabs[i].state !== "failed" && grabs[i].state !== "done") {
                say("Already grabbing that", true);
                return false;
            }
        }
        const q = qualityDef();
        grabs = grabs.concat([makeGrab({
                "url": url,
                "state": holdNew ? "paused" : "queued",
                "quality": q.label,
                "args": q.args,
                "audioOnly": q.audio === true,
                "playlist": playlist === true
            })]);
        if (holdNew)
            held[grabs[grabs.length - 1].id] = true;
        pumpGrabs();
        return true;
    }

    // qs ipc call downloads grab <link>, and G
    function grabLink(text) {
        const m = /(https?:\/\/\S+)/i.exec(text || "");
        if (!m) {
            say("Copy a video link first", true);
            return 0;
        }
        const ok = addGrab(m[1], false);
        if (ok)
            say("Grabbing the video  \u00b7  " + qualityDef().label, false);
        return ok ? 1 : 0;
    }

    function grabArgs(j) {
        const a = ["--newline", "--no-colors", "--progress", "--concurrent-fragments", "8", "--progress-template", "download:GRAB %(progress.downloaded_bytes)s %(progress.total_bytes)s %(progress.total_bytes_estimate)s %(progress.speed)s %(progress.eta)s %(info.vcodec)s %(info.acodec)s %(progress.tmpfilename)s", "--progress-template", "postprocess:POST %(progress.postprocessor)s %(progress.status)s", "--exec", "echo GRABFILE {}", j.playlist ? "--yes-playlist" : "--no-playlist"];
        if (Config.downloadVideoCookies !== "")
            a.push("--cookies-from-browser", Config.downloadVideoCookies);
        return a.concat(j.args, ["--", j.url]);
    }

    function slotList() {
        return [grabA, grabB].slice(0, Math.max(1, Math.min(2, Config.downloadVideoParallel)));
    }

    function pumpGrabs() {
        const slots = slotList();
        for (let i = 0; i < grabs.length; i++) {
            const j = grabs[i];
            if (j.state !== "queued")
                continue;
            let slot = null;
            for (let k = 0; k < slots.length; k++) {
                if (!slots[k].running) {
                    slot = slots[k];
                    break;
                }
            }
            if (slot === null)
                return;
            slot.jobId = j.id;
            // 2>&1: yt-dlp's errors arrive on stdout with the rest
            slot.command = ["sh", "-c", "exec yt-dlp \"$@\" 2>&1", "sh"].concat(grabArgs(j));
            patchGrab(j.id, {
                "state": "downloading",
                "stopReq": "",
                "error": "",
                "archived": false
            });
            slot.running = true;
        }
    }

    function stopSlot(id) {
        [grabA, grabB].forEach(function (sl) {
            if (sl.running && sl.jobId === id)
                sl.running = false;
        });
    }

    function onGrabLine(id, line) {
        const j = grabOf(id);
        if (j === null || j.stopReq !== "")
            return;
        if (line.indexOf("GRAB ") === 0) {
            const g = Aria2.parseGrab(line);
            usageGrab(id + g.tmp, g.done);
            const frac = g.total > 0 ? Math.min(1, g.done / g.total) : 0;
            let all = frac;
            let saw = j.sawVideo;
            // Video and sound arrive as two downloads: weigh them 85 / 15
            if (!j.audioOnly) {
                if (g.kind === "video") {
                    all = 0.85 * frac;
                    saw = true;
                } else if (g.kind === "audio" && saw) {
                    all = 0.85 + 0.15 * frac;
                }
            }
            const patch = {
                "state": "downloading",
                "pct": Math.min(0.99, all),
                "done": g.done,
                "total": g.total,
                "speed": g.speed,
                "eta": g.eta,
                "sawVideo": saw
            };
            if (g.tmp !== "" && g.tmp !== "NA") {
                patch["part"] = g.tmp;
                // Video and sound are separate files: remember each of them
                if (j.parts.indexOf(g.tmp) < 0)
                    patch["parts"] = j.parts.concat([g.tmp]);
                if (j.title === j.url)
                    patch["title"] = Aria2.titleFromPart(g.tmp);
            }
            patchGrab(id, patch);
        } else if (line.indexOf("POST ") === 0) {
            if (/ started$/.test(line))
                patchGrab(id, {
                    "state": "merging",
                    "pct": 0.99,
                    "speed": 0
                });
        } else if (line.indexOf("GRABFILE ") === 0) {
            patchGrab(id, {
                "path": line.slice(9).replace(/^'|'$/g, "")
            });
        } else if (/has already been recorded in the archive/.test(line)) {
            patchGrab(id, {
                "archived": true,
                "error": "Already downloaded (it is in your yt-dlp archive)"
            });
        } else if (line.indexOf("ERROR:") === 0 && /Unsupported URL|No video formats found|no video could be found/i.test(line)) {
            patchGrab(id, {
                "error": "No video found on that page. If it is a file, use direct:link"
            });
        } else if (line.indexOf("ERROR:") === 0) {
            patchGrab(id, {
                "error": line.replace(/^ERROR:\s*(\[[^\]]*\]\s*)?([\w-]{11}:\s*)?/, "").slice(0, 140)
            });
        }
    }

    function onGrabExit(id, code) {
        pushStatus(lastStat);
        const j = grabOf(id);
        if (j !== null) {
            if (j.stopReq === "pause") {
                patchGrab(id, {
                    "state": "paused",
                    "stopReq": "",
                    "speed": 0
                });
            } else if (j.stopReq === "") {
                if (code === 0 && !j.archived) {
                    patchGrab(id, {
                        "state": "done",
                        "pct": 1,
                        "speed": 0,
                        "eta": 0
                    });
                    notify("Download complete", defang(j.title), false);
                } else {
                    patchGrab(id, {
                        "state": "failed",
                        "speed": 0,
                        "error": j.error !== "" ? j.error : "yt-dlp stopped (exit " + code + ")"
                    });
                }
            }
        }
        pumpGrabs();
    }

    function pauseGrab(id) {
        const j = grabOf(id);
        if (j === null)
            return;
        if (j.state === "queued") {
            patchGrab(id, {
                "state": "paused"
            });
        } else if (j.state === "downloading" || j.state === "merging") {
            patchGrab(id, {
                "state": "paused",
                "stopReq": "pause",
                "speed": 0
            });
            stopSlot(id);
        }
    }

    function resumeGrab(id) {
        const j = grabOf(id);
        if (j !== null && j.state === "paused") {
            delete held[id];
            patchGrab(id, {
                "state": "queued"
            });
            pumpGrabs();
        }
    }

    function toggleGrabPause(id) {
        const j = grabOf(id);
        if (j === null)
            return;
        delete held[id];
        if (j.state === "paused")
            resumeGrab(id);
        else
            pauseGrab(id);
    }

    function retryGrab(id) {
        const j = grabOf(id);
        if (j !== null && j.state === "failed") {
            patchGrab(id, {
                "state": "queued",
                "error": "",
                "pct": 0
            });
            pumpGrabs();
        }
    }

    function removeGrab(id, wipe) {
        const j = grabOf(id);
        if (j === null)
            return;
        if (j.state === "downloading" || j.state === "merging") {
            patchGrab(id, {
                "stopReq": "remove"
            });
            stopSlot(id);
        }
        if (wipe && j.parts.length > 0)
            wipeParts(j.parts);
        grabs = grabs.filter(x => x.id !== id);
        pumpGrabs();
    }

    // Delete what a grab left behind: for each stream file (Title.f137.mp4.part,
    // Title.f140.m4a.part) the partial, its .ytdl bookkeeping, fragments, and the
    // stream file itself if it had just finished. A second's wait lets yt-dlp
    // finish dying first.
    function wipeParts(parts) {
        const script = "sleep 1; for f in \"$@\"; do rm -f -- \"$f\" \"$f.ytdl\" \"$f\"-Frag*; b=\"${f%.part}\"; if [ \"$b\" != \"$f\" ]; then rm -f -- \"$b\" \"$b.ytdl\"; fi; done";
        Quickshell.execDetached(["sh", "-c", script, "sh"].concat(parts));
    }

    // The grabs as rows of the list
    function grabRows() {
        return grabs.map(function (j, i) {
            const live = j.state !== "done" && j.state !== "failed";
            const group = j.state === "downloading" || j.state === "merging" ? "active" : (j.state === "queued" || j.state === "paused" ? "queued" : (j.state === "failed" ? "failed" : "done"));
            const pct = Math.round(j.pct * 100) + "%";
            let text = "";
            if (j.state === "downloading")
                text = "Video  \u00b7  " + pct + (j.speed > 0 ? "  \u00b7  " + Aria2.rate(j.speed) : "") + (j.eta > 0 ? "  \u00b7  " + Aria2.dur(j.eta) + " left" : "");
            else if (j.state === "merging")
                text = "Merging and tagging\u2026";
            else if (j.state === "paused")
                text = "Paused  \u00b7  " + pct;
            else if (j.state === "queued")
                text = "Waiting for a free slot";
            else if (j.state === "done")
                text = "Done  \u00b7  " + (j.path !== "" ? Aria2.basename(j.path) : j.quality);
            const base = j.path !== "" ? j.path : j.part;
            const dir = base !== "" ? base.slice(0, Math.max(0, base.lastIndexOf("/"))) : "";
            return {
                "gid": j.id,
                "name": j.title,
                "state": j.state,
                "group": group,
                "live": live,
                "total": j.total,
                "done": j.done,
                "fraction": j.pct,
                "speed": j.speed,
                "upSpeed": 0,
                "up": 0,
                "ratio": 0,
                "conns": 0,
                "seeders": 0,
                "error": j.error,
                "dir": dir,
                "path": j.path,
                "isBt": false,
                "complete": j.state === "done",
                "metadata": false,
                "pos": 1000000 + i,
                "link": j.url,
                "uris": [j.url],
                "files": [],
                "statusText": text,
                "info": [["Source", j.url], ["Quality", j.quality + (j.playlist ? "  \u00b7  playlist" : "")], ["Saved as", j.path !== "" ? Aria2.basename(j.path) : ""], ["Folder", dir]].filter(x => x[1] !== "")
            };
        });
    }

    // ---- Schedule, and what to do when everything is finished ---------------
    function nowMinutes() {
        const d = new Date();
        return d.getHours() * 60 + d.getMinutes();
    }

    // Every few seconds: is it time to start or stop? Only a change is acted on.
    function schedTick() {
        if (!schedOn || secret === "" || !connected)
            return;
        const c = Config.downloadSchedule;
        const w = Aria2.inWindow(nowMinutes(), Aria2.parseTime(c.start), Aria2.parseTime(c.stop));
        windowOpen = w;
        if (w === windowLast)
            return;
        windowLast = w;
        if (w)
            releaseHeld();
        else
            pauseEverything();
        say(w ? "Schedule  \u00b7  downloads running until " + c.stop : "Schedule  \u00b7  waiting for " + c.start, false);
        saveSettings();
    }

    function setSchedule(on) {
        if (on === schedOn)
            return;
        const wasHolding = windowLast === false;
        schedOn = on;
        windowLast = null;
        if (on) {
            schedTick();
            const c = Config.downloadSchedule;
            say("Schedule on  \u00b7  " + c.start + " \u2013 " + c.stop, false);
        } else {
            windowOpen = true;
            if (wasHolding)
                releaseHeld();
            say("Schedule off", false);
        }
        saveSettings();
    }

    function cancelAction() {
        const was = actionLeft > 0;
        actionLeft = 0;
        actionTimer.stop();
        whenDone = "none";
        if (was)
            say("Cancelled  \u00b7  the computer stays on", false);
    }

    function cycleWhenDone() {
        if (actionLeft > 0) {
            cancelAction();
            return;
        }
        const steps = ["none", "suspend", "poweroff"];
        setWhenDone(steps[(Math.max(0, steps.indexOf(whenDone)) + 1) % steps.length]);
    }

    function setWhenDone(m) {
        if (["none", "suspend", "hibernate", "poweroff"].indexOf(m) < 0)
            return "error: none, suspend, hibernate or poweroff";
        if (actionLeft > 0)
            cancelAction();
        whenDone = m;
        say(m === "none" ? "When finished: do nothing" : "When finished: " + whenLabel(m).toLowerCase(), false);
        return "ok";
    }

    // Called with each reading. Busy then idle, with an action chosen, starts the
    // countdown; any new work cancels it. Busy means: something downloading (not
    // just seeding), something waiting its turn, a video grab at work, or work the
    // schedule or the cap is holding back. What you paused yourself is not work.
    function checkIdle(st, active, waiting) {
        pushStatus(st);
        const busy = active.some(d => d.seeder !== "true") || waiting.some(d => d.status === "waiting") || grabs.some(j => j.state === "downloading" || j.state === "queued" || j.state === "merging") || Object.keys(held).length > 0;
        if (busy) {
            seenBusy = true;
            if (actionLeft > 0) {
                actionLeft = 0;
                actionTimer.stop();
                say("New download  \u00b7  " + whenLabel(whenDone).toLowerCase() + " cancelled", false);
            }
            return;
        }
        if (!seenBusy)
            return;
        seenBusy = false;
        if (whenDone !== "none" && actionLeft === 0) {
            actionLeft = 60;
            actionTimer.restart();
            notify("Downloads finished", whenLabel(whenDone) + " in 60 seconds. Press W in the downloads panel to cancel.", true);
        }
    }

    function runAction() {
        const a = whenDone;
        whenDone = "none";
        actionLeft = 0;
        actionTimer.stop();
        if (a !== "none")
            Quickshell.execDetached(["systemctl", a]);
    }

    // ---- Saved between runs -------------------------------------------------
    // The schedule, the video quality, the month's count and the video grabs that
    // were not finished (they come back paused). What to do when finished is not
    // saved: a forgotten "shut down" would be a nasty surprise.
    function saveSettings() {
        settingsFile.setText(JSON.stringify({
            "schedOn": schedOn,
            "holding": holding,
            "quality": videoQuality,
            "usage": usage,
            "grabs": grabs.filter(j => j.state !== "done").map(j => ({
                        "url": j.url,
                        "title": j.title,
                        "quality": j.quality,
                        "args": j.args,
                        "audioOnly": j.audioOnly,
                        "playlist": j.playlist,
                        "state": j.state === "failed" ? "failed" : "paused",
                        "error": j.error
                    }))
        }));
    }

    // ---- The panel ----------------------------------------------------------
    function open() {
        if (isOpen)
            return;
        isOpen = true;
        shown = true;
        secretFile.reload();
        refresh();
        loadGlobal();
        readClip();
        secretCheck.restart();
        if (pickQueue.length > 0)
            nextPick();
    }

    function close() {
        if (!isOpen)
            return;
        const choosing = pickOpen;
        isOpen = false;
        if (choosing)
            cancelPicker();
        if (confirmOpen)
            closeConfirm();
    }

    function toggle() {
        if (isOpen)
            close();
        else
            open();
    }

    // The window finished its leaving animation
    function panelGone() {
        if (!isOpen)
            shown = false;
    }

    // ---- Plumbing -----------------------------------------------------------
    Component.onCompleted: Quickshell.execDetached(["mkdir", "-p", stateDir])

    FileView {
        id: secretFile

        path: Config.aria2SecretFile
        printErrors: false
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

    FileView {
        id: settingsFile

        path: dl.stateDir + "/downloads.json"
        printErrors: false
        onLoaded: {
            try {
                const d = JSON.parse(text());
                if (d.schedOn === true) {
                    dl.schedOn = true;
                    dl.windowLast = null;
                }
                dl.holding = d.holding === true;
                if (typeof d.quality === "number" && d.quality >= 0 && d.quality < Config.downloadVideoQualities.length)
                    dl.videoQuality = d.quality;
                if (d.usage && typeof d.usage.month === "string")
                    dl.usage = Object.assign({
                        "month": "",
                        "down": 0,
                        "up": 0,
                        "history": {},
                        "warn": 0,
                        "capPaused": false
                    }, d.usage);
                if (Array.isArray(d.grabs) && dl.grabs.length === 0)
                    dl.grabs = d.grabs.filter(g => typeof g.url === "string").map(g => dl.makeGrab(g));
            } catch (e) {}
        }
    }

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

    // Copied links that are files, when Config.downloadClipboardAdd is on
    Process {
        id: clipWatch

        command: ["wl-paste", "--type", "text", "--watch", "sh", "-c", "tr '\n' ' '; echo"]
        running: Config.downloadClipboardAdd
        stdout: SplitParser {
            onRead: line => dl.captureClip(line)
        }
    }

    // .torrent / .metalink files are read as base64 and handed to aria2
    Process {
        id: fileReader

        // Held here, not looked up in fileJobs, because the exit handler drops
        // it from the queue and the output may still be on its way
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

    Process {
        id: previewProc

        stdout: SplitParser {
            onRead: line => dl.previewBuf += line
        }
        onExited: dl.onPreviewDone()
    }

    Process {
        id: cleanProc

        stdout: SplitParser {
            onRead: line => dl.cleanBuf += line
        }
        onExited: dl.onCleanDone()
    }

    // Two yt-dlp slots
    component GrabProc: Process {
        id: gp

        property string jobId: ""

        stdout: SplitParser {
            onRead: line => Downloads.onGrabLine(gp.jobId, line)
        }
        onExited: code => Downloads.onGrabExit(gp.jobId, code)
    }

    // Four slots for "page or file?" questions
    component ProbeProc: Process {
        id: pp

        property string url: ""
        property string dir: ""
        property string verdict: ""

        stdout: SplitParser {
            onRead: line => pp.verdict = line.trim()
        }
        onExited: Downloads.onProbed(pp.url, pp.dir, pp.verdict)
    }

    GrabProc {
        id: grabA
    }

    GrabProc {
        id: grabB
    }

    ProbeProc {
        id: probeA
    }

    ProbeProc {
        id: probeB
    }

    ProbeProc {
        id: probeC
    }

    ProbeProc {
        id: probeD
    }

    // Live updates while the panel is open
    Timer {
        interval: dl.pollMs
        repeat: true
        running: dl.isOpen && dl.secret !== ""
        onTriggered: dl.refresh()
    }

    // A quiet look while it is closed: finished downloads get their toast, the
    // counters and the bar keep up
    Timer {
        interval: dl.watchMs
        repeat: true
        running: !dl.isOpen && dl.secret !== ""
        onTriggered: dl.watch()
    }

    // The secret may not be there yet at login: keep asking until it is
    Timer {
        interval: 5000
        repeat: true
        running: dl.secret === ""
        onTriggered: secretFile.reload()
    }

    // The schedule is checked even while the panel is closed
    Timer {
        interval: 20000
        repeat: true
        running: dl.schedOn
        onTriggered: dl.schedTick()
    }

    Timer {
        id: actionTimer

        interval: 1000
        repeat: true
        onTriggered: {
            dl.actionLeft--;
            if (dl.actionLeft <= 0)
                dl.runAction();
            else if (dl.isOpen)
                dl.say(dl.whenLabel(dl.whenDone) + " in " + dl.actionLeft + " s  \u00b7  W cancels", false);
        }
    }

    // Settings are written now and then, not at every byte
    Timer {
        id: saveTimer

        interval: 15000
        onTriggered: dl.saveSettings()
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
}
