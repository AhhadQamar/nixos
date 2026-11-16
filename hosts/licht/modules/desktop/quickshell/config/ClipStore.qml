pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

// ClipStore.qml
// The brain of the clipboard panel. No UI in here: ClipPanel.qml draws, this file
// keeps the history, runs cliphist and wl-copy and remembers the extras.
// It lives outside the panel so the history is already loaded when the panel
// opens (no empty flash), and so copies are noticed while the panel is closed.
//
// The history itself is cliphist's (stored by `wl-paste --watch cliphist store`,
// started with the session). On top of it this adds:
//   - when and from which app each thing was copied (a watcher notes each new entry)
//   - pins: text kept for good, outside the history's size limit
//   - private mode: while on, new copies are dropped from the history again
//   - one-key transforms (clean a link, one line, a colour as rgb or hsl, ...)
//   - paste straight into the window you came from, and copy several as one
//   - the right type for a copied image (it used to be guessed by wl-copy)
//   - the wider preview line (cliphist -preview-width) the search runs on
//
// Things this fixes against the old ClipboardManager.qml:
//   - searches only saw the first 100 characters of an entry
//   - the list was fetched again, and showed empty, each time the panel opened
//   - copying an image left its type to be guessed
//   - nothing could be kept: the oldest entries were lost when the history filled
//   - what is visibly a password or an API key was shown in plain text
//
// Optional: paste needs `wtype` (it says so if it is missing).

