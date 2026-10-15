// The Bluetooth manager: a glass card that drops from the Bluetooth disc.
//   - Click the disc to open; click anywhere else to close.
//   - The header says what you are connected to. Under it the bar's hairline
//     ruler shows the battery of the first connected device that reports one:
//     the ticks up to the charge are lit and the accent marker stands on it.
//   - The list is every device: connected ones first (tinted), then devices
//     you have paired, then devices nearby that you have not. Click one to
//     connect it, disconnect it, or (a new one) pair it. Pairing also trusts
//     the device and connects it, so it comes back by itself next time.
//   - Right-click a device you have paired to forget it (it asks first).
//   - The foot: Scan looks for devices again, Disconnect drops every
//     connected one, and the last button switches the adapter on and off.
//
// It talks to BlueZ through Quickshell's own Bluetooth module, so it has no
// polling and no helper process: the list and every state in it are live. It
// scans while it is open (so what is nearby shows up by itself) and stops
// when it closes.
//
// Pairing needs the device to agree without a code (headphones, speakers,
// mice and most phones do). A device that asks for a PIN or a passkey needs a
// BlueZ agent running, which this popup is not; it says so when pairing does
// not finish.
//
// The card is the network popup's: Style.card glass, a light catching its top
// edge, and it grows out of the disc with CardFade.

import QtQuick
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Hyprland

