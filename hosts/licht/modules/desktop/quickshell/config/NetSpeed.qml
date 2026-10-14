// Download and upload speed of the connection in use, for the network disc's
// label (SystemStats.qml). It is a plain component, not a singleton, so every
// bar has its own and switches it on and off by itself.
//
// Linux counts every byte an interface has ever moved in /proc/net/dev. A
// speed is the difference between two readings divided by the time between
// them, so nothing can be shown until the second reading: `ready` says when.
//
// `active` is the only switch: the timer and the reading only run while it is
// true (the disc is hovered or locked open), so a calm bar costs nothing. The
// second reading comes quickly (250ms) so the label has numbers while the pill
// is still opening, then it settles to one a second.

import QtQuick
import Quickshell.Io

Item {
    id: root

    property bool active: false

    // Bytes per second, and whether they are real yet
    property real down: 0
    property real up: 0
    property bool ready: false

    // The last reading: { iface, rx, tx, t }, or null before the first
    property var prev: null

    // The speeds the label shows: they glide to each new reading instead of
    // jumping, so the numbers count up or down. Plain `property real` because
    // they have a Behavior.
    property real shownDown: down
    property real shownUp: up

    Behavior on shownDown {
        NumberAnimation {
            duration: Style.moveMs
            easing.type: Style.easeMove
        }
    }
    Behavior on shownUp {
        NumberAnimation {
            duration: Style.moveMs
            easing.type: Style.easeMove
        }
    }

    // What the label says, and the widest it can get (StatItem keeps that
    // much room, so the pill does not twitch as the digits change)
    readonly property string text: ready ? "↓ " + format(shownDown) + "  ↑ " + format(shownUp) : "↓ –  ↑ –"
    readonly property string sizer: "↓ 888 MB/s  ↑ 888 MB/s"

    // Bytes per second as KB/s, MB/s or GB/s, one decimal below 10
    function format(bytes) {
        let v = bytes / 1024;
        let unit = "KB/s";
        if (v >= 1000) {
            v /= 1024;
            unit = "MB/s";
        }
        if (v >= 1000) {
            v /= 1024;
            unit = "GB/s";
        }
        return v.toFixed(v < 10 ? 1 : 0) + " " + unit;
    }

    // Input: "<interface> <rx bytes> <tx bytes>", or nothing when there is no
    // default route. Switching interface (wifi to ethernet) starts again,
    // because the two counters are not comparable.
    function parse(raw) {
        const f = raw.trim().split(/\s+/);
        if (f.length < 3) {
            prev = null;
            ready = false;
            return;
        }
        const now = Date.now();
        const rx = Number(f[1]);
        const tx = Number(f[2]);
        // A counter that went backwards was reset: also a fresh start
        if (prev && prev.iface === f[0] && now > prev.t && rx >= prev.rx && tx >= prev.tx) {
            const secs = (now - prev.t) / 1000;
            down = (rx - prev.rx) / secs;
            up = (tx - prev.tx) / secs;
            ready = true;
        } else {
            ready = false;
        }
        prev = {
            "iface": f[0],
            "rx": rx,
            "tx": tx,
            "t": now
        };
    }

    // Switched off: forget the last reading, or the first one after the next
    // hover would be averaged over however long it was off
    onActiveChanged: if (!active) {
        prev = null;
        ready = false;
    }

    // The interface of the default route (`ip route` prints "default via X dev
    // wlan0 ..."; the 5th word is the name), then that interface's line of
    // /proc/net/dev. The sed turns the colon after the name into a space:
    // with big numbers the two touch ("eth0:12345678"). In that line, field 2
    // is bytes received and field 10 is bytes sent.
    Process {
        id: proc

        command: ["sh", "-c", `
            i=$(ip route show default 2>/dev/null | awk '{print $5; exit}')
            [ -n "$i" ] && sed 's/:/ /' /proc/net/dev | awk -v i="$i" '$1 == i {print $1, $2, $10}'
        `]

        stdout: StdioCollector {
            onStreamFinished: root.parse(text)
        }
    }

    // One reading is not a speed yet, so until the second one the timer ticks
    // fast: `prev` is set (there is a first reading) but `ready` is not
    Timer {
        interval: root.prev && !root.ready ? 250 : 1000
        running: root.active
        repeat: true
        triggeredOnStart: true
        onTriggered: if (!proc.running)
            proc.running = true
    }
}
