// MusicPlayer.qml
// The music player: one card, two sides, nothing hidden behind anything.
//
//   LEFT   what is playing. The cover runs edge to edge across the top with the
//          title laid over its foot; under it the time as a big light numeral, a
//          waveform that is the song (click or drag to seek), the transport, the
//          volume and what comes next. The lyrics (Ctrl+Y or the lines button)
//          slide in under a slim banner and stay beside the lists.
//   RIGHT  browsing, as real lists. Search on top (it is always the box you type
//          in), then six tabs one key apart (Tab):
//              Albums  one row per album: the quick way to put something on
//              Tracks  every song, an album's tracks together under its cover;
//                      the spine on the left is lit up to the song that plays
//              Queue   what is playing and what is coming; move, remove, undo
//              Online  search YouTube Music; Enter streams, Ctrl+D downloads
//              Lists   playlists (plain .m3u8 files), Liked Songs first
//          The row under the cursor shows its actions as buttons (play, next,
//          queue, like, add to a playlist); the keys still do the same.
//
//   qs ipc call music toggle | open | close | playpause | next | prev | stop | rescan
//   qs ipc call music download <url | ytsearch1:words | browse:id> <track|album>
//   qs ipc call music resume | like | lyrics | shuffleall | sleep <minutes, 0 = off>
//   qs ipc call music media <playpause|next|prev>   (media keys: falls back to playerctl)
//
// Keys   browse   Up Down (Ctrl+N / Ctrl+P) move   PgUp PgDn jump 8   Home End ends
//                 Tab (Shift+Tab) next / previous tab   Ctrl+1 .. 5 pick a tab
//                 Ctrl+Left Ctrl+Right previous / next album (in Tracks)   Ctrl+J back to what is playing
//        play     Enter  Albums: play the album   Tracks: play from this song on
//                 Ctrl+Enter  Albums: play from this album on   Tracks: play this album
//                 Shift+Enter add to the queue   Space play / pause (search empty)   Ctrl+Space always
//                 Ctrl+Shift+S shuffle everything shown
//        player   Alt+Left Alt+Right previous / next track   Shift+Left Shift+Right seek 10 s
//                 Shift+Up Shift+Down volume   Ctrl+M mute   Ctrl+S shuffle   Ctrl+R repeat
//                 Ctrl+E sleep timer (15, 30, 60 minutes, off)
//        queue    Delete (or Ctrl+D) remove the highlighted entry   Ctrl+Z puts it back
//                 Alt+Up / Alt+Down move it up / down   Alt+Enter play it next
//                 Ctrl+Shift+A save the queue as a playlist
//        any tab  Alt+Enter plays the song (album, playlist) right after the current one
//        albums   Ctrl+O sorts by artist or by album name
//        online   Ctrl+T songs / albums / playlists / artists   Enter stream (from here on)
//                 Shift+Enter queue   Ctrl+Enter open an album, playlist or artist
//                 Ctrl+D download (Ctrl+Shift+D: the whole album you are in)
//                 Esc or Backspace (search empty) goes back out of an album
//        lists    Enter play   Ctrl+Enter open   Delete remove (twice, for a whole list)
//                 Ctrl+L like the song (or the one playing)   Ctrl+A add to a playlist:
//                 pick one with Enter, or type a new name and press Enter
//        space    Space with nothing playing picks up the last queue and position
//        lyrics   Ctrl+Y (or the lines button) shows the lyrics of the song that plays, in
//                 time with it. Click a line to jump there. Up / Down nudge the timing.
//        Esc clears the search, then closes
// Mouse  click a row to put the cursor on it, double-click to play it; the buttons
//        on the row do the rest. Scroll the lists; scroll the left side for volume;
//        click or drag the waveform to seek; click outside to close
//
// State and mpv live in Music.qml; this file is only the interface.

import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets // ClippingRectangle: a Rectangle that clips its children to rounded corners

