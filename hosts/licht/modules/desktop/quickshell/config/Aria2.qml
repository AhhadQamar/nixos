// Pure helpers for aria2: turn its JSON status objects into the rows the
// downloads panel draws, and format sizes, speeds and times. No state and no
// UI in here, so the panel (DownloadManager.qml) only keeps what it shows.

pragma Singleton
import QtQuick
import Quickshell

Singleton {
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
}
