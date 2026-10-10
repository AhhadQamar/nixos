// Music backend: one resident mpv that plays ~/Music, driven over its JSON IPC
// socket. mpv is started detached, so music keeps playing when the shell is
// reloaded, and the shell reattaches to it. The panel (MusicPlayer.qml) and the
// bar chip (MusicChip.qml) both read from here.

pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    // ---- Settings -------------------------------------------------------
    readonly property string home: Quickshell.env("HOME")
    readonly property string libraryDir: home + "/Music"
    readonly property string runtime: Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"
    readonly property string sockPath: runtime + "/quickshell-music.sock"
    readonly property int queueCap: 2000
    // --no-config: your normal mpv.conf (uosc, night mode, resume) is for video
    readonly property var mpvCommand: ["mpv", "--no-config", "--idle=yes", "--no-video", "--force-window=no", "--no-terminal", "--audio-display=no", "--load-scripts=no", "--keep-open=no", "--audio-client-name=quickshell-music", "--volume=70", "--volume-max=130", "--input-ipc-server=" + sockPath]

    // ---- Library --------------------------------------------------------
    // [{ path, artist, album, title }], sorted
    property var library: []
    property bool scanning: false
    property bool scanned: false

    // ---- Playback (mirrored from mpv) -----------------------------------
    property bool online: false
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

    function lookup(p) {
        return byPath[p] || null;
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
            position = typeof d === "number" ? d : 0;
            break;
        case "duration":
            duration = typeof d === "number" ? d : 0;
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
            } else {
                // Until the tags arrive, show the file name
                title = baseName(path);
                fetchCover();
            }
            requestQueue();
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
        if (!d || typeof d !== "object")
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

    // Play paths[start], then everything after it
    function playList(paths, start) {
        const list = paths.slice(start || 0, (start || 0) + queueCap);
        if (list.length === 0)
            return;
        send(["loadfile", list[0], "replace"]);
        for (let i = 1; i < list.length; i++)
            send(["loadfile", list[i], "append"]);
        if (shuffle)
            send(["playlist-shuffle"]);
        send(["set_property", "pause", false]);
    }

    function enqueue(p) {
        send(["loadfile", p, "append-play"]);
    }

    function jumpTo(i) {
        send(["playlist-play-index", i]);
    }

    function removeFromQueue(i) {
        send(["playlist-remove", i]);
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

    Component.onCompleted: sock.connected = true

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
            if (root.attempts > 25)
                stop();
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
