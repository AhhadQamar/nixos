// Music backend: one resident mpv that plays ~/Music and streams from YouTube
// Music (mpv's yt-dlp hook), driven over its JSON IPC socket. mpv is started detached, so music keeps playing when the shell is
// reloaded, and the shell reattaches to it. The panel (MusicPlayer.qml) and the
// bar chip (MusicChip.qml) both read from here.
//
// Also here: the metadata of streamed tracks (mpv's own is poor), the download
// queue (yt-dlp, same settings and folders as the ytm aliases) and the last
// queue and position, so the player can pick up where it left off.

pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    // ---- Settings -------------------------------------------------------
    readonly property string home: Config.home
    readonly property string libraryDir: Config.musicDir
    readonly property string runtime: Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"
    readonly property string sockPath: runtime + "/quickshell-music.sock"
    // The play queue is written here and handed to mpv in one go
    readonly property string queueFile: runtime + "/quickshell-music-queue.m3u"
    readonly property int queueCap: 2000
    // --no-config: your normal mpv.conf (uosc, night mode, resume) is for video
    readonly property var mpvCommand: ["mpv", "--no-config", "--idle=yes", "--no-video", "--force-window=no", "--no-terminal", "--audio-display=no", "--load-scripts=no", "--load-unsafe-playlists=yes", "--keep-open=no", "--audio-client-name=quickshell-music", "--ytdl=yes", "--ytdl-format=ba[ext=m4a]/ba", "--volume=70", "--volume-max=130", "--input-ipc-server=" + sockPath]

    // ---- Library --------------------------------------------------------
    // [{ path, artist, album, title }], sorted
    property var library: []
    property bool scanning: false
    property bool scanned: false

    // ---- Playback (mirrored from mpv) -----------------------------------
    property bool online: false
    // mpv could not be started or never answered (not installed, say); the
    // panel says so. Cleared as soon as a connection is made or tried again.
    property bool failed: false
    property bool idle: true
    property bool paused: true
    property string path: ""
    property string title: ""
    property string artist: ""
    property string album: ""
    property real position: 0
    property real duration: 0
    property int volume: 70
    property bool muted: false
    property bool shuffle: false
    // off | all | one
    property string repeat: "off"
    // [{ filename, current }] and the index of the playing entry
    property var queue: []
    property string cover: ""

    readonly property bool hasTrack: online && !idle && path !== ""
    readonly property bool playing: hasTrack && !paused
    readonly property real progress: duration > 0 ? Math.min(1, position / duration) : 0

    // ---- Internals ------------------------------------------------------
    property var pending: []
    property bool launched: false
    property int attempts: 0
    property string coverFor: ""
    property bool coverDirty: false

    // "Daft Punk/Discovery/01 One More Time.mp3" → "01 One More Time"
    function baseName(p) {
        const f = p.split("/").pop();
        const i = f.lastIndexOf(".");
        return i > 0 ? f.slice(0, i) : f;
    }

    // Streamed tracks: url -> { path, title, artist, album, duration, cover }
    property var remote: ({})

    function isRemote(p) {
        return /^https?:\/\//.test(p || "");
    }

    // Tell the player what a URL is before it is queued
    function remember(list) {
        const m = Object.assign({}, remote);
        let any = false;
        for (const e of list) {
            if (e && isRemote(e.path)) {
                m[e.path] = {
                    "path": e.path,
                    "title": e.title || "",
                    "artist": e.artist || "",
                    "album": e.album || "",
                    "duration": e.duration || 0,
                    "cover": e.cover || ""
                };
                any = true;
            }
        }
        if (any)
            remote = m;
    }

    function lookup(p) {
        return byPath[p] || remote[p] || null;
    }

    // path → library entry, rebuilt with the library
    readonly property var byPath: {
        const m = {};
        for (const t of library)
            m[t.path] = t;
        return m;
    }

    function fmt(sec) {
        if (!isFinite(sec) || sec < 0)
            return "0:00";
        const s = Math.floor(sec);
        const m = Math.floor(s / 60);
        const h = Math.floor(m / 60);
        const pad = n => (n < 10 ? "0" : "") + n;
        return h > 0 ? h + ":" + pad(m % 60) + ":" + pad(s % 60) : m + ":" + pad(s % 60);
    }

    // ---- Talking to mpv ---------------------------------------------------
    function writeRaw(obj) {
        sock.write(JSON.stringify(obj) + "\n");
    }

    function send(cmd) {
        if (!online) {
            pending.push(cmd);
            ensure();
            return;
        }
        writeRaw({
            command: cmd
        });
        sock.flush();
    }

    // Connect to mpv, starting it if nothing is listening
    function ensure() {
        if (online)
            return;
        attempts = 0;
        failed = false;
        connectTimer.restart();
    }

    function onLine(line) {
        let m;
        try {
            m = JSON.parse(line);
        } catch (e) {
            return;
        }
        if (m.request_id === 100 && Array.isArray(m.data)) {
            queue = m.data.map(e => ({
                        filename: e.filename,
                        current: e.current === true
                    }));
            saveSoon();
            return;
        }
        if (m.event !== "property-change")
            return;
        const d = m.data;
        switch (m.name) {
        case "pause":
            paused = d === true;
            break;
        case "idle-active":
            idle = d === true;
            break;
        case "time-pos":
            {
                // mpv reports this many times a second while playing, and each
                // report moves the bar's ruler and the panel's seek bar. A
                // fifth of a second is finer than anything on screen shows, so
                // smaller steps are dropped (a jump, a seek or a reset to 0
                // always gets through).
                const p = typeof d === "number" ? d : 0;
                if (p === 0 || Math.abs(p - position) >= 0.2)
                    position = p;
                break;
            }
        case "duration":
            duration = typeof d === "number" ? d : 0;
            tryResumeSeek();
            break;
        case "volume":
            volume = typeof d === "number" ? Math.round(d) : volume;
            break;
        case "mute":
            muted = d === true;
            break;
        case "loop-playlist":
        case "loop-file":
            applyRepeat(m.name, d);
            break;
        case "path":
            path = typeof d === "string" ? d : "";
            if (path === "") {
                title = "";
                artist = "";
                album = "";
                cover = "";
            } else if (remote[path]) {
                const r = remote[path];
                title = r.title;
                artist = r.artist;
                album = r.album;
                cover = r.cover;
            } else if (isRemote(path)) {
                title = path;
                cover = "";
            } else {
                // Until the tags arrive, show the file name
                title = baseName(path);
                fetchCover();
            }
            tryResumeSeek();
            requestQueue();
            saveSoon();
            ensureLyrics();
            break;
        case "metadata":
            applyMeta(d);
            break;
        case "playlist-pos":
        case "playlist-count":
            requestQueue();
            break;
        }
    }

    property bool loopAll: false
    property bool loopOne: false

    function applyRepeat(name, d) {
        const on = d === "inf" || d === true || (typeof d === "number" && d > 0);
        if (name === "loop-playlist")
            loopAll = on;
        else
            loopOne = on;
        repeat = loopOne ? "one" : (loopAll ? "all" : "off");
    }

    // mpv hands tags over with whatever case the file used
    function applyMeta(d) {
        if (!d || typeof d !== "object" || remote[path])
            return;
        const m = {};
        for (const k of Object.keys(d))
            m[k.toLowerCase()] = d[k];
        if (m.title)
            title = m.title;
        artist = m.artist || m.album_artist || "";
        album = m.album || "";
    }

    function requestQueue() {
        if (!online)
            return;
        writeRaw({
            command: ["get_property", "playlist"],
            request_id: 100
        });
        sock.flush();
    }

    function observe() {
        const props = ["pause", "idle-active", "time-pos", "duration", "volume", "mute", "path", "metadata", "playlist-pos", "playlist-count", "loop-playlist", "loop-file"];
        props.forEach((p, i) => writeRaw({
                command: ["observe_property", i + 1, p]
            }));
        sock.flush();
    }

    function fetchCover() {
        if (isRemote(path))
            return;
        if (coverProc.running) {
            coverDirty = true;
            return;
        }
        coverFor = path;
        coverProc.running = true;
    }

    // ---- Controls -----------------------------------------------------------
    function playPause() {
        if (hasTrack)
            send(["cycle", "pause"]);
    }

    function next() {
        send(["playlist-next"]);
    }

    // Restart the track if it has been playing a while, like most players
    function prev() {
        if (position > 3)
            send(["seek", 0, "absolute"]);
        else
            send(["playlist-prev"]);
    }

    function stop() {
        send(["stop"]);
    }

    function seekTo(sec) {
        send(["seek", Math.max(0, sec), "absolute"]);
    }

    function seekBy(sec) {
        send(["seek", sec, "relative"]);
    }

    function setVolume(v) {
        send(["set_property", "volume", Math.max(0, Math.min(130, Math.round(v)))]);
    }

    function toggleMute() {
        send(["cycle", "mute"]);
    }

    function toggleShuffle() {
        shuffle = !shuffle;
        send([shuffle ? "playlist-shuffle" : "playlist-unshuffle"]);
    }

    function cycleRepeat() {
        const next = repeat === "off" ? "all" : (repeat === "all" ? "one" : "off");
        send(["set_property", "loop-playlist", next === "all" ? "inf" : "no"]);
        send(["set_property", "loop-file", next === "one" ? "inf" : "no"]);
    }

    // Play paths[start], then everything after it. The queue goes to mpv as
    // one playlist file (loadlist) rather than one command per track.
    property var nextList: null

    function playList(paths, start) {
        const list = paths.slice(start || 0, (start || 0) + queueCap);
        if (list.length === 0)
            return;
        ensure();
        // A second request while the first is still being written replaces it
        if (listWriter.running) {
            nextList = list;
            return;
        }
        writeList(list);
    }

    function writeList(list) {
        listWriter.command = ["sh", "-c", "f=\"$1\"; shift; printf '%s\\n' \"$@\" > \"$f\"", "sh", queueFile].concat(list);
        listWriter.running = true;
    }

    function enqueue(p) {
        send(["loadfile", p, "append-play"]);
    }

    // Entries are { path, title, artist, album, duration, cover }: files or URLs
    function playEntries(list, start) {
        const l = list.slice(start || 0);
        remember(l);
        playList(l.map(e => e.path), 0);
    }

    function enqueueEntries(list) {
        remember(list);
        list.forEach(e => enqueue(e.path));
        requestQueue();
    }

    function jumpTo(i) {
        send(["playlist-play-index", i]);
    }

    // ---- Editing the queue --------------------------------------------------
    // The entry that is playing (-1 if none)
    function currentIndex() {
        for (let i = 0; i < queue.length; i++) {
            if (queue[i].current)
                return i;
        }
        return -1;
    }

    // Put songs right after the one that plays, in order. With nothing playing
    // they just start. Returns true when they were put in the queue.
    function playNext(list) {
        if (list.length === 0)
            return false;
        remember(list);
        const cur = currentIndex();
        if (!online || idle || cur < 0) {
            playList(list.map(e => e.path), 0);
            return false;
        }
        list.forEach((e, k) => send(["loadfile", e.path, "insert-at", cur + 1 + k]));
        requestQueue();
        return true;
    }

    // Move the entry at `from` so it takes the place of the one at `to`. (mpv
    // counts `to` before the move: to take one step down, `to` is from + 2.)
    function moveInQueue(from, to) {
        send(["playlist-move", from, to]);
        requestQueue();
    }

    // What the last removal took out, for Ctrl+Z: { path, idx } or null
    property var lastRemoved: null

    function removeFromQueue(i) {
        if (i >= 0 && i < queue.length)
            lastRemoved = {
                "path": queue[i].filename,
                "idx": i
            };
        send(["playlist-remove", i]);
    }

    // Put the last removed entry back where it was
    function undoRemove() {
        const r = lastRemoved;
        if (r === null)
            return false;
        lastRemoved = null;
        if (!online || idle || queue.length === 0)
            send(["loadfile", r.path, "append-play"]);
        else
            send(["loadfile", r.path, "insert-at", Math.min(r.idx, queue.length)]);
        requestQueue();
        return true;
    }

    function clearQueue() {
        send(["playlist-clear"]);
    }

    function scan() {
        if (scanning)
            return;
        scanning = true;
        scanBuf = [];
        scanProc.running = true;
    }

    property var scanBuf: []

    Component.onCompleted: {
        sock.connected = true;
        loadArchive();
        Quickshell.execDetached(["mkdir", "-p", stateDir]);
    }

    // ---- Downloads --------------------------------------------------------
    // One yt-dlp at a time, with the settings of the ytm aliases
    // (yt-dlp/music.conf): ~/Music/Artist/Album/Title.m4a, tags and cover.
    // [{ id, target, mode, title, state: queued | running, pct }]
    property var jobs: []
    property int jobSeq: 0
    property string lastError: ""
    // YouTube ids yt-dlp has already filed (its download archive)
    property var archive: ({})
    property var archiveBuf: ({})
    readonly property int dlCount: jobs.length
    readonly property bool dlActive: jobs.length > 0
    readonly property real dlPct: {
        for (const j of jobs) {
            if (j.state === "running")
                return j.pct;
        }
        return 0;
    }

    signal downloadFinished(var job)
    signal downloadFailed(var job, string message)

    function videoId(u) {
        const m = /[?&]v=([\w-]{11})/.exec(u || "");
        return m ? m[1] : "";
    }

    function downloaded(p) {
        const id = videoId(p);
        return id !== "" && archive[id] === true;
    }

    function jobFor(target) {
        for (const j of jobs) {
            if (j.target === target)
                return j;
        }
        return null;
    }

    // target: a URL, "ytsearch1:words" or "browse:<album id>". mode: track | album
    function download(target, mode, title) {
        if (!target || isRemote(target) === false && target.indexOf("ytsearch") !== 0 && target.indexOf("browse:") !== 0)
            return false;
        if (jobFor(target) !== null)
            return false;
        jobSeq++;
        jobs = jobs.concat([
            {
                "id": jobSeq,
                "target": target,
                "mode": mode === "album" ? "album" : "track",
                "title": title || target,
                "state": "queued",
                "pct": 0
            }
        ]);
        pumpJobs();
        return true;
    }

    function patchJob(id, patch) {
        jobs = jobs.map(j => j.id === id ? Object.assign({}, j, patch) : j);
    }

    function pumpJobs() {
        if (dlProc.running)
            return;
        for (const j of jobs) {
            if (j.state === "queued") {
                runningJob = j.id;
                lastError = "";
                patchJob(j.id, {
                    "state": "running"
                });
                dlProc.command = ["bash", Quickshell.shellPath("music/dl.sh"), j.mode, j.target];
                dlProc.running = true;
                return;
            }
        }
    }

    property int runningJob: 0

    function onDlLine(line) {
        if (line.indexOf("PCT ") === 0) {
            const f = line.trim().split(/\s+/);
            const pct = parseFloat(f[1]);
            const idx = parseInt(f[2]);
            const n = parseInt(f[3]);
            if (!isFinite(pct))
                return;
            // A playlist is one bar across all its songs
            const all = isFinite(idx) && isFinite(n) && n > 1 ? ((idx - 1) + pct / 100) / n * 100 : pct;
            patchJob(runningJob, {
                "pct": Math.min(99, all)
            });
        } else if (line.indexOf("ERROR") === 0) {
            lastError = line.replace(/^ERROR:\s*(\[[^\]]*\]\s*)?/, "").slice(0, 120);
        }
    }

    function onDlExit(code) {
        let job = null;
        for (const j of jobs) {
            if (j.id === runningJob)
                job = j;
        }
        jobs = jobs.filter(j => j.id !== runningJob);
        runningJob = 0;
        if (job !== null) {
            if (code === 0)
                downloadFinished(job);
            else
                downloadFailed(job, lastError !== "" ? lastError : "yt-dlp stopped (exit " + code + ")");
        }
        loadArchive();
        scan();
        pumpJobs();
    }

    function loadArchive() {
        if (archiveProc.running)
            return;
        archiveBuf = {};
        archiveProc.running = true;
    }

    // ---- Resume -----------------------------------------------------------
    // The queue and the position are kept in ~/.local/state/quickshell, so a
    // new session can pick up where the last one stopped.
    readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || home + "/.local/state") + "/quickshell"
    readonly property string stateFilePath: stateDir + "/music-state.json"
    // { queue: [paths], index, position, remote: [entries] } or null
    property var saved: null
    readonly property bool resumable: saved !== null && Array.isArray(saved.queue) && saved.queue.length > 0 && !hasTrack
    readonly property string resumeTitle: {
        if (!resumable)
            return "";
        const p = saved.queue[Math.min(saved.index || 0, saved.queue.length - 1)];
        const t = lookup(p);
        return t ? t.title : baseName(p);
    }
    property int resumeIdx: -1
    property string resumePath: ""
    property real resumeAt: 0

    function saveSoon() {
        if (online && !idle)
            saveTimer.restart();
    }

    function saveNow() {
        if (!online || idle || path === "" || queue.length === 0)
            return;
        let idx = 0;
        for (let i = 0; i < queue.length; i++) {
            if (queue[i].current)
                idx = i;
        }
        const paths = queue.map(e => e.filename);
        const rem = [];
        for (const p of paths) {
            if (remote[p])
                rem.push(remote[p]);
        }
        stateFile.setText(JSON.stringify({
            "queue": paths,
            "index": idx,
            "position": Math.floor(position),
            "remote": rem
        }));
    }

    function restore(text) {
        let d = null;
        try {
            d = JSON.parse(text);
        } catch (e) {
            d = null;
        }
        if (d === null || !Array.isArray(d.queue))
            return;
        remember(d.remote || []);
        saved = d;
    }

    function resume() {
        if (!resumable)
            return;
        const list = saved.queue.slice(0, queueCap);
        resumeIdx = Math.max(0, Math.min(saved.index || 0, list.length - 1));
        resumePath = list[resumeIdx];
        resumeAt = saved.position || 0;
        ensure();
        if (listWriter.running) {
            nextList = list;
            return;
        }
        writeList(list);
    }

    function tryResumeSeek() {
        if (resumePath !== "" && path === resumePath && duration > 0) {
            const at = resumeAt;
            resumePath = "";
            resumeAt = 0;
            if (at > 2 && at < duration - 2)
                seekTo(at);
        }
    }

    // ---- Lyrics -----------------------------------------------------------
    // Fetched by music/lyrics.py (a .lrc next to the file, then a cache, then
    // LRCLIB) for the song that is playing, but only while the panel is showing
    // them. Synced lyrics have a time for every line; plain ones do not.
    // The panel is showing them, or the bar is (Config.musicBarLyrics)
    property bool lyricsView: false
    // Set by the bar chip: open the panel on the lyrics
    property bool lyricsViewRequest: false
    readonly property bool lyricsWanted: lyricsView || (Config.musicBarLyrics && hasTrack)

    onLyricsWantedChanged: ensureLyrics()
    // [{ t, text }]  (t is -1 when the lyrics are not synced)
    property var lyricLines: []
    property bool lyricSynced: false
    // "" | loading | ok | none | error
    property string lyricState: ""
    property string lyricError: ""
    // The song the lyrics above belong to, and the one being asked about
    property string lyricPath: ""
    property string lyricReq: ""
    property string lyricBuf: ""
    property bool lyricAgain: false

    // The line being sung: the last one that has started (a touch early reads better)
    readonly property int lyricIndex: {
        if (!lyricSynced || lyricLines.length === 0)
            return -1;
        const t = position + 0.2;
        let lo = 0;
        let hi = lyricLines.length - 1;
        let r = -1;
        while (lo <= hi) {
            const m = (lo + hi) >> 1;
            if (lyricLines[m].t <= t) {
                r = m;
                lo = m + 1;
            } else {
                hi = m - 1;
            }
        }
        return r;
    }

    // Look for the lyrics of what is playing, unless they are here already
    function ensureLyrics() {
        if (!lyricsWanted || !online || path === "")
            return;
        if (lyricPath === path && lyricState !== "error")
            return;
        lyricPath = path;
        lyricState = "loading";
        lyricLines = [];
        lyricSynced = false;
        lyricError = "";
        // The tags can still be arriving: give them a moment
        lyricsTimer.restart();
    }

    function startLyrics() {
        if (!online || path === "" || lyricPath !== path)
            return;
        if (lyricsProc.running) {
            lyricAgain = true;
            return;
        }
        const t = lookup(path);
        const dur = duration > 0 ? duration : (t && t.duration ? t.duration : 0);
        lyricReq = path;
        lyricBuf = "";
        lyricsProc.command = ["qs-music-py", Quickshell.shellPath("music/lyrics.py"), path, (t && t.artist) || artist, (t && t.title) || title, (t && t.album) || album, String(Math.round(dur)), Config.musicLyricsSave ? "save" : "nosave"];
        lyricsProc.running = true;
    }

    function onLyricsDone() {
        // The song changed while this was running: ask about the new one
        if (lyricAgain || lyricReq !== path) {
            lyricAgain = false;
            if (lyricPath === path)
                startLyrics();
            return;
        }
        let d = null;
        try {
            d = JSON.parse(lyricBuf);
        } catch (e) {
            d = null;
        }
        if (d === null || d.ok !== true) {
            lyricState = "error";
            lyricError = d && d.error ? d.error : "The lyrics lookup did not answer. Is python set up?";
            return;
        }
        if (d.none === true) {
            lyricState = "none";
            return;
        }
        lyricSynced = d.synced === true;
        lyricLines = d.lines.map(l => ({
                    "t": l[0],
                    "text": l[1]
                }));
        lyricState = "ok";
    }

    // ---- Plumbing -------------------------------------------------------
    Socket {
        id: sock

        path: root.sockPath
        connected: false
        parser: SplitParser {
            onRead: line => root.onLine(line)
        }
        onConnectedChanged: {
            if (connected) {
                root.online = true;
                root.failed = false;
                root.observe();
                root.requestQueue();
                const p = root.pending;
                root.pending = [];
                p.forEach(c => root.send(c));
            } else if (root.online) {
                // mpv went away
                root.online = false;
                root.launched = false;
                root.idle = true;
                root.paused = true;
                root.path = "";
                root.queue = [];
            }
        }
    }

    // Try the socket; if nobody answers after a moment, start mpv
    Timer {
        id: connectTimer

        interval: 400
        repeat: true
        onTriggered: {
            if (root.online) {
                stop();
                return;
            }
            root.attempts++;
            if (root.attempts === 2 && !root.launched) {
                root.launched = true;
                Quickshell.execDetached(root.mpvCommand);
            }
            sock.connected = false;
            sock.connected = true;
            if (root.attempts > 25) {
                root.failed = true;
                stop();
            }
        }
    }

    // Writes the queue file, then tells mpv to load it
    Process {
        id: listWriter

        onExited: code => {
            if (code === 0) {
                // Resuming: stay paused and go to the saved entry
                if (root.resumeIdx >= 0)
                    root.send(["set_property", "pause", true]);
                root.send(["loadlist", root.queueFile, "replace"]);
                if (root.resumeIdx >= 0) {
                    root.send(["playlist-play-index", root.resumeIdx]);
                    root.resumeIdx = -1;
                } else {
                    if (root.shuffle)
                        root.send(["playlist-shuffle"]);
                    root.send(["set_property", "pause", false]);
                }
            }
            if (root.nextList) {
                const l = root.nextList;
                root.nextList = null;
                root.writeList(l);
            }
        }
    }

    Process {
        id: scanProc

        command: ["bash", Quickshell.shellPath("music/scan.sh"), root.libraryDir]
        stdout: SplitParser {
            onRead: line => {
                const f = line.split("\t");
                if (f.length >= 5)
                    root.scanBuf.push({
                        path: f[0],
                        artist: f[1],
                        album: f[2],
                        title: f[3],
                        track: parseInt(f[4]) || 0
                    });
            }
        }
        onExited: {
            // Artist, album, then track number (files without one fall back to the path)
            const key = t => (t.artist || "\uffff").toLowerCase() + "\u0000" + (t.album || "\uffff").toLowerCase() + "\u0000" + String(t.track).padStart(4, "0") + "\u0000" + t.path.toLowerCase();
            root.scanBuf.sort((a, b) => key(a) < key(b) ? -1 : (key(a) > key(b) ? 1 : 0));
            root.library = root.scanBuf;
            root.scanBuf = [];
            root.scanning = false;
            root.scanned = true;
        }
    }

    Process {
        id: dlProc

        stdout: SplitParser {
            onRead: line => root.onDlLine(line)
        }
        onExited: code => root.onDlExit(code)
    }

    // ~/Music/.yt-dlp-archive.txt: lines of "youtube <id>"
    Process {
        id: archiveProc

        command: ["sh", "-c", "cat \"$1\" 2>/dev/null; true", "sh", root.libraryDir + "/.yt-dlp-archive.txt"]
        stdout: SplitParser {
            onRead: line => {
                const f = line.trim().split(" ");
                if (f.length >= 2)
                    root.archiveBuf[f[1]] = true;
            }
        }
        onExited: root.archive = root.archiveBuf
    }

    FileView {
        id: stateFile

        path: root.stateFilePath
        printErrors: false
        onLoaded: root.restore(text())
    }

    // A moment after the queue or the track changes, and every few seconds
    // while playing (for the position)
    Timer {
        id: saveTimer

        interval: 1500
        onTriggered: root.saveNow()
    }

    Timer {
        interval: 8000
        repeat: true
        running: root.playing
        onTriggered: root.saveNow()
    }

    Process {
        id: lyricsProc

        stdout: SplitParser {
            onRead: line => root.lyricBuf += line
        }
        onExited: root.onLyricsDone()
    }

    Timer {
        id: lyricsTimer

        interval: 450
        onTriggered: root.startLyrics()
    }

    Process {
        id: coverProc

        command: ["bash", Quickshell.shellPath("music/cover.sh"), root.coverFor]
        stdout: StdioCollector {
            onStreamFinished: {
                const p = text.trim();
                if (root.coverFor === root.path)
                    root.cover = p !== "" ? "file://" + p : "";
                if (root.coverDirty || root.coverFor !== root.path) {
                    root.coverDirty = false;
                    if (root.path !== "")
                        root.fetchCover();
                }
            }
        }
    }
}
