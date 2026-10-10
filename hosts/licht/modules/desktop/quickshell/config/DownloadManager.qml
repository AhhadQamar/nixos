import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
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
    // "Save to" choices, relative to $HOME. The first one means "aria2's default dir".
    readonly property var savePresets: [
        {
            "label": "",
            "dir": ""
        },
        {
            "label": "Videos",
            "dir": "Videos"
        },
        {
            "label": "Music",
            "dir": "Music"
        },
        {
            "label": "Documents",
            "dir": "Documents"
        }
    ]
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
            "k": ["\u2191", "\u2193", "j", "k"],
            "d": "move"
        },
        {
            "k": ["enter", "\u2192"],
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
            "d": "open / yazi / copy link"
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

    // ---- State ----------------------------------------------------------
    property string secret: ""
    property string home: ""
    property bool connected: false
    property string message: ""           // connection / auth problems (persistent)
    property string note: ""              // one-off feedback ("Added 2 downloads")
    property bool noteIsError: false
    property bool showHelp: false
    property bool primed: false           // watcher has recorded what already finished
    property var known: ({})              // gids already notified or seen finishing
    property var rows: []
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
    readonly property bool typing: addInput.activeFocus || searchInput.activeFocus
    readonly property int selectedCount: Object.keys(selected).length
    readonly property int topGap: Math.round(Screen.height / 8)
    // Room left for the list once the rest of the card is accounted for
    readonly property real listMax: Math.max(160, Math.min(430, Screen.height - topGap - 40 - 330))

    // ---- Formatting -----------------------------------------------------
    function bytes(n) {
        const units = ["B", "KB", "MB", "GB", "TB"];
        let i = 0;
        n = Number(n);
        while (n >= 1024 && i < 4) {
            n /= 1024;
            i++;
        }
        return (i === 0 ? n.toFixed(0) : n.toFixed(1)) + " " + units[i];
    }

    function rate(n) {
        return bytes(n) + "/s";
    }

    function dur(sec) {
        sec = Math.round(sec);
        const h = Math.floor(sec / 3600);
        const m = Math.floor((sec % 3600) / 60);
        if (h > 0)
            return h + "h " + m + "m";
        if (m > 0)
            return m + "m " + (sec % 60) + "s";
        return sec + "s";
    }

    function basename(p) {
        return p.split("/").pop();
    }

    function uriName(u) {
        const clean = u.split("#")[0].split("?")[0].split("/").pop();
        try {
            return decodeURIComponent(clean);
        } catch (e) {
            return clean;
        }
    }

    function limitLabel(v) {
        v = Number(v || 0);
        return v === 0 ? "Unlimited" : bytes(v) + "/s";
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
            return "\uf019";
        case "seeding":
            return "\uf093";
        case "checking":
            return "\uf021";
        case "paused":
            return "\uf04c";
        case "done":
            return "\uf00c";
        case "failed":
            return "\uf071";
        case "cancelled":
            return "\uf00d";
        default:
            return "\uf017";
        }
    }

    // ---- Turning aria2 status objects into rows -------------------------
    function nameOf(d) {
        if (d.bittorrent && d.bittorrent.info && d.bittorrent.info.name)
            return d.bittorrent.info.name;
        const f = d.files && d.files[0];
        if (f && f.path)
            return basename(f.path);
        if (f && f.uris && f.uris.length > 0)
            return uriName(f.uris[0].uri);
        return d.infoHash || d.gid;
    }

    function toRow(d) {
        const total = Number(d.totalLength || 0);
        const done = Number(d.completedLength || 0);
        const up = Number(d.uploadLength || 0);
        const bt = !!d.bittorrent;
        const files = (d.files || []).map(function (f) {
            return {
                "path": f.path || "",
                "name": f.path ? basename(f.path) : (f.uris && f.uris.length ? uriName(f.uris[0].uri) : ""),
                "len": Number(f.length || 0),
                "done": Number(f.completedLength || 0)
            };
        });
        const uris = [];
        (d.files || []).forEach(function (f) {
            (f.uris || []).forEach(function (u) {
                if (uris.indexOf(u.uri) < 0)
                    uris.push(u.uri);
            });
        });
        const trackers = [];
        if (bt && d.bittorrent.announceList)
            d.bittorrent.announceList.forEach(function (tier) {
                tier.forEach(function (t) {
                    if (trackers.indexOf(t) < 0)
                        trackers.push(t);
                });
            });

        let name = nameOf(d);
        const metadata = name.indexOf("[METADATA]") === 0;
        if (metadata)
            name = "Magnet link";
        const checking = d.verifiedLength !== undefined || d.verifyIntegrityPending === "true";
        let state = "queued";
        switch (d.status) {
        case "active":
            state = checking ? "checking" : (d.seeder === "true" ? "seeding" : "downloading");
            break;
        case "waiting":
            state = "queued";
            break;
        case "paused":
            state = "paused";
            break;
        case "complete":
            state = "done";
            break;
        case "error":
            state = "failed";
            break;
        case "removed":
            state = "cancelled";
            break;
        }
        const group = (state === "downloading" || state === "seeding" || state === "checking") ? "active" : (state === "queued" || state === "paused") ? "queued" : (state === "failed" ? "failed" : "done");

        let magnet = "";
        if (d.infoHash) {
            magnet = "magnet:?xt=urn:btih:" + d.infoHash + "&dn=" + encodeURIComponent(name);
            trackers.slice(0, 6).forEach(function (t) {
                magnet += "&tr=" + encodeURIComponent(t);
            });
        }
        const dir = d.dir || "";
        let path = files.length > 0 && files[0].path !== "" ? files[0].path : dir;
        if (bt && d.bittorrent.mode === "multi" && dir !== "")
            path = dir + "/" + name;

        const conns = Number(d.connections || 0);
        const seeders = Number(d.numSeeders || 0);
        const ratio = done > 0 ? up / done : 0;
        const info = [];
        if (dir !== "")
            info.push(["Location", dir]);
        if (!bt && uris.length > 0)
            info.push(["Source", uris[0]]);
        if (bt) {
            info.push(["Peers", conns + " connected, " + seeders + " seeders"]);
            info.push(["Uploaded", bytes(up) + "  (ratio " + ratio.toFixed(2) + ")"]);
            if (d.infoHash)
                info.push(["Info hash", d.infoHash]);
            if (trackers.length > 0)
                info.push(["Trackers", trackers.length + (trackers.length === 1 ? " tracker" : " trackers")]);
        } else if (conns > 0) {
            info.push(["Connections", String(conns)]);
        }
        info.push(["GID", d.gid]);

        return {
            "gid": d.gid,
            "name": name,
            "state": state,
            "group": group,
            "live": d.status === "active" || d.status === "waiting" || d.status === "paused",
            "total": total,
            "done": done,
            "fraction": checking ? Math.min(1, Number(d.verifiedLength || 0) / Math.max(1, total)) : (total > 0 ? Math.min(1, done / total) : 0),
            "speed": Number(d.downloadSpeed || 0),
            "upSpeed": Number(d.uploadSpeed || 0),
            "up": up,
            "ratio": ratio,
            "conns": conns,
            "seeders": seeders,
            "error": d.errorMessage || "",
            "dir": dir,
            "path": path,
            "isBt": bt,
            "complete": total > 0 && done >= total,
            "metadata": metadata,
            "pos": d._pos || 0,
            "link": bt ? magnet : (uris[0] || ""),
            "uris": uris,
            "files": files,
            "info": info
        };
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
            if (xhr.status === 200) {
                let res = null;
                try {
                    res = JSON.parse(xhr.responseText);
                } catch (e) {
                    message = "aria2 sent a reply the panel couldn't read";
                    return;
                }
                if (cb)
                    cb(res);
            } else {
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
        waiting.forEach(function (d, i) {
            d._pos = i + 1;
        });
        // Finished magnet links leave a "[METADATA]" stub that points at the real download.
        const real = stopped.filter(function (d) {
            return !(d.followedBy && d.followedBy.length > 0);
        });
        const arr = active.concat(waiting, real).map(toRow);
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
        rowMap = map;
        rows = arr;
        counts = c;
        stat = {
            "downloadSpeed": Number(st.downloadSpeed || 0),
            "uploadSpeed": Number(st.uploadSpeed || 0),
            "numActive": Number(st.numActive || 0),
            "numWaiting": Number(st.numWaiting || 0)
        };
        const h = speedHistory.slice(-(historyLength - 1));
        h.push(stat.downloadSpeed);
        speedHistory = h;

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
        recompute();
    }

    function recompute() {
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
        shownGids = out;
        syncModel(out);
        if (out.indexOf(cursorGid) < 0)
            cursorGid = out.length > 0 ? out[0] : "";
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

    // Keep the ListModel in step with the filtered list without rebuilding it,
    // so scrolling, hover and open details survive every refresh.
    function syncModel(gids) {
        for (let i = listModel.count - 1; i >= 0; i--) {
            if (gids.indexOf(listModel.get(i).gid) < 0)
                listModel.remove(i);
        }
        for (let i = 0; i < gids.length; i++) {
            const grp = rowMap[gids[i]] ? rowMap[gids[i]].group : "";
            if (i < listModel.count && listModel.get(i).gid === gids[i]) {
                if (listModel.get(i).grp !== grp)
                    listModel.setProperty(i, "grp", grp);
                continue;
            }
            let from = -1;
            for (let k = i + 1; k < listModel.count; k++) {
                if (listModel.get(k).gid === gids[i]) {
                    from = k;
                    break;
                }
            }
            if (from >= 0) {
                listModel.move(from, i, 1);
                if (listModel.get(i).grp !== grp)
                    listModel.setProperty(i, "grp", grp);
            } else {
                listModel.insert(i, {
                    "gid": gids[i],
                    "grp": grp
                });
            }
        }
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
            const name = defang(res.result ? nameOf(res.result) : ev.gid);
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
            if (t.indexOf("file://") === 0)
                t = decodeURIComponent(t.slice(7));
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
        Quickshell.execDetached(["kitty", "--title", "yazi", "-e", "yazi", r.path]);
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

    function moveCursor(delta) {
        if (shownGids.length === 0)
            return;
        const i = shownGids.indexOf(cursorGid);
        const next = Math.max(0, Math.min(shownGids.length - 1, (i < 0 ? 0 : i) + delta));
        cursorGid = shownGids[next];
        list.positionViewAtIndex(next, ListView.Contain);
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
        Qt.callLater(function () {
            const i = shownGids.indexOf(gid);
            if (i >= 0)
                list.positionViewAtIndex(i, ListView.Contain);
        });
    }

    function setTab(id) {
        tab = id;
        recompute();
        if (list.count > 0)
            list.positionViewAtBeginning();
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
        visible = true;
        showHelp = false;
        speedHistory = [];
        pendingDelete = [];
        secretFile.reload();
        refresh();
        loadGlobal();
        clip = "";
        if (!clipProc.running)
            clipProc.running = true;
        keys.forceActiveFocus();
        secretCheck.restart();
        fadeIn.restart();
    }

    function close() {
        visible = false;
    }

    function toggle() {
        if (visible)
            close();
        else
            open();
    }

    // Same placement as the other panels: anchored to the top edge only and
    // exactly as big as the card (capped at the screen height; the list scrolls).
    visible: false
    color: "transparent"
    margins.top: topGap
    implicitWidth: 660
    implicitHeight: Math.min(card.implicitHeight, Screen.height - topGap - 40)
    exclusiveZone: 0
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    anchors {
        top: true
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

        path: "/run/agenix/aria2-rpc-secret"
        onLoaded: {
            dl.secret = secretFile.text().trim();
            if (dl.visible) {
                dl.refresh();
                dl.loadGlobal();
            } else {
                dl.watch();
            }
        }
    }

    ListModel {
        id: listModel
    }

    // $HOME, for the "save to" folders
    Process {
        id: homeProc

        command: ["sh", "-c", "printf %s \"$HOME\""]
        running: true
        stdout: StdioCollector {
            onStreamFinished: dl.home = text.trim()
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

        stdout: StdioCollector {
            onStreamFinished: {
                const job = dl.fileJobs[0];
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
            if (exitCode !== 0)
                dl.say("Couldn't read " + dl.fileJobs[0].path, true);
            dl.fileJobs = dl.fileJobs.slice(1);
            dl.pumpFiles();
        }
    }

    // Live updates while the panel is open
    Timer {
        interval: dl.pollMs
        repeat: true
        running: dl.visible
        onTriggered: dl.refresh()
    }

    // Quiet check for finished downloads while the panel is closed
    Timer {
        interval: dl.watchMs
        repeat: true
        running: !dl.visible && dl.secret !== ""
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
                dl.message = "Can't read the RPC secret at /run/agenix/aria2-rpc-secret";
        }
    }

    // Keyboard handling for the list. The add and search boxes handle their own keys.
    Item {
        id: keys

        anchors.fill: parent
        focus: dl.visible
        Keys.onPressed: event => {
            const k = event.key;
            const shift = (event.modifiers & Qt.ShiftModifier) !== 0;
            const ctrl = (event.modifiers & Qt.ControlModifier) !== 0;
            const row = dl.rowMap[dl.cursorGid];
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
            } else if (k === Qt.Key_Down || (k === Qt.Key_J && !ctrl)) {
                dl.moveCursor(1);
            } else if (k === Qt.Key_Up || (k === Qt.Key_K && !ctrl)) {
                dl.moveCursor(-1);
            } else if (k === Qt.Key_Home) {
                dl.moveCursor(-9999);
            } else if (k === Qt.Key_End) {
                dl.moveCursor(9999);
            } else if (k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Right || k === Qt.Key_L && !shift) {
                if (dl.cursorGid !== "")
                    dl.toggleExpand(dl.cursorGid);
            } else if (k === Qt.Key_Left || k === Qt.Key_H) {
                dl.expandedGid = "";
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

    // ---- Look & feel ------------------------------------------------------------
    // Same language as the bar and the other panels: an inset glass card, round
    // pills that stay transparent until hovered (accent-tinted while switched on),
    // soft Style.hoverFill rows and fields, a 2px accent marker on the row under the
    // cursor, muted text for everything secondary. Everything is in the shell font.
    property string tip: ""

    function sectionLabel(g) {
        return g === "active" ? "Active" : g === "queued" ? "Queued" : g === "failed" ? "Failed" : "Finished";
    }

    // Text in the shell font, so no label can fall back to the system default.
    component Txt: Text {
        textFormat: Text.PlainText
        font.family: Style.fontFamily
    }

    // Keyboard hint
    component KeyCap: Rectangle {
        id: cap

        property string label: ""

        implicitWidth: Math.max(20, capText.implicitWidth + 12)
        implicitHeight: 20
        radius: 5
        color: Colors.surfaceAlt

        Txt {
            id: capText

            anchors.centerIn: parent
            text: cap.label
            color: Colors.foreground
            opacity: 0.75
            font.pixelSize: 10
            font.bold: true
        }
    }

    // Round icon button: transparent until hovered, accent-tinted while switched on
    component IconButton: Rectangle {
        id: btn

        property string glyph: ""
        property string tip: ""
        property bool on: false
        property bool danger: false
        property int size: Style.itemHeight

        signal clicked

        implicitWidth: size
        implicitHeight: size
        radius: height / 2
        antialiasing: true
        color: on ? Qt.alpha(Colors.accent, 0.2) : (btnArea.containsMouse ? Style.hoverFill : "transparent")
        scale: btnArea.pressed ? 0.94 : 1

        Behavior on color {
            ColorAnimation {
                duration: 200
            }
        }
        Behavior on scale {
            NumberAnimation {
                duration: 100
                easing.type: Easing.OutQuad
            }
        }

        Txt {
            anchors.centerIn: parent
            text: btn.glyph
            color: btn.on ? Colors.accent : (btn.danger && btnArea.containsMouse ? Colors.critical : (btnArea.containsMouse ? Colors.foreground : Colors.muted))
            font.pixelSize: 14

            Behavior on color {
                ColorAnimation {
                    duration: 200
                }
            }
        }

        MouseArea {
            id: btnArea

            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: btn.clicked()
            onContainsMouseChanged: if (btn.tip !== "")
                dl.tip = containsMouse ? btn.tip : ""
        }
    }

    // Labelled pill: transparent until hovered, accent-tinted while switched on
    component PillButton: Rectangle {
        id: pill

        property string glyph: ""
        property string label: ""
        property bool on: false
        property bool danger: false

        signal clicked

        implicitWidth: pillRow.implicitWidth + 24
        implicitHeight: Style.itemHeight
        radius: height / 2
        antialiasing: true
        color: on ? Qt.alpha(Colors.accent, 0.2) : (pillArea.containsMouse ? Style.hoverFill : "transparent")
        scale: pillArea.pressed ? 0.94 : 1

        Behavior on color {
            ColorAnimation {
                duration: 200
            }
        }
        Behavior on scale {
            NumberAnimation {
                duration: 100
                easing.type: Easing.OutQuad
            }
        }

        Row {
            id: pillRow

            anchors.centerIn: parent
            spacing: 6

            Txt {
                anchors.verticalCenter: parent.verticalCenter
                visible: pill.glyph !== ""
                text: pill.glyph
                color: pill.on ? Colors.accent : (pill.danger && pillArea.containsMouse ? Colors.critical : (pillArea.containsMouse ? Colors.foreground : Colors.muted))
                font.pixelSize: 13

                Behavior on color {
                    ColorAnimation {
                        duration: 200
                    }
                }
            }

            Txt {
                anchors.verticalCenter: parent.verticalCenter
                text: pill.label
                color: pill.on ? Colors.accent : (pill.danger && pillArea.containsMouse ? Colors.critical : Colors.foreground)
                opacity: pill.on || pillArea.containsMouse ? 1 : 0.75
                font.pixelSize: 13

                Behavior on color {
                    ColorAnimation {
                        duration: 200
                    }
                }
            }
        }

        MouseArea {
            id: pillArea

            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: pill.clicked()
        }
    }

    ParallelAnimation {
        id: fadeIn

        NumberAnimation {
            target: card
            property: "opacity"
            from: 0
            to: 1
            duration: 140
            easing.type: Easing.OutCubic
        }

        NumberAnimation {
            target: card
            property: "scale"
            from: 0.97
            to: 1
            duration: 140
            easing.type: Easing.OutCubic
        }
    }

    // ---- The card -----------------------------------------------------------------
    Rectangle {
        id: card

        anchors.fill: parent
        implicitHeight: content.implicitHeight + 28
        radius: Style.barRadius
        antialiasing: true
        // More solid than the bar: this card sits over other windows' text
        color: Qt.alpha(Colors.background, 0.97)
        border.width: 1
        border.color: Style.outline

        // Clicking empty card space hands the keyboard back to the list
        MouseArea {
            anchors.fill: parent
            onClicked: dl.leaveInput()
        }

        ColumnLayout {
            id: content

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 14
            spacing: 10

            // ============================ Main view ==============================
            ColumnLayout {
                visible: !dl.showHelp
                Layout.fillWidth: true
                spacing: 10

                // ---- Header ---------------------------------------------------
                RowLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: 6
                    spacing: 8

                    Txt {
                        Layout.minimumWidth: implicitWidth
                        text: "Downloads"
                        color: Colors.foreground
                        font.pixelSize: 14
                        font.bold: true
                    }

                    Rectangle {
                        visible: dl.counts.all > 0
                        width: 3
                        height: 3
                        radius: 1.5
                        color: Colors.muted
                    }

                    Txt {
                        visible: dl.counts.all > 0
                        text: dl.counts.all
                        color: Colors.muted
                        font.pixelSize: 13
                    }

                    Item {
                        Layout.fillWidth: true
                    }

                    Txt {
                        text: dl.tip
                        color: Colors.muted
                        font.pixelSize: 12
                    }

                    IconButton {
                        glyph: ""
                        tip: "Pause all"
                        onClicked: dl.act("aria2.forcePauseAll", [])
                    }

                    IconButton {
                        glyph: ""
                        tip: "Resume all"
                        onClicked: dl.act("aria2.unpauseAll", [])
                    }

                    IconButton {
                        glyph: ""
                        tip: "Clear finished"
                        danger: true
                        onClicked: dl.act("aria2.purgeDownloadResult", [])
                    }
                }

                // ---- Speed and graph ------------------------------------------------
                RowLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: 6
                    Layout.rightMargin: 6
                    spacing: 20

                    ColumnLayout {
                        spacing: 2

                        Txt {
                            text: dl.rate(dl.stat.downloadSpeed)
                            color: dl.stat.downloadSpeed > 0 ? Colors.foreground : Colors.muted
                            font.pixelSize: 24
                            font.bold: true
                        }

                        Txt {
                            text: "↑ " + dl.rate(dl.stat.uploadSpeed) + "    " + dl.stat.numActive + " active    " + dl.stat.numWaiting + " queued"
                            color: Colors.muted
                            font.pixelSize: 12
                        }
                    }

                    // Download speed over the last couple of minutes
                    Item {
                        id: spark

                        readonly property real peak: Math.max(262144, Math.max.apply(null, dl.speedHistory.concat([0])))
                        readonly property real barW: Math.max(2, (width - (dl.historyLength - 1)) / dl.historyLength)

                        Layout.fillWidth: true
                        Layout.preferredHeight: 40

                        Row {
                            anchors.fill: parent
                            spacing: 1

                            Repeater {
                                model: dl.historyLength

                                delegate: Item {
                                    id: bar

                                    required property int index

                                    readonly property int at: dl.speedHistory.length - dl.historyLength + index
                                    readonly property real v: at >= 0 ? dl.speedHistory[at] : 0
                                    readonly property bool latest: index === dl.historyLength - 1

                                    width: spark.barW
                                    height: spark.height

                                    Rectangle {
                                        anchors.bottom: parent.bottom
                                        width: parent.width
                                        height: bar.v > 0 ? Math.max(2, parent.height * bar.v / spark.peak) : 2
                                        radius: Math.min(2, width / 2)
                                        antialiasing: true
                                        color: bar.v > 0 ? Colors.accent : Style.hoverFill
                                        opacity: bar.v > 0 ? (bar.latest ? 1 : 0.4 + 0.5 * (bar.v / spark.peak)) : 1

                                        Behavior on height {
                                            NumberAnimation {
                                                duration: 200
                                                easing.type: Easing.OutCubic
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // ---- Add box -----------------------------------------------------------
                // Same field as the clipboard search and the capture input: a soft
                // fill, no hard border. Focus tints the icon and adds a faint edge.
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.min(116, Math.max(40, addInput.contentHeight + 24))
                    radius: 18
                    antialiasing: true
                    color: Style.hoverFill
                    border.width: 1
                    border.color: addInput.activeFocus ? Qt.alpha(Colors.accent, 0.5) : "transparent"

                    Behavior on border.color {
                        ColorAnimation {
                            duration: 200
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.IBeamCursor
                        onClicked: addInput.forceActiveFocus()
                    }

                    Txt {
                        x: 16
                        y: 12
                        text: ""
                        color: addInput.activeFocus ? Colors.accent : Colors.muted
                        font.pixelSize: 14

                        Behavior on color {
                            ColorAnimation {
                                duration: 200
                            }
                        }
                    }

                    TextEdit {
                        id: addInput

                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.leftMargin: 44
                        anchors.rightMargin: 48
                        y: 12
                        wrapMode: TextEdit.Wrap
                        color: Colors.foreground
                        selectionColor: Colors.accent
                        selectedTextColor: Colors.background
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
                            pixelSize: 14
                        }

                        Txt {
                            visible: addInput.text.length === 0
                            text: "Paste a link, magnet or .torrent path"
                            color: Colors.muted
                            font.pixelSize: 14
                        }
                    }

                    KeyCap {
                        anchors.right: parent.right
                        anchors.rightMargin: 14
                        anchors.top: parent.top
                        anchors.topMargin: 10
                        visible: !addInput.activeFocus && addInput.text.length === 0
                        label: "a"
                    }
                }

                // Where it will be saved (only while adding)
                RowLayout {
                    visible: addInput.activeFocus || addInput.text.length > 0
                    Layout.fillWidth: true
                    Layout.leftMargin: 6
                    spacing: 4

                    Txt {
                        text: "Save to"
                        color: Colors.muted
                        rightPadding: 6
                        font.pixelSize: 12
                    }

                    Repeater {
                        model: dl.savePresets

                        delegate: PillButton {
                            required property int index
                            required property var modelData

                            on: dl.savePick === index
                            label: modelData.label !== "" ? modelData.label : (dl.globalOpt["dir"] ? dl.basename(dl.globalOpt["dir"]) : "Default")
                            onClicked: {
                                dl.savePick = index;
                                addInput.forceActiveFocus();
                            }
                        }
                    }

                    Item {
                        Layout.fillWidth: true
                    }

                    KeyCap {
                        label: "enter"
                    }

                    Txt {
                        text: "add"
                        color: Colors.muted
                        rightPadding: 8
                        font.pixelSize: 11
                    }

                    KeyCap {
                        label: "tab"
                    }

                    Txt {
                        text: "folder"
                        color: Colors.muted
                        font.pixelSize: 11
                    }
                }

                // Link found on the clipboard
                Rectangle {
                    visible: dl.clip !== "" && !addInput.activeFocus
                    Layout.fillWidth: true
                    implicitHeight: 34
                    radius: height / 2
                    antialiasing: true
                    color: clipArea.containsMouse ? Style.hoverFill : Qt.alpha(Colors.foreground, 0.05)
                    scale: clipArea.pressed ? 0.985 : 1

                    Behavior on color {
                        ColorAnimation {
                            duration: 200
                        }
                    }
                    Behavior on scale {
                        NumberAnimation {
                            duration: 100
                            easing.type: Easing.OutQuad
                        }
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 16
                        anchors.rightMargin: 14
                        spacing: 10

                        Txt {
                            text: ""
                            color: Colors.accent
                            font.pixelSize: 13
                        }

                        Txt {
                            Layout.fillWidth: true
                            text: dl.clip.replace(/\s+/g, " ")
                            elide: Text.ElideMiddle
                            color: Colors.foreground
                            font.pixelSize: 12
                        }

                        KeyCap {
                            label: "v"
                        }

                        Txt {
                            text: "Add from clipboard"
                            color: Colors.accent
                            font.pixelSize: 12
                        }
                    }

                    MouseArea {
                        id: clipArea

                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: dl.pasteClipboard()
                    }
                }

                // Connection / auth problems stay on screen until they clear
                Rectangle {
                    visible: dl.message !== ""
                    Layout.fillWidth: true
                    implicitHeight: msgRow.implicitHeight + 24
                    radius: 12
                    antialiasing: true
                    color: Qt.alpha(Colors.foreground, 0.05)

                    Rectangle {
                        anchors.left: parent.left
                        anchors.leftMargin: 6
                        anchors.verticalCenter: parent.verticalCenter
                        width: 2
                        height: parent.height - 24
                        radius: 1
                        color: Colors.critical
                    }

                    RowLayout {
                        id: msgRow

                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.leftMargin: 18
                        anchors.rightMargin: 14
                        spacing: 10

                        Txt {
                            text: ""
                            color: Colors.critical
                            font.pixelSize: 13
                        }

                        Txt {
                            Layout.fillWidth: true
                            text: dl.message
                            wrapMode: Text.Wrap
                            color: Colors.critical
                            font.pixelSize: 12
                        }
                    }
                }

                // ---- Filter tabs + search -------------------------------------------------
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 4

                    // Transparent pills, accent-tinted while selected (same as the
                    // capture modes and the screen-time range switch)
                    Repeater {
                        model: dl.tabs

                        delegate: Rectangle {
                            id: tabBtn

                            required property var modelData

                            readonly property bool on: dl.tab === modelData.id
                            readonly property int n: dl.counts[modelData.id] || 0

                            implicitWidth: tabLabel.implicitWidth + 24
                            implicitHeight: Style.itemHeight
                            radius: height / 2
                            antialiasing: true
                            color: on ? Qt.alpha(Colors.accent, 0.2) : (tabArea.containsMouse ? Style.hoverFill : "transparent")
                            scale: tabArea.pressed ? 0.94 : 1

                            Behavior on color {
                                ColorAnimation {
                                    duration: 200
                                }
                            }
                            Behavior on scale {
                                NumberAnimation {
                                    duration: 100
                                    easing.type: Easing.OutQuad
                                }
                            }

                            Row {
                                id: tabLabel

                                anchors.centerIn: parent
                                spacing: 6

                                Txt {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: tabBtn.modelData.label
                                    color: tabBtn.on ? Colors.accent : (tabArea.containsMouse ? Colors.foreground : Colors.muted)
                                    font.pixelSize: 13

                                    Behavior on color {
                                        ColorAnimation {
                                            duration: 200
                                        }
                                    }
                                }

                                Txt {
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: tabBtn.n > 0
                                    text: tabBtn.n
                                    color: tabBtn.on ? Colors.accent : (tabBtn.modelData.id === "failed" ? Colors.critical : Colors.muted)
                                    opacity: 0.85
                                    font.pixelSize: 11
                                }
                            }

                            MouseArea {
                                id: tabArea

                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: dl.setTab(tabBtn.modelData.id)
                            }
                        }
                    }

                    Item {
                        Layout.fillWidth: true
                    }

                    Rectangle {
                        Layout.preferredWidth: 180
                        Layout.preferredHeight: 32
                        radius: height / 2
                        antialiasing: true
                        color: Style.hoverFill

                        Txt {
                            x: 14
                            anchors.verticalCenter: parent.verticalCenter
                            text: ""
                            color: searchInput.activeFocus ? Colors.accent : Colors.muted
                            font.pixelSize: 12

                            Behavior on color {
                                ColorAnimation {
                                    duration: 200
                                }
                            }
                        }

                        TextInput {
                            id: searchInput

                            anchors.fill: parent
                            anchors.leftMargin: 36
                            anchors.rightMargin: 38
                            verticalAlignment: TextInput.AlignVCenter
                            color: Colors.foreground
                            selectionColor: Colors.accent
                            selectedTextColor: Colors.background
                            clip: true
                            onTextChanged: {
                                dl.query = text;
                                dl.recompute();
                            }
                            Keys.onEscapePressed: {
                                text = "";
                                dl.leaveInput();
                            }
                            Keys.onReturnPressed: dl.leaveInput()
                            Keys.onDownPressed: dl.leaveInput()

                            font {
                                family: Style.fontFamily
                                pixelSize: 13
                            }

                            Txt {
                                visible: searchInput.text.length === 0
                                anchors.verticalCenter: parent.verticalCenter
                                text: "Search"
                                color: Colors.muted
                                font.pixelSize: 13
                            }
                        }

                        KeyCap {
                            anchors.right: parent.right
                            anchors.rightMargin: 10
                            anchors.verticalCenter: parent.verticalCenter
                            visible: !searchInput.activeFocus && searchInput.text.length === 0
                            label: "/"
                        }
                    }
                }

                // ---- Not running / empty states ---------------------------------------------
                ColumnLayout {
                    visible: !dl.connected && dl.secret !== ""
                    Layout.fillWidth: true
                    Layout.topMargin: 16
                    Layout.bottomMargin: 16
                    spacing: 6

                    Txt {
                        Layout.alignment: Qt.AlignHCenter
                        text: ""
                        color: Colors.muted
                        font.pixelSize: 26
                    }

                    Txt {
                        Layout.alignment: Qt.AlignHCenter
                        text: "aria2 isn't running"
                        color: Colors.foreground
                        font.pixelSize: 13
                        font.bold: true
                    }

                    Txt {
                        Layout.alignment: Qt.AlignHCenter
                        text: "The panel talks to the aria2 user service on port 6800."
                        color: Colors.muted
                        font.pixelSize: 12
                    }

                    PillButton {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.topMargin: 4
                        glyph: ""
                        label: "Start aria2"
                        onClicked: dl.startAria()
                    }
                }

                ColumnLayout {
                    visible: dl.connected && dl.shownGids.length === 0
                    Layout.fillWidth: true
                    Layout.topMargin: 16
                    Layout.bottomMargin: 16
                    spacing: 6

                    Txt {
                        Layout.alignment: Qt.AlignHCenter
                        text: dl.rows.length === 0 ? "" : ""
                        color: Colors.muted
                        font.pixelSize: 26
                    }

                    Txt {
                        Layout.alignment: Qt.AlignHCenter
                        text: dl.rows.length === 0 ? "No downloads yet" : "Nothing matches"
                        color: Colors.foreground
                        font.pixelSize: 13
                        font.bold: true
                    }

                    Txt {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.Wrap
                        text: dl.rows.length === 0 ? "Paste a link, magnet or .torrent path above, or press v to add what's on the clipboard." : "Try another tab or clear the search."
                        color: Colors.muted
                        font.pixelSize: 12
                    }
                }

                // ---- Downloads ------------------------------------------------------------
                Item {
                    id: listBox

                    readonly property bool scrolls: list.contentHeight > dl.listMax

                    visible: dl.connected && dl.shownGids.length > 0
                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.min(dl.listMax, list.contentHeight)

                    ListView {
                        id: list

                        anchors.fill: parent
                        anchors.rightMargin: listBox.scrolls ? 10 : 0
                        clip: true
                        model: listModel
                        boundsBehavior: Flickable.StopAtBounds
                        section.property: "grp"
                        section.criteria: ViewSection.FullString

                        // Active / Queued / Failed / Finished (only on the All tab)
                        section.delegate: Item {
                            id: sec

                            required property string section

                            width: list.width
                            height: dl.tab === "all" ? 28 : 0
                            visible: dl.tab === "all"

                            Row {
                                anchors.left: parent.left
                                anchors.leftMargin: 6
                                anchors.bottom: parent.bottom
                                anchors.bottomMargin: 4
                                spacing: 6

                                Txt {
                                    text: dl.sectionLabel(sec.section)
                                    color: sec.section === "failed" ? Colors.critical : Colors.muted
                                    font.pixelSize: 11
                                }

                                Txt {
                                    text: dl.counts[sec.section] || 0
                                    color: Colors.muted
                                    opacity: 0.7
                                    font.pixelSize: 11
                                }
                            }
                        }

                        add: Transition {
                            NumberAnimation {
                                property: "opacity"
                                from: 0
                                to: 1
                                duration: 140
                            }
                        }

                        remove: Transition {
                            NumberAnimation {
                                property: "opacity"
                                to: 0
                                duration: 100
                            }
                        }

                        displaced: Transition {
                            NumberAnimation {
                                property: "y"
                                duration: 160
                                easing.type: Easing.OutCubic
                            }
                        }

                        delegate: Item {
                            id: del

                            required property string gid

                            readonly property var r: dl.rowMap[gid] || dl.blankRow
                            readonly property bool isCursor: dl.cursorGid === gid
                            readonly property bool isSel: dl.selected[gid] === true
                            readonly property bool open: dl.expandedGid === gid
                            readonly property bool hot: rowArea.containsMouse || isCursor
                            readonly property color tone: dl.toneOf(r.state)
                            readonly property bool pausable: r.state === "downloading" || r.state === "seeding" || r.state === "checking" || r.state === "queued"

                            width: list.width
                            height: rowBox.implicitHeight + 2

                            Behavior on height {
                                NumberAnimation {
                                    duration: 150
                                    easing.type: Easing.OutCubic
                                }
                            }

                            Rectangle {
                                id: rowBox

                                implicitHeight: rowCol.implicitHeight
                                width: parent.width
                                height: del.height - 2
                                radius: 16
                                antialiasing: true
                                clip: true
                                color: del.isSel ? Qt.alpha(Colors.accent, 0.14) : (del.hot ? Style.hoverFill : "transparent")

                                Behavior on color {
                                    ColorAnimation {
                                        duration: 120
                                    }
                                }

                                ColumnLayout {
                                    id: rowCol

                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    spacing: 0

                                    Item {
                                        Layout.fillWidth: true
                                        implicitHeight: head.implicitHeight + 20

                                        MouseArea {
                                            id: rowArea

                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            // Position, not enter, so scrolling under a still mouse
                                            // doesn't steal the keyboard cursor
                                            onPositionChanged: dl.cursorGid = del.gid
                                            onClicked: mouse => {
                                                dl.leaveInput();
                                                dl.cursorGid = del.gid;
                                                if (mouse.modifiers & Qt.ControlModifier)
                                                    dl.toggleSelect(del.gid);
                                                else
                                                    dl.toggleExpand(del.gid);
                                            }
                                        }

                                        // Cursor marker: the bar's 2px accent, standing up
                                        Rectangle {
                                            visible: del.isCursor
                                            anchors.left: parent.left
                                            anchors.leftMargin: 5
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: 2
                                            height: 16
                                            radius: 1
                                            color: Colors.accent
                                        }

                                        RowLayout {
                                            id: head

                                            anchors.left: parent.left
                                            anchors.right: parent.right
                                            anchors.verticalCenter: parent.verticalCenter
                                            anchors.leftMargin: 16
                                            anchors.rightMargin: 10
                                            spacing: 12

                                            // Round state badge in the state's colour; a tick replaces it
                                            // while the row is selected
                                            Rectangle {
                                                implicitWidth: 32
                                                implicitHeight: 32
                                                radius: 16
                                                antialiasing: true
                                                color: del.isSel ? Colors.accent : Qt.alpha(del.tone, 0.2)

                                                Txt {
                                                    anchors.centerIn: parent
                                                    text: del.isSel ? "" : dl.glyphOf(del.r.state)
                                                    color: del.isSel ? Colors.background : del.tone
                                                    font.pixelSize: 14
                                                }
                                            }

                                            ColumnLayout {
                                                Layout.fillWidth: true
                                                spacing: 5

                                                Txt {
                                                    Layout.fillWidth: true
                                                    text: del.r.name
                                                    color: Colors.foreground
                                                    elide: Text.ElideMiddle
                                                    font.pixelSize: 13
                                                }

                                                Rectangle {
                                                    Layout.fillWidth: true
                                                    Layout.preferredHeight: 3
                                                    radius: 2
                                                    antialiasing: true
                                                    color: Style.hoverFill

                                                    Rectangle {
                                                        width: parent.width * (del.r.state === "seeding" ? 1 : del.r.fraction)
                                                        height: parent.height
                                                        radius: 2
                                                        antialiasing: true
                                                        color: del.tone
                                                        opacity: del.r.state === "queued" || del.r.state === "cancelled" ? 0.4 : 1

                                                        Behavior on width {
                                                            NumberAnimation {
                                                                duration: 300
                                                                easing.type: Easing.OutCubic
                                                            }
                                                        }
                                                    }
                                                }

                                                Txt {
                                                    Layout.fillWidth: true
                                                    elide: Text.ElideRight
                                                    color: del.r.state === "failed" ? Colors.critical : Colors.muted
                                                    font.pixelSize: 11
                                                    text: {
                                                        const m = del.r;
                                                        switch (m.state) {
                                                        case "failed":
                                                            return m.error !== "" ? m.error : "Failed";
                                                        case "done":
                                                            return "Done    " + dl.bytes(m.total);
                                                        case "cancelled":
                                                            return "Cancelled";
                                                        case "queued":
                                                            return "Queued #" + m.pos + (m.total > 0 ? "    " + dl.bytes(m.total) : "");
                                                        case "paused":
                                                            return "Paused    " + dl.bytes(m.done) + (m.total > 0 ? " of " + dl.bytes(m.total) : "");
                                                        case "checking":
                                                            return "Checking files… " + Math.floor(m.fraction * 100) + "%";
                                                        case "seeding":
                                                            return "Seeding    ↑ " + dl.rate(m.upSpeed) + "    ratio " + m.ratio.toFixed(2) + "    " + m.conns + (m.conns === 1 ? " peer" : " peers");
                                                        default:
                                                            if (m.metadata)
                                                                return "Fetching magnet metadata…    " + m.conns + (m.conns === 1 ? " peer" : " peers");
                                                            let s = dl.bytes(m.done) + " of " + dl.bytes(m.total) + "    " + dl.rate(m.speed);
                                                            if (m.speed > 0 && m.total > m.done)
                                                                s += "    " + dl.dur((m.total - m.done) / m.speed) + " left";
                                                            return s;
                                                        }
                                                    }
                                                }
                                            }

                                            // Percent at rest, actions on hover or under the cursor
                                            Item {
                                                implicitWidth: 84
                                                implicitHeight: Style.itemHeight

                                                Txt {
                                                    anchors.right: parent.right
                                                    anchors.rightMargin: 6
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    visible: !del.hot && del.r.total > 0 && (del.r.state === "downloading" || del.r.state === "paused" || del.r.state === "queued" || del.r.state === "checking")
                                                    text: Math.floor(del.r.fraction * 100) + "%"
                                                    color: del.tone
                                                    font.pixelSize: 12
                                                    font.bold: true
                                                }

                                                Row {
                                                    anchors.right: parent.right
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    spacing: 0
                                                    visible: del.hot

                                                    IconButton {
                                                        visible: del.pausable || del.r.state === "paused"
                                                        glyph: del.r.state === "paused" ? "" : ""
                                                        onClicked: dl.togglePause([del.gid])
                                                    }

                                                    IconButton {
                                                        visible: del.r.state === "failed"
                                                        glyph: ""
                                                        onClicked: dl.retryRows([del.gid])
                                                    }

                                                    IconButton {
                                                        glyph: ""
                                                        danger: true
                                                        onClicked: dl.removeRows([del.gid], false)
                                                    }
                                                }
                                            }

                                            Txt {
                                                text: del.open ? "" : ""
                                                color: Colors.muted
                                                font.pixelSize: 13
                                            }
                                        }
                                    }

                                    Loader {
                                        Layout.fillWidth: true
                                        active: del.open
                                        visible: active
                                        sourceComponent: detailsComp
                                    }
                                }
                            }

                            // Details drawer: plain rows under the name, lined up with it
                            Component {
                                id: detailsComp

                                Item {
                                    implicitHeight: dcol.implicitHeight + 16

                                    ColumnLayout {
                                        id: dcol

                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.top: parent.top
                                        anchors.leftMargin: 60
                                        anchors.rightMargin: 16
                                        anchors.topMargin: 0
                                        spacing: 7

                                        Repeater {
                                            model: del.r.info

                                            delegate: RowLayout {
                                                required property var modelData

                                                Layout.fillWidth: true
                                                spacing: 12

                                                Txt {
                                                    Layout.preferredWidth: 78
                                                    text: modelData[0]
                                                    color: Colors.muted
                                                    font.pixelSize: 11
                                                }

                                                Txt {
                                                    Layout.fillWidth: true
                                                    text: modelData[1]
                                                    color: Colors.foreground
                                                    elide: Text.ElideMiddle
                                                    font.pixelSize: 12
                                                }
                                            }
                                        }

                                        // Files inside a torrent or metalink
                                        ColumnLayout {
                                            visible: del.r.files.length > 1
                                            Layout.fillWidth: true
                                            Layout.topMargin: 4
                                            spacing: 4

                                            Repeater {
                                                model: del.r.files.slice(0, 8)

                                                delegate: RowLayout {
                                                    required property var modelData

                                                    Layout.fillWidth: true
                                                    spacing: 10

                                                    Txt {
                                                        Layout.fillWidth: true
                                                        text: modelData.name
                                                        color: Colors.foreground
                                                        opacity: 0.85
                                                        elide: Text.ElideMiddle
                                                        font.pixelSize: 12
                                                    }

                                                    Txt {
                                                        text: dl.bytes(modelData.len)
                                                        color: Colors.muted
                                                        font.pixelSize: 11
                                                    }

                                                    Txt {
                                                        Layout.preferredWidth: 34
                                                        horizontalAlignment: Text.AlignRight
                                                        text: modelData.len > 0 ? Math.floor(modelData.done / modelData.len * 100) + "%" : ""
                                                        color: Colors.muted
                                                        font.pixelSize: 11
                                                    }
                                                }
                                            }

                                            Txt {
                                                visible: del.r.files.length > 8
                                                text: "and " + (del.r.files.length - 8) + " more files"
                                                color: Colors.muted
                                                font.pixelSize: 11
                                            }
                                        }

                                        Flow {
                                            Layout.fillWidth: true
                                            Layout.topMargin: 4
                                            Layout.preferredHeight: childrenRect.height
                                            spacing: 4

                                            PillButton {
                                                visible: del.r.state === "done" || del.r.state === "seeding"
                                                glyph: ""
                                                label: "Open"
                                                onClicked: dl.openRow(del.r)
                                            }

                                            PillButton {
                                                visible: del.r.path !== ""
                                                glyph: ""
                                                label: "Show in yazi"
                                                onClicked: dl.revealRow(del.r)
                                            }

                                            PillButton {
                                                visible: del.r.link !== ""
                                                glyph: ""
                                                label: del.r.isBt ? "Copy magnet" : "Copy link"
                                                onClicked: dl.copyLink(del.r)
                                            }

                                            PillButton {
                                                visible: del.r.state === "failed"
                                                glyph: ""
                                                label: "Retry"
                                                onClicked: dl.retryRows([del.gid])
                                            }

                                            PillButton {
                                                visible: del.r.state === "queued" || del.r.state === "paused"
                                                glyph: ""
                                                label: "Move to top"
                                                onClicked: {
                                                    dl.cursorGid = del.gid;
                                                    dl.moveQueue("top");
                                                }
                                            }

                                            PillButton {
                                                visible: !del.r.complete && del.r.state !== "cancelled"
                                                danger: true
                                                glyph: ""
                                                label: "Remove and delete files"
                                                onClicked: {
                                                    dl.cursorGid = del.gid;
                                                    dl.askRemove(true);
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Slim scroll indicator, in the shell's muted style
                    Rectangle {
                        visible: listBox.scrolls
                        anchors.right: parent.right
                        width: 3
                        radius: 2
                        color: Qt.alpha(Colors.foreground, 0.2)
                        y: list.height * list.visibleArea.yPosition
                        height: Math.max(28, list.height * list.visibleArea.heightRatio)
                    }
                }

                // ---- Limits and hints -----------------------------------------------------
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 4

                    PillButton {
                        glyph: ""
                        on: Number(dl.globalOpt["max-overall-download-limit"] || 0) > 0
                        label: dl.limitLabel(dl.globalOpt["max-overall-download-limit"])
                        onClicked: dl.cycleLimit("max-overall-download-limit")
                    }

                    PillButton {
                        glyph: ""
                        on: Number(dl.globalOpt["max-overall-upload-limit"] || 0) > 0
                        label: dl.limitLabel(dl.globalOpt["max-overall-upload-limit"])
                        onClicked: dl.cycleLimit("max-overall-upload-limit")
                    }

                    Row {
                        spacing: 0

                        IconButton {
                            glyph: ""
                            onClicked: dl.stepParallel(-1)
                        }

                        Txt {
                            height: Style.itemHeight
                            verticalAlignment: Text.AlignVCenter
                            leftPadding: 4
                            rightPadding: 4
                            text: dl.parallel() + " at a time"
                            color: Colors.foreground
                            opacity: 0.75
                            font.pixelSize: 13
                        }

                        IconButton {
                            glyph: ""
                            onClicked: dl.stepParallel(1)
                        }
                    }

                    Item {
                        Layout.fillWidth: true
                    }

                    Txt {
                        visible: dl.selectedCount > 0
                        text: dl.selectedCount + " selected"
                        color: Colors.accent
                        rightPadding: 2
                        font.pixelSize: 11
                        font.bold: true
                    }

                    KeyCap {
                        visible: dl.selectedCount > 0
                        label: "esc"
                    }

                    KeyCap {
                        visible: dl.selectedCount === 0
                        label: "?"
                    }

                    Txt {
                        visible: dl.selectedCount === 0
                        text: "shortcuts"
                        color: Colors.muted
                        rightPadding: 6
                        font.pixelSize: 11
                    }
                }
            }

            // ============================ Shortcut sheet ==========================
            Item {
                visible: dl.showHelp
                Layout.fillWidth: true
                implicitHeight: helpCol.implicitHeight

                MouseArea {
                    anchors.fill: parent
                    onClicked: dl.showHelp = false
                }

                ColumnLayout {
                    id: helpCol

                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    spacing: 14

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.leftMargin: 6
                        spacing: 8

                        Txt {
                            Layout.fillWidth: true
                            text: "Shortcuts"
                            color: Colors.foreground
                            font.pixelSize: 14
                            font.bold: true
                        }

                        KeyCap {
                            label: "any key"
                        }

                        Txt {
                            text: "to close"
                            color: Colors.muted
                            font.pixelSize: 11
                        }
                    }

                    GridLayout {
                        Layout.fillWidth: true
                        Layout.leftMargin: 6
                        Layout.rightMargin: 6
                        columns: 2
                        columnSpacing: 30
                        rowSpacing: 10

                        Repeater {
                            model: dl.keyHelp

                            delegate: RowLayout {
                                id: helpRow

                                required property var modelData

                                Layout.fillWidth: true
                                Layout.preferredWidth: 1
                                spacing: 12

                                Row {
                                    Layout.preferredWidth: 132
                                    spacing: 4

                                    Repeater {
                                        model: helpRow.modelData.k

                                        delegate: KeyCap {
                                            required property string modelData

                                            label: modelData
                                        }
                                    }
                                }

                                Txt {
                                    Layout.fillWidth: true
                                    text: helpRow.modelData.d
                                    color: Colors.foreground
                                    elide: Text.ElideRight
                                    font.pixelSize: 12
                                }
                            }
                        }
                    }

                    Txt {
                        Layout.fillWidth: true
                        Layout.leftMargin: 6
                        Layout.rightMargin: 6
                        text: "Speed limits and parallel downloads last until aria2 restarts. Set them in aria2.conf to keep them."
                        color: Colors.muted
                        wrapMode: Text.Wrap
                        font.pixelSize: 11
                    }
                }
            }
        }

        // ---- Toast: one-off feedback, floats so nothing shifts -----------------------
        Rectangle {
            id: toast

            readonly property bool shown: dl.note !== ""

            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: shown ? 52 : 40
            width: Math.min(parent.width - 60, toastRow.implicitWidth + 32)
            height: Style.itemHeight + 8
            radius: height / 2
            antialiasing: true
            color: Colors.surfaceAlt
            border.width: 1
            border.color: Style.outline
            opacity: shown ? 1 : 0
            visible: opacity > 0
            z: 10

            Behavior on opacity {
                NumberAnimation {
                    duration: 140
                }
            }

            Behavior on anchors.bottomMargin {
                NumberAnimation {
                    duration: 160
                    easing.type: Easing.OutCubic
                }
            }

            Row {
                id: toastRow

                anchors.centerIn: parent
                spacing: 8

                Txt {
                    anchors.verticalCenter: parent.verticalCenter
                    text: dl.noteIsError ? "" : ""
                    color: dl.noteIsError ? Colors.critical : Colors.accent
                    font.pixelSize: 13
                }

                Txt {
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.min(implicitWidth, toast.parent.width - 112)
                    elide: Text.ElideRight
                    text: dl.note
                    color: Colors.foreground
                    font.pixelSize: 12
                }
            }
        }
    }
}
