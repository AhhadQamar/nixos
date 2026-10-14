pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

// The bar's one picture of the workspaces, taken from Hyprland in one go.
//
// One process runs `hyprctl -j clients`, `monitors` and `workspaces` back to
// back, and one parse publishes all three as `snapshot`. Everything the bar
// draws reads that object, so a disc can never mix windows from one moment
// with workspaces from another.
//
//   snapshot.windows     workspace id -> its windows (special ones have
//                        negative ids). Empty workspaces are left out.
//   snapshot.workspaces  workspace id -> { id, name, monitor }
//   snapshot.monitors    monitor name -> { name, active, special, focused }
//                        `active` is the REGULAR workspace on screen, and stays
//                        so while a special workspace is open over it;
//                        `special` is the open special workspace's short name,
//                        or "" when none is open.
//   snapshot.specials    short names of the special workspaces that exist
//                        AND have been open at least once since the bar
//                        started, sorted by name (never by focus)
//
// Identity is kept on purpose. A part that says the same thing as last time is
// not replaced (see settle), and the snapshot itself is only replaced when a
// part changed, so a focus change that moves nothing wakes nobody up.
//
// A refresh is asked for by Hyprland events and runs 60ms after the FIRST one
// of a burst. Later events in that window join it instead of pushing it back,
// so a burst (a scratchpad toggling) cannot starve the refresh.

