// The network manager: a glass card that drops from the wifi disc.
//   - Click the disc to open; click anywhere else to close.
//   - The header says what you are connected to, and under it the bar's
//     hairline ruler shows the signal: the ticks are lit up to the strength and
//     the accent marker stands on it.
//   - The list is every network in range, the strongest first, the one in use
//     tinted. Click one to join it. A network you have used before (or an open
//     one) just connects; a new locked one opens a password field under it.
//   - Under the list, the VPN row switches the WireGuard tunnel (the
//     wg-quick-wg0 unit) on and off. While it is up, the network in use
//     carries a small "VPN" tag and the header says so.
//   - The foot: Scan looks for networks again, Disconnect drops the current
//     one, and the last button turns the wifi radio off and on.
//
// It talks to NetworkManager through `nmcli`, like the bar's own network
// check. It only asks while it is open or while you act, so a closed popup
// costs nothing. It does not poll: the list is read when it opens, after a
// scan and after every action, and `connectionChanged` tells the bar to look again.
//
// The card is the tray's and the calendar's: Style.card glass, a light
// catching its top edge, and it grows out of the disc with CardFade.

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

PopupWindow {
    id: pop

    // The bar window this hangs from, and the disc it hangs under
    required property var barWindow
    required property Item target

    readonly property bool open: visible
    property double closedAt: 0

    // ---- What NetworkManager says -----------------------------------------
    // [{ ssid, signal (0..100), secure, inUse, saved }], the strongest first
    property var networks: []
    // What the list said last time, to tell when nothing changed
    property string listSig: ""
    property bool radioOn: true
    // The wifi interface (wlan0...), which Disconnect needs
    property string device: ""
    property bool scanning: false
    // The WireGuard tunnel (wg-quick-wg0) is up. SystemStats keeps it current
    // from the bar's five-second check; a switch here sets it at once.
    property bool vpnOn: false
    // The last failure of the VPN switch
    property string vpnError: ""
    // When the last VPN switch finished (ms since 1970). The bar ignores a
    // poll that was already running before it (see SystemStats.parseNet).
    property double vpnSetAt: 0

    // ---- What the person is doing -----------------------------------------
    // The network being joined, and the one whose password field is open
    property string pending: ""
    property string selected: ""
    // The last failure, and the network it belongs to
    property string error: ""
    property string errorFor: ""

    readonly property var current: networks.find(n => n.inUse) ?? null
    readonly property bool working: pending !== "" || actProc.running || vpnProc.running
    // The list scrolls past six rows
    readonly property int maxList: 6 * 36
    readonly property string status: {
        if (pending !== "")
            return "Connecting…";
        if (actProc.running && actProc.kind === "disconnect")
            return "Disconnecting…";
        if (vpnProc.running)
            return vpnProc.want === "start" ? "Connecting VPN…" : "Disconnecting VPN…";
        if (scanning)
            return "Scanning…";
        if (!radioOn)
            return "Wi-Fi off";
        return current ? "Connected  ·  " + current.signal + "%" + (vpnOn ? "  ·  VPN" : "") : "Not connected";
    }

    // Something changed the connection: the bar should check the network again
    signal connectionChanged

    // nmcli escapes ":" and "\" in names with a backslash
    function unesc(s) {
        return s.replace(/\\(.)/g, "$1");
    }

    // Input: four nmcli outputs, each ended by a line with "---":
    //   *:78:WPA2:MyNetwork        IN-USE:SIGNAL:SECURITY:SSID, per access point
    //   MyNetwork:802-11-wireless  NAME:TYPE, per saved connection
    //   enabled                    the wifi radio
    //   wlan0:wifi                 DEVICE:TYPE, per device
    function parseList(raw) {
        const found = new Map();
        const known = [];
        let radio = radioOn;
        let dev = "";
        let section = 0;

        for (const line of raw.split("\n")) {
            if (line === "---") {
                section++;
                continue;
            }
            if (line === "")
                continue;
            if (section === 0) {
                const m = line.match(/^([* ]?):(\d+):([^:]*):(.*)$/);
                const ssid = m ? unesc(m[4]) : "";
                if (ssid === "")
                    continue;
                // The same network seen through several access points is one
                // row: the strongest signal, and in use if any of them is
                const n = found.get(ssid) ?? {
                    "ssid": ssid,
                    "signal": 0,
                    "secure": false,
                    "inUse": false,
                    "saved": false
                };
                n.signal = Math.max(n.signal, parseInt(m[2]));
                n.secure = n.secure || (m[3] !== "" && m[3] !== "--");
                n.inUse = n.inUse || m[1] === "*";
                found.set(ssid, n);
            } else if (section === 1) {
                const m = line.match(/^(.*):([^:]*)$/);
                if (m && m[2] === "802-11-wireless")
                    known.push(unesc(m[1]));
            } else if (section === 2) {
                radio = line.trim() === "enabled";
            } else if (section === 3) {
                const f = line.split(":");
                if (f[1] === "wifi" && dev === "")
                    dev = f[0];
            }
        }

        const list = Array.from(found.values());
        for (const n of list)
            n.saved = known.includes(n.ssid);
        list.sort((a, b) => (b.inUse - a.inUse) || (b.signal - a.signal));
        // Same list as before (a refresh after an action, a scan that found
        // nothing new): keep it, so the rows are not rebuilt for nothing
        const sig = JSON.stringify(list);
        if (sig !== listSig) {
            listSig = sig;
            networks = list;
        }
        radioOn = radio;
        device = dev;
    }

    // Read the list again. Not while a password is being typed: a new list
    // rebuilds the rows, and the field would lose what was typed.
    function refresh() {
        if (selected === "" && !listProc.running)
            listProc.running = true;
    }

    function scan() {
        if (scanning || !radioOn)
            return;
        scanning = true;
        scanProc.running = true;
        // A scan takes a few seconds to come back
        settle.restart();
    }

    // Run `nmcli <args>` and report how it went. The shell prints the exit
    // code on the first line and everything nmcli said after it, so one
    // stream carries both and nothing can arrive out of order. The arguments
    // are passed as words ("$@"), never glued into a command line, so a
    // network called `"; reboot` is only a name.
    function run(kind, args) {
        if (actProc.running)
            return;
        actProc.kind = kind;
        actProc.command = ["sh", "-c", "out=$(nmcli \"$@\" 2>&1); echo \"$?\"; echo \"$out\"", "sh"].concat(args);
        actProc.running = true;
    }

    // Join a network. A saved one is brought up as it is; otherwise nmcli
    // makes a new connection, with the password if one was typed. `-w 20`
    // gives up after 20 seconds instead of nmcli's default 90.
    function joinNetwork(n, password) {
        if (working)
            return;
        error = "";
        errorFor = "";
        pending = n.ssid;
        actProc.ssid = n.ssid;
        // A failed new connection leaves a profile behind, which is removed
        actProc.fresh = !n.saved;
        if (n.saved && !password)
            run("connect", ["-w", "20", "connection", "up", "id", n.ssid]);
        else
            run("connect", ["-w", "20", "device", "wifi", "connect", n.ssid].concat(password ? ["password", password] : []));
    }

    function dropNetwork() {
        if (device !== "")
            run("disconnect", ["device", "disconnect", device]);
    }

    function toggleRadio() {
        run("radio", ["radio", "wifi", radioOn ? "off" : "on"]);
    }

    // Switch the tunnel. `systemctl` asks polkit, and system/wireguard.nix
    // lets wheel do this one unit without a password. The shell prints the
    // exit code on the first line and what systemctl said after it.
    function toggleVpn() {
        if (working)
            return;
        vpnError = "";
        vpnProc.want = vpnOn ? "stop" : "start";
        vpnProc.command = ["sh", "-c", "out=$(systemctl \"$1\" wg-quick-wg0.service 2>&1); echo \"$?\"; echo \"$out\"", "sh", vpnProc.want];
        vpnProc.running = true;
    }

    function vpnDone(raw) {
        const nl = raw.indexOf("\n");
        const code = parseInt(nl < 0 ? raw : raw.slice(0, nl));
        const msg = nl < 0 ? "" : raw.slice(nl + 1).trim();
        if (code === 0) {
            vpnOn = vpnProc.want === "start";
            vpnSetAt = Date.now();
        } else {
            vpnError = /authori[sz]|polkit|denied|interactive/i.test(msg) ? "Not allowed" : (msg.split("\n")[0] || "Could not switch the VPN");
        }
        connectionChanged();
    }

    // A click on a row
    function pick(n) {
        if (working || n.inUse)
            return;
        error = "";
        errorFor = "";
        if (n.saved || !n.secure) {
            selected = "";
            joinNetwork(n, "");
        } else {
            selected = selected === n.ssid ? "" : n.ssid;
        }
    }

    // nmcli finished an action (see run)
    function actionDone(raw) {
        const nl = raw.indexOf("\n");
        const code = parseInt(nl < 0 ? raw : raw.slice(0, nl));
        const msg = nl < 0 ? "" : raw.slice(nl + 1).trim();

        if (actProc.kind === "connect") {
            const ssid = pending;
            pending = "";
            if (code === 0) {
                selected = "";
            } else {
                errorFor = ssid;
                error = /secrets|password|auth/i.test(msg) ? "Wrong password" : (msg.replace(/^Error:\s*/, "").split("\n")[0] || "Could not connect");
                if (actProc.fresh)
                    Quickshell.execDetached(["nmcli", "connection", "delete", "id", ssid]);
            }
        } else if (actProc.kind === "radio" && code === 0) {
            radioOn = !radioOn;
            if (radioOn)
                scan();
        }
        refresh();
        connectionChanged();
    }

    function toggle() {
        if (visible) {
            visible = false;
            return;
        }
        // The click that closed us via the focus grab also lands on the disc
        if (Date.now() - closedAt < 200)
            return;
        selected = "";
        error = "";
        errorFor = "";
        vpnError = "";
        anchor.rect = barWindow.contentItem.mapFromItem(target, 0, 0, target.width, target.height + Style.spaceMd);
        visible = true;
    }

    function close() {
        visible = false;
    }

    visible: false
    color: "transparent"
    implicitWidth: 320
    implicitHeight: card.implicitHeight
    anchor.window: barWindow
    anchor.edges: Edges.Bottom | Edges.Right
    anchor.gravity: Edges.Bottom | Edges.Left
    onVisibleChanged: {
        if (visible) {
            fade.restart();
            refresh();
            // Look at the tunnel again now rather than at the next check
            connectionChanged();
        } else {
            selected = "";
        }
    }

    // ---- nmcli ------------------------------------------------------------
    Process {
        id: listProc

        // The four nmcli calls run side by side (each one is a round trip to
        // NetworkManager), then their answers are printed in the order
        // parseList expects.
        command: ["sh", "-c", `
            d=$(mktemp -d) || exit 1
            nmcli -t -f IN-USE,SIGNAL,SECURITY,SSID device wifi list --rescan no >"$d/1" 2>/dev/null &
            nmcli -t -f NAME,TYPE connection show >"$d/2" 2>/dev/null &
            nmcli radio wifi >"$d/3" 2>/dev/null &
            nmcli -t -f DEVICE,TYPE device >"$d/4" 2>/dev/null &
            wait
            cat "$d/1"
            echo ---
            cat "$d/2"
            echo ---
            cat "$d/3"
            echo ---
            cat "$d/4"
            rm -rf "$d"
        `]

        stdout: StdioCollector {
            onStreamFinished: pop.parseList(text)
        }
    }

    Process {
        id: scanProc

        command: ["nmcli", "device", "wifi", "rescan"]
    }

    // Join, drop or switch the radio (see run). `ssid` and `fresh` remember
    // what a connect was for, to report on it when it ends.
    Process {
        id: actProc

        property string kind: ""
        property string ssid: ""
        property bool fresh: false

        stdout: StdioCollector {
            onStreamFinished: pop.actionDone(text)
        }
    }

    // Start or stop the tunnel (see toggleVpn). `want` remembers which.
    Process {
        id: vpnProc

        property string want: ""

        stdout: StdioCollector {
            onStreamFinished: pop.vpnDone(text)
        }
    }

    // The scan has had time: show what it found
    Timer {
        id: settle

        interval: 3000
        onTriggered: {
            pop.scanning = false;
            pop.refresh();
        }
    }

    // One panel at a time, and closes itself when left alone. It waits while
    // a password is being typed or something is being joined.
    PanelLink {
        win: pop
        name: "network"
        barPopup: true
        idleMs: Style.popupIdleLongMs
        hovered: idleHover.hovered
        busy: pop.working || pop.selected !== ""
    }

    PopupKeys {
        id: popupKeys

        win: pop
    }

    HyprlandFocusGrab {
        windows: [pop]
        active: pop.visible
        onCleared: {
            pop.visible = false;
            pop.closedAt = Date.now();
        }
    }

    // The card grows out of the disc, which is at its top right corner
    CardFade {
        id: fade

        target: card
        fromScale: 0.94
    }

    Rectangle {
        id: card

        // For the idle close: it waits while the pointer is on the card
        HoverHandler {
            id: idleHover
        }

        anchors.fill: parent
        radius: Style.radiusXl
        antialiasing: true
        color: Style.card
        border.width: 1
        border.color: Style.outline
        implicitHeight: col.implicitHeight + 28
        transformOrigin: Item.TopRight

        // Light catching the top edge, as on the bar
        EdgeLight {
            corner: Style.radiusXl
        }

        Column {
            id: col

            x: 14
            y: 14
            width: parent.width - 28
            spacing: Style.spaceMd

            // ---- Header: what you are on, and how strongly -----------------
            Column {
                width: parent.width
                spacing: Style.spaceXs

                Txt {
                    width: parent.width
                    elide: Text.ElideRight
                    text: pop.current ? pop.current.ssid : (pop.radioOn ? "No Wi-Fi connection" : "Wi-Fi is off")
                    color: pop.current ? Colors.foreground : Colors.muted
                    font.pixelSize: Style.fontLg
                    font.bold: true

                    Behavior on color {
                        ColorAnimation {
                            duration: Style.fadeMs
                        }
                    }
                }

                Txt {
                    width: parent.width
                    elide: Text.ElideRight
                    text: pop.status
                    color: pop.pending !== "" ? Colors.accent : Colors.muted
                    font.pixelSize: Style.fontSm
                    font.letterSpacing: 1.4
                    font.capitalization: Font.AllUppercase

                    Behavior on color {
                        ColorAnimation {
                            duration: Style.fadeMs
                        }
                    }
                }
            }

            // The bar's ruler as a signal meter: the ticks up to the signal
            // are lit, the marker stands on it. Its marker glides to a new
            // value, and the lit part follows the marker.
            BarRuler {
                width: parent.width
                inset: 2
                markX: inset + (pop.current ? pop.current.signal : 0) / 100 * (width - inset * 2)
                markOpacity: pop.current ? 1 : 0
                fillX: pop.current ? markX : -1
            }

            // ---- The networks ----------------------------------------------
            ListView {
                id: list

                width: parent.width
                height: visible ? Math.min(contentHeight, pop.maxList) : 0
                visible: pop.radioOn && pop.networks.length > 0
                clip: true
                spacing: 2
                boundsBehavior: Flickable.StopAtBounds
                model: pop.networks

                delegate: Item {
                    id: row

                    required property var modelData

                    // Its password field is open, it is being joined, or it
                    // just failed
                    readonly property bool asking: pop.selected === modelData.ssid
                    readonly property bool connecting: pop.pending === modelData.ssid
                    readonly property bool failed: pop.errorFor === modelData.ssid && pop.error !== ""

                    function submit() {
                        pop.joinNetwork(modelData, pwField.text);
                    }

                    width: list.width
                    // The row, and under it whatever is open (field, error)
                    height: 34 + (extra.implicitHeight > 0 ? extra.implicitHeight + Style.spaceXs : 0)
                    onAskingChanged: if (asking)
                        pwField.forceActiveFocus();
                    else
                        pwField.clear()

                    Rectangle {
                        width: parent.width
                        height: 34
                        radius: Style.radiusLg
                        antialiasing: true
                        // The network in use is faintly lit; hover lifts any row
                        color: row.modelData.inUse ? Qt.alpha(Colors.accent, Style.tintAlpha) : (rowHover.hovered ? Style.hoverFill : "transparent")
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

                        // The same drawn wifi as the disc: arcs lit by signal
                        NetGlyph {
                            x: 10
                            anchors.verticalCenter: parent.verticalCenter
                            width: 16
                            height: 16
                            color: row.modelData.inUse || row.connecting ? Colors.accent : Colors.foreground
                            kind: "wifi"
                            strength: row.modelData.signal
                            vpn: row.modelData.inUse && pop.vpnOn
                        }

                        Txt {
                            anchors.left: parent.left
                            anchors.leftMargin: 36
                            anchors.right: info.left
                            anchors.rightMargin: Style.spaceMd
                            anchors.verticalCenter: parent.verticalCenter
                            elide: Text.ElideRight
                            text: row.modelData.ssid
                            color: row.modelData.inUse || row.connecting ? Colors.accent : Colors.foreground
                            font.pixelSize: Style.fontBase
                        }

                        // What is known about it, on the right
                        Row {
                            id: info

                            anchors.right: parent.right
                            anchors.rightMargin: 10
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: Style.spaceSm

                            Txt {
                                visible: row.connecting
                                text: "Connecting…"
                                color: Colors.accent
                                font.pixelSize: Style.fontSm
                            }
                            Txt {
                                visible: row.modelData.saved && !row.modelData.inUse && !row.connecting
                                text: "Saved"
                                color: Colors.muted
                                font.pixelSize: Style.fontXs
                                font.letterSpacing: 1
                                font.capitalization: Font.AllUppercase
                            }
                            Txt {
                                visible: row.modelData.inUse && pop.vpnOn && !row.connecting
                                text: "VPN"
                                color: Colors.accent
                                font.pixelSize: Style.fontXs
                                font.letterSpacing: 1
                                font.capitalization: Font.AllUppercase
                            }
                            Txt {
                                visible: row.modelData.secure && !row.connecting
                                text: Icons.lock
                                color: Colors.muted
                                font.pixelSize: Style.fontMd
                            }
                            Txt {
                                visible: row.modelData.inUse && !row.connecting
                                text: Icons.check
                                color: Colors.accent
                                font.pixelSize: Style.fontMd
                            }
                        }

                        HoverHandler {
                            id: rowHover

                            cursorShape: Qt.PointingHandCursor
                        }
                        TapHandler {
                            id: rowTap

                            onTapped: pop.pick(row.modelData)
                        }
                    }

                    // The password field and the error, under the row. A
                    // Column only counts what is visible, so with neither
                    // open its height is 0 and the row is just its 34px.
                    Column {
                        id: extra

                        y: 34 + Style.spaceXs
                        width: parent.width
                        spacing: Style.spaceXs

                        Item {
                            width: parent.width
                            height: Style.fieldHeight
                            visible: row.asking

                            SearchField {
                                id: pwField

                                anchors.left: parent.left
                                anchors.right: join.left
                                anchors.rightMargin: Style.spaceSm
                                anchors.verticalCenter: parent.verticalCenter
                                placeholder: "Password"
                                glyph: Icons.lock
                                clearable: false
                                fontSize: Style.fontMd
                                // Dots instead of letters
                                Component.onCompleted: input.echoMode = TextInput.Password
                                onAccepted: if (pwField.text !== "")
                                    row.submit()
                                Keys.onEscapePressed: {
                                    pop.selected = "";
                                    popupKeys.forceActiveFocus();
                                }
                            }

                            TextButton {
                                id: join

                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                compact: true
                                primary: true
                                text: "Join"
                                enabled: pwField.text !== "" && !pop.working
                                onClicked: row.submit()
                            }
                        }

                        Txt {
                            width: parent.width
                            leftPadding: 10
                            visible: row.failed
                            elide: Text.ElideRight
                            text: pop.error
                            color: Colors.critical
                            font.pixelSize: Style.fontSm
                        }
                    }
                }
            }

            // Nothing to list: say why
            Txt {
                width: parent.width
                height: visible ? 56 : 0
                visible: !list.visible
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                text: !pop.radioOn ? "Wi-Fi is off" : (pop.scanning ? "Scanning…" : "No networks found")
                color: Colors.muted
                font.pixelSize: Style.fontMd
            }

            // ---- The VPN ---------------------------------------------------
            // Same shape as a network row: lit in the accent while the tunnel
            // is up, a click switches it.
            Column {
                width: parent.width
                spacing: Style.spaceXs

                Rectangle {
                    width: parent.width
                    height: 34
                    radius: Style.radiusLg
                    antialiasing: true
                    color: pop.vpnOn ? Qt.alpha(Colors.accent, Style.tintAlpha) : (vpnHover.hovered && !pop.working ? Style.hoverFill : "transparent")
                    scale: vpnTap.pressed ? 0.98 : 1
                    opacity: pop.working && !vpnProc.running ? 0.5 : 1

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
                    Behavior on opacity {
                        NumberAnimation {
                            duration: Style.fadeMs
                        }
                    }

                    // The same shield as the bar's badge: solid while the
                    // tunnel is up, an outline while it is off
                    ShieldGlyph {
                        x: 10
                        anchors.verticalCenter: parent.verticalCenter
                        width: 16
                        height: 16
                        color: pop.vpnOn || vpnProc.running ? Colors.accent : Colors.foreground
                        on: pop.vpnOn
                    }

                    Txt {
                        anchors.left: parent.left
                        anchors.leftMargin: 36
                        anchors.right: vpnInfo.left
                        anchors.rightMargin: Style.spaceMd
                        anchors.verticalCenter: parent.verticalCenter
                        elide: Text.ElideRight
                        text: "WireGuard"
                        color: pop.vpnOn || vpnProc.running ? Colors.accent : Colors.foreground
                        font.pixelSize: Style.fontBase
                    }

                    Row {
                        id: vpnInfo

                        anchors.right: parent.right
                        anchors.rightMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Style.spaceSm

                        Txt {
                            visible: vpnProc.running
                            text: vpnProc.want === "start" ? "Connecting…" : "Disconnecting…"
                            color: Colors.accent
                            font.pixelSize: Style.fontSm
                        }
                        Txt {
                            visible: !vpnProc.running && !pop.vpnOn
                            text: "Off"
                            color: Colors.muted
                            font.pixelSize: Style.fontXs
                            font.letterSpacing: 1
                            font.capitalization: Font.AllUppercase
                        }
                        Txt {
                            visible: !vpnProc.running && pop.vpnOn
                            text: Icons.check
                            color: Colors.accent
                            font.pixelSize: Style.fontMd
                        }
                    }

                    HoverHandler {
                        id: vpnHover

                        cursorShape: Qt.PointingHandCursor
                    }
                    TapHandler {
                        id: vpnTap

                        onTapped: pop.toggleVpn()
                    }
                }

                Txt {
                    width: parent.width
                    leftPadding: 10
                    visible: pop.vpnError !== ""
                    elide: Text.ElideRight
                    text: pop.vpnError
                    color: Colors.critical
                    font.pixelSize: Style.fontSm
                }
            }

            // ---- The foot --------------------------------------------------
            Item {
                width: parent.width
                height: Style.buttonCompact

                Row {
                    spacing: Style.spaceSm

                    // Breathes while a scan is out
                    TextButton {
                        compact: true
                        text: "Scan"
                        busy: pop.scanning
                        enabled: pop.radioOn && !pop.scanning && !pop.working
                        onClicked: pop.scan()
                    }
                    TextButton {
                        compact: true
                        visible: pop.current !== null
                        text: "Disconnect"
                        enabled: !pop.working
                        onClicked: pop.dropNetwork()
                    }
                }

                // Lit in the accent when it is the way back from "off"
                TextButton {
                    anchors.right: parent.right
                    compact: true
                    primary: !pop.radioOn
                    text: pop.radioOn ? "Wi-Fi off" : "Wi-Fi on"
                    enabled: !pop.working
                    onClicked: pop.toggleRadio()
                }
            }
        }
    }
}
