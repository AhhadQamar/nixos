import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import Quickshell.Services.UPower

Island {
    id: root

    padding: 14
    spacing: 10

    // ---- audio -----------------------------------------------------------
    readonly property var sink: Pipewire.defaultAudioSink
    readonly property real volume: sink?.audio?.volume ?? 0
    readonly property bool muted: sink?.audio?.muted ?? false
    readonly property int audioGlyph: muted ? 0xF0581 : volume < 0.34 ? 0xF057F : volume < 0.67 ? 0xF0580 : 0xF057E

    // Pipewire objects only report volume/mute while something tracks them.
    PwObjectTracker {
        objects: [root.sink]
    }

    function toggleMute() {
        if (sink?.audio)
            sink.audio.muted = !sink.audio.muted;
    }

    function nudgeVolume(delta) {
        if (!sink?.audio)
            return;
        const step = delta > 0 ? 0.05 : -0.05;
        sink.audio.volume = Math.max(0, Math.min(1, sink.audio.volume + step));
    }

    // ---- network ---------------------------------------------------------
    property string netKind: "none" // "wifi" | "ethernet" | "none"
    property int netSignal: 0
    property string netName: ""

    readonly property int netGlyph: {
        if (netKind === "ethernet")
            return 0xF0200;
        if (netKind === "wifi")
            return netSignal >= 75 ? 0xF0928 : netSignal >= 50 ? 0xF0925 : netSignal >= 25 ? 0xF0922 : 0xF091F;
        return 0xF092D; // wifi_strength_off
    }

    // Input is two nmcli outputs separated by a line with "---":
    //   wifi:connected            <- TYPE:STATE for every device
    //   ---
    //   *:78:MyNetwork            <- IN-USE:SIGNAL:SSID for every access point
    function parseNet(raw) {
        const parts = raw.split("---");
        let wifi = false;
        let eth = false;

        const devices = (parts[0] || "").split("\n");
        for (let i = 0; i < devices.length; i++) {
            const f = devices[i].split(":");
            const connected = (f[1] || "").indexOf("connected") === 0;
            if (f[0] === "wifi" && connected)
                wifi = true;
            if (f[0] === "ethernet" && connected)
                eth = true;
        }

        let signal = 0;
        let name = "";
        const aps = (parts[1] || "").split("\n");
        for (let i = 0; i < aps.length; i++) {
            // nmcli escapes ":" inside the SSID as "\:".
            const m = aps[i].match(/^\*:(\d+):(.*)$/);
            if (m) {
                signal = parseInt(m[1]);
                name = m[2].replace(/\\:/g, ":");
                break;
            }
        }

        netKind = eth ? "ethernet" : (wifi ? "wifi" : "none");
        netSignal = signal;
        netName = eth ? "Ethernet" : (wifi ? name : "Offline");
    }

    Process {
        id: netProc

        command: ["sh", "-c", "nmcli -t -f TYPE,STATE device; echo ---; nmcli -t -f IN-USE,SIGNAL,SSID device wifi list --rescan no 2>/dev/null"]

        stdout: StdioCollector {
            onStreamFinished: root.parseNet(text)
        }
    }

    Timer {
        interval: 5000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: if (!netProc.running)
            netProc.running = true
    }

    // ---- battery ---------------------------------------------------------
    readonly property var bat: UPower.displayDevice
    readonly property bool hasBattery: bat?.isPresent ?? false
    readonly property real batLevel: {
        const p = bat?.percentage ?? 0;
        return p > 1 ? p / 100 : p;
    }
    readonly property int batPercent: Math.round(batLevel * 100)
    readonly property bool charging: bat ? bat.state === UPowerDeviceState.Charging : false

    readonly property var batGlyphs: [0xF007A, 0xF007B, 0xF007C, 0xF007D, 0xF007E, 0xF007F, 0xF0080, 0xF0081, 0xF0082, 0xF0079]
    readonly property var batChargingGlyphs: [0xF089C, 0xF0086, 0xF0087, 0xF0088, 0xF089D, 0xF0089, 0xF089E, 0xF008A, 0xF008B, 0xF0085]
    readonly property int batBucket: Math.min(10, Math.max(1, Math.round(batPercent / 10))) - 1
    readonly property int batGlyph: charging ? batChargingGlyphs[batBucket] : batGlyphs[batBucket]
    readonly property color batColor: charging ? Colors.success : (batPercent <= 15 ? Colors.critical : Colors.foreground)

    // ---- items -----------------------------------------------------------
    // Update indicator: only shows when there is something to tell. Glyphs:
    // 0xF04E6 sync, 0xF05D6 alert, 0xF06B0 update, 0xF0709 restart.
    StatItem {
        readonly property bool failed: Updater.error !== ""

        visible: Updater.busy || Updater.available || failed || Updater.rebootPending
        icon: String.fromCodePoint(Updater.busy ? 0xF04E6 : failed ? 0xF05D6 : Updater.available ? 0xF06B0 : 0xF0709)
        label: Updater.summary
        iconColor: failed ? Colors.critical : (Updater.available || Updater.busy ? Colors.accent : Colors.foreground)
        badge: Updater.available && !Updater.busy

        onClicked: Panels.toggleUpdater()
    }

    // Bell: click opens the notification centre, right click toggles Do Not
    // Disturb. 0xF009C bell-outline, 0xF009B bell-off.
    StatItem {
        readonly property bool dnd: NotificationServer.doNotDisturb
        readonly property int unread: NotificationServer.unread

        icon: String.fromCodePoint(dnd ? 0xF009B : 0xF009C)
        label: dnd ? "Silent" : (unread > 0 ? unread + " new" : "")
        iconColor: dnd ? Colors.muted : Colors.foreground
        badge: unread > 0 && !dnd

        onClicked: Panels.toggleNotifications()
        onRightClicked: NotificationServer.toggleDnd()
    }

    StatItem {
        icon: String.fromCodePoint(root.audioGlyph)
        label: root.muted ? "Muted" : Math.round(root.volume * 100) + "%"
        iconColor: root.muted ? Colors.muted : Colors.foreground
        labelColor: root.muted ? Colors.muted : Colors.foreground

        onClicked: root.toggleMute()
        onScrolled: delta => root.nudgeVolume(delta)
    }

    StatItem {
        icon: String.fromCodePoint(root.netGlyph)
        label: root.netName
        iconColor: root.netKind === "none" ? Colors.muted : Colors.foreground
    }

    StatItem {
        visible: root.hasBattery
        icon: String.fromCodePoint(root.batGlyph)
        label: root.batPercent + "%"
        iconColor: root.batColor
        labelColor: root.batColor
        alwaysShowLabel: true
    }
}
