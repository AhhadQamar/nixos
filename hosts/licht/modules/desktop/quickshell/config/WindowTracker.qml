pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

// Maps each workspace id to its windows, refreshed from `hyprctl clients -j`.

Singleton {
    id: root

    // Replaced wholesale on every refresh so bindings re-evaluate.
    property var byWorkspace: ({})

    property bool _pending: false
    property bool _reported: false
    property var _iconCache: ({})
    property var _nameCache: ({})

    function refresh() {
        debounce.restart();
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

    function parse(raw) {
        let clients;
        try {
            clients = JSON.parse(raw);
        } catch (e) {
            console.warn("WindowTracker: could not parse hyprctl output: " + raw.slice(0, 200));
            return;
        }

        const map = {};
        for (let i = 0; i < clients.length; i++) {
            const c = clients[i];
            const cls = c["class"] || c.initialClass || "";
            // Only skip windows hyprctl explicitly calls unmapped; if the
            // field is missing in some Hyprland version, keep the window.
            if (c.mapped === false || !c.workspace || cls === "")
                continue;

            const id = c.workspace.id;
            if (map[id] === undefined)
                map[id] = [];
            map[id].push({
                "address": c.address,
                "wsName": c.workspace.name || "",
                "cls": cls,
                "name": nameFor(cls),
                "title": c.title || "",
                "icon": iconFor(cls),
                "focused": false,
                "focusRank": c.focusHistoryID === undefined ? 9999 : c.focusHistoryID,
                "x": c.at ? c.at[0] : 0,
                "y": c.at ? c.at[1] : 0
            });
        }

        for (const id in map) {
            const list = map[id];
            let best = list[0];
            for (let i = 1; i < list.length; i++) {
                if (list[i].focusRank < best.focusRank)
                    best = list[i];
            }
            best.focused = true;
            list.sort((a, b) => a.x !== b.x ? a.x - b.x : a.y - b.y);
        }

        byWorkspace = map;

        if (!_reported) {
            _reported = true;
            console.log("WindowTracker: hyprctl listed " + clients.length + " clients, tracking windows on " + Object.keys(map).length + " workspaces");
        }
    }

    Component.onCompleted: refresh()

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

        command: ["hyprctl", "clients", "-j"]

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