Singleton {
    id: store

    // ---- Settings -----------------------------------------------------------
    // How much of an entry the panel loads to show (bytes)
    readonly property int textBytes: 24000
    // How many of the newest images get a thumbnail made when the list loads
    readonly property int thumbMax: 24
    readonly property string home: Config.home
    readonly property string thumbDir: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/qs-clip"
    readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || home + "/.local/state") + "/quickshell"
    // Terminals paste with ctrl+shift+v
    readonly property var terminals: ["kitty", "foot", "footclient", "alacritty", "ghostty", "com.mitchellh.ghostty", "org.wezfurlong.wezterm", "wezterm", "konsole", "xterm", "st", "st-256color"]
    readonly property var trackingParams: /^(utm_[a-z_]+|fbclid|gclid|dclid|msclkid|mc_eid|mc_cid|igshid|ref_src|spm|yclid|_hsenc|_hsmi|vero_id|oly_enc_id|oly_anon_id)$/i

    // ---- State --------------------------------------------------------------
    property bool isOpen: false
    property bool shown: false
    // When the last click outside the panel closed it (see toggle)
    property double closedAt: 0
    property bool loaded: false
    property var rawLines: []
    property var entries: []
    property var pinEntries: []
    property var counts: ({
            "all": 0,
            "text": 0,
            "link": 0,
            "image": 0,
            "pinned": 0
        })
    property var pins: []
    property var meta: ({})
    property var known: ({})
    property var thumbs: ({})
    property var textCache: ({})
    property var decodeQueue: []
    property var imageQueue: []
    // Private mode: new copies are removed from the history again
    property bool paused: false
    property string note: ""
    property bool noteIsError: false
    // The window you were in when the panel opened (paste goes back there)
    property string prevApp: ""
    property int newestTries: 0

    // The text that goes with an action's own words
    readonly property var kindLabels: ({
            "text": "Text",
            "link": "Link",
            "path": "Path",
            "color": "Colour",
            "image": "Image",
            "secret": "Secret"
        })

    function start() {
        scan();
        return true;
    }

    function say(text, isError) {
        note = text;
        noteIsError = !!isError;
        noteTimer.restart();
    }

    // ---- Reading what an entry is ------------------------------------------
    // Things that are plainly a secret (a key block, a token with a known prefix,
    // a JWT) are hidden in the list until you ask to see them. Nothing is guessed
    // from how random a string looks: a hash or an id is not a secret.
    function looksSecret(t) {
        if (t.length < 8 || t.length > 8192)
            return false;
        if (/-----BEGIN [A-Z ]*PRIVATE KEY-----/.test(t))
            return true;
        const one = t.trim();
        if (/\s/.test(one))
            return false;
        if (/^(ghp_|gho_|ghu_|ghs_|github_pat_|glpat-|sk-|sk_live_|rk_live_|xox[baprs]-|AKIA|ASIA|AIza|ya29\.|hf_|npm_|pypi-)[A-Za-z0-9_\-\.]{10,}$/.test(one))
            return true;
        return /^eyJ[A-Za-z0-9_-]{5,}\.[A-Za-z0-9_-]{5,}\.[A-Za-z0-9_-]*$/.test(one);
    }

    function kindOf(text, binary) {
        if (binary)
            return "image";
        const t = String(text).trim();
        if (t === "")
            return "text";
        if (looksSecret(t))
            return "secret";
        if (t.indexOf("\n") >= 0)
            return "text";
        if (/^#(?:[0-9a-fA-F]{3}|[0-9a-fA-F]{6})$/.test(t))
            return "color";
        if (/^(?:https?|ftp|magnet):\S+$/i.test(t))
            return "link";
        if (t.length > 1 && /^(?:~|\/)\S*$/.test(t))
            return "path";
        return "text";
    }

    // "[[ binary data 1.2 MiB png 1920x1080 ]]" -> [format, size, dimensions]
    function imageMeta(preview) {
        const m = /\[\[ binary data (\S+ \S+) (\S+) (\S+) \]\]/.exec(preview);
        return m ? [m[2], m[1], m[3]] : ["", "", ""];
    }

    function mimeOf(e) {
        const f = e.imgFmt.toLowerCase();
        return ({
                "png": "image/png",
                "jpg": "image/jpeg",
                "jpeg": "image/jpeg",
                "gif": "image/gif",
                "webp": "image/webp",
                "bmp": "image/bmp"
            })[f] || "";
    }

    function extOf(e) {
        const f = e.imgFmt.toLowerCase();
        return f === "jpeg" ? "jpg" : (f !== "" ? f : "png");
    }

    // "org.mozilla.firefox" -> "Firefox"
    function appLabel(cls) {
        if (!cls)
            return "";
        const last = String(cls).split(".").pop();
        return last.charAt(0).toUpperCase() + last.slice(1);
    }

    function ago(t) {
        if (!t)
            return "";
        const s = Math.max(0, Date.now() / 1000 - t);
        if (s < 45)
            return "now";
        if (s < 3600)
            return Math.round(s / 60) + "m";
        if (s < 86400)
            return Math.round(s / 3600) + "h";
        if (s < 172800)
            return "yesterday";
        return Math.floor(s / 86400) + "d";
    }

    function oneLine(t) {
        return String(t).replace(/\s+/g, " ").trim();
    }

    function expandPath(p) {
        const t = String(p).trim();
        return t.indexOf("~") === 0 ? home + t.slice(1) : t;
    }

    // ---- Building the list --------------------------------------------------
    function makeEntry(line, pinSrc) {
        const m = /^(\d+)\s+([\s\S]*)$/.exec(line);
        if (!m)
            return null;
        const preview = m[2];
        const binary = /^\[\[ binary data/.test(preview);
        const im = binary ? imageMeta(preview) : ["", "", ""];
        const mt = meta[m[1]];
        return {
            "id": m[1],
            "raw": line,
            "preview": preview,
            "binary": binary,
            "kind": kindOf(preview, binary),
            "t": mt ? mt.t : 0,
            "app": mt ? mt.app : "",
            "imgFmt": im[0],
            "imgSize": im[1],
            "imgDims": im[2],
            "pid": "",
            "pinned": pinSrc[m[1]] === true
        };
    }

    function makePinEntry(p) {
        return {
            "id": "p:" + p.pid,
            "raw": "",
            "preview": oneLine(p.text).slice(0, 400),
            "text": p.text,
            "binary": false,
            "kind": kindOf(p.text, false),
            "t": p.at,
            "app": "Pinned",
            "imgFmt": "",
            "imgSize": "",
            "imgDims": "",
            "pid": p.pid,
            "pinned": true
        };
    }

    function rebuild() {
        const pinSrc = {};
        pins.forEach(function (p) {
            if (p.src)
                pinSrc[p.src] = true;
        });
        const list = [];
        rawLines.forEach(function (l) {
            const e = makeEntry(l, pinSrc);
            if (e !== null)
                list.push(e);
        });
        entries = list;
        pinEntries = pins.map(makePinEntry);
        let t = 0;
        let l = 0;
        let im = 0;
        list.forEach(function (e) {
            if (e.kind === "image")
                im++;
            else if (e.kind === "link")
                l++;
            else
                t++;
        });
        counts = {
            "all": list.length,
            "text": t,
            "link": l,
            "image": im,
            "pinned": pins.length
        };
    }

    function scan() {
        if (!scanner.running)
            scanner.running = true;
    }

    function onScanned(text) {
        const lines = text.split("\n").filter(l => l.trim().length > 0);
        rawLines = lines;
        const k = {};
        lines.forEach(function (l) {
            const m = /^(\d+)\s/.exec(l);
            if (m)
                k[m[1]] = true;
        });
        known = k;
        // Notes about entries that are gone are dropped
        let changed = false;
        Object.keys(meta).forEach(function (id) {
            if (!k[id]) {
                delete meta[id];
                changed = true;
            }
        });
        if (changed)
            saveTimer.start();
        loaded = true;
        rebuild();
        makeThumbs();
    }

    function makeThumbs() {
        if (thumbProc.running)
            return;
        if (!entries.some(e => e.kind === "image" && thumbs[e.id] === undefined))
            return;
        thumbProc.command = ["bash", Quickshell.shellPath("clip/thumbs.sh"), thumbDir, String(thumbMax)];
        thumbProc.running = true;
    }

    function thumbUrl(e) {
        const p = thumbs[e.id];
        return p ? "file://" + p : "";
    }

    // ---- Loading one entry to show it ---------------------------------------
    function ensureText(e) {
        if (!e || e.binary || e.pid !== "" || textCache[e.id] !== undefined)
            return;
        if (decodeQueue.indexOf(e.id) < 0)
            decodeQueue = decodeQueue.concat([e.id]);
        pumpDecode();
    }

    function pumpDecode() {
        if (decodeProc.running || decodeQueue.length === 0)
            return;
        const id = decodeQueue[decodeQueue.length - 1];
        decodeQueue = decodeQueue.slice(0, -1);
        decodeProc.pendingId = id;
        decodeProc.command = ["bash", "-c", "cliphist decode \"$1\" | head -c \"$2\"", "_", id, String(textBytes)];
        decodeProc.running = true;
    }

    function cachePut(id, text) {
        const c = Object.assign({}, textCache);
        c[id] = text;
        const ks = Object.keys(c);
        if (ks.length > 40)
            delete c[ks[0]];
        textCache = c;
    }

    // The whole text of an entry, or "" while it is still loading
    function textOf(e) {
        if (!e || e.binary)
            return "";
        if (e.pid !== "")
            return e.text;
        const c = textCache[e.id];
        return c !== undefined ? c : "";
    }

    function ensureImage(e) {
        if (!e || !e.binary || thumbs[e.id] !== undefined)
            return;
        if (imageQueue.indexOf(e.id) < 0)
            imageQueue = imageQueue.concat([e.id]);
        pumpImage();
    }

    function pumpImage() {
        if (imageProc.running || imageQueue.length === 0)
            return;
        const id = imageQueue[imageQueue.length - 1];
        imageQueue = imageQueue.slice(0, -1);
        imageProc.pendingId = id;
        imageProc.command = ["bash", "-c", "umask 077; mkdir -p \"$1\"; cliphist decode \"$2\" > \"$1/$2.img\" && printf '%s' \"$1/$2.img\"", "_", thumbDir, id];
        imageProc.running = true;
    }

    // ---- Copying ------------------------------------------------------------
    // Pasting waits a moment for the window you came from to take the keys back.
    // Terminals paste with ctrl+shift+v.
    readonly property string pasteTail: "sleep 0.25; if ! command -v wtype >/dev/null 2>&1; then notify-send -a Clipboard 'Cannot paste' 'wtype is not installed'; exit 0; fi; case \"$(printf %s \"$CLS\" | tr A-Z a-z)\" in " + "kitty|foot|footclient|alacritty|ghostty|com.mitchellh.ghostty|org.wezfurlong.wezterm|wezterm|konsole|xterm|st|st-256color) wtype -M ctrl -M shift -k v -m shift -m ctrl;; *) wtype -M ctrl -k v -m ctrl;; esac"

    // The thing as it is stored, with its own type
    function copyEntry(e, paste) {
        if (!e)
            return;
        if (e.pid !== "") {
            copyText(e.text, paste);
            return;
        }
        const script = "id=$1; mime=$2; paste=$3; CLS=$4; if [ -n \"$mime\" ]; then cliphist decode \"$id\" | wl-copy --type \"$mime\"; else cliphist decode \"$id\" | wl-copy; fi; [ \"$paste\" = 1 ] || exit 0; " + pasteTail;
        Quickshell.execDetached(["bash", "-c", script, "_", e.id, mimeOf(e), paste ? "1" : "0", prevApp]);
        close();
    }

    function copyText(text, paste) {
        const script = "printf '%s' \"$1\" | wl-copy; [ \"$2\" = 1 ] || exit 0; CLS=$3; " + pasteTail;
        Quickshell.execDetached(["bash", "-c", script, "_", text, paste ? "1" : "0", prevApp]);
        close();
    }

    // Several entries as one, oldest first, one per line
    function copyMany(list) {
        const items = list.filter(e => !e.binary).slice().reverse().map(e => e.pid !== "" ? "p:" + e.text : "h:" + e.id);
        if (items.length === 0) {
            say("Only text can be joined", true);
            return;
        }
        const script = "{ first=1; for a in \"$@\"; do [ $first = 1 ] || printf '\\n'; first=0; case \"$a\" in h:*) cliphist decode \"${a#h:}\";; p:*) printf '%s' \"${a#p:}\";; esac; done; } | wl-copy";
        Quickshell.execDetached(["bash", "-c", script, "_"].concat(items));
        say("Copied " + items.length + " entries as one", false);
        close();
    }

    // ---- Removing -----------------------------------------------------------
    function deleteEntries(list) {
        const hist = list.filter(e => e.pid === "");
        const pinned = list.filter(e => e.pid !== "").map(e => e.pid);
        if (hist.length > 0) {
            Quickshell.execDetached(["bash", "-c", "d=$1; shift; for l in \"$@\"; do printf '%s\\n' \"$l\" | cliphist delete; id=${l%%[[:space:]]*}; rm -f -- \"$d/$id.img\"; done", "_", thumbDir].concat(hist.map(e => e.raw)));
            const gone = {};
            hist.forEach(e => gone[e.id] = true);
            rawLines = rawLines.filter(l => !gone[/^(\d+)\s/.exec(l) ? /^(\d+)\s/.exec(l)[1] : ""]);
        }
        if (pinned.length > 0) {
            pins = pins.filter(p => pinned.indexOf(p.pid) < 0);
            saveTimer.restart();
        }
        rebuild();
        say(list.length === 1 ? "Removed" : "Removed " + list.length + " entries", false);
    }

    // The history goes; pins stay
    function wipe() {
        Quickshell.execDetached(["bash", "-c", "cliphist wipe; rm -rf -- \"$1\"", "_", thumbDir]);
        rawLines = [];
        thumbs = {};
        textCache = {};
        rebuild();
        say("History cleared  \u00b7  pins kept", false);
    }

    // ---- Pins ---------------------------------------------------------------
    function togglePin(e) {
        if (!e)
            return;
        if (e.pid !== "") {
            pins = pins.filter(p => p.pid !== e.pid);
            saveTimer.restart();
            rebuild();
            say("Unpinned", false);
            return;
        }
        if (e.pinned) {
            pins = pins.filter(p => p.src !== e.id);
            saveTimer.restart();
            rebuild();
            say("Unpinned", false);
            return;
        }
        if (e.binary) {
            say("Only text can be pinned", true);
            return;
        }
        const text = textOf(e);
        if (text === "") {
            ensureText(e);
            say("Still loading, try again", true);
            return;
        }
        if (unescape(encodeURIComponent(text)).length >= textBytes) {
            say("Too long to pin whole", true);
            return;
        }
        pins = [
            {
                "pid": Date.now().toString(36) + Math.floor(Math.random() * 1296).toString(36),
                "text": text,
                "at": Math.floor(Date.now() / 1000),
                "src": e.id
            }
        ].concat(pins);
        saveTimer.restart();
        rebuild();
        say("Pinned", false);
    }

    // qs ipc call clipboard pin: the newest entry
    function pinNewest() {
        if (entries.length === 0)
            return "error: history is empty";
        const e = entries[0];
        if (e.binary)
            return "error: only text can be pinned";
        if (e.pinned)
            return "ok: already pinned";
        // The text has to be read first
        pinWait.target = e.id;
        ensureText(e);
        pinWait.restart();
        return "ok";
    }

    // ---- What else an entry can do ------------------------------------------
    function actionsFor(e) {
        if (!e)
            return [];
        switch (e.kind) {
        case "link":
            return [
                {
                    "id": "open",
                    "label": "Open"
                },
                {
                    "id": "clean",
                    "label": "Clean link"
                }
            ];
        case "path":
            return [
                {
                    "id": "open",
                    "label": "Open"
                },
                {
                    "id": "folder",
                    "label": "Show in " + Config.fileManager
                }
            ];
        case "color":
            return [
                {
                    "id": "hex",
                    "label": "hex"
                },
                {
                    "id": "rgb",
                    "label": "rgb()"
                },
                {
                    "id": "hsl",
                    "label": "hsl()"
                }
            ];
        case "image":
            return [
                {
                    "id": "save",
                    "label": "Save"
                },
                {
                    "id": "open",
                    "label": "Open"
                }
            ];
        case "secret":
            return [];
        default:
            return [
                {
                    "id": "oneline",
                    "label": "One line"
                },
                {
                    "id": "trim",
                    "label": "Trim"
                },
                {
                    "id": "upper",
                    "label": "UPPER"
                },
                {
                    "id": "lower",
                    "label": "lower"
                }
            ];
        }
    }

    function cleanLink(url) {
        const h = url.indexOf("#");
        const frag = h >= 0 ? url.slice(h) : "";
        const base = h >= 0 ? url.slice(0, h) : url;
        const q = base.indexOf("?");
        if (q < 0)
            return url;
        const keep = base.slice(q + 1).split("&").filter(p => p !== "" && !trackingParams.test(p.split("=")[0]));
        return base.slice(0, q) + (keep.length > 0 ? "?" + keep.join("&") : "") + frag;
    }

    function colorAs(kind, text) {
        const c = Qt.color(text.trim());
        if (kind === "rgb")
            return "rgb(" + Math.round(c.r * 255) + ", " + Math.round(c.g * 255) + ", " + Math.round(c.b * 255) + ")";
        if (kind === "hsl") {
            const h = c.hslHue < 0 ? 0 : c.hslHue;
            return "hsl(" + Math.round(h * 360) + ", " + Math.round(c.hslSaturation * 100) + "%, " + Math.round(c.hslLightness * 100) + "%)";
        }
        return String(c);
    }

    function runAction(id, e) {
        if (!e)
            return;
        const text = e.pid !== "" ? e.text : (textOf(e) !== "" ? textOf(e) : e.preview);
        switch (id) {
        case "open":
            if (e.kind === "image") {
                Quickshell.execDetached(["bash", "-c", "umask 077; mkdir -p \"$1\"; f=\"$1/open-$2.$3\"; cliphist decode \"$2\" > \"$f\" && xdg-open \"$f\"", "_", thumbDir, e.id, extOf(e)]);
            } else {
                Quickshell.execDetached(["xdg-open", e.kind === "path" ? expandPath(text) : text.trim()]);
            }
            close();
            return;
        case "folder":
            {
                const p = expandPath(text);
                Quickshell.execDetached([Config.terminal, "--title", Config.fileManager, "-e", Config.fileManager, p]);
                close();
                return;
            }
        case "save":
            Quickshell.execDetached(["bash", "-c", "d=\"$HOME/Pictures/Clipboard\"; mkdir -p \"$d\" && cliphist decode \"$1\" > \"$d/clip-$1.$2\" && notify-send -a Clipboard -i image-x-generic 'Image saved' \"$d/clip-$1.$2\"", "_", e.id, extOf(e)]);
            say("Saving to ~/Pictures/Clipboard", false);
            return;
        default:
            break;
        }
        let out = text;
        if (id === "clean")
            out = cleanLink(text.trim());
        else if (id === "oneline")
            out = oneLine(text);
        else if (id === "trim")
            out = text.trim();
        else if (id === "upper")
            out = text.toUpperCase();
        else if (id === "lower")
            out = text.toLowerCase();
        else if (id === "hex" || id === "rgb" || id === "hsl")
            out = colorAs(id, text);
        copyText(out, false);
    }

    // ---- Private mode -------------------------------------------------------
    function setPaused(on) {
        if (on === paused)
            return;
        paused = on;
        say(on ? "Private  \u00b7  new copies are not kept" : "Private mode off", false);
    }

    // ---- Noticing new copies ------------------------------------------------
    function curClass() {
        const t = Hyprland.activeToplevel;
        const o = t ? t.lastIpcObject : null;
        return o && o.class ? String(o.class) : "";
    }

    // A change on the clipboard: a moment later, look at the newest entry
    function onCopied() {
        if (!loaded) {
            scan();
            return;
        }
        newestTries = 2;
        afterCopy.interval = 350;
        afterCopy.restart();
    }

    function onNewest(line) {
        const m = /^(\d+)\s/.exec(line);
        if (!m)
            return;
        const id = m[1];
        if (known[id]) {
            if (newestTries > 0) {
                newestTries--;
                afterCopy.interval = 1200;
                afterCopy.restart();
            }
            return;
        }
        newestTries = 0;
        known[id] = true;
        if (paused) {
            Quickshell.execDetached(["bash", "-c", "printf '%s\\n' \"$1\" | cliphist delete", "_", line]);
            return;
        }
        meta[id] = {
            "t": Math.floor(Date.now() / 1000),
            "app": appLabel(curClass())
        };
        saveTimer.restart();
        scan();
    }

    // ---- The panel ----------------------------------------------------------
    function open() {
        if (isOpen)
            return;
        prevApp = curClass();
        isOpen = true;
        shown = true;
        scan();
    }

    function close() {
        isOpen = false;
    }

    function toggle() {
        // The click that closed the panel by landing outside it must not reopen it
        if (!isOpen && Date.now() - closedAt < 250)
            return;
        if (isOpen)
            close();
        else
            open();
    }

    // The window finished its leaving animation
    function panelGone() {
        if (!isOpen)
            shown = false;
    }

    function saveState() {
        stateFile.setText(JSON.stringify({
            "pins": pins,
            "meta": meta
        }));
    }

    // ---- Plumbing -----------------------------------------------------------
    Component.onCompleted: Quickshell.execDetached(["mkdir", "-p", stateDir])

    FileView {
        id: stateFile

        path: store.stateDir + "/clipboard.json"
        printErrors: false
        onLoaded: {
            try {
                const d = JSON.parse(text());
                if (Array.isArray(d.pins))
                    store.pins = d.pins.filter(p => typeof p.text === "string" && typeof p.pid === "string");
                if (d.meta && typeof d.meta === "object")
                    store.meta = d.meta;
                store.rebuild();
            } catch (e) {}
        }
    }

    Process {
        id: scanner

        command: ["sh", "-c", "cliphist -preview-width 400 list 2>/dev/null || cliphist list"]
        stdout: StdioCollector {
            onStreamFinished: store.onScanned(text)
        }
    }

    Process {
        id: thumbProc

        stdout: StdioCollector {
            onStreamFinished: {
                const map = Object.assign({}, store.thumbs);
                // The script prints the id of every image that is ready
                text.split("\n").forEach(function (l) {
                    const id = l.trim();
                    if (/^\d+$/.test(id))
                        map[id] = store.thumbDir + "/" + id + ".img";
                });
                store.thumbs = map;
            }
        }
    }

    Process {
        id: decodeProc

        property string pendingId: ""

        stdout: StdioCollector {
            onStreamFinished: store.cachePut(decodeProc.pendingId, text)
        }
        onExited: store.pumpDecode()
    }

    Process {
        id: imageProc

        property string pendingId: ""

        stdout: StdioCollector {
            onStreamFinished: {
                if (text.trim() !== "") {
                    const map = Object.assign({}, store.thumbs);
                    map[imageProc.pendingId] = text.trim();
                    store.thumbs = map;
                }
            }
        }
        onExited: store.pumpImage()
    }

    // wl-paste runs the command each time the clipboard changes
    Process {
        command: ["wl-paste", "--type", "text", "--watch", "echo", "t"]
        running: true
        stdout: SplitParser {
            onRead: store.onCopied()
        }
    }

    Process {
        command: ["wl-paste", "--type", "image", "--watch", "echo", "i"]
        running: true
        stdout: SplitParser {
            onRead: store.onCopied()
        }
    }

    Process {
        id: newestProc

        command: ["sh", "-c", "cliphist -preview-width 400 list 2>/dev/null | head -n 1"]
        stdout: StdioCollector {
            onStreamFinished: store.onNewest(text.split("\n")[0])
        }
    }

    // A moment after a copy, once cliphist has stored it
    Timer {
        id: afterCopy

        interval: 350
        onTriggered: if (!newestProc.running)
            newestProc.running = true
    }

    // "Pin the newest" waits for its text to load
    Timer {
        id: pinWait

        property string target: ""

        interval: 150
        repeat: true
        property int ticks: 0
        onRunningChanged: if (running)
            ticks = 0
        onTriggered: {
            ticks++;
            const e = store.entries.find(x => x.id === target);
            if (e && store.textOf(e) !== "") {
                stop();
                store.togglePin(e);
            } else if (ticks > 20) {
                stop();
                store.say("Could not read the entry to pin it", true);
            }
        }
    }

    Timer {
        id: saveTimer

        interval: 3000
        onTriggered: store.saveState()
    }

    Timer {
        id: noteTimer

        interval: 3500
        onTriggered: store.note = ""
    }
}