Singleton {
    id: root

    property var snapshot: ({
            windows: ({}),
            workspaces: ({}),
            monitors: ({}),
            specials: []
        })

    // Kept for the code that still reads it. A binding that returns the same
    // object as before does not notify anyone.
    readonly property var byWorkspace: snapshot.windows

    property bool _pending: false
    property bool _reported: false
    // Special workspaces that have been open at least once since the bar
    // started. A scratchpad that pyprland parked at login exists in Hyprland
    // from the start but has never been shown, so it gets no disc until its
    // first opening; after that it keeps one, open or hidden. A plain object
    // on purpose: changing a key notifies nobody, parse() reads it right away.
    property var _opened: ({})
    property var _iconCache: ({})
    property var _nameCache: ({})

    function refresh() {
        // Not restart(): see the header
        if (!debounce.running)
            debounce.start();
    }

    // Make `next` (a map of plain objects) reuse the objects in `prev` that say
    // the same thing. Gives back `prev` itself when nothing at all changed, so
    // assigning the result wakes no binding.
    function settle(prev, next) {
        let same = Object.keys(prev).length === Object.keys(next).length;
        for (const key in next) {
            const old = prev[key];
            if (old !== undefined && JSON.stringify(old) === JSON.stringify(next[key]))
                next[key] = old;
            else
                same = false;
        }
        return same ? prev : next;
    }

    // Window classes come in several shapes: "firefox", "Alacritty",
    // "md.obsidian.Obsidian" (reverse-DNS app ids). Try each spelling in turn.
    function candidates(cls) {
        const out = [cls];
        const lower = cls.toLowerCase();
        if (lower !== cls)
            out.push(lower);
        const parts = cls.split(".");
        if (parts.length > 1) {
            const last = parts[parts.length - 1];
            if (last !== "") {
                out.push(last);
                out.push(last.toLowerCase());
            }
        }
        return out;
    }

    function entryFor(cls) {
        const names = candidates(cls);
        for (let i = 0; i < names.length; i++) {
            const entry = DesktopEntries.heuristicLookup(names[i]);
            if (entry)
                return entry;
        }
        return null;
    }

    // Only successful lookups are cached. DesktopEntries and the icon theme can
    // still be loading the first time we ask, and caching that miss would leave
    // the app on a letter badge for the whole session.
    function iconFor(cls) {
        if (cls === "")
            return "";
        if (_iconCache[cls] !== undefined)
            return _iconCache[cls];

        const entry = entryFor(cls);
        const names = candidates(cls);
        if (entry && entry.icon)
            names.unshift(entry.icon);

        for (let i = 0; i < names.length; i++) {
            const n = names[i];
            if (n.charAt(0) === "/") {
                _iconCache[cls] = "file://" + n;
                return _iconCache[cls];
            }
            // Empty string when the theme has no such icon.
            const path = Quickshell.iconPath(n, true);
            if (path !== "") {
                _iconCache[cls] = path;
                return path;
            }
        }
        return "";
    }

    // "firefox" -> "Firefox" via the .desktop entry; falls back to the raw
    // class. Only cached on a hit, for the same reason as iconFor().
    function nameFor(cls) {
        if (cls === "")
            return "";
        if (_nameCache[cls] !== undefined)
            return _nameCache[cls];

        const entry = entryFor(cls);
        if (entry && entry.name) {
            _nameCache[cls] = entry.name;
            return entry.name;
        }
        return cls;
    }

    // "special:magic" -> "magic" (the form toggle_special takes)
    function shortName(name) {
        return (name || "").replace(/^special:/, "");
    }

    function parse(raw) {
        // The three outputs are separated by a line holding "@@"
        const parts = raw.split("@@");
        let clients, monitors, workspaces;
        try {
            if (parts.length !== 3)
                throw new Error("expected 3 parts, got " + parts.length);
            clients = JSON.parse(parts[0]);
            monitors = JSON.parse(parts[1]);
            workspaces = JSON.parse(parts[2]);
        } catch (e) {
            // Publish nothing rather than half a picture
            console.warn("WindowTracker: could not parse hyprctl output: " + e + " / " + raw.slice(0, 200));
            return;
        }

        // ---- Windows ---------------------------------------------------------
        // Only skip windows hyprctl explicitly calls unmapped; if the field is
        // missing in some Hyprland version, keep the window.
        const live = clients.filter(c => c.mapped !== false && c.workspace && (c["class"] || c.initialClass));
        const at = (c, i) => c.at ? c.at[i] : 0;
        const rank = c => c.focusHistoryID === undefined ? 9999 : c.focusHistoryID;
        // Left to right, then top to bottom: the order the icons are drawn in
        live.sort((a, b) => at(a, 0) - at(b, 0) || at(a, 1) - at(b, 1));

        // The window you were last in on each workspace is the bright one
        const best = {};
        for (const c of live) {
            const id = c.workspace.id;
            if (best[id] === undefined || rank(c) < rank(best[id]))
                best[id] = c;
        }

        // One lookup per class per refresh: three terminals share one, and an
        // app with no .desktop entry is not searched for three times
        const looked = {};
        const lookup = cls => {
            if (looked[cls] === undefined)
                looked[cls] = {
                    "name": nameFor(cls),
                    "icon": iconFor(cls)
                };
            return looked[cls];
        };

        // Nothing here changes on a plain focus move between workspaces (no
        // raw focus rank, no title, no position), so such a move leaves the
        // lists equal and settle() can keep them.
        const windows = {};
        for (const c of live) {
            const id = c.workspace.id;
            const cls = c["class"] || c.initialClass;
            const found = lookup(cls);
            if (windows[id] === undefined)
                windows[id] = [];
            windows[id].push({
                "address": c.address,
                "wsName": c.workspace.name || "",
                "cls": cls,
                "name": found.name,
                "icon": found.icon,
                "focused": best[id] === c
            });
        }

        // ---- Workspaces and monitors ----------------------------------------
        // Monitors first: a special workspace open over one is "opened" for good
        const mons = {};
        for (const m of monitors) {
            const open = m.specialWorkspace ? shortName(m.specialWorkspace.name) : "";
            if (open !== "")
                _opened[open] = true;
            mons[m.name] = {
                "name": m.name,
                "active": m.activeWorkspace ? m.activeWorkspace.id : 0,
                "special": open,
                "focused": m.focused === true
            };
        }

        const spaces = {};
        const specials = [];
        for (const w of workspaces) {
            spaces[w.id] = {
                "id": w.id,
                "name": w.name,
                "monitor": w.monitor
            };
            // Only a special workspace that has been shown at least once gets
            // a disc; one that is just sitting hidden since login does not
            if (w.id < 0 && _opened[shortName(w.name)] === true)
                specials.push(shortName(w.name));
        }
        specials.sort();

        // ---- Publish, once, and only if something changed ---------------------
        const prev = snapshot;
        const next = {
            "windows": settle(prev.windows, windows),
            "workspaces": settle(prev.workspaces, spaces),
            "monitors": settle(prev.monitors, mons),
            "specials": specials.join("\n") === prev.specials.join("\n") ? prev.specials : specials
        };
        if (next.windows !== prev.windows || next.workspaces !== prev.workspaces || next.monitors !== prev.monitors || next.specials !== prev.specials)
            snapshot = next;

        if (!_reported) {
            _reported = true;
            console.log("WindowTracker: hyprctl listed " + clients.length + " clients, tracking windows on " + Object.keys(windows).length + " workspaces");
        }
    }

    Component.onCompleted: refresh()

    // Everything that can change what the bar draws: windows coming, going,
    // moving or taking focus; workspaces appearing, going or moving between
    // monitors; the active workspace; which monitor has focus; and a special
    // workspace opening or closing.
    Connections {
        target: Hyprland

        function onRawEvent(event) {
            switch (event.name) {
            case "openwindow":
            case "closewindow":
            case "movewindow":
            case "movewindowv2":
            case "activewindowv2":
            case "changefloatingmode":
            case "workspacev2":
            case "createworkspacev2":
            case "destroyworkspacev2":
            case "moveworkspacev2":
            case "renameworkspace":
            case "focusedmon":
            case "focusedmonv2":
            case "activespecial":
            case "activespecialv2":
            case "monitoradded":
            case "monitoraddedv2":
            case "monitorremoved":
            case "monitorremovedv2":
                root.refresh();
                break;
            }
        }
    }

    Timer {
        id: debounce

        interval: 60
        repeat: false
        onTriggered: {
            if (proc.running)
                root._pending = true;
            else
                proc.running = true;
        }
    }

    Process {
        id: proc

        command: ["sh", "-c", "hyprctl -j clients; echo @@; hyprctl -j monitors; echo @@; hyprctl -j workspaces"]

        stdout: StdioCollector {
            onStreamFinished: root.parse(text)
        }

        stderr: StdioCollector {
            onStreamFinished: if (text.trim() !== "")
                console.warn("WindowTracker: hyprctl said: " + text.trim())
        }

        onExited: (code, status) => {
            if (code !== 0)
                console.warn("WindowTracker: hyprctl exited with code " + code);
        }

        onRunningChanged: {
            if (!running && root._pending) {
                root._pending = false;
                running = true;
            }
        }
    }
}
