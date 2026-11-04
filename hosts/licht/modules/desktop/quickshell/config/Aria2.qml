// Pure helpers for aria2: turn its JSON status objects into the rows the
// downloads panel draws, format sizes, speeds and times, and read what people
// paste into the "add" box (batch patterns, mirrors, checksums, cURL commands).
// No state and no UI in here, so the panel (DownloadManager.qml) only keeps
// what it shows.

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

    // ---- Reading what is pasted ------------------------------------------
    // Batch patterns, as in IDM's "batch download":
    //   https://x.org/img[001-100].jpg      numbers, zero padded to the width of the first
    //   https://x.org/img[1-99:2].jpg       with a step
    //   https://x.org/part[a-e].zip         letters
    // Several patterns in one link multiply out. At most `limit` links come back
    // (the second value says whether it was cut off).
    function expand(url, limit) {
        const out = [];
        let cut = false;
        const walk = function (u) {
            if (out.length >= limit) {
                cut = true;
                return;
            }
            const m = /\[(\d+)-(\d+)(?::(\d+))?\]/.exec(u) || /\[([a-zA-Z])-([a-zA-Z])()\]/.exec(u);
            if (!m) {
                out.push(u);
                return;
            }
            const pre = u.slice(0, m.index);
            const post = u.slice(m.index + m[0].length);
            if (/^\d/.test(m[1])) {
                const a = parseInt(m[1], 10);
                const b = parseInt(m[2], 10);
                const step = Math.max(1, parseInt(m[3] || "1", 10));
                const width = m[1].length > 1 && m[1].charAt(0) === "0" ? m[1].length : (m[1].length === m[2].length ? m[1].length : 0);
                if (b < a) {
                    out.push(u);
                    return;
                }
                for (let v = a; v <= b; v += step) {
                    let t = String(v);
                    while (t.length < width)
                        t = "0" + t;
                    walk(pre + t + post);
                    if (cut)
                        return;
                }
            } else {
                const a = m[1].charCodeAt(0);
                const b = m[2].charCodeAt(0);
                if (b < a) {
                    out.push(u);
                    return;
                }
                for (let v = a; v <= b; v++) {
                    walk(pre + String.fromCharCode(v) + post);
                    if (cut)
                        return;
                }
            }
        };
        walk(url);
        return {
            "urls": out,
            "cut": cut
        };
    }

    // One pasted word -> what to hand to aria2.
    //   a|b|c                   mirrors of one file
    //   url#sha256=<hex>        checked after the download (also sha-1, sha-512, md5)
    //   url[001-050].jpg        a batch
    // Returns { groups: [[uri, mirror...], ...], checksum, cut }
    function parseToken(tok, limit) {
        let checksum = "";
        let t = tok;
        const hm = /#(sha-?1|sha-?256|sha-?512|md5)=([0-9a-fA-F]+)$/i.exec(t);
        if (hm) {
            t = t.slice(0, hm.index);
            checksum = hm[1].toLowerCase().replace(/^sha(\d)/, "sha-$1") + "=" + hm[2].toLowerCase();
        }
        const parts = t.split("|").filter(function (x) {
            return x.length > 0;
        });
        if (parts.length > 1)
            return {
                "groups": [parts],
                "checksum": checksum,
                "cut": false
            };
        const e = expand(t, limit);
        return {
            "groups": e.urls.map(function (u) {
                return [u];
            }),
            "checksum": checksum,
            "cut": e.cut
        };
    }

    // Split a shell command line into words: '...', "...", $'...', backslashes
    // and line continuations, which is what a browser's "Copy as cURL" gives.
    function shellWords(text) {
        const words = [];
        let cur = "";
        let have = false;
        let i = 0;
        const n = text.length;
        while (i < n) {
            const c = text.charAt(i);
            if (c === "\\" && text.charAt(i + 1) === "\n") {
                i += 2;
            } else if (c === "\\" && text.charAt(i + 1) === "\r" && text.charAt(i + 2) === "\n") {
                i += 3;
            } else if (/\s/.test(c)) {
                if (have) {
                    words.push(cur);
                    cur = "";
                    have = false;
                }
                i++;
            } else if (c === "'" || (c === "$" && text.charAt(i + 1) === "'")) {
                const ansi = c === "$";
                i += ansi ? 2 : 1;
                have = true;
                while (i < n && text.charAt(i) !== "'") {
                    if (ansi && text.charAt(i) === "\\" && i + 1 < n) {
                        const e = text.charAt(i + 1);
                        cur += e === "n" ? "\n" : (e === "t" ? "\t" : (e === "r" ? "\r" : e));
                        i += 2;
                    } else {
                        cur += text.charAt(i);
                        i++;
                    }
                }
                i++;
            } else if (c === "\"") {
                i++;
                have = true;
                while (i < n && text.charAt(i) !== "\"") {
                    if (text.charAt(i) === "\\" && i + 1 < n && /["\\$`]/.test(text.charAt(i + 1))) {
                        cur += text.charAt(i + 1);
                        i += 2;
                    } else {
                        cur += text.charAt(i);
                        i++;
                    }
                }
                i++;
            } else if (c === "\\" && i + 1 < n) {
                cur += text.charAt(i + 1);
                have = true;
                i += 2;
            } else {
                cur += c;
                have = true;
                i++;
            }
        }
        if (have)
            words.push(cur);
        return words;
    }

    // "Copy as cURL" -> { url, headers, referer, ua, user, pass, out } or { error }.
    // Cookies, the referer and the login travel with the download, which is what
    // makes a link that only works inside the browser session download here.
    function parseCurl(text) {
        const w = shellWords(text);
        if (w.length === 0 || w[0] !== "curl")
            return {
                "error": "Not a curl command"
            };
        const r = {
            "url": "",
            "headers": [],
            "referer": "",
            "ua": "",
            "user": "",
            "pass": "",
            "out": ""
        };
        // Headers that aria2 sets itself, or that would break a plain GET
        const skip = /^(host|connection|content-length|accept-encoding|range|if-range|:authority|:method|:path|:scheme|te|upgrade-insecure-requests)$/i;
        const takesArg = /^(-X|--request|-d|--data|--data-raw|--data-binary|--data-urlencode|-F|--form|-x|--proxy|-m|--max-time|--connect-timeout|--retry|-w|--write-out|--cacert|--cert|--key|-T|--upload-file|--url-query|--resolve|--interface|--limit-rate)$/;
        let post = false;
        for (let i = 1; i < w.length; i++) {
            const a = w[i];
            const next = function () {
                i++;
                return i < w.length ? w[i] : "";
            };
            if (a === "-H" || a === "--header") {
                const h = next();
                const k = h.split(":")[0].trim();
                if (!skip.test(k))
                    r.headers.push(h);
            } else if (a === "-b" || a === "--cookie") {
                const c = next();
                if (c.indexOf("=") >= 0)
                    r.headers.push("Cookie: " + c);
            } else if (a === "-e" || a === "--referer") {
                r.referer = next();
            } else if (a === "-A" || a === "--user-agent") {
                r.ua = next();
            } else if (a === "-u" || a === "--user") {
                const up = next();
                const k = up.indexOf(":");
                r.user = k < 0 ? up : up.slice(0, k);
                r.pass = k < 0 ? "" : up.slice(k + 1);
            } else if (a === "-o" || a === "--output") {
                r.out = next();
            } else if (a === "--url") {
                r.url = next();
            } else if (/^-(X|-request)$/.test(a)) {
                if (next().toUpperCase() !== "GET")
                    post = true;
            } else if (/^(-d|--data|--data-raw|--data-binary|--data-urlencode|-F|--form|-T|--upload-file)$/.test(a)) {
                next();
                post = true;
            } else if (takesArg.test(a)) {
                next();
            } else if (a.charAt(0) !== "-" && r.url === "") {
                r.url = a;
            }
        }
        // The referer and user agent have their own aria2 options; keep the
        // headers from repeating them
        r.headers = r.headers.filter(function (h) {
            const k = h.split(":")[0].trim().toLowerCase();
            if (k === "referer") {
                if (r.referer === "")
                    r.referer = h.slice(h.indexOf(":") + 1).trim();
                return false;
            }
            if (k === "user-agent") {
                if (r.ua === "")
                    r.ua = h.slice(h.indexOf(":") + 1).trim();
                return false;
            }
            return true;
        });
        if (!/^(https?|ftp|sftp):\/\//i.test(r.url))
            return {
                "error": "No link in that curl command"
            };
        if (post)
            return {
                "error": "That curl command sends data (POST); only plain downloads work"
            };
        return r;
    }

    // ---- Folders by file type ------------------------------------------------
    function extOf(url) {
        const path = url.split("#")[0].split("?")[0];
        const m = /\.([A-Za-z0-9]{1,8})$/.exec(path);
        return m ? m[1].toLowerCase() : "";
    }

    // The folder (relative to $HOME) for a link, from the categories in Config.qml
    // ("" = no match, so aria2's default folder is used)
    function categoryDir(url, cats) {
        const e = extOf(url);
        if (e === "")
            return "";
        for (let i = 0; i < cats.length; i++) {
            if (cats[i].exts.indexOf(e) >= 0)
                return cats[i].dir;
        }
        return "";
    }

    // A copied link that is a file download (for catching links from the clipboard)
    function isFileLink(text, cats) {
        const t = text.trim();
        if (/\s/.test(t) || t.length > 2000)
            return false;
        if (/^magnet:\?xt=urn:btih:/i.test(t))
            return true;
        if (!/^(https?|ftp|sftp):\/\//i.test(t))
            return false;
        const e = extOf(t);
        if (e === "torrent" || e === "metalink" || e === "meta4")
            return true;
        return categoryDir(t, cats) !== "" && e !== "";
    }

    // ---- Video pages ---------------------------------------------------------
    // A page (not a file) on one of the video sites: yt-dlp downloads it, aria2
    // can't. A direct link to a media file always goes to aria2.
    function hostOf(url) {
        const m = /^[a-z][a-z0-9+.-]*:\/\/(?:[^@\/]*@)?([^\/:?#]+)/i.exec(url);
        return m ? m[1].toLowerCase() : "";
    }

    function isVideoPage(url, sites) {
        const h = hostOf(url);
        if (h === "")
            return false;
        const e = extOf(url);
        if (["mp4", "webm", "mkv", "mov", "m4v", "mp3", "m4a", "flac", "ogg", "opus", "wav", "zip", "torrent"].indexOf(e) >= 0)
            return false;
        for (let i = 0; i < sites.length; i++) {
            if (h === sites[i] || h.endsWith("." + sites[i]))
                return true;
        }
        return false;
    }

    // Where a web link goes: "video" (yt-dlp), "file" (aria2) or "probe" (ask the
    // server what it sends, see downloads/probe.sh). Any site works: known video
    // sites and .html pages go straight to yt-dlp, links that end in a file type
    // go straight to aria2, and the rest are asked about first.
    function routeOf(url, sites) {
        if (isVideoPage(url, sites))
            return "video";
        const e = extOf(url);
        if (e === "")
            return "probe";
        if (["html", "htm", "xhtml", "shtml"].indexOf(e) >= 0)
            return "video";
        if (["php", "asp", "aspx", "jsp", "cgi", "do", "action"].indexOf(e) >= 0)
            return "probe";
        const files = ["mp4", "webm", "mkv", "avi", "mov", "wmv", "flv", "m4v", "mpg", "mpeg", "ts", "mp3", "flac", "ogg", "opus", "m4a", "aac", "wav", "wma", "zip", "rar", "7z", "tar", "gz", "xz", "bz2", "zst", "tgz", "iso", "img", "bin", "exe", "msi", "deb", "rpm", "appimage", "apk", "dmg", "pkg", "pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "odt", "ods", "odp", "epub", "djvu", "mobi", "txt", "csv", "json", "xml", "jpg", "jpeg", "png", "gif", "webp", "svg", "bmp", "tif", "tiff", "ico", "torrent", "metalink", "meta4", "jar", "whl", "patch", "diff", "sig", "asc", "sha256", "md5", "ttf", "otf", "woff", "woff2", "srt", "vtt", "ass", "m3u8", "mpd"];
        return files.indexOf(e) >= 0 ? "file" : "probe";
    }

    // What yt-dlp prints for a stream it is downloading ("GRAB ..." line, see the
    // panel) -> { done, total, speed, eta, kind, tmp }. kind: video | audio | both
    function parseGrab(line) {
        const f = line.split(" ");
        const num = function (x) {
            const v = parseFloat(x);
            return isFinite(v) ? v : 0;
        };
        const tb = num(f[2]);
        const te = num(f[3]);
        const vc = f[6] || "";
        const ac = f[7] || "";
        return {
            "done": num(f[1]),
            "total": tb > 0 ? tb : te,
            "speed": num(f[4]),
            "eta": num(f[5]),
            "kind": vc === "none" ? "audio" : (ac === "none" ? "video" : "both"),
            "tmp": f.slice(8).join(" ")
        };
    }

    // A readable title from the file yt-dlp is writing: "Title.f137.mp4.part"
    function titleFromPart(path) {
        let b = path.split("/").pop();
        b = b.replace(/\.(part|ytdl)$/i, "").replace(/\.(part|ytdl)$/i, "");
        b = b.replace(/\.[A-Za-z0-9]{2,5}$/, "");
        b = b.replace(/\.f\d+$/, "");
        return b;
    }

    // ---- Schedule ----------------------------------------------------------
    // "02:30" -> minutes since midnight, or -1
    function parseTime(t) {
        const m = /^(\d{1,2}):(\d{2})$/.exec(String(t).trim());
        if (!m)
            return -1;
        const h = parseInt(m[1], 10);
        const mi = parseInt(m[2], 10);
        return h < 24 && mi < 60 ? h * 60 + mi : -1;
    }

    // Is `now` (minutes) inside the window from `start` to `stop`? A window that
    // ends before it starts runs over midnight (23:00 - 07:00).
    function inWindow(now, start, stop) {
        if (start < 0 || stop < 0 || start === stop)
            return true;
        return start < stop ? (now >= start && now < stop) : (now >= start || now < stop);
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
