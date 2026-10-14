// MusicPlayer.qml
// Music on the launcher's dial: the same borderless stage rising from the
// bottom edge, the same fine ruler, glass squircles and accent underline.
//
// Two things are on screen at once and neither hides the other:
//   BROWSE   a dial of covers. Three tabs, one key apart (Tab):
//              Albums  one cover per album: the quick way to put something on
//              Tracks  every song, an album's tracks together, a gap between
//              Queue   what is coming up
//            Type to search: the dial jumps to the best matching song (and
//            goes back to Albums when you clear it).
//   PLAYING  a glass card at the foot, always there: cover, title, transport,
//            volume, and a ruler that is the track itself. Click or drag the
//            ruler to seek.
// Opening lands you on the album that is playing.
//
//   qs ipc call music toggle | open | close | playpause | next | prev | stop | rescan
//   qs ipc call music media <playpause|next|prev>   (media keys: falls back to playerctl)
//
// Keys   browse   ← → ↑ ↓ (Ctrl+N / Ctrl+P) move   PgUp PgDn jump 8   Home End ends
//                 Tab (Shift+Tab) next / previous tab   Ctrl+1 2 3 pick a tab
//                 Ctrl+← Ctrl+→ previous / next album (in Tracks)   Ctrl+J back to what is playing
//        play     Enter  Albums: play the album   Tracks: play from this song on
//                 Ctrl+Enter  Albums: play from this album on   Tracks: play this album
//                 Shift+Enter add to the queue   Space play / pause (search empty)   Ctrl+Space always
//        player   Alt+← Alt+→ previous / next track   Shift+← Shift+→ seek 10 s
//                 Shift+↑ Shift+↓ volume   Ctrl+M mute   Ctrl+S shuffle   Ctrl+R repeat
//        queue    Delete (or Ctrl+D) remove the highlighted entry
//        Esc clears the search, then closes
// Mouse  click a cover to bring it to the middle, click it again to play from
//        there; scroll the dial to move, scroll the player card for volume;
//        click or drag its ruler to seek; click outside to close
//
// Like the launcher it arrives as a rainbow: the covers swing in from the left
// over a tight dome and unfurl into the calm dial. Closing plays it in reverse.
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
    // The dial, in the launcher's proportions
    readonly property int topY: 64
    readonly property int ruleDrop: 46
    readonly property int ruleY: topY + ruleDrop
    readonly property real stepPx: 74
    readonly property real dialR: Math.max(900, width * 0.92)
    // The dome the dial starts as when it opens (and ends as when it closes)
    readonly property real rainbowR: Math.min(380, Math.max(280, width * 0.2))
    readonly property int itemSize: 46
    readonly property int selectedSize: 76
    readonly property int tickGap: 12
    readonly property int tickCount: Math.ceil(width / tickGap) + 24
    readonly property int slotHalf: Math.min(22, Math.ceil(width * 0.52 / stepPx) + 1)
    // The extra gap, in discs, between two albums
    readonly property real groupGap: 0.5

    // Rows of the stage, top to bottom (all measured from the top of the stage)
    readonly property int readoutY: ruleY + 22
    readonly property int rowY: readoutY + 66
    readonly property int cardW: Math.min(720, width - 40)
    readonly property int cardH: 74
    readonly property int cardY: rowY + Style.fieldHeight + 10
    readonly property int stageH: cardY + cardH + 22
    // How dark the shade under the player gets (the launcher's value)
    readonly property real scrim: 0.95

    // ---- State ----------------------------------------------------------
    property bool isOpen: false
    // 0 = hidden below the edge, 1 = in place
    property real reveal: 0
    // Slots the dial is swung to the left while arriving (and right when leaving)
    property real spinIn: 0
    // 1 = tight rainbow dome, 0 = the resting dial
    property real fan: 1
    // A slow pulse (0..1) for the rings
    property real breath: 0
    // 0 -> 1 each time the selection changes: the read-out fades up
    property real swap: 1
    // 0 = albums, 1 = tracks, 2 = queue
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
    // The Clear button of the queue has been pressed once
    property bool clearArmed: false
    // A short message that takes the place of the small line over the name
    property string note: ""
    // Whether the dial glides to a new selection (off while jumping)
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

    readonly property var items: tab === 0 ? albItems : (tab === 1 ? libItems : qItems)
    readonly property var poss: tab === 0 ? albPos : (tab === 1 ? libPos : qPos)
    readonly property int n: items.length
    readonly property int selIdx: n > 0 ? clamp(tab === 0 ? asel : (tab === 1 ? sel : qsel), 0, n - 1) : 0
    // The album that is playing right now
    readonly property string playingGroup: {
        const t = Music.lookup(Music.path);
        return Music.hasTrack && t ? groupOf(t) : "";
    }
    readonly property var curItem: n > 0 ? items[selIdx] : null
    readonly property bool curPlaying: curItem !== null && isPlaying(curItem)
    readonly property real targetPos: n > 0 ? poss[selIdx] : 0
    // Where the dial is turned to; glides to the selected entry
    property real viewPos: targetPos
    readonly property int baseIdx: nearestIdx(viewPos)
    // Radius of the dial right now: curvature eases from the dome to the dial
    readonly property real dialNow: 1 / (1 / dialR + (1 / rainbowR - 1 / dialR) * fan)
    readonly property color tint: Colors.accent

    Behavior on viewPos {
        enabled: panel.animateView

        // The dial glides into place and settles, with no bounce. Quick, so
        // that holding an arrow key keeps up.
        NumberAnimation {
            duration: Style.moveMs
            easing.type: Style.easeMove
        }
    }

    onSelIdxChanged: {
        if (isOpen)
            swapAnim.restart();
        coverTimer.restart();
    }
    onTabChanged: {
        if (isOpen)
            swapAnim.restart();
        coverTimer.restart();
    }
    onQueryChanged: {
        const q = query.trim();
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
    }

    // ---- Helpers --------------------------------------------------------
    function clamp(v, a, b) {
        return Math.max(a, Math.min(b, v));
    }

    function g(cp) {
        return String.fromCodePoint(cp);
    }

    // Ease-out with a small overshoot for the arrival of each cover (0..1 in,
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

    // The entry whose place on the dial is nearest to `v`
    function nearestIdx(v) {
        const p = poss;
        if (p.length === 0)
            return 0;
        let lo = 0;
        let hi = p.length - 1;
        while (lo < hi) {
            const mid = (lo + hi) >> 1;
            if (p[mid] < v)
                lo = mid + 1;
            else
                hi = mid;
        }
        if (lo > 0 && Math.abs(p[lo - 1] - v) <= Math.abs(p[lo] - v))
            return lo - 1;
        return lo;
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
        if (!m || m.group === "" || covers[m.group] !== undefined || coverBusy === m.group)
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
        for (let d = 1; d <= 6; d++) {
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
        const paths = [];
        for (let k = 0; k < libItems.length; k++) {
            if (libItems[k].group === grp)
                paths.push(libItems[k].path);
        }
        if (paths.length === 0)
            return;
        Music.playList(paths, 0);
        say("Playing the album, " + paths.length + (paths.length === 1 ? " song" : " songs"));
        watchPlay();
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

    // ---- Moving ---------------------------------------------------------
    function setSel(i) {
        if (n === 0)
            return;
        const v = clamp(i, 0, n - 1);
        if (tab === 0)
            asel = v;
        else if (tab === 1)
            sel = v;
        else
            qsel = v;
    }

    function move(delta) {
        setSel(selIdx + delta);
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
        }
        animateView = true;
    }

    // ---- Doing ----------------------------------------------------------
    function togglePlay() {
        if (Music.hasTrack)
            Music.playPause();
        else
            activate();
    }

    // Enter. Albums: the album. Tracks: this song and what follows it.
    function activate() {
        if (curItem === null)
            return;
        if (tab === 0)
            playGroup(curItem.group);
        else if (tab === 1)
            playFrom(selIdx);
        else {
            Music.jumpTo(curItem.idx);
            watchPlay();
        }
    }

    // Ctrl+Enter, the other one. Albums: from this album on. Tracks: its album.
    function activateAlt() {
        if (curItem === null)
            return;
        if (tab === 0)
            playFrom(curItem.first);
        else if (tab === 1)
            playGroup(curItem.group);
    }

    function enqueueSel() {
        if (curItem === null || tab === 2)
            return;
        if (tab === 1) {
            Music.enqueue(curItem.path);
            say("Added to the queue");
        } else {
            let c = 0;
            for (let k = curItem.first; k < libItems.length && libItems[k].group === curItem.group; k++) {
                Music.enqueue(libItems[k].path);
                c++;
            }
            say("Added " + c + (c === 1 ? " song" : " songs") + " to the queue");
        }
        Music.requestQueue();
    }

    // Remove the highlighted queue entry (not the one playing)
    function removeSel() {
        if (tab !== 2 || curItem === null || curItem.current)
            return;
        Music.removeFromQueue(curItem.idx);
        say("Removed from the queue");
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
        search.text = "";
        tab = 0;
        if (!Music.scanned)
            Music.scan();
        Music.requestQueue();
        seedCover();
        refilter("playing");
        refilterQueue(true);
        reveal = 0;
        spinIn = 3.2;
        fan = 1;
        openAnim.restart();
        search.forceActiveFocus();
    }

    function close() {
        if (!isOpen)
            return;
        isOpen = false;
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

        // A new track: the name fades and settles
        function onPathChanged() {
            if (panel.isOpen)
                swapAnim.restart();
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

        // Re-read ~/Music (the ytm download aliases call this)
        function rescan() {
            Music.scan();
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

    // Covers are looked for a moment after the dial settles, not on every
    // step of a fast scroll
    Timer {
        id: coverTimer

        interval: 140
        onTriggered: panel.ensureCovers()
    }

    // After letting go of the ruler, keep showing where it was dragged to
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

    // Rises smoothly. The covers swing in from the left over a tight dome and
    // unfurl into the dial.
    ParallelAnimation {
        id: openAnim

        NumberAnimation {
            target: panel
            property: "reveal"
            from: 0
            to: 1
            duration: Style.sweepMs
            easing.type: Style.easeEnter
        }
        NumberAnimation {
            target: panel
            property: "spinIn"
            from: 3.2
            to: 0
            duration: Style.sweepMs + Style.moveMs
            easing.type: Style.easeEnter
        }
        NumberAnimation {
            target: panel
            property: "fan"
            from: 1
            to: 0
            duration: Style.sweepMs + Style.ambientMs / 2
            easing.type: Style.easeMove
        }
    }

    // Leaving: the dial curls back into the dome and sweeps off right.
    ParallelAnimation {
        id: closeAnim

        NumberAnimation {
            target: panel
            property: "reveal"
            to: 0
            duration: Style.moveMs + Style.fadeMs
            easing.type: Style.easeExit
        }
        NumberAnimation {
            target: panel
            property: "spinIn"
            to: -3.2
            duration: Style.moveMs + Style.fadeMs
            easing.type: Style.easeExit
        }
        NumberAnimation {
            target: panel
            property: "fan"
            to: 1
            duration: Style.moveMs + Style.fadeMs
            easing.type: Style.easeExit
        }
    }

    // Slow breath for the rings
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

    // A different entry is selected: the words fade up
    NumberAnimation {
        id: swapAnim

        target: panel
        property: "swap"
        from: 0
        to: 1
        duration: Style.baseMs
        easing.type: Style.easeMove
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

    // Click above the stage to close. It stops at the stage's top edge: a
    // click on a button inside must not fall through to this as well.
    MouseArea {
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: stage.top
        onClicked: panel.close()
    }

    // The shared dim (Dim.qml): the same wash as the screenshot tool
    Dim {
        reveal: panel.reveal
    }

    // Screenshot's feathered backing (StageShade.qml), outside the stage which
    // clips, so it can reach above it and fade out instead of ending in an edge.
    Item {
        anchors.fill: parent
        opacity: Math.min(1, panel.reveal * 3)
        transform: Translate {
            y: (1 - panel.reveal) * (panel.stageH + 40)
        }

        StageShade {
            h: panel.stageH
        }
    }

    // ---- Stage ----------------------------------------------------------
    Item {
        id: stage

        readonly property real cx: width / 2

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: panel.stageH
        clip: true
        opacity: Math.min(1, panel.reveal * 3)
        transform: Translate {
            y: (1 - panel.reveal) * (panel.stageH + 40)
        }

        // Scroll wheel turns the dial. It takes no clicks, so a click on the
        // empty stage still closes the player.
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.NoButton
            onWheel: wheel => {
                const d = wheel.angleDelta.y !== 0 ? wheel.angleDelta.y : -wheel.angleDelta.x;
                if (d !== 0)
                    panel.move(d < 0 ? 1 : -1);
            }
        }

        // Low light in the accent, brighter while music plays
        Shape {
            id: horizon

            readonly property real r: Math.min(stage.width * 0.46, 760)

            x: stage.cx - r
            y: stage.height - r
            width: r * 2
            height: r * 2
            layer.enabled: true
            layer.samples: 4
            transform: Scale {
                origin.x: horizon.r
                origin.y: horizon.r
                yScale: 0.45
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
                        color: Qt.alpha(panel.tint, Music.playing ? 0.10 + 0.05 * panel.breath : 0.07)
                    }
                    GradientStop {
                        position: 0.5
                        color: Qt.alpha(panel.tint, 0.035)
                    }
                    GradientStop {
                        position: 1
                        color: Qt.alpha(panel.tint, 0)
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
        // rise a little, like a magnifier ------------------------------------
        Repeater {
            model: panel.tickCount

            delegate: Rectangle {
                id: tick

                required property int index

                readonly property real s: (index - panel.tickCount / 2) * panel.tickGap - panel.mod(panel.viewPos * panel.stepPx - panel.spinIn * panel.stepPx * 0.5, panel.tickGap * 10)
                readonly property real a: s / panel.dialNow
                readonly property real rr: panel.dialNow - panel.ruleDrop
                readonly property bool major: index % 10 === 0
                readonly property real near: Math.max(0, 1 - Math.abs(s) / 90)

                x: stage.cx + rr * Math.sin(a) - 0.75
                y: panel.topY + panel.dialNow - rr * Math.cos(a)
                width: 1.5
                height: (major ? 9 : 5) + 6 * near
                radius: 0.75
                antialiasing: true
                visible: Math.abs(a) < 1.2
                transformOrigin: Item.Top
                rotation: a * 180 / Math.PI
                color: Qt.tint(Qt.alpha(Colors.foreground, major ? 0.34 : 0.18), Qt.alpha(panel.tint, 0.7 * near))
                opacity: panel.clamp((stage.cx - Math.abs(x - stage.cx)) / 230, 0, 1) * panel.clamp(panel.reveal * 2 - Math.abs(x - stage.cx) / stage.cx * 0.9, 0, 1)
            }
        }

        // The middle of the ruler: the accent's 2px, standing where the
        // selected entry is.
        Rectangle {
            x: stage.cx - 1
            y: panel.ruleY - 3
            width: 2
            height: 16
            radius: 1
            color: panel.tint
            opacity: panel.clamp(panel.reveal * 2 - 0.5, 0, 1)
        }

        // ---- The covers --------------------------------------------------
        // A fixed set of slots that is handed whichever entries are near the
        // middle, so a library of thousands costs the same as a dozen. The
        // swell is a function of where a slot is, not of which entry it holds.
        Repeater {
            model: panel.slotHalf * 2 + 1

            delegate: Item {
                id: slot

                required property int index

                readonly property int idx: panel.baseIdx + index - panel.slotHalf
                readonly property var m: idx >= 0 && idx < panel.n ? panel.items[idx] : null
                readonly property real pos: m ? panel.poss[idx] : 0
                readonly property bool current: m !== null && idx === panel.selIdx
                readonly property bool playing: m ? panel.isPlaying(m) : false
                readonly property real rel: pos - panel.viewPos
                // Swung left while arriving, right while leaving
                readonly property real s: (rel - panel.spinIn) * panel.stepPx
                readonly property real a: s / panel.dialNow
                // 0 at rest, 1 in the middle, smooth in between
                readonly property real near: Math.max(0, 1 - Math.abs(rel))
                readonly property real grow: near * near * (3 - 2 * near)
                readonly property real sz: panel.itemSize + (panel.selectedSize - panel.itemSize) * grow
                readonly property real corner: sz * 0.3
                readonly property real px: stage.cx + panel.dialNow * Math.sin(a)
                // The one in the middle also lifts a little off the dial
                readonly property real py: panel.topY + panel.dialNow * (1 - Math.cos(a)) - 6 * grow
                // Arrive in a left-to-right wave, each with a small overshoot
                readonly property real appear: panel.clamp(panel.reveal * 2.2 - (panel.clamp(rel, -6, 6) + 6) * 0.09, 0, 1)
                readonly property real edge: panel.clamp((stage.cx - Math.abs(px - stage.cx)) / 230, 0, 1)
                readonly property string coverUrl: m ? (playing && Music.cover !== "" ? Music.cover : panel.coverOf(m)) : ""

                visible: m !== null && Math.abs(a) < 1.3 && opacity > 0.01
                width: sz
                height: sz
                x: px - sz / 2
                y: py - sz / 2
                z: 10 + grow * 10
                opacity: appear * edge
                scale: 0.55 + 0.45 * panel.backOut(appear)
                // Tilts along the dial, and rises from below as it arrives
                rotation: a * 180 / Math.PI * 0.6
                transform: Translate {
                    y: (1 - slot.appear) * 30
                }

                // Breathing ring around the one in the middle
                Rectangle {
                    anchors.centerIn: parent
                    width: parent.width + 12
                    height: width
                    radius: slot.corner + 6
                    color: "transparent"
                    antialiasing: true
                    visible: slot.grow > 0.05
                    border.width: 1
                    border.color: Qt.alpha(panel.tint, slot.grow * (Music.playing && slot.playing ? 0.3 + 0.3 * panel.breath : 0.25))
                }

                // Glass, like the bar: one flat surface with a hairline outline
                Rectangle {
                    anchors.fill: parent
                    radius: slot.corner
                    antialiasing: true
                    color: Style.card
                    border.width: 1
                    border.color: slot.current ? Qt.alpha(panel.tint, 0.8) : (slot.playing ? Qt.alpha(panel.tint, 0.55) : Qt.alpha(Colors.foreground, 0.2))

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
                    radius: slot.corner - 1
                    antialiasing: true
                    color: Qt.alpha(panel.tint, slot.current ? Style.tintAlpha : (slot.playing ? Style.tintAlpha * 0.6 : 0))

                    Behavior on color {
                        ColorAnimation {
                            duration: Style.baseMs
                        }
                    }
                }

                // The album's cover, or its first letter
                Art {
                    anchors.fill: parent
                    anchors.margins: 3
                    corner: slot.corner - 3
                    source: slot.coverUrl
                    letter: slot.m ? (slot.m.album || slot.m.title || "?").charAt(0).toUpperCase() : ""
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
                            color: Qt.alpha(Colors.foreground, 0.16)
                        }
                        GradientStop {
                            position: 1
                            color: Qt.alpha(Colors.foreground, 0)
                        }
                    }
                }

                // This is the one playing: bars that dance (still when paused)
                Rectangle {
                    x: parent.width - width * 0.62
                    y: parent.height - height * 0.62
                    width: 22
                    height: 22
                    radius: 11
                    antialiasing: true
                    color: Style.card
                    border.width: 1
                    border.color: Qt.alpha(panel.tint, 0.7)
                    opacity: slot.playing ? 1 : 0
                    scale: slot.playing ? 1 : 0.4

                    Behavior on opacity {
                        NumberAnimation {
                            duration: Style.baseMs
                        }
                    }
                    Behavior on scale {
                        NumberAnimation {
                            duration: Style.baseMs
                            easing.type: Style.easeMove
                        }
                    }

                    Eq {
                        anchors.centerIn: parent
                        active: Music.playing
                    }
                }

                // Click to bring it to the middle; click the one in the
                // middle to play from there. Position, not hover, so the dial
                // never turns under a mouse you are only passing over.
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (!slot.m)
                            return;
                        if (slot.current)
                            panel.activate();
                        else
                            panel.setSel(slot.idx);
                    }
                }
            }
        }

        // Nothing here: one quiet squircle in the middle, in place of the dial
        Item {
            id: emptyDisc

            readonly property real appear: panel.stage_(0.1, 0.6)

            x: stage.cx - width / 2
            y: panel.topY - 6 - height / 2
            width: panel.selectedSize
            height: panel.selectedSize
            opacity: panel.n === 0 ? appear : 0
            visible: opacity > 0.01
            scale: 0.55 + 0.45 * panel.backOut(appear)

            Behavior on opacity {
                NumberAnimation {
                    duration: Style.baseMs
                }
            }

            Rectangle {
                anchors.fill: parent
                radius: width * 0.3
                antialiasing: true
                color: Style.card
                border.width: 1
                border.color: Qt.alpha(Colors.foreground, 0.2)
            }

            Txt {
                anchors.centerIn: parent
                text: panel.g(0xF075A)
                color: Colors.muted
                font.pixelSize: 28
            }
        }

        // Accent underline under the selected cover; it breathes with the ring.
        Rectangle {
            readonly property real rel: panel.targetPos - panel.viewPos
            readonly property real a: (rel - panel.spinIn) * panel.stepPx / panel.dialNow

            visible: panel.n > 0
            width: 20 + 10 * panel.breath
            height: 2
            radius: 1
            color: panel.tint
            x: stage.cx + panel.dialNow * Math.sin(a) - width / 2
            y: panel.topY + panel.dialNow * (1 - Math.cos(a)) - 6 + panel.selectedSize / 2 + 8
            rotation: a * 180 / Math.PI
            opacity: panel.clamp(panel.reveal * 2 - 0.6, 0, 1)
        }

        // ---- The middle: what the selected entry is ------------------------
        Item {
            id: readout

            x: stage.cx - width / 2
            y: panel.readoutY
            width: Math.min(560, stage.width - 48)
            height: 60
            // Clicks pass through to the dial
            enabled: false
            opacity: (0.25 + 0.75 * panel.swap) * panel.stage_(0.2, 0.7)
            transform: Translate {
                y: (1 - panel.stage_(0.2, 0.7)) * 12 + (1 - panel.swap) * 6
            }

            Column {
                width: parent.width
                spacing: 3

                // Where it is, or what just happened
                Txt {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                    visible: text !== ""
                    text: {
                        if (panel.note !== "")
                            return panel.note;
                        if (panel.curItem === null)
                            return "";
                        return (panel.curPlaying ? "Now playing" : ["Album", "Track", "Queue"][panel.tab]) + "  ·  " + (panel.selIdx + 1) + " / " + panel.n;
                    }
                    color: panel.note !== "" || panel.curPlaying ? Colors.accent : Colors.muted
                    font.pixelSize: Style.fontXs
                    font.letterSpacing: 1.4
                    font.capitalization: Font.AllUppercase
                }

                // The title, with a soft shadow in the background colour so it reads on any wallpaper
                Item {
                    width: parent.width
                    height: title.implicitHeight

                    Txt {
                        y: 1.5
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                        text: title.text
                        color: Qt.alpha(Colors.background, 0.9)
                        font.pixelSize: Style.fontXl + 2
                        font.bold: true
                    }

                    Txt {
                        id: title

                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                        text: {
                            if (panel.curItem !== null)
                                return panel.curItem.title;
                            if (panel.query.trim() !== "")
                                return "No match";
                            if (panel.tab === 2)
                                return "The queue is empty";
                            return Music.scanning || !Music.scanned ? "Reading your music" : "No music found";
                        }
                        color: Colors.foreground
                        font.pixelSize: Style.fontXl + 2
                        font.bold: true
                    }
                }

                Txt {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                    visible: text !== ""
                    text: {
                        const c = panel.curItem;
                        if (c !== null) {
                            if (panel.tab === 0)
                                return (c.artist !== "" ? c.artist + "  ·  " : "") + c.count + (c.count === 1 ? " song" : " songs");
                            return c.artist !== "" && c.album !== "" ? c.artist + "  ·  " + c.album : (c.artist || c.album);
                        }
                        if (panel.query.trim() !== "")
                            return "Try fewer letters";
                        if (panel.tab === 2)
                            return "Press Tab and play an album";
                        return Music.scanning || !Music.scanned ? "This takes a moment the first time" : "Nothing in " + Config.musicDir;
                    }
                    color: Colors.muted
                    font.pixelSize: Style.fontMd
                }
            }
        }

        // ---- Library or queue, and the search ------------------------------
        RowLayout {
            id: row

            x: stage.cx - width / 2
            y: panel.rowY
            width: panel.cardW
            spacing: Style.spaceMd
            opacity: panel.stage_(0.25, 0.8)
            transform: Translate {
                y: (1 - panel.stage_(0.25, 0.8)) * 10
            }

            // The three lists, one Tab apart
            Rectangle {
                id: seg

                Layout.preferredWidth: 300
                Layout.preferredHeight: Style.fieldHeight
                radius: height / 2
                antialiasing: true
                color: Style.well

                // The highlight glides between them
                Rectangle {
                    x: 3 + panel.tab * (seg.width - 6) / 3
                    y: 3
                    width: (seg.width - 6) / 3
                    height: seg.height - 6
                    radius: height / 2
                    antialiasing: true
                    color: Qt.alpha(Colors.accent, Style.selectedAlpha)

                    Behavior on x {
                        NumberAnimation {
                            duration: Style.moveMs
                            easing.type: Style.easeMove
                        }
                    }
                }

                Repeater {
                    model: [
                        {
                            "label": "Albums",
                            "count": panel.albItems.length
                        },
                        {
                            "label": "Tracks",
                            "count": Music.library.length
                        },
                        {
                            "label": "Queue",
                            "count": Music.queue.length
                        }
                    ]

                    delegate: Item {
                        id: segItem

                        required property var modelData
                        required property int index

                        readonly property bool on: panel.tab === index

                        x: 3 + index * (seg.width - 6) / 3
                        y: 3
                        width: (seg.width - 6) / 3
                        height: seg.height - 6

                        Row {
                            anchors.centerIn: parent
                            spacing: Style.spaceXs + 1

                            Txt {
                                anchors.verticalCenter: parent.verticalCenter
                                text: segItem.modelData.label
                                color: segItem.on ? Colors.accent : (segHover.hovered ? Colors.foreground : Colors.muted)
                                font.pixelSize: Style.fontMd
                                font.bold: segItem.on

                                Behavior on color {
                                    ColorAnimation {
                                        duration: Style.baseMs
                                    }
                                }
                            }

                            Txt {
                                anchors.verticalCenter: parent.verticalCenter
                                visible: segItem.modelData.count > 0
                                text: segItem.modelData.count
                                color: Colors.muted
                                opacity: 0.8
                                font.pixelSize: Style.fontXs
                            }
                        }

                        HoverHandler {
                            id: segHover

                            cursorShape: Qt.PointingHandCursor
                        }

                        TapHandler {
                            onTapped: {
                                panel.setTab(segItem.index);
                                search.forceActiveFocus();
                            }
                        }
                    }
                }
            }

            SearchField {
                id: search

                Layout.fillWidth: true
                placeholder: panel.tab === 2 ? "Filter the queue" : "Search songs, albums, artists"
                badge: panel.query.trim() !== "" ? String(panel.n) : ""
                busy: Music.scanning
                onTextChanged: panel.query = text
                Keys.onPressed: event => {
                    const k = event.key;
                    const ctrl = (event.modifiers & Qt.ControlModifier) !== 0;
                    const shift = (event.modifiers & Qt.ShiftModifier) !== 0;
                    const alt = (event.modifiers & Qt.AltModifier) !== 0;
                    const plain = event.modifiers === Qt.NoModifier;
                    const left = k === Qt.Key_Left;
                    const right = k === Qt.Key_Right;
                    if (k === Qt.Key_Escape) {
                        if (panel.query !== "")
                            search.clear();
                        else
                            panel.close();
                    } else if (alt && left)
                        Music.prev();
                    else if (alt && right)
                        Music.next();
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
                    else if (ctrl && k === Qt.Key_S)
                        Music.toggleShuffle();
                    else if (ctrl && k === Qt.Key_R)
                        Music.cycleRepeat();
                    else if (ctrl && k === Qt.Key_D)
                        panel.removeSel();
                    else if (ctrl && k === Qt.Key_Space)
                        panel.togglePlay();
                    else if (k === Qt.Key_Space && panel.query === "" && plain)
                        panel.togglePlay();
                    else if (ctrl && k >= Qt.Key_1 && k <= Qt.Key_3)
                        panel.setTab(k - Qt.Key_1);
                    else if (k === Qt.Key_Tab)
                        panel.setTab((panel.tab + 1) % 3);
                    else if (k === Qt.Key_Backtab)
                        panel.setTab((panel.tab + 2) % 3);
                    else if (k === Qt.Key_Return || k === Qt.Key_Enter) {
                        if (ctrl)
                            panel.activateAlt();
                        else if (shift)
                            panel.enqueueSel();
                        else
                            panel.activate();
                    } else if (plain && (right || k === Qt.Key_Down))
                        panel.move(1);
                    else if (plain && (left || k === Qt.Key_Up))
                        panel.move(-1);
                    else if (ctrl && k === Qt.Key_N)
                        panel.move(1);
                    else if (ctrl && k === Qt.Key_P)
                        panel.move(-1);
                    else if (plain && k === Qt.Key_PageDown)
                        panel.move(8);
                    else if (plain && k === Qt.Key_PageUp)
                        panel.move(-8);
                    else if (plain && k === Qt.Key_Home)
                        panel.setSel(0);
                    else if (plain && k === Qt.Key_End)
                        panel.setSel(panel.n - 1);
                    else if (plain && k === Qt.Key_Delete && panel.query === "" && panel.tab === 2)
                        panel.removeSel();
                    else
                        return;
                    event.accepted = true;
                }
            }

            // Library: read the folder again
            IconButton {
                Layout.alignment: Qt.AlignVCenter
                visible: panel.tab !== 2
                glyph: Icons.refresh
                size: Style.fieldHeight - 4
                active: !Music.scanning
                onClicked: {
                    Music.scan();
                    panel.say("Reading " + Config.musicDir);
                    search.forceActiveFocus();
                }
            }

            // Queue: empty it, with a second press to be sure
            TextButton {
                Layout.alignment: Qt.AlignVCenter
                visible: panel.tab === 2 && panel.qItems.length > 0
                compact: true
                minWidth: 92
                danger: panel.clearArmed
                armed: panel.clearArmed
                text: panel.clearArmed ? "Press again" : "Clear"
                onClicked: {
                    panel.requestClear();
                    search.forceActiveFocus();
                }
            }
        }

        // ---- What is playing ----------------------------------------------
        // Always here. The bar's glass, with the dial's parts in it: a
        // squircle cover, the transport, and along the foot a ruler that is
        // the track itself.
        Item {
            id: card

            x: stage.cx - width / 2
            y: panel.cardY
            width: panel.cardW
            height: panel.cardH
            opacity: panel.stage_(0.3, 0.85)
            transform: Translate {
                y: (1 - panel.stage_(0.3, 0.85)) * 14
            }

            // Scroll the card for volume
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.NoButton
                onWheel: wheel => {
                    const d = wheel.angleDelta.y !== 0 ? wheel.angleDelta.y : wheel.angleDelta.x;
                    if (d !== 0)
                        panel.nudgeVolume(d > 0 ? 5 : -5);
                }
            }

            Rectangle {
                anchors.fill: parent
                radius: Style.barRadius
                antialiasing: true
                color: Style.card
                border.width: 1
                border.color: Style.outline
            }

            // Light catching the top edge, as on the bar
            Rectangle {
                anchors.top: parent.top
                anchors.topMargin: 1
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: Style.barRadius
                anchors.rightMargin: Style.barRadius
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

            // The cover of what is playing: click to play or pause
            Item {
                id: nowCover

                x: 14
                y: 10
                width: 44
                height: 44

                // Breathes while the music plays
                Rectangle {
                    anchors.centerIn: parent
                    width: parent.width + 8
                    height: width
                    radius: nowArt.corner + 4
                    color: "transparent"
                    antialiasing: true
                    visible: Music.hasTrack
                    border.width: 1
                    border.color: Qt.alpha(Colors.accent, Music.playing ? 0.2 + 0.3 * panel.breath : 0.14)
                }

                Rectangle {
                    anchors.fill: parent
                    radius: width * 0.3
                    antialiasing: true
                    color: Style.well
                    border.width: 1
                    border.color: Music.hasTrack ? Qt.alpha(Colors.accent, 0.6) : Style.outline
                }

                Art {
                    id: nowArt

                    anchors.fill: parent
                    anchors.margins: 2
                    corner: 11
                    source: Music.hasTrack ? Music.cover : ""
                    letter: Music.hasTrack ? (Music.album || Music.title || "?").charAt(0).toUpperCase() : ""
                }

                Txt {
                    anchors.centerIn: parent
                    visible: !Music.hasTrack
                    text: panel.g(0xF075A)
                    color: Colors.muted
                    font.pixelSize: 20
                }

                HoverHandler {
                    cursorShape: Qt.PointingHandCursor
                }

                TapHandler {
                    onTapped: {
                        panel.togglePlay();
                        search.forceActiveFocus();
                    }
                }
            }

            // Transport and volume, on the right
            Row {
                id: controls

                anchors.right: parent.right
                anchors.rightMargin: 14
                y: 10 + (44 - height) / 2
                spacing: Style.spaceLg

                Row {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2

                    IconButton {
                        anchors.verticalCenter: parent.verticalCenter
                        glyph: panel.g(0xF049F)
                        on: Music.shuffle
                        size: 30
                        onClicked: Music.toggleShuffle()
                    }

                    IconButton {
                        anchors.verticalCenter: parent.verticalCenter
                        glyph: panel.g(0xF04AE)
                        size: 32
                        glyphSize: 16
                        onClicked: Music.prev()
                    }

                    // Play and pause: the one accent-filled control
                    Rectangle {
                        id: playBtn

                        anchors.verticalCenter: parent.verticalCenter
                        width: 40
                        height: 40
                        radius: width / 2
                        antialiasing: true
                        color: Qt.alpha(Colors.accent, playHover.hovered ? 0.32 : 0.22)
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
                            color: Colors.accent
                            font.pixelSize: 19
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

                    IconButton {
                        anchors.verticalCenter: parent.verticalCenter
                        glyph: panel.g(0xF04AD)
                        size: 32
                        glyphSize: 16
                        onClicked: Music.next()
                    }

                    IconButton {
                        anchors.verticalCenter: parent.verticalCenter
                        glyph: panel.g(Music.repeat === "one" ? 0xF0458 : 0xF0456)
                        on: Music.repeat !== "off"
                        size: 30
                        onClicked: Music.cycleRepeat()
                    }
                }

                // Volume: the speaker mutes, the bars set it (click or drag),
                // and they turn red past 100%
                Row {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Style.spaceXs

                    IconButton {
                        anchors.verticalCenter: parent.verticalCenter
                        glyph: panel.g(Music.muted || Music.volume === 0 ? 0xF0581 : 0xF057E)
                        on: Music.muted
                        size: 28
                        onClicked: Music.toggleMute()
                    }

                    Item {
                        id: volBars

                        readonly property int bars: 13
                        readonly property int gap: 6
                        readonly property real shown: Music.muted ? 0 : Music.volume

                        anchors.verticalCenter: parent.verticalCenter
                        width: bars * gap
                        height: 22

                        Repeater {
                            model: volBars.bars

                            delegate: Rectangle {
                                required property int index

                                readonly property bool lit: (index + 1) * 10 <= volBars.shown + 4
                                readonly property bool over: (index + 1) * 10 > 100

                                x: index * volBars.gap + (volBars.gap - width) / 2
                                anchors.bottom: parent.bottom
                                width: 2
                                height: 5 + index * 1.1
                                radius: 1
                                antialiasing: true
                                color: lit ? (over ? Colors.critical : Colors.accent) : Qt.alpha(Colors.foreground, 0.14)

                                Behavior on color {
                                    ColorAnimation {
                                        duration: Style.fadeMs
                                    }
                                }
                            }
                        }

                        // A little wider than the bars, so they are easy to hit
                        MouseArea {
                            id: volArea

                            function set(mx) {
                                const f = panel.clamp((mx - 4) / volBars.width, 0, 1);
                                Music.setVolume(Math.round(f * 130 / 5) * 5);
                            }

                            anchors.fill: parent
                            anchors.margins: -4
                            cursorShape: Qt.PointingHandCursor
                            onPressed: mouse => set(mouse.x)
                            onPositionChanged: mouse => {
                                if (pressed)
                                    set(mouse.x);
                            }
                        }
                    }

                    Txt {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 34
                        horizontalAlignment: Text.AlignRight
                        text: Music.muted ? "Muted" : Music.volume + "%"
                        color: Music.muted ? Colors.muted : (Music.volume > 100 ? Colors.critical : Colors.muted)
                        font.pixelSize: Style.fontXs
                    }
                }
            }

            // What is playing
            Item {
                x: 70
                y: 10
                width: Math.max(40, controls.x - 70 - 14)
                height: 44

                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width
                    spacing: 2

                    Txt {
                        width: parent.width
                        elide: Text.ElideRight
                        text: Music.hasTrack ? (Music.title || "Unknown") : "Nothing playing"
                        color: Music.hasTrack ? Colors.foreground : Colors.muted
                        font.pixelSize: Style.fontLg
                        font.bold: Music.hasTrack
                    }

                    Txt {
                        width: parent.width
                        elide: Text.ElideRight
                        text: Music.hasTrack ? (Music.artist !== "" && Music.album !== "" ? Music.artist + "  ·  " + Music.album : (Music.artist || Music.album)) : "Pick something and press Enter"
                        color: Colors.muted
                        font.pixelSize: Style.fontMd
                    }
                }
            }

            // The track as a ruler: lit up to where it is, the head standing
            // taller. Click or drag to seek; the time at the left follows the
            // pointer while you do.
            Item {
                id: seekRow

                readonly property bool can: Music.hasTrack && Music.duration > 0
                readonly property real frac: panel.seeking ? panel.seekFrac : Music.progress
                readonly property bool aiming: seekArea.pressed || (seekArea.containsMouse && can)
                readonly property real aim: panel.clamp(seekArea.mouseX / Math.max(1, ticks.width), 0, 1)

                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.leftMargin: 14
                anchors.rightMargin: 14
                anchors.bottomMargin: 8
                height: 14

                Txt {
                    id: elapsed

                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    width: 36
                    text: seekRow.can ? Music.fmt(seekRow.aiming ? seekRow.aim * Music.duration : Music.position) : ""
                    color: seekRow.aiming ? Colors.accent : Colors.muted
                    font.pixelSize: Style.fontXs
                }

                Txt {
                    id: total

                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: 36
                    horizontalAlignment: Text.AlignRight
                    text: seekRow.can ? Music.fmt(Music.duration) : ""
                    color: Colors.muted
                    font.pixelSize: Style.fontXs
                }

                Item {
                    id: ticks

                    readonly property int gap: 6
                    readonly property int n: Math.max(1, Math.floor(width / gap))
                    // The tick the head stands on
                    readonly property int head: Math.min(n - 1, Math.floor(seekRow.frac * n))

                    anchors.left: elapsed.right
                    anchors.right: total.left
                    anchors.leftMargin: Style.spaceMd
                    anchors.rightMargin: Style.spaceMd
                    anchors.verticalCenter: parent.verticalCenter
                    height: parent.height

                    Repeater {
                        model: ticks.n

                        delegate: Rectangle {
                            required property int index

                            readonly property bool major: index % 10 === 0
                            readonly property bool played: seekRow.can && (index + 0.5) / ticks.n <= seekRow.frac
                            readonly property bool isHead: seekRow.can && index === ticks.head
                            // Ticks near the pointer rise, like the dial's
                            readonly property real near: seekRow.aiming ? Math.max(0, 1 - Math.abs((index + 0.5) / ticks.n - seekRow.aim) * ticks.n / 6) : 0

                            x: index * ticks.gap + (ticks.gap - width) / 2
                            anchors.verticalCenter: parent.verticalCenter
                            width: isHead ? 2.5 : 1.5
                            height: (isHead ? 14 : (major ? 8 : 5)) + 4 * near
                            radius: 1
                            antialiasing: true
                            color: isHead ? Colors.accent : (played ? Qt.alpha(Colors.accent, 0.7) : Qt.alpha(Colors.foreground, 0.16 + 0.3 * near))

                            Behavior on height {
                                NumberAnimation {
                                    duration: Style.fadeMs
                                }
                            }
                        }
                    }

                    MouseArea {
                        id: seekArea

                        anchors.fill: parent
                        anchors.topMargin: -8
                        anchors.bottomMargin: -8
                        hoverEnabled: true
                        enabled: seekRow.can
                        cursorShape: Qt.PointingHandCursor
                        onPressed: mouse => {
                            panel.seeking = true;
                            seekHold.stop();
                            panel.seekFrac = panel.clamp(mouse.x / ticks.width, 0, 1);
                            dragSeek.start();
                        }
                        onPositionChanged: mouse => {
                            if (pressed)
                                panel.seekFrac = panel.clamp(mouse.x / ticks.width, 0, 1);
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
            }
        }
    }
}
