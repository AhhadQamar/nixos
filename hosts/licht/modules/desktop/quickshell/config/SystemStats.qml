// The status cluster on the right of the bar, drawn as the dial in miniature:
// a row of small glass discs (updates, CPU, bell, volume, Bluetooth, network,
// battery)
// with a short hairline ruler curving over them. Each disc holds an icon drawn
// in hairline strokes (the *Glyph.qml files) rather than a font glyph. The
// state that drives a picture lives here and is handed to the icon as inputs.
//
// The disc under the pointer is the "selected" one, as in the launcher: it
// takes the accent (outline, soft tint, a breathing ring and a 2px underline),
// opens into a label, and the ruler's 2px accent marker glides over to stand
// above it while the ticks beside the marker rise like a magnifier. Off the
// cluster the marker fades and the ruler rests.
//
// The network disc opens into the download and upload speed on hover, and a
// double tap locks it open (another double tap lets go). A click opens the
// network manager (NetworkPopup.qml): join, disconnect, scan.
//
// The Bluetooth disc is muted while the adapter is off, plain while it is on
// and in the accent while a device is connected; hover for the device's name.
// A click opens the Bluetooth manager (BluetoothPopup.qml): connect, pair,
// forget, scan. A right click switches the adapter on and off. It only exists
// on a machine that has a Bluetooth adapter.
//
// Indicators that only matter sometimes (the update icon, the battery) grow
// in and shrink away instead of popping. CPU load and volume wear the same
// hairline ring the volume OSD draws round its icon.

import QtQuick
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Services.Pipewire
import Quickshell.Services.UPower