PopupWindow {
    id: pop

    // The bar window this hangs from, and the disc it hangs under
    required property var barWindow
    required property Item target

    readonly property bool open: visible
    property double closedAt: 0

    // ---- What BlueZ says --------------------------------------------------
    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property bool powered: adapter?.enabled ?? false
    readonly property bool scanning: adapter?.discovering ?? false

    // Connected first, then paired, then nearby; by name inside each group.
    // Devices with no name are skipped (they are only an address), and a
    // nearby device only shows while scanning or while it is being paired.
    readonly property var list: {
        const all = adapter?.devices?.values ?? [];
        const rank = d => d.connected ? 0 : (d.paired ? 1 : 2);
        return all.filter(d => (d.name ?? "") !== "" && (d.paired || d.connected || scanning || d === wantDevice)).sort((a, b) => rank(a) - rank(b) || a.name.localeCompare(b.name));
    }
    // The list changes when something is added, removed, renamed, paired or
    // connected. This string says so, and the ListView is only given a new
    // model when it changes, so its rows are not rebuilt for nothing.
    readonly property string listSig: list.map(d => d.address + ":" + (d.connected ? 2 : d.paired ? 1 : 0) + ":" + d.name).join("|")
    property var shown: []
    onListSigChanged: shown = list
    Component.onCompleted: shown = list

    readonly property var connected: list.filter(d => d.connected)
    // The first connected device that says how full its battery is
    readonly property var batDev: connected.find(d => d.batteryAvailable) ?? null
    readonly property real batLevel: {
        const b = batDev?.battery ?? 0;
        return Math.max(0, Math.min(1, b > 1 ? b / 100 : b));
    }

    // ---- What the person is doing -----------------------------------------
    // The device being connected or paired, what for ("connect" or "pair"),
    // and the one whose "forget?" question is open
    property var wantDevice: null
    property string wantAddr: ""
    property string wantKind: ""
    property string forgetAddr: ""
    // The last failure, and the device it belongs to
    property string error: ""
    property string errorFor: ""

    // The list scrolls past six rows
    readonly property int maxList: 6 * 36
    readonly property string status: {
        if (!powered)
            return "Bluetooth off";
        if (wantAddr !== "")
            return wantKind === "pair" ? "Pairing…" : "Connecting…";
        const n = connected.length;
        const link = n > 0 ? "Connected  ·  " + n + (n === 1 ? " device" : " devices") : "Not connected";
        return scanning ? link + "  ·  Scanning" : link;
    }

    // The picture for a device, from the kind BlueZ reports for it
    function glyphFor(icon) {
        const i = icon ?? "";
        if (i.indexOf("headset") >= 0 || i.indexOf("headphone") >= 0)
            return Icons.headphones;
        if (i.indexOf("audio") >= 0)
            return Icons.speaker;
        if (i.indexOf("keyboard") >= 0)
            return Icons.keyboard;
        if (i.indexOf("mouse") >= 0)
            return Icons.mouse;
        if (i.indexOf("gaming") >= 0)
            return Icons.gamepad;
        if (i.indexOf("phone") >= 0)
            return Icons.cellphone;
        if (i.indexOf("computer") >= 0)
            return Icons.laptop;
        return Icons.bluetooth;
    }

    function clearWant() {
        wantTimer.stop();
        wantDevice = null;
        wantAddr = "";
        wantKind = "";
    }

    // One click on a row: drop a connected device, join a paired one, pair a
    // new one. A click on the device already being worked on gives up on it.
    function act(d) {
        error = "";
        errorFor = "";
        forgetAddr = "";
        if (wantAddr !== "") {
            if (wantAddr === d.address) {
                if (wantKind === "pair")
                    d.cancelPair();
                clearWant();
            }
            return;
        }
        if (d.connected) {
            d.connected = false;
            return;
        }
        wantDevice = d;
        wantAddr = d.address;
        if (d.paired) {
            wantKind = "connect";
            d.connected = true;
        } else {
            wantKind = "pair";
            d.pair();
        }
        // Neither BlueZ call says when it has failed, so give it a while
        wantTimer.interval = wantKind === "pair" ? 25000 : 12000;
        wantTimer.restart();
    }

    function dropAll() {
        for (const d of connected)
            d.connected = false;
    }

    function forget(d) {
        forgetAddr = "";
        d.forget();
    }

    function togglePower() {
        if (adapter)
            adapter.enabled = !adapter.enabled;
    }

    function toggleScan() {
        if (adapter)
            adapter.discovering = !adapter.discovering;
    }

    function toggle() {
        if (visible) {
            visible = false;
            return;
        }
        // The click that closed us via the focus grab also lands on the disc
        if (Date.now() - closedAt < 200)
            return;
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
        forgetAddr = "";
        if (visible) {
            error = "";
            errorFor = "";
            fade.restart();
            // What is nearby shows up by itself
            if (powered && adapter)
                adapter.discovering = true;
        } else if (adapter && adapter.discovering && wantAddr === "") {
            adapter.discovering = false;
        }
    }

    // Switched on from here while open: start looking
    Connections {
        target: pop.adapter
        ignoreUnknownSignals: true

        function onEnabledChanged() {
            if (pop.visible && pop.adapter.enabled)
                pop.adapter.discovering = true;
        }
    }

    // Follow the device being worked on, even if it drops off the list: a
    // pairing that completes goes on to trust and connect it, and a device
    // that ends up connected is done with.
    Connections {
        target: pop.wantDevice
        ignoreUnknownSignals: true

        function onPairedChanged() {
            const d = pop.wantDevice;
            if (d && d.paired && pop.wantKind === "pair") {
                d.trusted = true;
                pop.wantKind = "connect";
                d.connected = true;
                wantTimer.interval = 12000;
                wantTimer.restart();
            }
        }
        function onConnectedChanged() {
            if (pop.wantDevice && pop.wantDevice.connected)
                pop.clearWant();
        }
    }

    // Time ran out on a connect or a pair
    Timer {
        id: wantTimer

        onTriggered: {
            const d = pop.wantDevice;
            const name = d ? d.name : "the device";
            if (pop.wantKind === "pair") {
                if (d)
                    d.cancelPair();
                pop.error = "Could not pair with " + name + ". It may need a PIN, which needs a Bluetooth agent.";
            } else {
                pop.error = "Could not connect to " + name + ".";
            }
            pop.errorFor = pop.wantAddr;
            pop.clearWant();
        }
    }

    // One panel at a time, and closes itself when left alone. It waits while
    // a device is being connected or paired.
    PanelLink {
        win: pop
        name: "bluetooth"
        barPopup: true
        idleMs: Style.popupIdleLongMs
        hovered: idleHover.hovered
        busy: pop.wantAddr !== ""
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

            // ---- Header: what you are connected to ------------------------
            Column {
                width: parent.width
                spacing: Style.spaceXs

                Txt {
                    width: parent.width
                    elide: Text.ElideRight
                    text: pop.connected.length > 0 ? pop.connected[0].name + (pop.connected.length > 1 ? "  +" + (pop.connected.length - 1) : "") : (pop.powered ? "No device connected" : "Bluetooth is off")
                    color: pop.connected.length > 0 ? Colors.foreground : Colors.muted
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
                    color: pop.wantAddr !== "" ? Colors.accent : Colors.muted
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

            // The bar's ruler as a battery meter, for the first connected
            // device that reports one. With none, the marker rests out of sight.
            BarRuler {
                width: parent.width
                inset: 2
                markX: inset + pop.batLevel * (width - inset * 2)
                markOpacity: pop.batDev ? 1 : 0
                fillX: pop.batDev ? markX : -1
            }

            // ---- The devices ----------------------------------------------
            ListView {
                id: devList

                width: parent.width
                height: visible ? Math.min(contentHeight, pop.maxList) : 0
                visible: pop.powered && pop.shown.length > 0
                clip: true
                spacing: 2
                boundsBehavior: Flickable.StopAtBounds
                model: pop.shown

                delegate: Item {
                    id: row

                    required property var modelData

                    readonly property var dev: modelData
                    readonly property bool wanting: pop.wantAddr === dev.address
                    // BlueZ may be mid-connect for a reason other than our click
                    readonly property bool working: wanting || dev.state === BluetoothDeviceState.Connecting || dev.state === BluetoothDeviceState.Disconnecting
                    readonly property bool lit: dev.connected || working
                    readonly property bool asking: pop.forgetAddr === dev.address
                    readonly property bool failed: pop.errorFor === dev.address && pop.error !== ""

                    width: devList.width
                    // The row, and under it whatever is open (question, error)
                    height: 34 + (extra.implicitHeight > 0 ? extra.implicitHeight + Style.spaceXs : 0)

                    Rectangle {
                        width: parent.width
                        height: 34
                        radius: Style.radiusLg
                        antialiasing: true
                        // A connected device is faintly lit; hover lifts any row
                        color: row.dev.connected ? Qt.alpha(Colors.accent, Style.tintAlpha) : (rowHover.hovered ? Style.hoverFill : "transparent")
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
                            x: 10
                            width: 16
                            anchors.verticalCenter: parent.verticalCenter
                            horizontalAlignment: Text.AlignHCenter
                            text: pop.glyphFor(row.dev.icon)
                            color: row.lit ? Colors.accent : Colors.foreground
                            font.pixelSize: Style.fontMd
                        }

                        Txt {
                            anchors.left: parent.left
                            anchors.leftMargin: 36
                            anchors.right: info.left
                            anchors.rightMargin: Style.spaceMd
                            anchors.verticalCenter: parent.verticalCenter
                            elide: Text.ElideRight
                            text: row.dev.name
                            color: row.lit ? Colors.accent : Colors.foreground
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
                                visible: row.working
                                text: row.wanting && pop.wantKind === "pair" ? "Pairing…" : (row.dev.state === BluetoothDeviceState.Disconnecting ? "Disconnecting…" : "Connecting…")
                                color: Colors.accent
                                font.pixelSize: Style.fontSm
                            }
                            Txt {
                                visible: !row.working && row.dev.connected && row.dev.batteryAvailable
                                text: Math.round((row.dev.battery > 1 ? row.dev.battery / 100 : row.dev.battery) * 100) + "%"
                                color: Colors.muted
                                font.pixelSize: Style.fontSm
                            }
                            Txt {
                                visible: !row.working && !row.dev.connected && row.dev.paired
                                text: "Paired"
                                color: Colors.muted
                                font.pixelSize: Style.fontXs
                                font.letterSpacing: 1
                                font.capitalization: Font.AllUppercase
                            }
                            Txt {
                                visible: !row.working && !row.dev.paired && !row.dev.connected
                                text: "Pair"
                                color: Colors.muted
                                font.pixelSize: Style.fontXs
                                font.letterSpacing: 1
                                font.capitalization: Font.AllUppercase
                            }
                            Txt {
                                visible: !row.working && row.dev.connected
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

                            onTapped: pop.act(row.dev)
                        }
                        // Right-click: forget a device you have paired
                        TapHandler {
                            acceptedButtons: Qt.RightButton
                            onTapped: pop.forgetAddr = row.asking || !row.dev.paired ? "" : row.dev.address
                        }
                    }

                    // Under the row: the "forget?" question, or what went wrong
                    Column {
                        id: extra

                        y: 34 + Style.spaceXs
                        width: parent.width
                        spacing: Style.spaceXs

                        Item {
                            width: parent.width
                            height: visible ? Style.buttonCompact : 0
                            visible: row.asking

                            Txt {
                                anchors.left: parent.left
                                anchors.leftMargin: 10
                                anchors.verticalCenter: parent.verticalCenter
                                text: "Forget this device?"
                                color: Colors.muted
                                font.pixelSize: Style.fontSm
                            }

                            Row {
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: Style.spaceSm

                                TextButton {
                                    compact: true
                                    text: "Keep"
                                    onClicked: pop.forgetAddr = ""
                                }
                                TextButton {
                                    compact: true
                                    danger: true
                                    text: "Forget"
                                    onClicked: pop.forget(row.dev)
                                }
                            }
                        }

                        Txt {
                            width: parent.width
                            leftPadding: 10
                            rightPadding: 10
                            visible: row.failed
                            wrapMode: Text.WordWrap
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
                visible: !devList.visible
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                text: !pop.adapter ? "No Bluetooth adapter" : (!pop.powered ? "Bluetooth is off" : (pop.scanning ? "Looking for devices…" : "No devices"))
                color: Colors.muted
                font.pixelSize: Style.fontMd
            }

            // ---- The foot -------------------------------------------------
            Item {
                width: parent.width
                height: Style.buttonCompact

                Row {
                    spacing: Style.spaceSm

                    // Stop turns into Scan and back: it is on while the card is open
                    TextButton {
                        compact: true
                        text: pop.scanning ? "Stop" : "Scan"
                        enabled: pop.powered
                        onClicked: pop.toggleScan()
                    }
                    TextButton {
                        compact: true
                        visible: pop.connected.length > 0
                        text: "Disconnect"
                        enabled: pop.wantAddr === ""
                        onClicked: pop.dropAll()
                    }
                }

                // Lit in the accent when it is the way back from "off"
                TextButton {
                    anchors.right: parent.right
                    compact: true
                    primary: !pop.powered
                    text: pop.powered ? "Bluetooth off" : "Bluetooth on"
                    enabled: pop.adapter !== null
                    onClicked: pop.togglePower()
                }
            }
        }
    }
}
