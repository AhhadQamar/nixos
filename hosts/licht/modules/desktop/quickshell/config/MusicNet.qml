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

    readonly property var kinds: ["top", "songs", "videos", "albums", "playlists", "artists"]
    readonly property var labels: ["Top", "Songs", "Videos", "Albums", "Playlists", "Artists"]
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
    // How many results are asked for, and whether there may be more past them
    property int limit: Config.musicSearchPage
    property bool more: false
    // The answer that just arrived was a "load more": the list grew, keep your place
    property bool lastMore: false
    property bool reqMore: false
    property int reqLimit: 0

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
            more = false;
            limit = Config.musicSearchPage;
            return;
        }
        if (t === ranQuery && kind === ranKind)
            return;
        limit = Config.musicSearchPage;
        more = false;
        timer.restart();
    }

    function cycleKind() {
        kindIdx = (kindIdx + 1) % kinds.length;
        results = [];
        ranQuery = "";
        ranKind = "";
        error = "";
        more = false;
        limit = Config.musicSearchPage;
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
        reqLimit = limit;
        reqMore = pendingMore;
        pendingMore = false;
        buf = "";
        proc.command = ["qs-music-py", Quickshell.shellPath("music/search.py"), "search", reqKind, reqQuery, String(reqLimit)];
        proc.running = true;
    }

    property bool pendingMore: false

    // Searches that found something, newest first, kept in
    // ~/.local/state/quickshell/music-searches.json
    property var history: []
    readonly property int historyMax: 15

    function remember(q) {
        const t = q.trim();
        if (t === "")
            return;
        const h = [t].concat(history.filter(x => x.toLowerCase() !== t.toLowerCase())).slice(0, historyMax);
        history = h;
        historyFile.setText(JSON.stringify(h));
    }

    function forget(q) {
        history = history.filter(x => x !== q);
        historyFile.setText(JSON.stringify(history));
    }

    FileView {
        id: historyFile

        path: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/quickshell/music-searches.json"
        printErrors: false
        onLoaded: {
            try {
                const d = JSON.parse(text());
                if (Array.isArray(d))
                    root.history = d.filter(x => typeof x === "string").slice(0, root.historyMax);
            } catch (e) {}
        }
    }

    // Ask for the next page of the same search: more results, same query. The list
    // is replaced by the longer one, so the panel keeps your place (lastMore).
    function loadMore() {
        if (!more || busy || query === "" || query !== ranQuery || kind !== ranKind)
            return;
        if (limit >= Config.musicSearchMax)
            return;
        limit = Math.min(Config.musicSearchMax, limit + Config.musicSearchPage);
        pendingMore = true;
        run();
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
        // Only offer more while the cap is not reached
        more = d.more === true && reqLimit < Config.musicSearchMax;
        lastMore = reqMore;
        results = decorate(d.items, reqKind);
        ranQuery = reqQuery;
        ranKind = reqKind;
        if (results.length === 0)
            error = "";
        else if (!reqMore)
            remember(reqQuery);
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
