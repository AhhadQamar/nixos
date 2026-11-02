// Online lookups for the music player: YouTube Music search, and the songs of
// an album, playlist or artist. The work is done by music/search.py (ytmusicapi,
// no login); this file only debounces, keeps one request in flight and hands
// back the results. Streaming itself is Music.qml's job (mpv + yt-dlp).

pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    readonly property var kinds: ["top", "songs", "albums", "playlists", "artists"]
    readonly property var labels: ["Top", "Songs", "Albums", "Playlists", "Artists"]
    property int kindIdx: 0
    readonly property string kind: kinds[kindIdx]
    readonly property string kindLabel: labels[kindIdx]

    property string query: ""
    // [{ key, kind, id, path, title, artist, album, cover, group, ... }]
    property var results: []
    property bool busy: false
    property string error: ""
    // What `results` answers
    property string ranQuery: ""
    property string ranKind: ""

    signal tracksReady(int id, var data)
    signal tracksFailed(int id, string message)

    property bool again: false
    property string reqQuery: ""
    property string reqKind: ""
    property string buf: ""
    property int trackSeq: 0
    property var trackReq: null
    property var nextTrackReq: null
    property string trackBuf: ""

    // Rows the dial can show: a key, and no local "group" (covers come as URLs)
    function decorate(list, tag) {
        return list.map((r, i) => Object.assign({}, r, {
                "key": tag + ":" + (r.id || r.path) + ":" + i,
                "group": "",
                "album": r.album || ""
            }));
    }

    function setQuery(q) {
        const t = q.trim();
        query = t;
        if (t === "") {
            timer.stop();
            results = [];
            error = "";
            ranQuery = "";
            ranKind = "";
            busy = false;
            return;
        }
        if (t === ranQuery && kind === ranKind)
            return;
        timer.restart();
    }

    function cycleKind() {
        kindIdx = (kindIdx + 1) % kinds.length;
        results = [];
        ranQuery = "";
        ranKind = "";
        error = "";
        if (query !== "")
            timer.restart();
    }

    function run() {
        if (query === "")
            return;
        if (proc.running) {
            again = true;
            return;
        }
        again = false;
        busy = true;
        error = "";
        reqQuery = query;
        reqKind = kind;
        buf = "";
        proc.command = ["qs-music-py", Quickshell.shellPath("music/search.py"), "search", reqKind, reqQuery];
        proc.running = true;
    }

    function onSearchDone() {
        if (query === "") {
            busy = false;
            return;
        }
        // The question changed while this was running: ask again
        if (again || reqQuery !== query || reqKind !== kind) {
            run();
            return;
        }
        busy = false;
        let d = null;
        try {
            d = JSON.parse(buf);
        } catch (e) {
            d = null;
        }
        if (d === null) {
            results = [];
            error = "Search did not answer. Is ytmusicapi installed?";
            return;
        }
        if (!d.ok) {
            results = [];
            error = d.error || "Search failed";
            return;
        }
        results = decorate(d.items, reqKind);
        ranQuery = reqQuery;
        ranKind = reqKind;
        if (results.length === 0)
            error = "";
    }

    // Songs of an album, playlist or artist. Returns an id; the answer comes
    // as tracksReady / tracksFailed with the same id. Only the newest request
    // waits its turn.
    function fetchTracks(kind, ident) {
        trackSeq++;
        const req = {
            "id": trackSeq,
            "kind": kind,
            "ident": ident
        };
        if (trackProc.running)
            nextTrackReq = req;
        else
            startTracks(req);
        return trackSeq;
    }

    function startTracks(req) {
        trackReq = req;
        trackBuf = "";
        trackProc.command = ["qs-music-py", Quickshell.shellPath("music/search.py"), "tracks", req.kind, req.ident];
        trackProc.running = true;
    }

    function onTracksDone() {
        const req = trackReq;
        trackReq = null;
        if (nextTrackReq !== null) {
            const n = nextTrackReq;
            nextTrackReq = null;
            if (req !== null)
                tracksFailed(req.id, "Superseded");
            startTracks(n);
            return;
        }
        if (req === null)
            return;
        let d = null;
        try {
            d = JSON.parse(trackBuf);
        } catch (e) {
            d = null;
        }
        if (d === null || !d.ok) {
            tracksFailed(req.id, d && d.error ? d.error : "Could not load it");
            return;
        }
        d.items = decorate(d.items, "t" + req.id);
        tracksReady(req.id, d);
    }

    Timer {
        id: timer

        interval: 380
        onTriggered: root.run()
    }

    Process {
        id: proc

        stdout: SplitParser {
            onRead: line => root.buf += line
        }
        onExited: root.onSearchDone()
    }

    Process {
        id: trackProc

        stdout: SplitParser {
            onRead: line => root.trackBuf += line
        }
        onExited: root.onTracksDone()
    }
}