PanelWindow {
    id: panel

    // ---- Settings -------------------------------------------------------
    // One card in the middle of the screen: the player on the left, the lists
    // on the right
    readonly property int stageW: Math.min(980, width - 48)
    readonly property int stageH: Math.min(640, height - 64)
    readonly property int leftW: 340
    readonly property int pad: 28
    // The cover banner: tall, or a slim strip while the lyrics are open
    readonly property int bannerTall: 330
    readonly property int bannerSlim: 92
    // The spine and the gutters of the lists
    readonly property int spineX: 54
    readonly property int gutter: 34
    // Where each entry sits along a list (kept for the code that builds the lists)
    readonly property real groupGap: 0.5

    // ---- State ----------------------------------------------------------
    property bool isOpen: false
    // 0 = away, 1 = in place
    property real reveal: 0
    // A slow pulse (0..1) for the node of the song that plays
    property real breath: 0
    // The lyrics open on the left, under a slim banner; lyricsMix is 0..1 as it fades
    property bool lyricsOn: false
    property real lyricsMix: lyricsOn ? 1 : 0
    // Which line unsynced lyrics are scrolled to
    property real lyricScroll: 0

    // The shortcuts sheet (F1, or ? with an empty search): any key puts it away
    property bool helpOn: false
    property real helpMix: helpOn ? 1 : 0
    // What a hovered row button does, shown in the foot
    property string tipNow: ""
    // Albums: "artist" (the library's order) or "title"
    property string albSort: "artist"
    // The songs of each album, by group, for playing one or several
    property var groupPaths: ({})
    readonly property var keyHelp: [
        {
            "k": ["Enter"],
            "d": "play"
        },
        {
            "k": ["Shift", "Enter"],
            "d": "add to the end of the queue"
        },
        {
            "k": ["Alt", "Enter"],
            "d": "play next"
        },
        {
            "k": ["Space"],
            "d": "play / pause"
        },
        {
            "k": ["Alt", "\u2190\u2192"],
            "d": "previous / next song"
        },
        {
            "k": ["Shift", "\u2190\u2192"],
            "d": "seek 10 seconds"
        },
        {
            "k": ["Shift", "\u2191\u2193"],
            "d": "volume"
        },
        {
            "k": ["Ctrl", "L"],
            "d": "like"
        },
        {
            "k": ["Ctrl", "A"],
            "d": "add to a playlist"
        },
        {
            "k": ["Ctrl", "D"],
            "d": "download, or remove from the queue"
        },
        {
            "k": ["Ctrl", "Z"],
            "d": "put a removed song back"
        },
        {
            "k": ["Alt", "\u2191\u2193"],
            "d": "move a song in the queue"
        },
        {
            "k": ["Ctrl", "T"],
            "d": "what to search for online"
        },
        {
            "k": ["Ctrl", "Y"],
            "d": "lyrics (\u2191\u2193 nudge the timing)"
        },
        {
            "k": ["Ctrl", "Shift", "S"],
            "d": "shuffle everything shown"
        },
        {
            "k": ["Ctrl", "Shift", "A"],
            "d": "save the queue as a playlist"
        },
        {
            "k": ["Ctrl", "O"],
            "d": "sort albums by artist or name"
        },
        {
            "k": ["Ctrl", "E"],
            "d": "sleep timer: 15, 30, 60 min, off"
        }
    ]

    Behavior on helpMix {
        NumberAnimation {
            duration: Style.baseMs * 1.5
            easing.type: Easing.OutCubic
        }
    }

    Behavior on lyricsMix {
        NumberAnimation {
            duration: Style.baseMs * 1.5
            easing.type: Easing.OutCubic
        }
    }

    onLyricsOnChanged: {
        Music.lyricsView = lyricsOn;
        if (lyricsOn)
            Music.ensureLyrics();
    }
    // 0 = albums, 1 = tracks, 2 = queue, 3 = online, 4 = lists
    property int tab: 0
    // The search moved us from Albums to Tracks by itself (so clearing it goes back)
    property bool autoTracks: false
    property string query: ""
    // Highlighted entry in the albums, the tracks and the queue
    property int asel: 0
    property int sel: 0
    property int qsel: 0
    // What is on the dial: [{ key, path, title, artist, album, group, ... }]
    // and where each sits along it, in disc units
    property var albItems: []
    property var albPos: []
    property var libItems: []
    property var libPos: []
    property var qItems: []
    property var qPos: []
    // Online results (or the songs of the album you opened), and the lists
    property var oItems: []
    property var oPos: []
    property var lItems: []
    property var lPos: []
    property int osel: 0
    property int lsel: 0
    // An album, playlist or artist opened from the results: { item, title, items, playlist }
    property var oOpened: null
    property int oBackSel: 0
    property string oBackQuery: ""
    // The playlist whose songs are shown ("" = the playlists themselves)
    property string lOpen: ""
    property var lTracks: []
    property int lBackSel: 0
    // Songs waiting for a playlist to be picked, and where to go back to
    property var pickFor: []
    property int pickBack: 0
    property string pickQuery: ""
    // What an album, playlist or list that is being loaded is wanted for
    property var fetchTag: null
    property var listTag: null
    property int listSeq: 0
    // The Clear button of the queue has been pressed once
    property bool clearArmed: false
    // A short message that takes the place of the small line over the name
    property string note: ""
    // (kept so the lists below can say "jump, do not glide"; the lists do not glide)
    property bool animateView: false
    // Covers by album, and the albums still waiting for theirs
    property var covers: ({})
    property var coverQueue: []
    property string coverBusy: ""
    // Seeking by dragging the ruler: where it is dragged to, 0..1
    property bool seeking: false
    property real seekFrac: 0
    // Opens on the monitor that has focus (set in open())
    property var targetScreen: Focus.screen

    readonly property var items: [albItems, libItems, qItems, oItems, lItems][tab]
    readonly property int n: items.length
    readonly property int selIdx: n > 0 ? clamp([asel, sel, qsel, osel, lsel][tab], 0, n - 1) : 0
    // Something to step back out of: an album you opened, a playlist
    readonly property bool canGoBack: (tab === 3 && oOpened !== null) || (tab === 4 && lOpen !== "")
    // The song that is playing, as the hearts see it
    readonly property bool playingLiked: Music.hasTrack && MusicLists.isLiked(Music.path)
    readonly property var playingJob: Music.hasTrack ? Music.jobFor(Music.path) : null
    // The album that is playing right now
    readonly property string playingGroup: {
        const t = Music.lookup(Music.path);
        return Music.hasTrack && t ? groupOf(t) : "";
    }
    readonly property var curItem: n > 0 ? items[selIdx] : null
    readonly property bool curPlaying: curItem !== null && isPlaying(curItem)
    // Where the song that plays sits among the shown songs (-1 = not shown), for the spine
    readonly property int playIdx: {
        if (!Music.hasTrack)
            return -1;
        const p = Music.path;
        for (let i = 0; i < libItems.length; i++) {
            if (libItems[i].path === p)
                return i;
        }
        return -1;
    }
    readonly property string playIdxGroup: playIdx >= 0 ? libItems[playIdx].group : ""
    // The next song in the queue, for the line under the transport
    readonly property string nextTitle: {
        const q = Music.queue;
        let c = -1;
        for (let i = 0; i < q.length; i++) {
            if (q[i].current) {
                c = i;
                break;
            }
        }
        if (c < 0 || c + 1 >= q.length)
            return "";
        const t = Music.lookup(q[c + 1].filename);
        return t && t.title ? t.title : Music.baseName(q[c + 1].filename);
    }
    readonly property color tint: Colors.accent

    onSelIdxChanged: {
        coverTimer.restart();
        Qt.callLater(scrollToSel);
    }
    onTabChanged: {
        coverTimer.restart();
        Qt.callLater(scrollToSel);
    }
    onQueryChanged: {
        const q = query.trim();
        if (q !== "")
            lyricsOn = false;
        // Searching is for songs: go there, and come back when it is cleared
        if (q !== "" && tab === 0) {
            tab = 1;
            autoTracks = true;
        } else if (q === "" && autoTracks && tab === 1) {
            tab = 0;
            autoTracks = false;
        }
        refilter(q === "" ? "playing" : "best");
        refilterQueue(q === "");
        // Online it is a web search; inside an album it filters its songs
        if (oOpened !== null)
            refilterOnline(false);
        else if (tab === 3 && pickFor.length === 0) {
            MusicNet.setQuery(q);
            // Typing replaces the recent searches; clearing brings them back
            refilterOnline(false);
        }
        refilterLists(false);
    }

    // ---- Helpers --------------------------------------------------------
    function clamp(v, a, b) {
        return Math.max(a, Math.min(b, v));
    }

    function g(cp) {
        return String.fromCodePoint(cp);
    }

    function mod(a, b) {
        return ((a % b) + b) % b;
    }

    function say(t, ms) {
        note = t;
        noteTimer.interval = ms || 2200;
        noteTimer.restart();
    }

    // After asking for something to play: if nothing starts, say why
    function watchPlay() {
        playCheck.restart();
    }

    function folderOf(path) {
        const parts = path.split("/");
        return parts.length >= 2 ? parts[parts.length - 2] : path;
    }

    // Keep the cursor row in view (the lists are plain ListViews)
    function scrollToSel() {
        if (typeof list === "undefined" || list === null || n === 0)
            return;
        if (selIdx === 0)
            list.positionViewAtBeginning();
        else
            list.positionViewAtIndex(selIdx, ListView.Contain);
    }

    // Tracks: a header (the album's cover and name) before the first song of each album
    function groupHead(i) {
        return tab === 1 && i >= 0 && i < n && (i === 0 || items[i - 1].group !== items[i].group);
    }

    // Queue: what each stretch of it is called
    function queueCaption(i) {
        if (tab !== 2 || query.trim() !== "" || i < 0 || i >= n)
            return "";
        if (items[i].current)
            return "now playing";
        if (i > 0 && items[i - 1].current)
            return "up next  \u00b7  " + (n - i);
        if (i === 0)
            return "played";
        return "";
    }

    // Tracks of one album share a group; a loose file groups with its folder
    function groupOf(t) {
        if (t.album)
            return (t.artist || "") + "\u0000" + t.album;
        const i = t.path.lastIndexOf("/");
        return "dir:" + (i > 0 ? t.path.slice(0, i) : t.path);
    }

    function isPlaying(m) {
        if (tab === 2)
            return m.current === true;
        if (tab === 0)
            return playingGroup !== "" && m.group === playingGroup;
        if (tab === 3 || tab === 4)
            return m.kind === "song" && Music.hasTrack && m.path === Music.path;
        return Music.hasTrack && m.path === Music.path;
    }

    // ---- Covers ---------------------------------------------------------
    // One per album, found on demand for the entries near the middle, one at
    // a time (cover.sh takes the picture next to the file or in its tags).
    function coverOf(m) {
        const c = covers[m.group];
        return c ? c : "";
    }

    function setCover(group, url) {
        const c = Object.assign({}, covers);
        c[group] = url;
        covers = c;
    }

    function wantCover(m, front) {
        // Streamed songs and online results bring their own cover (a URL)
        if (!m || m.group === "" || m.cover || Music.isRemote(m.path) || covers[m.group] !== undefined || coverBusy === m.group)
            return;
        for (const q of coverQueue) {
            if (q.group === m.group)
                return;
        }
        const job = {
            "group": m.group,
            "path": m.path
        };
        coverQueue = front ? [job].concat(coverQueue) : coverQueue.concat([job]);
    }

    function pumpCovers() {
        if (coverProc.running || coverQueue.length === 0)
            return;
        const j = coverQueue[0];
        coverQueue = coverQueue.slice(1);
        coverBusy = j.group;
        coverProc.command = ["bash", Quickshell.shellPath("music/cover.sh"), j.path];
        coverProc.running = true;
    }

    function ensureCovers() {
        if (n === 0)
            return;
        wantCover(items[selIdx], true);
        for (let d = 1; d <= 14; d++) {
            if (selIdx + d < n)
                wantCover(items[selIdx + d], false);
            if (selIdx - d >= 0)
                wantCover(items[selIdx - d], false);
        }
        pumpCovers();
    }

    // The cover mpv's track already has is the best one for its album
    function seedCover() {
        const t = Music.lookup(Music.path);
        if (t && Music.cover !== "")
            setCover(groupOf(t), Music.cover);
    }

    // ---- Library --------------------------------------------------------
    // Fuzzy: the typed letters only have to appear in order. The order of the
    // library (artist, album, track) is kept so albums stay together; the
    // highlight goes to the best match. The albums are the same tracks, one
    // cover each. `mode`: "best" the best match, "playing" what is playing,
    // "keep" whatever was highlighted.
    function refilter(mode) {
        const q = query.trim();
        const keepPath = mode === "keep" ? (sel < libItems.length ? libItems[sel].path : "") : (mode === "playing" ? Music.path : "");
        const keepGroup = mode === "keep" ? (asel < albItems.length ? albItems[asel].group : "") : (mode === "playing" ? playingGroup : "");
        const out = [];
        const pos = [];
        let last = null;
        let gi = -1;
        let best = 0;
        let bestScore = -1;
        for (const t of Music.library) {
            let sc = 0;
            if (q !== "") {
                sc = Fuzzy.score(t.artist + " " + t.album + " " + t.title, q);
                if (sc < 0)
                    continue;
            }
            const grp = groupOf(t);
            if (grp !== last) {
                gi++;
                last = grp;
            }
            if (sc > bestScore) {
                bestScore = sc;
                best = out.length;
            }
            out.push({
                "key": t.path,
                "path": t.path,
                "title": t.title,
                "artist": t.artist,
                "album": t.album,
                "track": t.track || 0,
                "group": grp
            });
            pos.push(out.length - 1 + groupGap * gi);
        }
        let at = -1;
        if (keepPath !== "") {
            for (let i = 0; i < out.length; i++) {
                if (out[i].path === keepPath) {
                    at = i;
                    break;
                }
            }
        }
        if (at < 0)
            at = mode === "keep" ? clamp(sel, 0, Math.max(0, out.length - 1)) : best;
        // One cover per album, from the same tracks
        const alb = [];
        const apos = [];
        let lastGroup = null;
        for (let i = 0; i < out.length; i++) {
            const t = out[i];
            if (t.group !== lastGroup) {
                lastGroup = t.group;
                apos.push(alb.length);
                alb.push({
                    "key": t.group,
                    "path": t.path,
                    "title": t.album || folderOf(t.path),
                    "artist": t.artist,
                    "album": t.album,
                    "group": t.group,
                    "first": i,
                    "count": 1
                });
            } else {
                alb[alb.length - 1].count++;
            }
        }
        if (albSort === "title")
            alb.sort((a, b) => a.title.localeCompare(b.title, undefined, {
                    "sensitivity": "base",
                    "numeric": true
                }));
        const gp = {};
        for (const t of out) {
            if (gp[t.group] === undefined)
                gp[t.group] = [];
            gp[t.group].push(t.path);
        }
        groupPaths = gp;
        let aAt = -1;
        const wantGroup = keepGroup !== "" ? keepGroup : (mode === "best" && out.length > 0 ? out[best].group : "");
        if (wantGroup !== "") {
            for (let i = 0; i < alb.length; i++) {
                if (alb[i].group === wantGroup) {
                    aAt = i;
                    break;
                }
            }
        }
        if (aAt < 0)
            aAt = mode === "keep" ? clamp(asel, 0, Math.max(0, alb.length - 1)) : 0;
        // Jump there, do not glide
        animateView = false;
        libItems = out;
        libPos = pos;
        albItems = alb;
        albPos = apos;
        sel = Math.max(0, at);
        asel = Math.max(0, aAt);
        animateView = true;
        Qt.callLater(scrollToSel);
        coverTimer.restart();
    }

    // Play the shown songs from entry i on
    function playFrom(i) {
        const paths = [];
        for (let k = i; k < libItems.length && paths.length < 2000; k++)
            paths.push(libItems[k].path);
        if (paths.length === 0)
            return;
        Music.playList(paths, 0);
        say("Playing " + paths.length + (paths.length === 1 ? " song" : " songs"));
        watchPlay();
    }

    // Play just the songs of one album (the shown ones, if a search is on)
    function playGroup(grp) {
        const paths = groupPaths[grp] || [];
        if (paths.length === 0)
            return;
        Music.playList(paths, 0);
        say("Playing the album, " + paths.length + (paths.length === 1 ? " song" : " songs"));
        watchPlay();
    }

    // Albums, in the order they are shown: this one, then the ones after it
    function playAlbumsFrom(i) {
        const paths = [];
        for (let k = i; k < albItems.length && paths.length < 2000; k++) {
            const g = groupPaths[albItems[k].group] || [];
            for (const p of g)
                paths.push(p);
        }
        if (paths.length === 0)
            return;
        Music.playList(paths, 0);
        say("Playing " + paths.length + (paths.length === 1 ? " song" : " songs"));
        watchPlay();
    }

    // Ctrl+Shift+S: everything that is shown (the whole library, or what a search found), shuffled
    function shuffleAll() {
        const paths = libItems.map(m => m.path);
        if (paths.length === 0) {
            say("Nothing to shuffle");
            return;
        }
        for (let i = paths.length - 1; i > 0; i--) {
            const j = Math.floor(Math.random() * (i + 1));
            const t = paths[i];
            paths[i] = paths[j];
            paths[j] = t;
        }
        Music.playList(paths, 0);
        say("Shuffling " + songsWord(Math.min(paths.length, Music.queueCap)));
        watchPlay();
    }

    function cycleSort() {
        if (tab !== 0)
            return;
        albSort = albSort === "artist" ? "title" : "artist";
        refilter("keep");
        say(albSort === "artist" ? "Albums by artist" : "Albums by name");
    }

    // The queue as songs, for saving it as a playlist
    function queueEntries() {
        return Music.queue.map(e => {
            const t = Music.lookup(e.filename);
            return entryOf(t ? t : {
                "path": e.filename
            });
        });
    }

    function saveQueue() {
        const list = queueEntries();
        if (list.length === 0) {
            say("The queue is empty");
            return;
        }
        startPick(list);
    }

    // ---- Queue ----------------------------------------------------------
    // `reset` puts the highlight on the track that is playing
    function refilterQueue(reset) {
        const q = query.trim();
        const list = Music.queue;
        const out = [];
        const pos = [];
        let cur = -1;
        for (let i = 0; i < list.length; i++) {
            const e = list[i];
            const info = Music.lookup(e.filename);
            const title = info ? info.title : Music.baseName(e.filename);
            const artist = info ? info.artist : "";
            if (q !== "" && Fuzzy.score(artist + " " + title, q) < 0)
                continue;
            if (e.current)
                cur = out.length;
            pos.push(out.length);
            out.push({
                "key": "q" + i,
                "idx": i,
                "path": e.filename,
                "title": title,
                "artist": artist,
                "album": info ? info.album : "",
                "group": info ? groupOf(info) : "",
                "cover": info && info.cover ? info.cover : "",
                "current": e.current === true
            });
        }
        animateView = false;
        qItems = out;
        qPos = pos;
        if (reset)
            qsel = cur >= 0 ? cur : 0;
        else
            qsel = clamp(qsel, 0, Math.max(0, out.length - 1));
        animateView = true;
        Qt.callLater(scrollToSel);
        coverTimer.restart();
    }

    function requestClear() {
        if (!clearArmed) {
            clearArmed = true;
            clearTimer.restart();
            return;
        }
        clearArmed = false;
        Music.clearQueue();
        say("Queue cleared");
    }

    // ---- Online ---------------------------------------------------------
    // The search box is a web search here (music/search.py, YouTube Music).
    // Results are songs, albums, playlists or artists; an album, playlist or
    // artist opens into its songs.
    function entryOf(m) {
        return {
            "path": m.path,
            "title": m.title || "",
            "artist": m.artist || "",
            "album": m.album || "",
            "duration": m.duration || 0,
            "cover": m.cover || ""
        };
    }

    function kindWord(k) {
        return ({
                "song": "Song",
                "album": "Album",
                "playlist": "Playlist",
                "artist": "Artist",
                "list": "Playlist",
                "recent": "Recent",
                "new": "New playlist"
            })[k] || "";
    }

    function songsWord(c) {
        return c + (c === 1 ? " song" : " songs");
    }

    function refilterOnline(keepSel) {
        const q = query.trim();
        // With nothing typed, the Online tab offers your recent searches
        const src = oOpened !== null ? oOpened.items : (q === "" ? MusicNet.history.map(h => ({
                        "key": "r:" + h,
                        "kind": "recent",
                        "title": h,
                        "artist": "",
                        "album": "",
                        "path": "",
                        "group": "",
                        "cover": ""
                    })) : MusicNet.results);
        const out = [];
        const pos = [];
        for (const r of src) {
            if (oOpened !== null && q !== "" && Fuzzy.score(r.artist + " " + r.album + " " + r.title, q) < 0)
                continue;
            pos.push(out.length);
            out.push(r);
        }
        animateView = false;
        oItems = out;
        oPos = pos;
        osel = keepSel ? clamp(osel, 0, Math.max(0, out.length - 1)) : 0;
        animateView = true;
        Qt.callLater(scrollToSel);
        coverTimer.restart();
    }

    function cycleKind() {
        if (tab === 3 && oOpened === null)
            MusicNet.cycleKind();
    }

    // Load the songs of an album, playlist or artist, then do `action`:
    // play | queue | open | pick | download
    function fetchThen(item, action) {
        if (item.kind === "song" || item.kind === "recent")
            return;
        const id = MusicNet.fetchTracks(item.kind, item.id);
        fetchTag = {
            "id": id,
            "action": action,
            "item": item
        };
        say("Loading  ·  " + (item.title || ""), 8000);
    }

    function onTracks(id, data) {
        const t = fetchTag;
        if (t === null || t.id !== id)
            return;
        fetchTag = null;
        note = "";
        noteTimer.stop();
        const entries = data.items.map(entryOf);
        if (entries.length === 0) {
            say("Nothing in it");
            return;
        }
        if (t.action === "play") {
            Music.playEntries(entries, 0);
            say("Playing " + songsWord(entries.length));
            watchPlay();
        } else if (t.action === "queue") {
            Music.enqueueEntries(entries);
            say("Added " + songsWord(entries.length) + " to the end of the queue");
        } else if (t.action === "next") {
            playNextEntries(entries);
        } else if (t.action === "open") {
            openCollection(t.item, data);
        } else if (t.action === "pick") {
            startPick(entries);
        } else if (t.action === "download") {
            downloadEntries(entries);
        }
    }

    function onTracksFailed(id, message) {
        if (fetchTag !== null && fetchTag.id === id) {
            fetchTag = null;
            say(message, 6000);
        }
    }

    function openCollection(item, data) {
        oBackSel = osel;
        oBackQuery = query;
        oOpened = {
            "item": item,
            "title": data.title || item.title,
            "items": data.items,
            "playlist": data.playlist || item.playlist || ""
        };
        search.clear();
        refilterOnline(false);
    }

    // Esc or Backspace: out of an album, out of a playlist
    function goBack() {
        if (tab === 3 && oOpened !== null) {
            oOpened = null;
            search.text = oBackQuery;
            refilterOnline(false);
            osel = clamp(oBackSel, 0, Math.max(0, oItems.length - 1));
        } else if (tab === 4 && lOpen !== "") {
            lOpen = "";
            lTracks = [];
            search.clear();
            refilterLists(false);
            lsel = clamp(lBackSel, 0, Math.max(0, lItems.length - 1));
        }
    }

    function activateOnline() {
        const c = curItem;
        // A recent search: run it again
        if (c.kind === "recent") {
            search.text = c.title;
            return;
        }
        if (c.kind !== "song") {
            fetchThen(c, "play");
            return;
        }
        // This song and the ones after it
        const list = [];
        for (let k = selIdx; k < oItems.length; k++) {
            if (oItems[k].kind === "song")
                list.push(entryOf(oItems[k]));
        }
        Music.playEntries(list, 0);
        say("Streaming " + songsWord(list.length));
        watchPlay();
    }

    // ---- Lists ----------------------------------------------------------
    function refilterLists(keepSel) {
        const q = query.trim();
        const out = [];
        const pos = [];
        if (lOpen === "") {
            let exact = false;
            for (const l of MusicLists.lists) {
                if (q !== "" && l.name.toLowerCase() === q.toLowerCase())
                    exact = true;
                if (q !== "" && Fuzzy.score(l.name, q) < 0)
                    continue;
                pos.push(out.length);
                out.push({
                    "key": "l:" + l.name,
                    "kind": "list",
                    "name": l.name,
                    "count": l.count,
                    "path": "",
                    "title": l.name,
                    "artist": "",
                    "album": "",
                    "group": "",
                    "cover": ""
                });
            }
            // A name that matches nothing can be made into a list
            if (q !== "" && !exact) {
                pos.push(out.length);
                out.push({
                    "key": "new:" + q,
                    "kind": "new",
                    "name": q,
                    "count": 0,
                    "path": "",
                    "title": "New playlist  “" + q + "”",
                    "artist": "",
                    "album": "",
                    "group": "",
                    "cover": ""
                });
            }
        } else {
            for (let i = 0; i < lTracks.length; i++) {
                const t = lTracks[i];
                if (q !== "" && Fuzzy.score(t.artist + " " + t.album + " " + t.title, q) < 0)
                    continue;
                pos.push(out.length);
                out.push({
                    "key": "t" + i + ":" + t.path,
                    "kind": "song",
                    "path": t.path,
                    "title": t.title,
                    "artist": t.artist,
                    "album": t.album,
                    "duration": t.duration,
                    "cover": t.cover,
                    "group": Music.isRemote(t.path) ? "" : groupOf(t)
                });
            }
        }
        animateView = false;
        lItems = out;
        lPos = pos;
        // With nothing matching, the "new playlist" entry is the one to land on
        lsel = keepSel ? clamp(lsel, 0, Math.max(0, out.length - 1)) : 0;
        animateView = true;
        Qt.callLater(scrollToSel);
        coverTimer.restart();
    }

    function listFetchThen(name, action) {
        listSeq++;
        listTag = {
            "seq": listSeq,
            "action": action,
            "name": name
        };
        MusicLists.fetch(name, listSeq);
    }

    function onListFetched(tag, name, entries) {
        const t = listTag;
        if (t === null || t.seq !== tag)
            return;
        listTag = null;
        if (t.action === "reopen") {
            if (lOpen === name) {
                lTracks = entries;
                refilterLists(true);
            }
            return;
        }
        if (entries.length === 0) {
            say(name + " is empty");
            return;
        }
        if (t.action === "play") {
            Music.playEntries(entries, 0);
            say("Playing " + name + "  ·  " + songsWord(entries.length));
            watchPlay();
        } else if (t.action === "queue") {
            Music.enqueueEntries(entries);
            say("Added " + songsWord(entries.length) + " to the end of the queue");
        } else if (t.action === "next") {
            playNextEntries(entries);
        } else if (t.action === "open") {
            lBackSel = lsel;
            lOpen = name;
            lTracks = entries;
            search.clear();
            refilterLists(false);
        } else if (t.action === "pick") {
            startPick(entries);
        } else if (t.action === "download") {
            downloadEntries(entries);
        }
    }

    function onListWritten(name) {
        if (lOpen === name)
            listFetchThen(name, "reopen");
    }

    // Enter on a list: play it; on its songs: play from here on
    function activateList() {
        const c = curItem;
        if (pickFor.length > 0) {
            pickList(c);
            return;
        }
        if (c.kind === "new") {
            MusicLists.create(c.name);
            say("Created  ·  " + c.name);
            search.clear();
        } else if (c.kind === "list") {
            listFetchThen(c.name, "play");
        } else {
            const list = [];
            for (let k = selIdx; k < lItems.length; k++)
                list.push(entryOf(lItems[k]));
            Music.playEntries(list, 0);
            say("Playing " + songsWord(list.length));
            watchPlay();
        }
    }

    // ---- Picking a playlist to add songs to -------------------------------
    // The Lists tab with a different Enter: it adds, rather than plays. A
    // name typed there that matches nothing makes a new list.
    function startPick(entries) {
        if (entries.length === 0 || pickFor.length > 0)
            return;
        pickFor = entries;
        pickBack = tab;
        pickQuery = query;
        lOpen = "";
        lTracks = [];
        autoTracks = false;
        search.clear();
        setTab(4);
        refilterLists(false);
        say("Add " + songsWord(entries.length) + " to…", 4000);
    }

    function endPick() {
        const back = pickBack;
        const q = pickQuery;
        pickFor = [];
        pickQuery = "";
        search.text = q;
        setTab(back);
    }

    function cancelPick() {
        if (pickFor.length === 0)
            return;
        endPick();
        say("Cancelled");
    }

    function pickList(c) {
        if (c.kind !== "list" && c.kind !== "new")
            return;
        const cnt = pickFor.length;
        MusicLists.add(c.name, pickFor);
        endPick();
        say("Added " + songsWord(cnt) + " to " + c.name);
    }

    // Ctrl+A
    function pickSel() {
        const c = curItem;
        if (pickFor.length > 0)
            return;
        if (c !== null && tab === 0) {
            const list = [];
            for (let k = 0; k < libItems.length; k++) {
                if (libItems[k].group === c.group)
                    list.push(entryOf(libItems[k]));
            }
            startPick(list);
        } else if (c !== null && tab === 3 && c.kind !== "song") {
            fetchThen(c, "pick");
        } else if (c !== null && tab === 4 && lOpen === "" && c.kind === "list") {
            listFetchThen(c.name, "pick");
        } else {
            const e = likeTarget();
            if (e === null)
                say("Nothing to add");
            else
                startPick([e]);
        }
    }

    // ---- Likes ------------------------------------------------------------
    function playingEntry() {
        if (!Music.hasTrack)
            return null;
        const t = Music.lookup(Music.path);
        return {
            "path": Music.path,
            "title": Music.title || (t ? t.title : ""),
            "artist": Music.artist || (t ? t.artist : ""),
            "album": Music.album || (t ? t.album : ""),
            "duration": Music.duration || 0,
            "cover": Music.isRemote(Music.path) ? Music.cover : ""
        };
    }

    // The highlighted song when the dial is on songs, otherwise what plays
    function likeTarget() {
        const c = curItem;
        const onSongs = tab === 1 || tab === 2 || (tab === 3 && c !== null && c.kind === "song") || (tab === 4 && lOpen !== "");
        if (c !== null && onSongs && c.path)
            return entryOf(c);
        return playingEntry();
    }

    function likeSel() {
        const e = likeTarget();
        if (e === null) {
            say("Nothing to like");
            return;
        }
        say(MusicLists.toggleLike(e) ? "Added to Liked Songs" : "Removed from Liked Songs");
    }

    function likePlaying() {
        const e = playingEntry();
        if (e === null)
            return;
        say(MusicLists.toggleLike(e) ? "Added to Liked Songs" : "Removed from Liked Songs");
    }

    // ---- Downloads --------------------------------------------------------
    function downloadEntries(entries) {
        let c = 0;
        for (const e of entries) {
            if (Music.isRemote(e.path) && !Music.downloaded(e.path) && Music.download(e.path, "track", e.title))
                c++;
        }
        say(c > 0 ? "Downloading " + songsWord(c) : "Nothing new to download");
    }

    function downloadCollection(item, playlist) {
        const ok = Music.download(playlist || ("browse:" + item.id), "album", item.title);
        say(ok ? "Downloading  ·  " + item.title : "Already in the queue");
    }

    // Ctrl+D. `all`: the whole album you are inside, not the highlighted song
    function downloadSel(all) {
        const c = curItem;
        if (c === null)
            return;
        if (tab === 4 && lOpen === "") {
            if (c.kind === "list")
                listFetchThen(c.name, "download");
            return;
        }
        if (c.kind === "song") {
            if (all && tab === 3 && oOpened !== null) {
                downloadCollection(oOpened.item, oOpened.playlist);
                return;
            }
            if (!Music.isRemote(c.path))
                say("Already on this computer");
            else if (Music.downloaded(c.path))
                say("Already downloaded");
            else
                say(Music.download(c.path, "track", c.title) ? "Downloading  ·  " + c.title : "Already in the queue");
        } else if (c.kind === "album" || c.kind === "playlist") {
            downloadCollection(c, c.playlist);
        } else if (c.kind === "artist") {
            fetchThen(c, "download");
        }
    }

    function ctrlD(all) {
        if (tab === 2)
            removeSel();
        else if (tab === 3 || tab === 4)
            downloadSel(all);
    }

    function downloadPlaying() {
        if (!Music.hasTrack || !Music.isRemote(Music.path) || Music.downloaded(Music.path))
            return;
        say(Music.download(Music.path, "track", Music.title) ? "Downloading  ·  " + Music.title : "Already in the queue");
    }

    // ---- Words for the middle of the stage ---------------------------------
    function lineOne() {
        if (note !== "")
            return note;
        if (Music.dlActive)
            return "Downloading " + Music.dlCount + "  ·  " + Math.round(Music.dlPct) + "%";
        if (curItem === null)
            return "";
        let word = "";
        if (curPlaying)
            word = "Now playing";
        else if (tab === 3)
            word = oOpened !== null ? oOpened.title : kindWord(curItem.kind);
        else if (tab === 4)
            word = lOpen !== "" ? lOpen : kindWord(curItem.kind);
        else
            word = ["Album", "Track", "Queue"][tab];
        return word + "  ·  " + (selIdx + 1) + " / " + n + (tab === 3 && oOpened === null && MusicNet.more ? "+" : "");
    }

    function emptyTitle() {
        if (tab === 3) {
            if (oOpened !== null)
                return query.trim() !== "" ? "No match" : "Nothing here";
            if (query.trim() === "")
                return "Search YouTube Music";
            if (MusicNet.busy)
                return "Searching";
            return MusicNet.error !== "" ? "Search failed" : "No results";
        }
        if (tab === 4)
            return query.trim() !== "" ? "No match" : (lOpen !== "" ? "Nothing in " + lOpen : "No playlists yet");
        if (query.trim() !== "")
            return "No match";
        if (tab === 2)
            return "The queue is empty";
        return Music.scanning || !Music.scanned ? "Reading your music" : "No music found";
    }

    function emptySub() {
        if (tab === 3) {
            if (oOpened !== null || query.trim() !== "")
                return MusicNet.error !== "" && oOpened === null ? MusicNet.error : "";
            return "";
        }
        if (tab === 4)
            return "";
        if (query.trim() !== "" || tab === 2)
            return "";
        return Music.scanning || !Music.scanned ? "This takes a moment the first time" : "Nothing in " + Config.musicDir;
    }

    function subLine(c) {
        if (tab === 0)
            return (c.artist !== "" ? c.artist + "  ·  " : "") + c.count + (c.count === 1 ? " song" : " songs");
        if (c.kind === "list")
            return songsWord(c.count);
        if (c.kind === "new")
            return "";
        if (c.kind === "album")
            return [c.artist, c.type !== "Album" ? c.type : "", c.year].filter(x => x).join("  ·  ");
        if (c.kind === "playlist")
            return [c.artist, c.count ? c.count + " songs" : ""].filter(x => x).join("  ·  ");
        if (c.kind === "artist")
            return "Artist";
        if (c.kind === "recent")
            return "Recent search";
        const base = c.artist !== "" && c.album !== "" ? c.artist + "  ·  " + c.album : (c.artist || c.album);
        // A heart for the ones you like, and a note on streamed songs you have kept
        const marks = (c.path && MusicLists.isLiked(c.path) ? "  ·  \u2665" : "") + (c.path && Music.isRemote(c.path) && Music.downloaded(c.path) ? "  ·  downloaded" : "");
        return base + marks;
    }

    function placeholderText() {
        if (tab === 2)
            return "Filter the queue";
        if (tab === 3)
            return oOpened !== null ? "Filter  ·  " + oOpened.title : (MusicNet.kind === "top" ? "Search YouTube Music" : "Search " + MusicNet.kindLabel.toLowerCase() + " on YouTube Music");
        if (tab === 4)
            return pickFor.length > 0 ? "Type a new name, or pick a playlist" : (lOpen !== "" ? "Filter  ·  " + lOpen : "Filter, or type a new name");
        return "Search songs, albums, artists";
    }

    function badgeText() {
        if (query.trim() === "")
            return "";
        if (tab === 3 && oOpened === null)
            return MusicNet.busy ? "" : String(n) + (MusicNet.more ? "+" : "");
        return String(n);
    }

    // ---- Moving ---------------------------------------------------------
    function setSel(i) {
        if (n === 0)
            return;
        const v = clamp(i, 0, n - 1);
        if (tab === 0)
            asel = v;
        else if (tab === 1)
            sel = v;
        else if (tab === 2)
            qsel = v;
        else if (tab === 3) {
            osel = v;
            // Near the end of the results: fetch the next page
            if (oOpened === null && n - v <= 8)
                MusicNet.loadMore();
        } else
            lsel = v;
    }

    function move(delta) {
        if (lyricsOn) {
            if (!Music.lyricSynced)
                lyricScroll = clamp(lyricScroll + delta, 0, Math.max(0, Music.lyricLines.length - 1));
            else
                nudgeLyrics(delta);
            return;
        }
        setSel(selIdx + delta);
    }

    // In synced lyrics, the arrows move the timing: right or down = later, left
    // or up = earlier, a quarter second a press, remembered for the song
    function nudgeLyrics(delta) {
        const off = Music.nudgeLyrics(-0.25 * (delta > 0 ? 1 : -1));
        say(off === 0 ? "Lyrics in time" : "Lyrics " + Math.abs(off).toFixed(2) + " s " + (off > 0 ? "earlier" : "later"), 2500);
    }

    function toggleLyrics() {
        if (lyricsOn) {
            lyricsOn = false;
            return;
        }
        if (!Music.hasTrack) {
            say("Nothing playing");
            return;
        }
        lyricScroll = 0;
        lyricsOn = true;
    }

    // Tracks: to the start of the next album, or of this one (and then the
    // one before). Albums and queue: five at a time.
    function jumpAlbum(dir) {
        if (n === 0)
            return;
        if (tab !== 1) {
            move(dir * 5);
            return;
        }
        const grp = items[selIdx].group;
        let i = selIdx;
        if (dir > 0) {
            while (i < n && items[i].group === grp)
                i++;
            setSel(Math.min(i, n - 1));
        } else {
            while (i > 0 && items[i - 1].group === grp)
                i--;
            if (i === selIdx && i > 0) {
                const before = items[i - 1].group;
                while (i > 0 && items[i - 1].group === before)
                    i--;
            }
            setSel(i);
        }
    }

    function jumpToPlaying() {
        for (let i = 0; i < n; i++) {
            if (isPlaying(items[i])) {
                setSel(i);
                return;
            }
        }
        say("Nothing playing here");
    }

    // Switching keeps your place: from an album to its first song, and from a
    // song back to its album
    function setTab(i) {
        if (tab === i)
            return;
        // Leaving the playlist picker any other way is cancelling it
        if (pickFor.length > 0 && i !== 4) {
            cancelPick();
            return;
        }
        lyricsOn = false;
        autoTracks = false;
        clearArmed = false;
        const c = curItem;
        animateView = false;
        if (c !== null && tab === 0 && i === 1) {
            sel = clamp(c.first, 0, Math.max(0, libItems.length - 1));
        } else if (c !== null && tab === 1 && i === 0) {
            for (let k = 0; k < albItems.length; k++) {
                if (albItems[k].group === c.group) {
                    asel = k;
                    break;
                }
            }
        }
        tab = i;
        if (i === 2) {
            Music.requestQueue();
            refilterQueue(true);
        } else if (i === 3) {
            if (oOpened === null)
                MusicNet.setQuery(query);
            refilterOnline(true);
        } else if (i === 4) {
            MusicLists.refresh();
            refilterLists(true);
        }
        animateView = true;
        Qt.callLater(scrollToSel);
    }

    // ---- Doing ----------------------------------------------------------
    function togglePlay() {
        if (Music.hasTrack)
            Music.playPause();
        else if (Music.resumable && query.trim() === "") {
            Music.resume();
            say("Resuming  ·  " + Music.resumeTitle, 3000);
            watchPlay();
        } else
            activate();
    }

    // Enter. Albums: the album. Tracks: this song and what follows it.
    // Online: stream it. Lists: play the list.
    function activate() {
        if (curItem === null)
            return;
        if (tab === 0)
            playGroup(curItem.group);
        else if (tab === 1)
            playFrom(selIdx);
        else if (tab === 2) {
            Music.jumpTo(curItem.idx);
            watchPlay();
        } else if (tab === 3)
            activateOnline();
        else
            activateList();
    }

    // Ctrl+Enter, the other one. Albums: from this album on. Tracks: its album.
    // Online and Lists: open it.
    function activateAlt() {
        if (curItem === null)
            return;
        if (tab === 0)
            playAlbumsFrom(selIdx);
        else if (tab === 1)
            playGroup(curItem.group);
        else if (tab === 3) {
            if (curItem.kind === "song")
                activateOnline();
            else
                fetchThen(curItem, "open");
        } else if (tab === 4 && lOpen === "" && curItem.kind === "list" && pickFor.length === 0)
            listFetchThen(curItem.name, "open");
    }

    function enqueueSel() {
        if (curItem === null || tab === 2)
            return;
        if (tab === 3 || tab === 4) {
            if (curItem.kind === "song") {
                Music.enqueueEntries([entryOf(curItem)]);
                say("Added to the end of the queue");
            } else if (tab === 3)
                fetchThen(curItem, "queue");
            else if (curItem.kind === "list")
                listFetchThen(curItem.name, "queue");
            return;
        }
        if (tab === 1) {
            Music.enqueue(curItem.path);
            say("Added to the end of the queue");
        } else {
            const g = groupPaths[curItem.group] || [];
            g.forEach(p => Music.enqueue(p));
            say("Added " + g.length + (g.length === 1 ? " song" : " songs") + " to the end of the queue");
        }
        Music.requestQueue();
    }

    // ---- Play next, and moving things around in the queue ----------------------
    function nextNote(entries, queued) {
        if (!queued)
            say("Playing");
        else
            say(entries.length === 1 ? "Playing next" : "Playing next  ·  " + songsWord(entries.length));
    }

    function playNextEntries(entries) {
        nextNote(entries, Music.playNext(entries));
        watchPlay();
    }

    // Alt+Enter: the highlighted song, album or list goes right after the one playing
    function playNextSel() {
        const c = curItem;
        if (c === null)
            return;
        if (tab === 0) {
            playNextEntries(libItems.filter(t => t.group === c.group).map(entryOf));
        } else if (tab === 2) {
            // An entry of the queue: move it to just after the current one
            const cur = Music.currentIndex();
            if (query.trim() !== "")
                say("Clear the search first");
            else if (cur < 0 || c.current)
                say(c.current ? "That one is playing" : "Nothing is playing");
            else {
                Music.moveInQueue(c.idx, cur + 1);
                say("Playing next");
                qsel = clamp(c.idx < cur ? cur : cur + 1, 0, Math.max(0, Music.queue.length - 1));
            }
        } else if (c.kind === "album" || c.kind === "playlist" || c.kind === "artist") {
            fetchThen(c, "next");
        } else if (c.kind === "list") {
            listFetchThen(c.name, "next");
        } else if (c.path) {
            playNextEntries([entryOf(c)]);
        }
    }

    // Alt+Up / Alt+Down in the queue: one place up or down
    function moveEntry(dir) {
        if (tab !== 2 || curItem === null)
            return;
        if (query.trim() !== "") {
            say("Clear the search first");
            return;
        }
        const i = curItem.idx;
        const j = i + dir;
        if (j < 0 || j >= Music.queue.length)
            return;
        Music.moveInQueue(i, dir > 0 ? i + 2 : i - 1);
        qsel = j;
    }

    // Ctrl+Z
    function undoRemove() {
        say(Music.undoRemove() ? "Put back" : "Nothing to put back");
    }

    // Remove the highlighted entry: from the queue (not the one playing), from
    // an open playlist, or a whole playlist (asks twice; Liked Songs stays)
    function removeSel() {
        if (curItem === null)
            return;
        // A recent search is forgotten
        if (tab === 3 && curItem.kind === "recent") {
            MusicNet.forget(curItem.title);
            say("Forgotten  ·  " + curItem.title);
            return;
        }
        if (tab === 4) {
            if (lOpen !== "") {
                MusicLists.removeTrack(lOpen, curItem.path);
                say("Removed from " + lOpen);
            } else if (curItem.kind === "list") {
                if (curItem.name === MusicLists.likedName) {
                    say("Liked Songs stays");
                } else if (!clearArmed) {
                    clearArmed = true;
                    clearTimer.restart();
                    say("Press again to delete  ·  " + curItem.name, 3000);
                } else {
                    clearArmed = false;
                    MusicLists.del(curItem.name);
                    say("Deleted  ·  " + curItem.name);
                }
            }
            return;
        }
        if (tab !== 2 || curItem.current)
            return;
        Music.removeFromQueue(curItem.idx);
        say("Removed from the queue", 5000);
    }

    function nudgeVolume(delta) {
        Music.setVolume(Music.volume + delta);
    }

    function open() {
        if (isOpen)
            return;
        targetScreen = Focus.screen;
        isOpen = true;
        closeAnim.stop();
        clearArmed = false;
        note = "";
        oOpened = null;
        lOpen = "";
        lTracks = [];
        pickFor = [];
        fetchTag = null;
        listTag = null;
        search.text = "";
        tab = 0;
        MusicNet.setQuery("");
        MusicLists.refresh();
        if (!Music.scanned)
            Music.scan();
        Music.requestQueue();
        seedCover();
        refilter("playing");
        refilterQueue(true);
        refilterOnline(false);
        refilterLists(false);
        // The bar's chip asked for the lyrics
        if (Music.lyricsViewRequest) {
            Music.lyricsViewRequest = false;
            if (Music.hasTrack) {
                lyricScroll = 0;
                lyricsOn = true;
            }
        }
        reveal = 0;
        openAnim.restart();
        search.forceActiveFocus();
        Qt.callLater(scrollToSel);
    }

    function close() {
        if (!isOpen)
            return;
        isOpen = false;
        lyricsOn = false;
        helpOn = false;
        Music.lyricsViewRequest = false;
        openAnim.stop();
        closeAnim.restart();
    }

    function toggle() {
        if (isOpen)
            close();
        else
            open();
    }

    // ---- Window ---------------------------------------------------------
    // Fullscreen and invisible, like the launcher: it only exists so a click
    // outside the dial can close the player.
    visible: isOpen || reveal > 0.001
    screen: targetScreen
    color: "transparent"
    exclusiveZone: 0
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "qs-music"
    WlrLayershell.keyboardFocus: isOpen ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    Connections {
        target: Music

        function onLibraryChanged() {
            panel.refilter("keep");
            panel.refilterQueue(false);
        }

        function onQueueChanged() {
            panel.refilterQueue(false);
        }

        // A new track: its cover is the album's
        function onPathChanged() {
            panel.seedCover();
        }

        function onCoverChanged() {
            panel.seedCover();
        }

        // mpv would not start or does not answer
        function onFailedChanged() {
            if (Music.failed)
                panel.say("mpv isn't answering. Is it installed?", 6000);
        }

        function onDownloadFinished(job) {
            panel.say("Downloaded  ·  " + job.title, 3500);
        }

        function onDownloadFailed(job, message) {
            panel.say("Download failed  ·  " + message, 7000);
        }
    }

    Connections {
        target: Music

        // A stream or a file that would not play. mpv's own words say why; when
        // the panel is closed the same goes to a notification.
        function onPlaybackFailed(message, remote) {
            const text = remote ? "Couldn't stream that  ·  " + message + "  ·  yt-dlp may be out of date" : "Couldn't play that  ·  " + message;
            if (panel.isOpen)
                panel.say(text, 7000);
            else
                Quickshell.execDetached(["notify-send", "-a", "Music", "-i", "audio-x-generic", "Couldn't play that", text]);
        }
    }

    Connections {
        target: MusicNet

        function onResultsChanged() {
            if (panel.oOpened === null)
                panel.refilterOnline(MusicNet.lastMore);
        }

        function onHistoryChanged() {
            if (panel.tab === 3 && panel.oOpened === null && panel.query.trim() === "")
                panel.refilterOnline(true);
        }

        function onTracksReady(id, data) {
            panel.onTracks(id, data);
        }

        function onTracksFailed(id, message) {
            panel.onTracksFailed(id, message);
        }
    }

    Connections {
        target: MusicLists

        function onListsChanged() {
            if (panel.lOpen === "")
                panel.refilterLists(true);
        }

        function onFetched(tag, name, entries) {
            panel.onListFetched(tag, name, entries);
        }

        function onWritten(name) {
            panel.onListWritten(name);
        }
    }

    Connections {
        target: Panels

        function onToggleMusic() {
            panel.toggle();
        }
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

        function playpause() {
            Music.playPause();
        }

        function next() {
            Music.next();
        }

        function prev() {
            Music.prev();
        }

        function stop() {
            Music.stop();
        }

        // Re-read ~/Music
        function rescan() {
            Music.scan();
        }

        // The ytm / ytal / ytms aliases: target is a URL, "ytsearch1:words"
        // or "browse:<album id>"; mode is track or album
        function download(target: string, mode: string): string {
            return Music.download(target, mode, target) ? "queued" : "skipped (already queued, or not something to download)";
        }

        // Pick up the last queue and position
        function resume() {
            Music.resume();
        }

        // Heart the song that is playing
        function like() {
            panel.likePlaying();
        }

        // Shuffle everything in the library
        function shuffleall() {
            panel.shuffleAll();
        }

        // Pause after this many minutes, fading out (0 = off)
        function sleep(minutes: int) {
            Music.setSleep(minutes);
        }

        // Show or hide the lyrics of the song that is playing
        function lyrics() {
            panel.toggleLyrics();
        }

        // Media keys: drive this player when it has a track, otherwise leave
        // the key to whatever else is playing (VLC, a browser) via playerctl
        function media(action: string) {
            if (!Music.hasTrack) {
                Quickshell.execDetached(["playerctl", action === "playpause" ? "play-pause" : (action === "prev" ? "previous" : action)]);
                return;
            }
            if (action === "playpause")
                Music.playPause();
            else if (action === "next")
                Music.next();
            else if (action === "prev")
                Music.prev();
        }

        target: "music"
    }

    PanelLink {
        win: panel
        name: "music"
    }

    Timer {
        id: clearTimer

        interval: 3000
        onTriggered: panel.clearArmed = false
    }

    Timer {
        id: noteTimer

        interval: 2200
        onTriggered: panel.note = ""
    }

    // Something was asked to play: if nothing is playing a moment later, say so
    Timer {
        id: playCheck

        interval: 3500
        onTriggered: {
            if (!Music.hasTrack)
                panel.say(Music.online ? "Nothing started playing" : "mpv isn't answering. Is it installed?", 6000);
        }
    }

    // Covers are looked for a moment after the cursor settles, not on every
    // step of a fast scroll
    Timer {
        id: coverTimer

        interval: 140
        onTriggered: panel.ensureCovers()
    }

    // After letting go of the waveform, keep showing where it was dragged to
    // until mpv's own position has caught up
    Timer {
        id: seekHold

        interval: 450
        onTriggered: panel.seeking = false
    }

    Process {
        id: coverProc

        stdout: StdioCollector {
            onStreamFinished: {
                const p = text.trim();
                panel.setCover(panel.coverBusy, p !== "" ? "file://" + p : "");
                panel.coverBusy = "";
                panel.pumpCovers();
            }
        }
    }

    // Arrives with a short rise and a fade, leaves the same way back
    NumberAnimation {
        id: openAnim

        target: panel
        property: "reveal"
        from: 0
        to: 1
        duration: Style.enterMs
        easing.type: Style.easeEnter
    }

    NumberAnimation {
        id: closeAnim

        target: panel
        property: "reveal"
        to: 0
        duration: Style.moveMs
        easing.type: Style.easeExit
    }

    // Slow breath for the playing node
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

    // ---- Small pieces ---------------------------------------------------
    // Three bars that dance while the music plays
    component Eq: Item {
        id: eq

        property bool active: false
        property color color: Colors.accent

        implicitWidth: 12
        implicitHeight: 12

        Row {
            anchors.bottom: parent.bottom
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 2

            Repeater {
                model: 3

                delegate: Rectangle {
                    id: bar

                    required property int index

                    property real h: 4

                    width: 2.5
                    height: eq.active ? h : 3
                    radius: 1
                    color: eq.color

                    SequentialAnimation on h {
                        running: eq.active && eq.visible
                        loops: Animation.Infinite

                        NumberAnimation {
                            to: 12
                            duration: 360 + bar.index * 110
                            easing.type: Style.easeAmbient
                        }
                        NumberAnimation {
                            to: 3
                            duration: 360 + bar.index * 110
                            easing.type: Style.easeAmbient
                        }
                    }
                }
            }
        }
    }

    // An album cover (or its letter) in a squircle
    component Art: Item {
        id: art

        property string source: ""
        property string letter: ""
        property real corner: width * 0.3

        ClippingRectangle {
            anchors.fill: parent
            radius: art.corner
            color: "transparent"

            Image {
                anchors.fill: parent
                source: art.source
                sourceSize.width: 160
                sourceSize.height: 160
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                opacity: status === Image.Ready ? 1 : 0

                Behavior on opacity {
                    NumberAnimation {
                        duration: Style.baseMs
                    }
                }
            }
        }

        Txt {
            anchors.centerIn: parent
            visible: art.source === ""
            text: art.letter
            color: Colors.muted
            font.pixelSize: art.width * 0.4
            font.bold: true
        }
    }

    // Download: the arrow, a ring that fills while it works, a check when done
    component DlButton: Item {
        id: dl

        property real progress: 0
        property bool busy: false
        property bool done: false
        readonly property bool hovered: dlHover.hovered

        signal clicked

        implicitWidth: 28
        implicitHeight: 28
        opacity: done || busy || hovered ? 1 : 0.9

        Rectangle {
            anchors.fill: parent
            radius: width / 2
            antialiasing: true
            color: dl.done ? Qt.alpha(Colors.accent, 0.2) : (dl.hovered ? Style.hoverFill : "transparent")

            Behavior on color {
                ColorAnimation {
                    duration: Style.baseMs
                }
            }
        }

        Shape {
            anchors.fill: parent
            visible: dl.busy
            layer.enabled: true
            layer.samples: 4

            ShapePath {
                strokeColor: Qt.alpha(Colors.foreground, 0.16)
                strokeWidth: 2
                fillColor: "transparent"

                PathAngleArc {
                    centerX: dl.width / 2
                    centerY: dl.height / 2
                    radiusX: 11
                    radiusY: 11
                    startAngle: 0
                    sweepAngle: 359.9
                }
            }

            ShapePath {
                strokeColor: Colors.accent
                strokeWidth: 2
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap

                PathAngleArc {
                    centerX: dl.width / 2
                    centerY: dl.height / 2
                    radiusX: 11
                    radiusY: 11
                    startAngle: -90
                    sweepAngle: Math.max(14, 359 * dl.progress)
                }
            }
        }

        Txt {
            anchors.centerIn: parent
            text: dl.done ? Icons.check : Icons.download
            color: dl.done || dl.busy ? Colors.accent : (dl.hovered ? Colors.foreground : Colors.muted)
            font.pixelSize: dl.busy ? 11 : 14
        }

        HoverHandler {
            id: dlHover

            cursorShape: dl.done || dl.busy ? Qt.ArrowCursor : Qt.PointingHandCursor
        }

        TapHandler {
            onTapped: if (!dl.done && !dl.busy)
                dl.clicked()
        }
    }

    // A quiet text button: muted until hovered, accent while `on`
    component Link: Item {
        id: lk

        property string text: ""
        property bool on: false
        property bool armed: false

        signal clicked

        implicitWidth: lkText.implicitWidth + 14
        implicitHeight: 24

        Rectangle {
            anchors.fill: parent
            radius: Style.radiusSm
            color: lkHover.hovered ? Style.well : "transparent"

            Behavior on color {
                ColorAnimation {
                    duration: Style.fadeMs
                }
            }
        }

        Txt {
            id: lkText

            anchors.centerIn: parent
            text: lk.text
            color: lk.armed ? Colors.critical : (lk.on ? Colors.accent : (lkHover.hovered ? Colors.foreground : Colors.muted))
            font.pixelSize: Style.fontSm

            Behavior on color {
                ColorAnimation {
                    duration: Style.fadeMs
                }
            }
        }

        HoverHandler {
            id: lkHover

            cursorShape: Qt.PointingHandCursor
        }

        TapHandler {
            onTapped: lk.clicked()
        }
    }

    // A row button: the icon button, and while the pointer is on it the foot says what it does
    component Act: IconButton {
        size: 28
        glyphSize: 14
        onHoveredChanged: panel.tipNow = hovered ? tip : (panel.tipNow === tip ? "" : panel.tipNow)
        Component.onDestruction: if (panel.tipNow === tip)
            panel.tipNow = ""
    }

    // The song as bars: their height is how loud it is. Played ones are lit,
    // the head stands taller, and the bars near the pointer rise a little.
    // Without peaks (a stream, or no ffmpeg) it is a plain ruler.
    component Wave: Item {
        id: wv

        property var peaks: []
        property real frac: 0
        // 0..1 under the pointer, or -1
        property real aim: -1
        readonly property int count: Math.max(8, Math.floor(width / 5))
        readonly property real slot: width / count

        Repeater {
            model: wv.count

            delegate: Rectangle {
                id: bar

                required property int index

                readonly property real t: (index + 0.5) / wv.count
                readonly property real pk: wv.peaks.length > 7 ? wv.peaks[Math.min(wv.peaks.length - 1, Math.floor(t * wv.peaks.length))] : (index % 4 === 0 ? 0.42 : 0.22)
                readonly property real near: wv.aim >= 0 ? Math.max(0, 1 - Math.abs(t - wv.aim) * wv.count / 6) : 0

                x: index * wv.slot + (wv.slot - width) / 2
                anchors.verticalCenter: parent.verticalCenter
                width: 2
                height: Math.min(wv.height, 4 + pk * (wv.height - 4) + 4 * near)
                radius: 1
                antialiasing: true
                color: t <= wv.frac ? Qt.alpha(Colors.accent, 0.75) : Qt.alpha(Colors.foreground, 0.17 + 0.3 * near)

                Behavior on height {
                    NumberAnimation {
                        duration: Style.fadeMs
                    }
                }
            }
        }

        // A soft halo and the head
        Rectangle {
            x: wv.frac * wv.width - 4
            anchors.verticalCenter: parent.verticalCenter
            width: 8
            height: wv.height + 12
            radius: 4
            color: Qt.alpha(Colors.accent, 0.16)
        }

        Rectangle {
            x: wv.frac * wv.width - 1
            anchors.verticalCenter: parent.verticalCenter
            width: 2
            height: wv.height + 8
            radius: 1
            color: Colors.accent
        }
    }

    // ---- The stage --------------------------------------------------------
    // Click outside the card to close
    MouseArea {
        anchors.fill: parent
        onClicked: panel.close()
    }

    // The shared dim (Dim.qml): the same wash as the screenshot tool
    Dim {
        reveal: panel.reveal
    }

    Item {
        id: stage

        width: panel.stageW
        height: panel.stageH
        anchors.horizontalCenter: parent.horizontalCenter
        y: (parent.height - height) / 2 + (1 - panel.reveal) * 28
        opacity: Math.min(1, panel.reveal * 2.2)
        scale: 0.985 + 0.015 * panel.reveal

        ClippingRectangle {
            id: card

            anchors.fill: parent
            radius: 24
            color: Style.card
            border.width: 1
            border.color: Style.outline

            // Keeps a click on the card from reaching the "outside" area
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.AllButtons
                onClicked: search.forceActiveFocus()
            }

            // The record behind the cover: a little of it shows past the edge
            // while music plays, turning slowly
            Item {
                id: disc

                x: panel.leftW - 164
                y: 56
                width: 220
                height: 220
                opacity: Music.hasTrack && !panel.lyricsOn ? 0.45 : 0

                Behavior on opacity {
                    NumberAnimation {
                        duration: Style.moveMs
                    }
                }

                RotationAnimator on rotation {
                    from: 0
                    to: 360
                    duration: 14000
                    loops: Animation.Infinite
                    running: Music.playing && panel.isOpen && !panel.lyricsOn
                }

                Rectangle {
                    anchors.fill: parent
                    radius: width / 2
                    antialiasing: true
                    color: Style.vinyl
                    border.width: 1
                    border.color: Qt.alpha(Colors.foreground, 0.1)
                }

                Repeater {
                    model: [92, 72, 54]

                    delegate: Rectangle {
                        required property int modelData

                        anchors.centerIn: parent
                        width: modelData * 2
                        height: width
                        radius: width / 2
                        color: "transparent"
                        border.width: 1
                        border.color: Qt.alpha(Style.vinylLight, 0.06)
                    }
                }

                Rectangle {
                    anchors.centerIn: parent
                    width: 42
                    height: width
                    radius: width / 2
                    color: Qt.alpha(Colors.accent, 0.6)
                }

                // The notch that shows it turning
                Rectangle {
                    x: parent.width / 2 - 1.5
                    y: 14
                    width: 3
                    height: 14
                    radius: 1.5
                    color: Qt.alpha(Style.vinylLight, 0.22)
                }
            }

            // ---- Left: what is playing --------------------------------------
            Item {
                id: leftPane

                width: panel.leftW
                height: parent.height

                // The cover, edge to edge, with the title over its foot
                Item {
                    id: banner

                    width: parent.width
                    height: panel.lyricsOn ? panel.bannerSlim : panel.bannerTall
                    clip: true

                    Behavior on height {
                        NumberAnimation {
                            duration: Style.moveMs
                            easing.type: Style.easeMove
                        }
                    }

                    Rectangle {
                        anchors.fill: parent
                        color: Qt.tint(Style.card, Qt.alpha(Colors.accent, 0.1))
                    }

                    Txt {
                        anchors.centerIn: parent
                        anchors.verticalCenterOffset: -30
                        visible: !bannerArt.ready
                        text: Music.hasTrack ? (Music.album || Music.title || "?").charAt(0).toUpperCase() : ""
                        color: Qt.alpha(Colors.foreground, 0.3)
                        font.pixelSize: 110
                        font.weight: Font.Light
                    }

                    Image {
                        id: bannerArt

                        readonly property bool ready: status === Image.Ready

                        anchors.fill: parent
                        source: Music.hasTrack ? Music.cover : ""
                        sourceSize.width: 700
                        sourceSize.height: 700
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        opacity: ready ? 1 : 0

                        Behavior on opacity {
                            NumberAnimation {
                                duration: Style.moveMs
                            }
                        }
                    }

                    // Fades into the card, so the words are always readable
                    Rectangle {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        height: Math.min(parent.height, 210)

                        gradient: Gradient {
                            GradientStop {
                                position: 0
                                color: Qt.alpha(Style.card, 0)
                            }
                            GradientStop {
                                position: 0.6
                                color: Qt.alpha(Style.card, 0.8)
                            }
                            GradientStop {
                                position: 1
                                color: Style.card
                            }
                        }
                    }

                    // Click the cover to play or pause
                    TapHandler {
                        onTapped: {
                            panel.togglePlay();
                            search.forceActiveFocus();
                        }
                    }

                    Row {
                        id: bannerBtns

                        anchors.right: parent.right
                        anchors.rightMargin: panel.pad - 6
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: panel.lyricsOn ? 12 : 16
                        spacing: 0
                        visible: Music.hasTrack

                        Act {
                            glyph: "≡"
                            tip: panel.lyricsOn ? "Close the lyrics" : "Lyrics"
                            on: panel.lyricsOn
                            glyphSize: 18
                            onClicked: {
                                panel.toggleLyrics();
                                search.forceActiveFocus();
                            }
                        }

                        Act {
                            glyph: panel.playingLiked ? Icons.heart : Icons.heartOutline
                            tip: panel.playingLiked ? "Unlike" : "Like"
                            on: panel.playingLiked
                            glyphSize: 15
                            onClicked: {
                                panel.likePlaying();
                                search.forceActiveFocus();
                            }
                        }

                        DlButton {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: Music.isRemote(Music.path)
                            busy: panel.playingJob !== null
                            progress: panel.playingJob !== null ? panel.playingJob.pct / 100 : 0
                            done: Music.downloaded(Music.path)
                            onClicked: {
                                panel.downloadPlaying();
                                search.forceActiveFocus();
                            }
                        }
                    }

                    Column {
                        anchors.left: parent.left
                        anchors.leftMargin: panel.pad
                        anchors.right: bannerBtns.left
                        anchors.rightMargin: 8
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: panel.lyricsOn ? 12 : 18
                        spacing: 4

                        Txt {
                            width: parent.width
                            visible: !panel.lyricsOn
                            elide: Text.ElideRight
                            text: Music.hasTrack ? (panel.note !== "" ? panel.note : (Music.dlActive ? "downloading " + Music.dlCount + "  ·  " + Math.round(Music.dlPct) + "%" : (Music.playing ? "now playing" : "paused"))) : (Music.resumable ? "pick up where you left off" : "nothing playing")
                            color: Colors.accent
                            font.pixelSize: Style.fontSm
                        }

                        Txt {
                            width: parent.width
                            elide: Text.ElideRight
                            text: Music.hasTrack ? (Music.title || "Unknown") : (Music.resumable ? Music.resumeTitle : "Pick something and press Enter")
                            color: Music.hasTrack || Music.resumable ? Colors.foreground : Colors.muted
                            font.pixelSize: panel.lyricsOn ? Style.fontBase : 22
                            font.weight: Font.Medium
                            font.letterSpacing: panel.lyricsOn ? 0 : -0.4
                        }

                        Txt {
                            width: parent.width
                            elide: Text.ElideRight
                            text: Music.hasTrack ? (Music.artist !== "" && Music.album !== "" ? Music.artist + "  ·  " + Music.album : (Music.artist || Music.album)) : ""
                            visible: text !== ""
                            color: Qt.alpha(Colors.foreground, 0.65)
                            font.pixelSize: panel.lyricsOn ? Style.fontSm : Style.fontMd
                        }
                    }
                }

                // ---- Lyrics, under the slim banner --------------------------
                Item {
                    id: lyricsView

                    readonly property real lineH: 34
                    // Synced: the line being sung. Plain: where the wheel has scrolled to.
                    readonly property real focusIdx: Music.lyricSynced ? Math.max(0, Music.lyricIndex) : panel.lyricScroll

                    anchors.top: banner.bottom
                    anchors.bottom: lower.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    visible: panel.lyricsMix > 0.01
                    opacity: panel.lyricsMix

                    Row {
                        id: lyricHead

                        x: panel.pad
                        y: 6
                        width: parent.width - panel.pad * 2
                        height: 20
                        spacing: 6

                        Txt {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "lyrics"
                            color: Colors.accent
                            font.pixelSize: Style.fontSm
                        }

                        Txt {
                            anchors.verticalCenter: parent.verticalCenter
                            text: Music.lyricLines.length === 0 ? "" : (Music.lyricSynced ? "·  synced  ·  ↑↓ timing" : "·  plain  ·  scroll")
                            color: Colors.muted
                            font.pixelSize: Style.fontSm
                        }
                    }

                    Item {
                        id: lyricClip

                        anchors.top: lyricHead.bottom
                        anchors.topMargin: 4
                        anchors.bottom: parent.bottom
                        anchors.left: parent.left
                        anchors.leftMargin: panel.pad
                        anchors.right: parent.right
                        anchors.rightMargin: panel.pad
                        clip: true

                        Column {
                            id: lyricCol

                            width: parent.width
                            y: lyricClip.height / 2 - (lyricsView.focusIdx + 0.5) * lyricsView.lineH

                            Behavior on y {
                                NumberAnimation {
                                    duration: 340
                                    easing.type: Easing.OutCubic
                                }
                            }

                            Repeater {
                                model: Music.lyricLines

                                delegate: Item {
                                    id: ln

                                    required property var modelData
                                    required property int index
                                    readonly property bool cur: Music.lyricSynced && index === Music.lyricIndex

                                    width: lyricCol.width
                                    height: lyricsView.lineH
                                    opacity: Math.max(0.12, 1 - Math.abs(index - lyricsView.focusIdx) * 0.28)

                                    Txt {
                                        anchors.fill: parent
                                        verticalAlignment: Text.AlignVCenter
                                        elide: Text.ElideRight
                                        fontSizeMode: Text.Fit
                                        minimumPixelSize: 11
                                        text: ln.modelData.text !== "" ? ln.modelData.text : "♪"
                                        color: ln.cur ? Colors.foreground : Colors.muted
                                        font.pixelSize: ln.cur ? Style.fontXl + 3 : Style.fontMd
                                        font.weight: ln.cur ? Font.Medium : Font.Normal

                                        Behavior on color {
                                            ColorAnimation {
                                                duration: Style.baseMs
                                            }
                                        }
                                    }

                                    // Click a line to jump to it
                                    TapHandler {
                                        enabled: Music.lyricSynced
                                        onTapped: Music.seekTo(ln.modelData.t)
                                    }
                                }
                            }
                        }

                        Txt {
                            anchors.centerIn: parent
                            width: parent.width
                            horizontalAlignment: Text.AlignHCenter
                            wrapMode: Text.WordWrap
                            visible: Music.lyricLines.length === 0
                            text: !Music.hasTrack ? "Nothing playing" : (Music.lyricState === "error" ? Music.lyricError : (Music.lyricState === "none" ? "No lyrics found for this song" : "Looking for lyrics…"))
                            color: Colors.muted
                            font.pixelSize: Style.fontMd
                        }
                    }

                    // The edges fade into the card
                    Rectangle {
                        anchors.top: lyricClip.top
                        anchors.left: parent.left
                        anchors.right: parent.right
                        height: 36

                        gradient: Gradient {
                            GradientStop {
                                position: 0
                                color: Style.card
                            }
                            GradientStop {
                                position: 1
                                color: Qt.alpha(Style.card, 0)
                            }
                        }
                    }

                    Rectangle {
                        anchors.bottom: parent.bottom
                        anchors.left: parent.left
                        anchors.right: parent.right
                        height: 36

                        gradient: Gradient {
                            GradientStop {
                                position: 0
                                color: Qt.alpha(Style.card, 0)
                            }
                            GradientStop {
                                position: 1
                                color: Style.card
                            }
                        }
                    }
                }

                // ---- Time, waveform, transport, volume ------------------------
                Item {
                    id: lower

                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: 212

                    // Scroll here for volume
                    MouseArea {
                        anchors.fill: parent
                        acceptedButtons: Qt.NoButton
                        onWheel: wheel => {
                            const d = wheel.angleDelta.y !== 0 ? wheel.angleDelta.y : wheel.angleDelta.x;
                            if (d !== 0)
                                panel.nudgeVolume(d > 0 ? 5 : -5);
                        }
                    }

                    // The time, big and light
                    Item {
                        id: timeRow

                        x: panel.pad
                        y: 4
                        width: parent.width - panel.pad * 2
                        height: 46

                        Txt {
                            id: bigTime

                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            text: Music.hasTrack ? Music.fmt(seekArea.aiming ? seekArea.aim * Music.duration : Music.position) : "0:00"
                            color: Music.hasTrack ? (seekArea.aiming ? Colors.accent : Colors.foreground) : Colors.muted
                            font.pixelSize: 44
                            font.weight: Font.Light
                            font.letterSpacing: -1.5
                        }

                        Txt {
                            anchors.right: parent.right
                            anchors.baseline: bigTime.baseline
                            visible: seekArea.can
                            text: "−" + Music.fmt(Math.max(0, Music.duration - Music.position)) + "  ·  " + Music.fmt(Music.duration)
                            color: Colors.muted
                            font.pixelSize: Style.fontSm
                        }
                    }

                    // The song
                    Item {
                        id: seekArea

                        readonly property bool can: Music.hasTrack && Music.duration > 0
                        readonly property bool aiming: seekMouse.pressed || (seekMouse.containsMouse && can)
                        readonly property real aim: panel.clamp(seekMouse.mouseX / Math.max(1, width), 0, 1)

                        x: panel.pad
                        y: timeRow.y + timeRow.height + 10
                        width: parent.width - panel.pad * 2
                        height: 34

                        Wave {
                            anchors.fill: parent
                            peaks: Music.peaks
                            frac: panel.seeking ? panel.seekFrac : Music.progress
                            aim: seekArea.aiming ? seekArea.aim : -1
                        }

                        MouseArea {
                            id: seekMouse

                            anchors.fill: parent
                            anchors.topMargin: -8
                            anchors.bottomMargin: -8
                            hoverEnabled: true
                            enabled: seekArea.can
                            cursorShape: Qt.PointingHandCursor
                            onPressed: mouse => {
                                panel.seeking = true;
                                seekHold.stop();
                                panel.seekFrac = panel.clamp(mouse.x / seekArea.width, 0, 1);
                                dragSeek.start();
                            }
                            onPositionChanged: mouse => {
                                if (pressed)
                                    panel.seekFrac = panel.clamp(mouse.x / seekArea.width, 0, 1);
                            }
                            onReleased: {
                                dragSeek.stop();
                                Music.seekTo(panel.seekFrac * Music.duration);
                                seekHold.restart();
                                search.forceActiveFocus();
                            }
                        }

                        // While dragging, the music follows the pointer
                        Timer {
                            id: dragSeek

                            interval: 140
                            repeat: true
                            onTriggered: Music.seekTo(panel.seekFrac * Music.duration)
                        }
                    }

                    // Transport
                    RowLayout {
                        id: transport

                        x: panel.pad - 4
                        y: seekArea.y + seekArea.height + 16
                        width: parent.width - panel.pad * 2 + 8
                        height: 48
                        spacing: 0

                        IconButton {
                            glyph: panel.g(0xF049F)
                            tip: "Shuffle"
                            on: Music.shuffle
                            size: 30
                            onClicked: {
                                Music.toggleShuffle();
                                search.forceActiveFocus();
                            }
                        }

                        Item {
                            Layout.fillWidth: true
                        }

                        IconButton {
                            glyph: panel.g(0xF04AE)
                            size: 36
                            glyphSize: 17
                            onClicked: {
                                Music.prev();
                                search.forceActiveFocus();
                            }
                        }

                        Item {
                            Layout.fillWidth: true
                        }

                        // Play and pause: the one solid control
                        Rectangle {
                            id: playBtn

                            Layout.preferredWidth: 48
                            Layout.preferredHeight: 48
                            radius: width / 2
                            antialiasing: true
                            color: Qt.alpha(Colors.foreground, playHover.hovered ? 1 : 0.92)
                            scale: playTap.pressed ? 0.94 : 1

                            Behavior on color {
                                ColorAnimation {
                                    duration: Style.baseMs
                                }
                            }
                            Behavior on scale {
                                NumberAnimation {
                                    duration: Style.pressMs
                                    easing.type: Style.easePress
                                }
                            }

                            Txt {
                                anchors.centerIn: parent
                                text: panel.g(Music.playing ? 0xF03E4 : 0xF040A)
                                color: Colors.background
                                font.pixelSize: 20
                            }

                            HoverHandler {
                                id: playHover

                                cursorShape: Qt.PointingHandCursor
                            }

                            TapHandler {
                                id: playTap

                                onTapped: {
                                    panel.togglePlay();
                                    search.forceActiveFocus();
                                }
                            }
                        }

                        Item {
                            Layout.fillWidth: true
                        }

                        IconButton {
                            glyph: panel.g(0xF04AD)
                            size: 36
                            glyphSize: 17
                            onClicked: {
                                Music.next();
                                search.forceActiveFocus();
                            }
                        }

                        Item {
                            Layout.fillWidth: true
                        }

                        IconButton {
                            glyph: panel.g(Music.repeat === "one" ? 0xF0458 : 0xF0456)
                            tip: "Repeat"
                            on: Music.repeat !== "off"
                            size: 30
                            onClicked: {
                                Music.cycleRepeat();
                                search.forceActiveFocus();
                            }
                        }
                    }

                    // Volume, and what comes next
                    Item {
                        x: panel.pad
                        y: transport.y + transport.height + 12
                        width: parent.width - panel.pad * 2
                        height: 24

                        IconButton {
                            id: muteBtn

                            anchors.left: parent.left
                            anchors.leftMargin: -4
                            anchors.verticalCenter: parent.verticalCenter
                            glyph: panel.g(Music.muted || Music.volume === 0 ? 0xF0581 : 0xF057E)
                            on: Music.muted
                            size: 24
                            glyphSize: 13
                            onClicked: {
                                Music.toggleMute();
                                search.forceActiveFocus();
                            }
                        }

                        // A hairline with a 2px mark; past 100% it turns red
                        Item {
                            id: vol

                            readonly property real shown: Music.muted ? 0 : Music.volume

                            anchors.left: muteBtn.right
                            anchors.leftMargin: 4
                            anchors.verticalCenter: parent.verticalCenter
                            width: 72
                            height: 18

                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width
                                height: 1
                                color: Qt.alpha(Colors.foreground, 0.16)
                            }

                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width * Math.min(1, vol.shown / 130)
                                height: 1
                                color: vol.shown > 100 ? Colors.critical : Qt.alpha(Colors.foreground, 0.6)
                            }

                            Rectangle {
                                x: parent.width * Math.min(1, vol.shown / 130) - 1
                                anchors.verticalCenter: parent.verticalCenter
                                width: 2
                                height: 11
                                radius: 1
                                color: vol.shown > 100 ? Colors.critical : Colors.foreground
                            }

                            MouseArea {
                                anchors.fill: parent
                                anchors.margins: -5
                                cursorShape: Qt.PointingHandCursor
                                onPressed: mouse => set(mouse.x)
                                onPositionChanged: mouse => {
                                    if (pressed)
                                        set(mouse.x);
                                }

                                function set(mx) {
                                    const f = panel.clamp((mx - 5) / vol.width, 0, 1);
                                    Music.setVolume(Math.round(f * 130 / 5) * 5);
                                }
                            }
                        }

                        Txt {
                            id: volText

                            anchors.left: vol.right
                            anchors.leftMargin: 8
                            anchors.verticalCenter: parent.verticalCenter
                            text: Music.muted ? "muted" : String(Music.volume)
                            color: Music.volume > 100 && !Music.muted ? Colors.critical : Colors.muted
                            font.pixelSize: Style.fontXs
                        }

                        Row {
                            anchors.right: parent.right
                            anchors.left: volText.right
                            anchors.leftMargin: 14
                            anchors.verticalCenter: parent.verticalCenter
                            layoutDirection: Qt.RightToLeft
                            spacing: 6

                            Txt {
                                width: Math.min(implicitWidth, 120)
                                elide: Text.ElideRight
                                text: panel.nextTitle
                                visible: panel.nextTitle !== ""
                                color: Qt.alpha(Colors.foreground, 0.7)
                                font.pixelSize: Style.fontSm
                            }

                            Txt {
                                text: "next"
                                visible: panel.nextTitle !== ""
                                color: Colors.muted
                                font.pixelSize: Style.fontSm
                            }

                            Txt {
                                text: "sleep " + Math.ceil(Music.sleepLeft / 60) + "m"
                                visible: Music.sleepMin > 0
                                color: Colors.accent
                                font.pixelSize: Style.fontSm
                            }
                        }
                    }
                }
            }

            // ---- Right: the lists -------------------------------------------
            Item {
                id: rightPane

                x: panel.leftW
                width: parent.width - panel.leftW
                height: parent.height

                // Search: always the box you type in
                FocusScope {
                    id: search

                    property alias text: field.text
                    property alias input: field
                    readonly property bool filled: field.text !== ""

                    function clear() {
                        field.text = "";
                    }

                    x: panel.gutter
                    y: 26
                    width: parent.width - panel.gutter * 2
                    height: 34
                    activeFocusOnTab: false
                    onTextChanged: panel.query = text

                    Keys.onPressed: event => {
                        const k = event.key;
                        const ctrl = (event.modifiers & Qt.ControlModifier) !== 0;
                        const shift = (event.modifiers & Qt.ShiftModifier) !== 0;
                        const alt = (event.modifiers & Qt.AltModifier) !== 0;
                        const plain = event.modifiers === Qt.NoModifier;
                        const left = k === Qt.Key_Left;
                        const right = k === Qt.Key_Right;
                        if (panel.helpOn) {
                            panel.helpOn = false;
                            event.accepted = true;
                        } else if (k === Qt.Key_F1 || (event.text === "?" && panel.query === "")) {
                            panel.helpOn = true;
                            event.accepted = true;
                        } else if (k === Qt.Key_Escape) {
                            if (panel.pickFor.length > 0)
                                panel.cancelPick();
                            else if (panel.lyricsOn)
                                panel.lyricsOn = false;
                            else if (panel.query !== "")
                                search.clear();
                            else if (panel.canGoBack)
                                panel.goBack();
                            else
                                panel.close();
                        } else if (k === Qt.Key_Backspace && panel.query === "" && panel.canGoBack)
                            panel.goBack();
                        else if (alt && left)
                            Music.prev();
                        else if (alt && right)
                            Music.next();
                        else if (alt && k === Qt.Key_Up)
                            panel.moveEntry(-1);
                        else if (alt && k === Qt.Key_Down)
                            panel.moveEntry(1);
                        else if (ctrl && k === Qt.Key_Z)
                            panel.undoRemove();
                        else if (shift && !ctrl && left)
                            Music.seekBy(-10);
                        else if (shift && !ctrl && right)
                            Music.seekBy(10);
                        else if (shift && !ctrl && k === Qt.Key_Up)
                            panel.nudgeVolume(5);
                        else if (shift && !ctrl && k === Qt.Key_Down)
                            panel.nudgeVolume(-5);
                        else if (ctrl && left)
                            panel.jumpAlbum(-1);
                        else if (ctrl && right)
                            panel.jumpAlbum(1);
                        else if (ctrl && k === Qt.Key_J)
                            panel.jumpToPlaying();
                        else if (ctrl && k === Qt.Key_M)
                            Music.toggleMute();
                        else if (ctrl && shift && k === Qt.Key_S)
                            panel.shuffleAll();
                        else if (ctrl && shift && k === Qt.Key_A)
                            panel.saveQueue();
                        else if (ctrl && k === Qt.Key_S)
                            Music.toggleShuffle();
                        else if (ctrl && k === Qt.Key_R)
                            Music.cycleRepeat();
                        else if (ctrl && k === Qt.Key_O)
                            panel.cycleSort();
                        else if (ctrl && k === Qt.Key_E)
                            Music.cycleSleep();
                        else if (ctrl && k === Qt.Key_D)
                            panel.ctrlD(shift);
                        else if (ctrl && k === Qt.Key_T)
                            panel.cycleKind();
                        else if (ctrl && k === Qt.Key_L)
                            panel.likeSel();
                        else if (ctrl && k === Qt.Key_Y)
                            panel.toggleLyrics();
                        else if (ctrl && k === Qt.Key_A)
                            panel.pickSel();
                        else if (ctrl && k === Qt.Key_Space)
                            panel.togglePlay();
                        else if (k === Qt.Key_Space && panel.query === "" && plain)
                            panel.togglePlay();
                        else if (ctrl && k >= Qt.Key_1 && k <= Qt.Key_5)
                            panel.setTab(k - Qt.Key_1);
                        else if (k === Qt.Key_Tab)
                            panel.setTab((panel.tab + 1) % 5);
                        else if (k === Qt.Key_Backtab)
                            panel.setTab((panel.tab + 4) % 5);
                        else if (k === Qt.Key_Return || k === Qt.Key_Enter) {
                            if (alt)
                                panel.playNextSel();
                            else if (ctrl)
                                panel.activateAlt();
                            else if (shift)
                                panel.enqueueSel();
                            else
                                panel.activate();
                        } else if (plain && k === Qt.Key_Down)
                            panel.move(1);
                        else if (plain && k === Qt.Key_Up)
                            panel.move(-1);
                        else if (ctrl && k === Qt.Key_N)
                            panel.move(1);
                        else if (ctrl && k === Qt.Key_P)
                            panel.move(-1);
                        else if (plain && k === Qt.Key_PageDown)
                            panel.move(8);
                        else if (plain && k === Qt.Key_PageUp)
                            panel.move(-8);
                        else if (plain && k === Qt.Key_Home && panel.query === "")
                            panel.setSel(0);
                        else if (plain && k === Qt.Key_End && panel.query === "")
                            panel.setSel(panel.n - 1);
                        else if (plain && k === Qt.Key_Delete && panel.query === "" && (panel.tab === 2 || panel.tab === 4 || (panel.tab === 3 && panel.curItem !== null && panel.curItem.kind === "recent")))
                            panel.removeSel();
                        else
                            return;
                        event.accepted = true;
                    }

                    Txt {
                        id: searchIcon

                        anchors.left: parent.left
                        anchors.leftMargin: 2
                        anchors.verticalCenter: parent.verticalCenter
                        text: Icons.search
                        color: field.activeFocus || search.filled ? Colors.accent : Colors.muted
                        opacity: (panel.tab === 3 ? MusicNet.busy : Music.scanning) ? searchBreath : 1
                        font.pixelSize: Style.fontXl

                        property real searchBreath: 1

                        SequentialAnimation on searchBreath {
                            running: (panel.tab === 3 ? MusicNet.busy : Music.scanning) && panel.isOpen
                            loops: Animation.Infinite

                            NumberAnimation {
                                to: 0.35
                                duration: Style.ambientMs
                                easing.type: Style.easeAmbient
                            }
                            NumberAnimation {
                                to: 1
                                duration: Style.ambientMs
                                easing.type: Style.easeAmbient
                            }
                        }

                        Behavior on color {
                            ColorAnimation {
                                duration: Style.baseMs
                            }
                        }
                    }

                    TextInput {
                        id: field

                        anchors.left: searchIcon.right
                        anchors.leftMargin: 12
                        anchors.right: scopeText.left
                        anchors.rightMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        focus: true
                        clip: true
                        color: Colors.foreground
                        selectionColor: Qt.alpha(Colors.accent, 0.4)
                        selectedTextColor: Colors.foreground
                        Keys.forwardTo: [search]

                        font {
                            family: Style.fontFamily
                            pixelSize: Style.fontBase
                        }

                        Txt {
                            anchors.fill: parent
                            visible: field.text.length === 0
                            verticalAlignment: Text.AlignVCenter
                            elide: Text.ElideRight
                            text: panel.placeholderText()
                            color: Colors.muted
                            font.pixelSize: Style.fontBase
                        }
                    }

                    // Where the words go, and how many things they found
                    Txt {
                        id: scopeText

                        anchors.right: clearX.left
                        anchors.rightMargin: 6
                        anchors.verticalCenter: parent.verticalCenter
                        text: panel.badgeText() !== "" ? panel.badgeText() : (panel.tab === 3 ? "online" : "library")
                        color: Colors.muted
                        font.pixelSize: Style.fontSm
                    }

                    Rectangle {
                        id: clearX

                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        width: search.filled ? 24 : 0
                        height: 24
                        radius: 12
                        opacity: search.filled ? 1 : 0
                        color: xHover.hovered ? Style.hoverFill : "transparent"

                        Txt {
                            anchors.centerIn: parent
                            text: Icons.close
                            color: Colors.muted
                            font.pixelSize: Style.fontMd
                        }

                        HoverHandler {
                            id: xHover

                            cursorShape: Qt.PointingHandCursor
                        }

                        TapHandler {
                            onTapped: {
                                search.clear();
                                field.forceActiveFocus();
                            }
                        }
                    }

                    // The underline
                    Rectangle {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        height: 1
                        color: field.activeFocus || search.filled ? Qt.alpha(Colors.accent, 0.5) : Qt.alpha(Colors.foreground, 0.1)

                        Behavior on color {
                            ColorAnimation {
                                duration: Style.baseMs
                            }
                        }
                    }
                }

                // Tabs, with a hairline under them
                Item {
                    id: tabsBar

                    x: panel.gutter
                    y: search.y + search.height + 12
                    width: parent.width - panel.gutter * 2
                    height: 30

                    Rectangle {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        height: 1
                        color: Qt.alpha(Colors.foreground, 0.07)
                    }

                    Row {
                        spacing: 0

                        Repeater {
                            model: [
                                {
                                    "label": "Albums",
                                    "tab": 0
                                },
                                {
                                    "label": "Tracks",
                                    "tab": 1
                                },
                                {
                                    "label": "",
                                    "tab": -1
                                },
                                {
                                    "label": "Queue",
                                    "tab": 2
                                },
                                {
                                    "label": "Online",
                                    "tab": 3
                                },
                                {
                                    "label": "Lists",
                                    "tab": 4
                                }
                            ]

                            delegate: Item {
                                id: tabItem

                                required property var modelData

                                readonly property bool gap: modelData.tab < 0
                                readonly property bool on: panel.tab === modelData.tab

                                width: gap ? 26 : tabLabel.implicitWidth + (tabCount.visible ? tabCount.implicitWidth + 6 : 0) + 16
                                height: tabsBar.height

                                Rectangle {
                                    visible: tabItem.gap
                                    anchors.centerIn: parent
                                    width: 1
                                    height: 12
                                    color: Qt.alpha(Colors.foreground, 0.14)
                                }

                                Row {
                                    visible: !tabItem.gap
                                    anchors.left: parent.left
                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.verticalCenterOffset: -1
                                    spacing: 6

                                    Txt {
                                        id: tabLabel

                                        text: tabItem.modelData.label
                                        color: tabItem.on ? Colors.foreground : (tabHover.hovered ? Qt.alpha(Colors.foreground, 0.85) : Colors.muted)
                                        font.pixelSize: Style.fontMd

                                        Behavior on color {
                                            ColorAnimation {
                                                duration: Style.fadeMs
                                            }
                                        }
                                    }

                                    // Only the queue's length: the one number that matters at a glance
                                    Txt {
                                        id: tabCount

                                        anchors.baseline: tabLabel.baseline
                                        visible: tabItem.modelData.tab === 2 && Music.queue.length > 0
                                        text: Music.queue.length
                                        color: Colors.muted
                                        font.pixelSize: Style.fontXs
                                    }
                                }

                                Rectangle {
                                    visible: tabItem.on
                                    anchors.left: parent.left
                                    anchors.bottom: parent.bottom
                                    width: tabLabel.implicitWidth + (tabCount.visible ? tabCount.implicitWidth + 6 : 0)
                                    height: 2
                                    radius: 1
                                    color: Colors.foreground
                                }

                                HoverHandler {
                                    id: tabHover

                                    enabled: !tabItem.gap
                                    cursorShape: Qt.PointingHandCursor
                                }

                                TapHandler {
                                    enabled: !tabItem.gap
                                    onTapped: {
                                        panel.setTab(tabItem.modelData.tab);
                                        search.forceActiveFocus();
                                    }
                                }
                            }
                        }
                    }

                    // What can be done to the whole list, for this tab
                    Row {
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 3
                        spacing: 0

                        Link {
                            visible: panel.tab === 0
                            text: panel.albSort === "artist" ? "sort · artist" : "sort · name"
                            onClicked: {
                                panel.cycleSort();
                                search.forceActiveFocus();
                            }
                        }

                        Link {
                            visible: panel.tab < 2
                            text: "shuffle all"
                            onClicked: {
                                panel.shuffleAll();
                                search.forceActiveFocus();
                            }
                        }

                        Link {
                            visible: panel.tab < 2
                            text: Music.scanning ? "reading…" : "rescan"
                            onClicked: {
                                Music.scan();
                                panel.say("Reading " + Config.musicDir);
                                search.forceActiveFocus();
                            }
                        }

                        Link {
                            visible: panel.tab === 2 && panel.qItems.length > 0
                            text: "save as playlist"
                            onClicked: {
                                panel.saveQueue();
                                search.forceActiveFocus();
                            }
                        }

                        Link {
                            visible: panel.tab === 2
                            on: Music.sleepMin > 0
                            text: Music.sleepMin > 0 ? "sleep · " + Music.sleepMin + "m" : "sleep"
                            onClicked: {
                                Music.cycleSleep();
                                search.forceActiveFocus();
                            }
                        }

                        Link {
                            visible: panel.tab === 2 && panel.qItems.length > 0
                            text: panel.clearArmed ? "press again" : "clear"
                            armed: panel.clearArmed
                            onClicked: {
                                panel.requestClear();
                                search.forceActiveFocus();
                            }
                        }

                        Link {
                            visible: panel.tab === 3 && panel.oOpened === null
                            text: MusicNet.kindLabel.toLowerCase()
                            onClicked: {
                                panel.cycleKind();
                                search.forceActiveFocus();
                            }
                        }

                        Link {
                            visible: panel.tab === 4 && panel.pickFor.length > 0
                            text: "cancel"
                            onClicked: {
                                panel.cancelPick();
                                search.forceActiveFocus();
                            }
                        }

                        Link {
                            visible: panel.canGoBack
                            text: "← back"
                            onClicked: {
                                panel.goBack();
                                search.forceActiveFocus();
                            }
                        }
                    }
                }

                // ---- The list ------------------------------------------------
                ListView {
                    id: list

                    anchors.top: tabsBar.bottom
                    anchors.topMargin: 4
                    anchors.bottom: foot.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    clip: true
                    model: panel.items
                    boundsBehavior: Flickable.StopAtBounds
                    reuseItems: true
                    cacheBuffer: 600
                    onAtYEndChanged: {
                        if (atYEnd && panel.tab === 3 && panel.oOpened === null && panel.n > 0)
                            MusicNet.loadMore();
                    }

                    delegate: Item {
                        id: row

                        required property var modelData
                        required property int index

                        readonly property var m: modelData
                        readonly property bool cur: index === panel.selIdx
                        readonly property bool playing: panel.isPlaying(m)
                        readonly property bool showHead: panel.groupHead(index)
                        readonly property string cap: panel.queueCaption(index)
                        readonly property bool spine: panel.tab === 1
                        readonly property int headH: showHead ? 62 : (cap !== "" ? 34 : 0)
                        readonly property int bodyH: panel.tab === 0 ? 56 : (panel.tab === 1 ? 40 : 50)
                        readonly property bool song: m.kind === undefined || m.kind === "song"
                        readonly property bool liked: song && m.path !== undefined && m.path !== "" && MusicLists.isLiked(m.path)
                        readonly property bool showActs: cur || bodyHover.hovered
                        // Tracks: lit from the top of the playing album to the playing song
                        readonly property bool lit: spine && panel.playIdx >= 0 && index <= panel.playIdx && m.group === panel.playIdxGroup
                        readonly property int cardX: spine ? 68 : panel.gutter
                        readonly property int leadX: spine ? 90 : panel.gutter + 12
                        readonly property string coverUrl: m.cover ? m.cover : panel.coverOf(m)

                        width: list.width
                        height: headH + bodyH

                        // The spine
                        Rectangle {
                            visible: row.spine
                            x: panel.spineX
                            width: 1
                            height: parent.height
                            color: row.lit ? Qt.alpha(Colors.accent, 0.55) : Qt.alpha(Colors.foreground, 0.1)
                        }

                        // Tracks: the album's cover and name
                        Item {
                            visible: row.showHead
                            width: parent.width
                            height: row.headH

                            Art {
                                x: 68
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.verticalCenterOffset: 2
                                width: 40
                                height: 40
                                corner: 10
                                source: row.coverUrl
                                letter: (row.m.album || row.m.title || "?").charAt(0).toUpperCase()
                            }

                            Column {
                                x: 120
                                width: parent.width - 120 - 30
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.verticalCenterOffset: 2
                                spacing: 2

                                Txt {
                                    width: parent.width
                                    elide: Text.ElideRight
                                    text: row.m.artist
                                    visible: text !== ""
                                    color: Colors.muted
                                    font.pixelSize: Style.fontSm
                                }

                                Txt {
                                    width: parent.width
                                    elide: Text.ElideRight
                                    text: row.m.album !== "" ? row.m.album : panel.folderOf(row.m.path)
                                    color: row.m.group === panel.playingGroup ? Colors.accent : Colors.foreground
                                    font.pixelSize: Style.fontBase
                                    font.weight: Font.Medium
                                }
                            }
                        }

                        // Queue: "now playing", "up next"
                        Txt {
                            visible: row.cap !== ""
                            x: panel.gutter + 12
                            y: row.headH - 22
                            text: row.cap
                            color: row.cap === "now playing" ? Colors.accent : Colors.muted
                            font.pixelSize: Style.fontSm
                        }

                        // The row itself
                        Item {
                            id: body

                            y: row.headH
                            width: parent.width
                            height: row.bodyH

                            // The cursor: a lifted card
                            Rectangle {
                                x: row.cardX
                                width: parent.width - row.cardX - 30
                                y: 2
                                height: parent.height - 4
                                radius: Style.radiusLg
                                antialiasing: true
                                opacity: row.cur ? 1 : (bodyHover.hovered ? 0.5 : 0)
                                color: Qt.alpha(Colors.foreground, 0.06)
                                border.width: 1
                                border.color: Qt.alpha(Colors.foreground, 0.09)

                                Behavior on opacity {
                                    NumberAnimation {
                                        duration: Style.fadeMs
                                    }
                                }
                            }

                            // Tracks: a node on the spine, and the number or the dancing bars
                            Rectangle {
                                visible: row.spine
                                x: panel.spineX + 0.5 - width / 2
                                anchors.verticalCenter: parent.verticalCenter
                                width: row.playing ? 9 : 5
                                height: width
                                radius: width / 2
                                color: row.playing ? Colors.accent : (row.cur ? Colors.foreground : Qt.alpha(Colors.foreground, 0.28))

                                Rectangle {
                                    anchors.centerIn: parent
                                    width: parent.width + 6 + 6 * panel.breath
                                    height: width
                                    radius: width / 2
                                    color: "transparent"
                                    border.width: 1
                                    border.color: Qt.alpha(Colors.accent, 0.35 * (1 - panel.breath))
                                    visible: row.playing && Music.playing
                                }
                            }

                            Item {
                                visible: row.spine
                                x: 74
                                anchors.verticalCenter: parent.verticalCenter
                                width: 22
                                height: 14

                                Eq {
                                    anchors.centerIn: parent
                                    visible: row.playing
                                    active: Music.playing
                                }

                                Txt {
                                    anchors.centerIn: parent
                                    visible: !row.playing
                                    text: row.m.track > 0 ? String(row.m.track).padStart(2, "0") : "·"
                                    color: Colors.muted
                                    font.pixelSize: Style.fontSm
                                }
                            }

                            // Everything else: a cover (or a glyph) in front
                            Art {
                                visible: !row.spine && row.m.kind !== "recent" && row.m.kind !== "new"
                                x: row.leadX
                                anchors.verticalCenter: parent.verticalCenter
                                width: panel.tab === 0 ? 40 : 34
                                height: width
                                corner: width * 0.28
                                source: row.coverUrl
                                letter: (row.m.title || row.m.name || "?").charAt(0).toUpperCase()
                            }

                            Txt {
                                visible: !row.spine && (row.m.kind === "recent" || row.m.kind === "new")
                                x: row.leadX
                                anchors.verticalCenter: parent.verticalCenter
                                width: 34
                                horizontalAlignment: Text.AlignHCenter
                                text: row.m.kind === "new" ? Icons.plus : Icons.clock
                                color: Colors.muted
                                font.pixelSize: Style.fontXl
                            }

                            Column {
                                x: row.spine ? row.leadX + 18 : row.leadX + (panel.tab === 0 ? 40 : 34) + 12
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - x - 44 - (row.showActs ? actions.width + 8 : 0)
                                spacing: 2

                                Txt {
                                    width: parent.width
                                    elide: Text.ElideRight
                                    text: row.m.title !== undefined ? row.m.title : (row.m.name !== undefined ? row.m.name : "")
                                    color: row.playing ? Colors.accent : (row.cur ? Colors.foreground : Qt.alpha(Colors.foreground, 0.88))
                                    font.pixelSize: Style.fontBase
                                    font.weight: row.playing || row.cur ? Font.Medium : Font.Normal
                                }

                                Txt {
                                    width: parent.width
                                    visible: !row.spine && text !== ""
                                    elide: Text.ElideRight
                                    text: panel.subLine(row.m)
                                    color: Colors.muted
                                    font.pixelSize: Style.fontSm
                                }
                            }

                            // A heart for the ones you like
                            Txt {
                                visible: row.liked && !row.showActs
                                anchors.right: parent.right
                                anchors.rightMargin: 46
                                anchors.verticalCenter: parent.verticalCenter
                                text: Icons.heart
                                color: Qt.alpha(Colors.foreground, 0.4)
                                font.pixelSize: Style.fontSm
                            }

                            // What can be done to this row
                            // Built only while the row is hovered or under the cursor: twenty
                            // rows with a dozen buttons each would be a lot to keep around
                            Loader {
                                id: actions

                                active: row.showActs
                                anchors.right: parent.right
                                anchors.rightMargin: 36
                                anchors.verticalCenter: parent.verticalCenter
                                sourceComponent: actionsRow
                            }

                            Component {
                                id: actionsRow

                                Row {
                                spacing: 0

                                // Play it
                                Act {
                                    visible: panel.tab !== 2 || !row.m.current
                                    glyph: Icons.play
                                    tip: panel.tab === 0 ? "Play the album" : (panel.tab === 1 ? "Play from here" : "Play")
                                    onClicked: {
                                        panel.setSel(row.index);
                                        panel.activate();
                                        search.forceActiveFocus();
                                    }
                                }

                                // Open an album, a playlist, an artist
                                Act {
                                    visible: (panel.tab === 3 && row.m.kind !== "song" && row.m.kind !== "recent") || (panel.tab === 4 && row.m.kind === "list" && panel.lOpen === "")
                                    glyph: Icons.folderOpen
                                    tip: "Open it"
                                    onClicked: {
                                        panel.setSel(row.index);
                                        panel.activateAlt();
                                        search.forceActiveFocus();
                                    }
                                }

                                // Move in the queue
                                Act {
                                    visible: panel.tab === 2 && panel.query.trim() === ""
                                    glyph: Icons.arrowUp
                                    tip: "Move up"
                                    onClicked: {
                                        panel.setSel(row.index);
                                        panel.moveEntry(-1);
                                        search.forceActiveFocus();
                                    }
                                }

                                Act {
                                    visible: panel.tab === 2 && panel.query.trim() === ""
                                    glyph: Icons.arrowDown
                                    tip: "Move down"
                                    onClicked: {
                                        panel.setSel(row.index);
                                        panel.moveEntry(1);
                                        search.forceActiveFocus();
                                    }
                                }

                                // Next, queue
                                Act {
                                    visible: panel.tab !== 4 && !(panel.tab === 3 && row.m.kind === "recent") && !(panel.tab === 2 && row.m.current)
                                    glyph: Icons.chevronRight
                                    tip: "Play next"
                                    onClicked: {
                                        panel.setSel(row.index);
                                        panel.playNextSel();
                                        search.forceActiveFocus();
                                    }
                                }

                                Act {
                                    visible: panel.tab !== 2 && !(panel.tab === 3 && row.m.kind === "recent") && !(panel.tab === 4 && panel.pickFor.length > 0)
                                    glyph: Icons.plus
                                    tip: "Add to the queue"
                                    onClicked: {
                                        panel.setSel(row.index);
                                        panel.enqueueSel();
                                        search.forceActiveFocus();
                                    }
                                }

                                // Like, add to a playlist
                                Act {
                                    visible: row.song && row.m.path !== undefined && row.m.path !== "" && panel.tab !== 4
                                    glyph: row.liked ? Icons.heart : Icons.heartOutline
                                    on: row.liked
                                    tip: row.liked ? "Unlike" : "Like"
                                    onClicked: {
                                        panel.setSel(row.index);
                                        panel.likeSel();
                                        search.forceActiveFocus();
                                    }
                                }

                                Act {
                                    visible: panel.tab < 4 && !(panel.tab === 3 && row.m.kind === "recent") && panel.pickFor.length === 0
                                    glyph: Icons.playlistPlus
                                    tip: "Add to a playlist"
                                    onClicked: {
                                        panel.setSel(row.index);
                                        panel.pickSel();
                                        search.forceActiveFocus();
                                    }
                                }

                                // Download a streamed song
                                Act {
                                    visible: panel.tab === 3 && (row.m.kind === "song" || row.m.kind === "album" || row.m.kind === "playlist")
                                    glyph: Icons.download
                                    tip: "Download"
                                    onClicked: {
                                        panel.setSel(row.index);
                                        panel.ctrlD(false);
                                        search.forceActiveFocus();
                                    }
                                }

                                // Remove
                                Act {
                                    visible: (panel.tab === 2 && !row.m.current) || (panel.tab === 4 && (panel.lOpen !== "" || (row.m.kind === "list" && row.m.name !== MusicLists.likedName))) || (panel.tab === 3 && row.m.kind === "recent")
                                    glyph: Icons.close
                                    danger: true
                                    tip: panel.tab === 4 && panel.lOpen === "" ? "Delete the playlist (press twice)" : "Remove"
                                    onClicked: {
                                        panel.setSel(row.index);
                                        panel.removeSel();
                                        search.forceActiveFocus();
                                    }
                                }
                                }
                            }

                            HoverHandler {
                                id: bodyHover

                                cursorShape: Qt.PointingHandCursor
                            }

                            // Click puts the cursor here, double-click plays
                            TapHandler {
                                onTapped: {
                                    panel.setSel(row.index);
                                    search.forceActiveFocus();
                                }
                                onDoubleTapped: {
                                    panel.setSel(row.index);
                                    panel.activate();
                                    search.forceActiveFocus();
                                }
                            }
                        }
                    }

                    // The edge fades into the card
                    footer: Item {
                        width: list.width
                        height: 40
                    }
                }

                // Nothing to show
                Column {
                    anchors.horizontalCenter: list.horizontalCenter
                    anchors.verticalCenter: list.verticalCenter
                    spacing: 6
                    visible: panel.n === 0
                    width: list.width - 80

                    Txt {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        text: panel.emptyTitle()
                        color: Colors.foreground
                        font.pixelSize: Style.fontLg
                        font.weight: Font.Medium
                    }

                    Txt {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WordWrap
                        visible: text !== ""
                        text: panel.emptySub()
                        color: Colors.muted
                        font.pixelSize: Style.fontMd
                    }
                }

                // The foot fades the list out
                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: foot.top
                    height: 36

                    gradient: Gradient {
                        GradientStop {
                            position: 0
                            color: Qt.alpha(Style.card, 0)
                        }
                        GradientStop {
                            position: 1
                            color: Style.card
                        }
                    }
                }

                // What just happened, and the way to take it back
                Rectangle {
                    id: toast

                    readonly property bool undoable: Music.lastRemoved !== null && panel.note === "Removed from the queue"

                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: foot.top
                    anchors.bottomMargin: 6
                    height: 34
                    width: toastRow.implicitWidth + 30
                    radius: height / 2
                    color: Colors.raisedAlt
                    border.width: 1
                    border.color: Style.outline
                    opacity: panel.note !== "" ? 1 : 0
                    visible: opacity > 0.01
                    transform: Translate {
                        y: panel.note !== "" ? 0 : 8

                        Behavior on y {
                            NumberAnimation {
                                duration: Style.baseMs
                                easing.type: Style.easeEnter
                            }
                        }
                    }

                    Behavior on opacity {
                        NumberAnimation {
                            duration: Style.fadeMs
                        }
                    }

                    Row {
                        id: toastRow

                        anchors.centerIn: parent
                        spacing: 10

                        Txt {
                            anchors.verticalCenter: parent.verticalCenter
                            text: panel.note
                            color: Colors.foreground
                            font.pixelSize: Style.fontMd
                        }

                        Link {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: toast.undoable
                            on: true
                            text: "undo"
                            onClicked: {
                                panel.undoRemove();
                                search.forceActiveFocus();
                            }
                        }

                        KeyCap {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: toast.undoable
                            label: "Ctrl Z"
                        }
                    }
                }

                // The foot: the keys that matter, or what the button under the pointer does
                Item {
                    id: foot

                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.leftMargin: panel.gutter
                    anchors.rightMargin: panel.gutter
                    height: 44

                    Txt {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: panel.tipNow !== ""
                        text: panel.tipNow
                        color: Colors.foreground
                        opacity: 0.85
                        font.pixelSize: Style.fontSm
                    }

                    Row {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 18
                        visible: panel.tipNow === ""

                        Repeater {
                            model: panel.tab === 2 ? [["Enter", "play"], ["Alt ↑↓", "move"], ["Del", "remove"]] : [["Enter", "play"], ["Shift Enter", "queue"], ["Alt Enter", "next"]]

                            delegate: Row {
                                id: hint

                                required property var modelData

                                spacing: 6

                                KeyCap {
                                    anchors.verticalCenter: parent.verticalCenter
                                    label: hint.modelData[0]
                                }

                                Txt {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: hint.modelData[1]
                                    color: Colors.muted
                                    font.pixelSize: Style.fontSm
                                }
                            }
                        }
                    }

                    Row {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 6

                        KeyCap {
                            anchors.verticalCenter: parent.verticalCenter
                            label: "?"
                        }

                        Txt {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "all keys"
                            color: Colors.muted
                            font.pixelSize: Style.fontSm
                        }
                    }
                }
            }

            // ---- The shortcuts: over the card, any key puts them away -------
            Rectangle {
                anchors.fill: parent
                color: Qt.alpha(Style.card, 0.98)
                visible: panel.helpMix > 0.01
                opacity: panel.helpMix

                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        panel.helpOn = false;
                        search.forceActiveFocus();
                    }
                }

                Txt {
                    x: 48
                    y: 36
                    text: "keys"
                    color: Colors.accent
                    font.pixelSize: Style.fontSm
                }

                Grid {
                    anchors.centerIn: parent
                    flow: Grid.TopToBottom
                    rows: Math.ceil(panel.keyHelp.length / 2)
                    columnSpacing: 56
                    rowSpacing: 4

                    Repeater {
                        model: panel.keyHelp

                        delegate: Row {
                            id: helpRow

                            required property var modelData

                            height: 26
                            spacing: 12

                            Row {
                                width: 150
                                height: parent.height
                                spacing: 4

                                Repeater {
                                    model: helpRow.modelData.k

                                    delegate: KeyCap {
                                        required property string modelData

                                        anchors.verticalCenter: parent.verticalCenter
                                        label: modelData
                                    }
                                }
                            }

                            Txt {
                                width: 250
                                anchors.verticalCenter: parent.verticalCenter
                                text: modelData.d
                                elide: Text.ElideRight
                                color: Qt.alpha(Colors.foreground, 0.85)
                                font.pixelSize: Style.fontMd
                            }
                        }
                    }
                }
            }
        }
    }
}
