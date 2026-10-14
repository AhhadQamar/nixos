// Backend for the package search: a local index of the nixpkgs your flake is
// pinned to (so results are what you can actually install), instant search over
// it, details for the selected package, and the actions on it.

pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    // ---- Settings -------------------------------------------------------
    // Folders and programs come from Config.qml
    readonly property string home: Config.home
    readonly property string flakeDir: Config.flakeDir
    readonly property string homeFile: flakeDir + "/hosts/licht/home.nix"
    readonly property string dir: (Quickshell.env("XDG_CACHE_HOME") || home + "/.cache") + "/qs-nixsearch"
    readonly property string terminal: Config.terminal

    // ---- State ----------------------------------------------------------
    property string query: ""
    // [{ attr, version, desc }]
    property var results: []
    property bool searching: false

    // The index
    property int indexCount: 0
    property real indexTime: 0
    property string ref: ""
    property bool building: false
    property string buildNote: ""
    readonly property bool ready: indexCount > 0

    // The selected package
    property string selected: ""
    // { homepage, license, mainProgram, unfree, broken, longDescription }
    property var info: ({})
    property bool infoLoaded: false
    property bool listed: false
    property bool addArmed: false
    property string message: ""

    readonly property var current: {
        for (const r of results)
            if (r.attr === selected)
                return r;
        return null;
    }

    // Short nixpkgs revision, for the footer
    readonly property string refShort: ref.indexOf("/") >= 0 ? ref.split("/").pop().slice(0, 7) : ref

    // ---- Helpers --------------------------------------------------------
    function age(sec) {
        const d = Math.max(0, Date.now() / 1000 - sec);
        if (d < 3600)
            return Math.max(1, Math.round(d / 60)) + " min ago";
        if (d < 86400)
            return Math.round(d / 3600) + " h ago";
        const days = Math.round(d / 86400);
        return days + (days === 1 ? " day ago" : " days ago");
    }

    function say(text) {
        message = text;
        messageTimer.restart();
    }

    // The flake reference commands use: pinned to your lock when the index knows it
    readonly property string flakeRef: ref !== "" ? ref : "nixpkgs"

    // ---- Search ---------------------------------------------------------
    property string ranQuery: ""
    property bool again: false

    function setQuery(q) {
        query = q;
        searchTimer.restart();
    }

    function runSearch() {
        if (!ready)
            return;
        if (query.trim() === "") {
            results = [];
            select("");
            return;
        }
        if (searchProc.running) {
            again = true;
            return;
        }
        searching = true;
        ranQuery = query;
        searchProc.running = true;
    }

    function onSearch(text) {
        const rows = [];
        for (const line of text.split("\n")) {
            const f = line.split("\t");
            if (f.length >= 2 && f[0] !== "")
                rows.push({
                    attr: f[0],
                    version: f[1],
                    desc: f[2] || ""
                });
        }
        results = rows;
        searching = false;
        if (again || ranQuery !== query) {
            again = false;
            runSearch();
            return;
        }
        if (!rows.some(r => r.attr === selected))
            select(rows.length > 0 ? rows[0].attr : "");
    }

    // ---- Details --------------------------------------------------------
    property string infoFor: ""
    property bool infoDirty: false

    function select(attr) {
        if (attr === selected)
            return;
        selected = attr;
        info = ({});
        infoLoaded = false;
        listed = false;
        addArmed = false;
        if (attr !== "")
            loadInfo();
    }

    function loadInfo() {
        if (infoProc.running) {
            infoDirty = true;
            return;
        }
        infoFor = selected;
        infoProc.running = true;
    }

    function onInfo(text) {
        if (infoFor === selected) {
            const lines = text.split("\n");
            listed = lines.length > 0 && lines[0].trim() === "listed=1";
            let meta = ({});
            try {
                meta = JSON.parse(lines.slice(1).join("").trim() || "{}");
            } catch (e) {}
            info = meta;
            infoLoaded = true;
        }
        if (infoDirty || infoFor !== selected) {
            infoDirty = false;
            if (selected !== "")
                loadInfo();
        }
    }

    // ---- Actions --------------------------------------------------------
    // A throwaway shell with the package, in a terminal
    function tryShell(attr) {
        if (attr === "")
            return;
        Quickshell.execDetached([terminal, "-e", "env", "NIXPKGS_ALLOW_UNFREE=1", "nix", "shell", "--impure", flakeRef + "#" + attr]);
    }

    // Run the package's main program, in a terminal
    function tryRun(attr) {
        if (attr === "")
            return;
        Quickshell.execDetached([terminal, "-e", "env", "NIXPKGS_ALLOW_UNFREE=1", "nix", "run", "--impure", flakeRef + "#" + attr]);
    }

    function copy(text) {
        Quickshell.execDetached(["wl-copy", text]);
        say("Copied " + text);
    }

    function openHomepage() {
        if (info.homepage)
            Quickshell.execDetached(["xdg-open", info.homepage]);
    }

    // Two presses: the first arms, the second edits home.nix
    function addToHome() {
        if (selected === "" || listed || addProc.running)
            return;
        if (!addArmed) {
            addArmed = true;
            armTimer.restart();
            return;
        }
        addArmed = false;
        addFor = selected;
        addProc.running = true;
    }

    property string addFor: ""

    // ---- Index ----------------------------------------------------------
    function refreshStatus() {
        statusProc.running = true;
    }

    function buildIndex() {
        if (building)
            return;
        building = true;
        buildNote = "Starting…";
        buildProc.running = true;
    }

    Component.onCompleted: refreshStatus()

    Timer {
        id: searchTimer

        interval: 180
        onTriggered: root.runSearch()
    }
    Timer {
        id: armTimer

        interval: 4000
        onTriggered: root.addArmed = false
    }
    Timer {
        id: messageTimer

        interval: 6000
        onTriggered: root.message = ""
    }

    Process {
        id: statusProc

        command: ["bash", Quickshell.shellPath("nixsearch/status.sh"), root.dir]
        stdout: StdioCollector {
            onStreamFinished: {
                const f = text.trim().split("\t");
                if (f.length >= 2) {
                    root.indexCount = parseInt(f[0]) || 0;
                    root.indexTime = parseInt(f[1]) || 0;
                    root.ref = f[2] || "";
                    if (root.query.trim() !== "")
                        root.runSearch();
                }
            }
        }
    }

    Process {
        id: buildProc

        command: ["bash", Quickshell.shellPath("nixsearch/index.sh"), root.flakeDir, root.dir]
        stdout: SplitParser {
            onRead: data => root.buildNote = data
        }
        onExited: (exitCode, exitStatus) => {
            root.building = false;
            if (exitCode === 0)
                root.refreshStatus();
            else
                root.say("Indexing failed: " + root.buildNote);
        }
    }

    Process {
        id: searchProc

        command: ["bash", Quickshell.shellPath("nixsearch/search.sh"), root.dir + "/index.tsv", root.ranQuery]
        stdout: StdioCollector {
            onStreamFinished: root.onSearch(text)
        }
    }

    Process {
        id: infoProc

        command: ["bash", Quickshell.shellPath("nixsearch/info.sh"), root.flakeRef, root.infoFor, root.homeFile]
        stdout: StdioCollector {
            onStreamFinished: root.onInfo(text)
        }
    }

    Process {
        id: addProc

        command: ["bash", Quickshell.shellPath("nixsearch/addpkg.sh"), root.homeFile, root.addFor]
        stdout: StdioCollector {
            onStreamFinished: {
                root.say(text.trim());
                root.loadInfo();
            }
        }
    }
}
