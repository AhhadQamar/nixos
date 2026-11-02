// Playlists of the music player: plain .m3u8 files in ~/Music/Playlists that any
// other player can open. "Liked Songs" is one of them. The files are read and
// written by music/lists.py, one request at a time, in order.

pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    readonly property string dir: Config.musicDir + "/Playlists"
    readonly property string likedName: "Liked Songs"

    // [{ name, count }], Liked Songs first
    property var lists: []
    // path or URL -> true, for the hearts
    property var liked: ({})

    // A list was changed on disk (name)
    signal written(string name)
    // The songs of a list: the tag you asked with, the list's name, and
    // [{ path, title, artist, album, duration, cover }]
    signal fetched(int tag, string name, var entries)

    property var ops: []
    property var cur: null
    property var buf: []

    function isLiked(p) {
        return liked[p] === true;
    }

    function run(kind, args, extra) {
        ops.push(Object.assign({
            "kind": kind,
            "args": args
        }, extra || {}));
        pump();
    }

    function pump() {
        if (proc.running || ops.length === 0)
            return;
        cur = ops.shift();
        buf = [];
        proc.command = ["qs-music-py", Quickshell.shellPath("music/lists.py"), dir].concat(cur.args);
        proc.running = true;
    }

    function refresh() {
        run("list", ["list"]);
        run("liked", ["show", likedName]);
    }

    function fetch(name, tag) {
        run("show", ["show", name], {
            "name": name,
            "tag": tag
        });
    }

    function add(name, entries) {
        const clean = entries.filter(e => e && e.path);
        if (clean.length === 0)
            return;
        run("write", ["add", name, JSON.stringify(clean)], {
            "name": name
        });
    }

    function removeTrack(name, path) {
        run("write", ["remove", name, path], {
            "name": name
        });
    }

    function create(name) {
        run("write", ["create", name], {
            "name": name
        });
    }

    function del(name) {
        run("write", ["delete", name], {
            "name": name
        });
    }

    // Heart on or off. The heart answers at once; the file follows.
    function toggleLike(entry) {
        if (!entry || !entry.path)
            return false;
        const m = Object.assign({}, liked);
        const was = m[entry.path] === true;
        if (was) {
            delete m[entry.path];
            removeTrack(likedName, entry.path);
        } else {
            m[entry.path] = true;
            add(likedName, [entry]);
        }
        liked = m;
        return !was;
    }

    function entryOf(f) {
        return {
            "path": f[0],
            "title": f[1] || "",
            "artist": f[2] || "",
            "album": f[3] || "",
            "duration": parseInt(f[4]) || 0,
            "cover": f[5] || ""
        };
    }

    function onDone() {
        const c = cur;
        cur = null;
        if (c !== null) {
            if (c.kind === "list") {
                root.lists = buf.map(l => l.split("\t")).filter(f => f[0] !== "").map(f => ({
                            "name": f[0],
                            "count": parseInt(f[1]) || 0
                        }));
            } else if (c.kind === "liked" || c.kind === "show") {
                const entries = buf.map(l => l.split("\t")).filter(f => f.length >= 2 && f[0] !== "").map(f => entryOf(f));
                if (c.kind === "liked") {
                    const m = {};
                    for (const e of entries)
                        m[e.path] = true;
                    root.liked = m;
                } else {
                    root.fetched(c.tag, c.name, entries);
                }
            } else if (c.kind === "write") {
                // Counts and, for Liked Songs, the hearts
                root.refresh();
                root.written(c.name);
            }
        }
        pump();
    }

    Component.onCompleted: refresh()

    Process {
        id: proc

        stdout: SplitParser {
            onRead: line => root.buf.push(line)
        }
        onExited: root.onDone()
    }
}