Item {
    id: root

    // Room between the cluster's ends and the first / last disc
    readonly property int padding: Style.spaceLg

    implicitHeight: Style.barHeight
    implicitWidth: row.implicitWidth + padding * 2

    // ---- ruler and marker --------------------------------------------------
    // Every disc, left to right. `lit` is the one under the pointer (null when
    // none is): reading `hovered` inside the loop makes this re-run on change.
    readonly property var stops: [updateItem, cpuItem, bellItem, volumeItem, btItem, netItem, batteryItem]
    readonly property Item lit: {
        for (let i = 0; i < stops.length; i++) {
            if (stops[i].hovered)
                return stops[i];
        }
        return null;
    }
    // Where the lit disc's centre is, in the cluster's own pixels. It is a
    // binding, so it follows the disc while it widens to show its label.
    readonly property real litX: lit ? row.x + lit.x + lit.disc.width / 2 : -1

    // The marker stays where it last stood while it fades out. The very first
    // hover snaps it into place (glide is off until then) instead of sweeping
    // in from the left edge.
    property real markX: 0
    property bool placed: false

    onLitXChanged: {
        if (litX < 0)
            return;
        markX = litX;
        placed = true;
    }

    BarRuler {
        anchors.left: parent.left
        anchors.right: parent.right
        y: 2
        inset: root.padding
        markX: root.markX
        markOpacity: root.lit ? 1 : 0
        glide: root.placed
    }

    // ---- audio -----------------------------------------------------------
    readonly property var sink: Pipewire.defaultAudioSink
    readonly property real volume: sink?.audio?.volume ?? 0
    readonly property bool muted: sink?.audio?.muted ?? false

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

    // ---- bluetooth -------------------------------------------------------
    // There is no disc on a machine without an adapter
    readonly property var btAdapter: Bluetooth.defaultAdapter
    readonly property bool btPresent: btAdapter !== null
    readonly property bool btOn: btAdapter?.enabled ?? false
    // Every device that is connected now
    readonly property var btLinked: (btAdapter?.devices?.values ?? []).filter(d => d.connected)
    readonly property bool btConnected: btLinked.length > 0

    function toggleBluetooth() {
        if (btAdapter)
            btAdapter.enabled = !btAdapter.enabled;
    }

    // ---- network ---------------------------------------------------------
    property string netKind: "none" // "wifi" | "ethernet" | "none"
    property int netSignal: 0
    property string netName: ""
    // The WireGuard tunnel is up; the flag lives on the network popup, which
    // can also switch it
    property alias vpnOn: netMenu.vpnOn

    // The network just came back: a scheduled update check that failed while
    // offline can run again now
    onNetKindChanged: if (netKind !== "none")
        Updater.networkBack()

    // Input is three outputs separated by a line with "---":
    //   wifi:connected            <- TYPE:STATE for every device
    //   ---
    //   *:78:MyNetwork            <- IN-USE:SIGNAL:SSID for every access point
    //   ---
    //   up                        <- only if the WireGuard tunnel is active
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
        // Third part: "up" when the wg0 interface exists. Only trust it if
        // this run started after the last switch in the network popup;
        // otherwise it may describe the tunnel from before the switch.
        if (netProc.startedAt >= netMenu.vpnSetAt)
            vpnOn = (parts[2] || "").indexOf("up") >= 0;
    }

    Process {
        id: netProc

        // When this run began (ms since 1970). A run that began before the
        // last VPN switch has an out-of-date answer about the tunnel, see
        // parseNet. `onRunningChanged` fires every time `running` changes.
        property double startedAt: 0
        onRunningChanged: if (running)
            startedAt = Date.now()

        // The access-point list is only asked for while wifi is connected
        command: ["sh", "-c", "d=$(nmcli -t -f TYPE,STATE device); echo \"$d\"; echo ---; case \"$d\" in *wifi:connected*) nmcli -t -f IN-USE,SIGNAL,SSID device wifi list --rescan no 2>/dev/null;; esac; echo ---; [ -d /sys/class/net/wg0 ] && echo up"]

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

    // Download and upload speed. It only reads while the network disc is open
    // (hovered or locked), so it costs nothing the rest of the time.
    NetSpeed {
        id: netSpeed

        active: netItem.open && netItem.online
    }

    // The network manager, opened by a click on the network disc. When it
    // changes the connection, the bar looks at the network again at once
    // instead of waiting for the next five-second check.
    NetworkPopup {
        id: netMenu

        barWindow: root.QsWindow.window
        target: netItem.disc
        onConnectionChanged: if (!netProc.running)
            netProc.running = true
    }

    // The Bluetooth manager, opened by a click on the Bluetooth disc
    BluetoothPopup {
        id: btMenu

        barWindow: root.QsWindow.window
        target: btItem.disc
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

    readonly property color batColor: charging ? Colors.success : (batPercent <= 15 ? Colors.critical : Colors.foreground)

    // ---- output picker (right click the volume item) --------------------
    // Every audio output; the one in use is ticked
    readonly property var outputs: Pipewire.nodes.values.filter(n => n.isSink && !n.isStream)

    PopupWindow {
        id: sinkMenu

        property double closedAt: 0

        function toggle() {
            if (visible) {
                visible = false;
                return;
            }
            if (Date.now() - closedAt < 200)
                return;
            const win = root.QsWindow.window;
            anchor.rect = win.contentItem.mapFromItem(volumeItem.disc, 0, 0, volumeItem.disc.width, volumeItem.disc.height + Style.spaceMd);
            visible = true;
        }

        function close() {
            visible = false;
        }

        visible: false
        color: "transparent"
        implicitWidth: 300
        implicitHeight: outputList.implicitHeight + 12
        anchor.window: root.QsWindow.window
        anchor.edges: Edges.Bottom | Edges.Right
        anchor.gravity: Edges.Bottom | Edges.Left
        onVisibleChanged: if (visible)
            menuFade.restart()

        PanelLink {
            win: sinkMenu
            name: "volume"
            barPopup: true
            idleMs: Style.popupIdleMs
            hovered: menuHover.hovered
        }

        PopupKeys {
            id: popupKeys

            win: sinkMenu
        }

        HyprlandFocusGrab {
            windows: [sinkMenu]
            active: sinkMenu.visible
            onCleared: {
                sinkMenu.visible = false;
                sinkMenu.closedAt = Date.now();
            }
        }

        CardFade {
            id: menuFade

            target: menuCard
        }

        Rectangle {
            id: menuCard

            HoverHandler {
                id: menuHover
            }

            anchors.fill: parent
            radius: Style.radiusXl
            antialiasing: true
            color: Style.card
            border.width: 1
            border.color: Style.outline

            EdgeLight {
                corner: Style.radiusXl
            }

            Column {
                id: outputList

                x: 6
                y: 6
                width: parent.width - 12
                spacing: 2

                Txt {
                    visible: root.outputs.length === 0
                    height: visible ? 34 : 0
                    verticalAlignment: Text.AlignVCenter
                    leftPadding: 10
                    text: "No audio outputs found"
                    color: Colors.muted
                    font.pixelSize: Style.fontBase
                }

                Repeater {
                    model: root.outputs

                    delegate: Rectangle {
                        id: outRow

                        required property var modelData
                        readonly property bool current: modelData.id === Pipewire.defaultAudioSink?.id

                        width: outputList.width
                        height: 34
                        radius: Style.radiusLg
                        // The output in use is faintly lit; hover lifts any row
                        color: rowHover.hovered ? Style.hoverFill : (current ? Qt.alpha(Colors.accent, Style.tintAlpha) : "transparent")
                        scale: rowTap.pressed ? 0.98 : 1

                        Behavior on color {
                            ColorAnimation {
                                duration: Style.fadeMs
                            }
                        }
                        Behavior on scale {
                            NumberAnimation {
                                duration: Style.pressMs
                                easing.type: Style.easePress
                            }
                        }

                        Txt {
                            anchors.left: parent.left
                            anchors.leftMargin: 10
                            anchors.right: tick.left
                            anchors.rightMargin: 8
                            anchors.verticalCenter: parent.verticalCenter
                            elide: Text.ElideRight
                            text: outRow.modelData.description || outRow.modelData.nickname || outRow.modelData.name
                            color: outRow.current ? Colors.accent : Colors.foreground
                            font.pixelSize: Style.fontBase
                        }

                        Txt {
                            id: tick

                            anchors.right: parent.right
                            anchors.rightMargin: 10
                            anchors.verticalCenter: parent.verticalCenter
                            visible: outRow.current
                            text: Icons.check
                            color: Colors.accent
                            font.pixelSize: Style.fontMd
                        }

                        HoverHandler {
                            id: rowHover

                            cursorShape: Qt.PointingHandCursor
                        }

                        TapHandler {
                            id: rowTap

                            onTapped: {
                                Pipewire.preferredDefaultAudioSink = outRow.modelData;
                                sinkMenu.close();
                            }
                        }
                    }
                }
            }
        }
    }

    // ---- items -----------------------------------------------------------
    // The discs, left to right. The row is as tall as the bar, so its x/y are
    // the cluster's own and the ruler marker can be placed from them.
    Row {
        id: row

        x: root.padding
        spacing: Style.spaceMd

        // Update indicator: only shows when there is something to tell. The
        // picture is the Updater's state, in the order it matters: busy, then
        // failed, then an update waiting, then a reboot pending.
        StatItem {
            id: updateItem

            readonly property bool failed: Updater.error !== ""
            // Not called `state`: every Item already has a property by that name
            readonly property string mode: Updater.busy ? "busy" : failed ? "failed" : Updater.available ? "available" : "reboot"

            present: Updater.busy || Updater.available || failed || Updater.rebootPending
            label: Updater.summary
            iconColor: failed ? Colors.critical : (Updater.available || Updater.busy ? Colors.accent : Colors.foreground)
            badge: Updater.available && !Updater.busy
            // While it builds, the ring around the picture fills with the
            // progress (none until there is something to estimate from)
            ring: Updater.progress
            // A new state swells the picture while the two pictures cross-fade
            glyphKey: mode

            // Arrows, tray, triangle or restart arrow (UpdateGlyph.qml). The
            // arrows only turn while busy.
            glyph: Component {
                UpdateGlyph {
                    color: updateItem.iconColor
                    mode: updateItem.mode
                }
            }

            onClicked: Panels.toggleUpdater()
        }

        // CPU, memory and temperature: the ring is the CPU load, hover for the
        // numbers, red when it runs hot.
        StatItem {
            id: cpuItem

            readonly property bool hot: Sysinfo.cpuPercent >= 90 || Sysinfo.temp >= 85

            label: "CPU " + Sysinfo.cpuPercent + "%  ·  RAM " + Sysinfo.memUsed.toFixed(1) + "G" + (Sysinfo.temp > 0 ? "  ·  " + Sysinfo.temp + "°C" : "")
            iconColor: hot ? Colors.critical : Colors.foreground
            labelColor: hot ? Colors.critical : Colors.foreground
            ring: Sysinfo.cpuPercent / 100
            ringColor: hot ? Colors.critical : Colors.accent
            // Running hot swells the chip as it changes colour
            glyphKey: hot

            // A drawn chip (CpuGlyph.qml), in the 14px box because of the ring
            glyph: Component {
                CpuGlyph {
                    color: cpuItem.iconColor
                }
            }
        }

        // Bell: click opens the notification centre, right click toggles Do Not
        // Disturb. It swings once when a notification arrives.
        StatItem {
            id: bellItem

            readonly property bool dnd: NotificationServer.doNotDisturb
            readonly property int unread: NotificationServer.unread

            label: dnd ? "Silent" : (unread > 0 ? unread + " new" : "")
            iconColor: dnd ? Colors.muted : Colors.foreground
            badge: unread > 0 && !dnd
            // Do Not Disturb swells the picture; the swing is the bell's own
            glyphKey: dnd

            // A drawn bell that swings on a new notification (BellGlyph.qml)
            glyph: Component {
                BellGlyph {
                    color: bellItem.iconColor
                    unread: bellItem.unread
                    dnd: bellItem.dnd
                }
            }

            onClicked: Panels.toggleNotifications()
            onRightClicked: NotificationServer.toggleDnd()
        }

        // Volume: click mutes, scroll changes it, right click picks the output.
        // The ring is the volume, the same one the OSD shows.
        StatItem {
            id: volumeItem

            label: root.muted ? "Muted" : Math.round(root.volume * 100) + "%"
            iconColor: root.muted ? Colors.muted : Colors.foreground
            labelColor: root.muted ? Colors.muted : Colors.foreground
            ring: root.muted ? 0 : root.volume
            ringColor: root.muted ? Colors.muted : (root.volume > 1 ? Colors.critical : Colors.accent)
            // Muting swells the picture; the waves fade by themselves
            glyphKey: root.muted

            // A drawn speaker with waves (VolumeGlyph.qml). It is drawn in the
            // 14px box because this disc has the ring.
            glyph: Component {
                VolumeGlyph {
                    color: volumeItem.iconColor
                    level: root.volume
                    muted: root.muted
                }
            }

            onClicked: root.toggleMute()
            onRightClicked: sinkMenu.toggle()
            onScrolled: delta => root.nudgeVolume(delta)
        }

        // Bluetooth: click opens the manager, right click switches the adapter.
        // Hover says what is connected.
        StatItem {
            id: btItem

            present: root.btPresent
            label: !root.btOn ? "Off" : (root.btConnected ? root.btLinked[0].name + (root.btLinked.length > 1 ? "  +" + (root.btLinked.length - 1) : "") : "On")
            iconColor: !root.btOn ? Colors.muted : (root.btConnected ? Colors.accent : Colors.foreground)
            labelColor: !root.btOn ? Colors.muted : Colors.foreground
            // Switching on or off, or a device linking, swells the picture
            glyphKey: root.btOn + ":" + root.btConnected

            // The rune, slashed when off, with link dots when connected
            // (BluetoothGlyph.qml)
            glyph: Component {
                BluetoothGlyph {
                    color: btItem.iconColor
                    powered: root.btOn
                    linked: root.btConnected
                }
            }

            onClicked: btMenu.toggle()
            onRightClicked: root.toggleBluetooth()
        }

        // Network: hover for the speeds, double tap to keep them showing
        StatItem {
            id: netItem

            // Locked open by a double tap
            property bool locked: false
            readonly property bool online: root.netKind !== "none"

            // Offline there is nothing to measure, so it still says "Offline"
            label: online ? netSpeed.text : root.netName
            labelSizer: online ? netSpeed.sizer : ""
            alwaysShowLabel: locked
            iconColor: root.netKind === "none" ? Colors.muted : Colors.foreground
            // Signal strength glides by itself; only a change of kind swells the picture
            glyphKey: root.netKind

            // Arcs lit by signal, a port, or a slashed dot (NetGlyph.qml)
            glyph: Component {
                NetGlyph {
                    color: netItem.iconColor
                    kind: root.netKind
                    strength: root.netSignal
                    vpn: root.vpnOn
                }
            }

            // A click opens the manager. The first tap of a double tap does
            // too, but the second tap's click closes it again (the focus grab
            // clears it), as the lock flips.
            onClicked: netMenu.toggle()
            onDoubleClicked: {
                locked = !locked;
                netMenu.close();
            }
        }

        StatItem {
            id: batteryItem

            present: root.hasBattery
            label: root.batPercent + "%"
            iconColor: root.batColor
            labelColor: root.batColor
            alwaysShowLabel: true
            // The fill glides by itself; only plugging in swells the picture
            glyphKey: root.charging

            // A drawn cell filled to the charge (BatteryGlyph.qml). It takes
            // its colour from the disc, so batColor stays the one rule.
            glyph: Component {
                BatteryGlyph {
                    color: batteryItem.iconColor
                    level: root.batLevel
                    charging: root.charging
                }
            }
        }
    }
}
