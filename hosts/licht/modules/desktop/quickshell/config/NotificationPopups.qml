// NotificationPopups.qml
// Toasts for new notifications, stacked under the bar at its right edge.
// Driven entirely by NotificationServer.active.
//
// The dial in miniature: every toast is bar-style glass with a hairline
// outline and a light catching its top edge. A glass disc on the left holds the
// notification's picture, its app's icon or the app's first letter, ringed in
// the accent (the alert red when urgent). Under the words runs a short curved
// ruler, the launcher's ruler in miniature: it is the time left. The ticks up
// to the front are lit and the ones at the front rise like a magnifier as it
// drains towards the left. Urgent toasts stay until dismissed, so their ruler
// is lit in red and does not move.
//
// Arrival: the toast slides in from the right, the disc swells with a small
// overshoot and sends a ring off, a glint runs round the edge, and the ruler
// unfurls from a tight dome into the calm arc, washed with the wallpaper's
// palette colours while it does (the launcher's rainbow, quickened).
//
// Hover a toast and its clock stops, and a close mark appears.
// Click: runs the notification's "default" action when it has one (usually
//        "bring the app up"), otherwise dismisses. Right or middle click always
//        dismisses. The buttons run the notification's own actions (three at
//        most). A dismissed toast stays in the notification centre.
// When more than four are waiting a "+N more" pill under the stack opens the
// centre; opening the centre clears the toasts (urgent ones stay).
// Leaving: the toast slides away and the ones under it glide up into the gap.

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland

PanelWindow {
    id: popups

    // ---- Settings -------------------------------------------------------
    // How many toasts are drawn at once; the rest wait behind a "+N more" pill
    readonly property int maxShown: 4
    // Tall enough for a full stack (the window itself is only as tall as what
    // is on screen, see keepH)
    readonly property int stackH: 760
    readonly property int toastW: 360
    readonly property int padX: 14
    readonly property int padTop: 14
    // Room at the foot of the card for the ruler
    readonly property int rulerH: 22
    readonly property int discSize: 40
    readonly property int closeSize: 22
    // The ruler's arc: the calm radius, and the dome it unfurls from
    readonly property real dialR: 1500
    readonly property real rainbowR: 380
    readonly property int tickCount: 33

    // The window's height. It grows with the stack at once, but only shrinks
    // once the exit animations have played, otherwise they would be cut off.
    property real keepH: 0
    readonly property real wantH: list.contentHeight

    function clamp(v, a, b) {
        return Math.max(a, Math.min(b, v));
    }

    // Ease-out with a small overshoot for the arrival of the disc: the
    // shell's `pop`, kept gentle (same curve as the dial panels use).
    function backOut(t) {
        const c1 = 0.8;
        const u = t - 1;
        return 1 + (c1 + 1) * u * u * u + c1 * u * u;
    }

    // `base` washed with one of the palette's colours, chosen by where along
    // the ruler it is (colour1 on the left through colour6 on the right). The
    // wash is `fan` strong, so it only shows while the ruler is unfurling.
    function spectral(base, f, a, fan) {
        const ramp = [Colors.color1, Colors.color2, Colors.color3, Colors.color4, Colors.color5, Colors.color6];
        const t = clamp(f, 0, 1) * (ramp.length - 1);
        const i = Math.min(ramp.length - 2, Math.floor(t));
        const c = Qt.tint(ramp[i], Qt.alpha(ramp[i + 1], t - i));
        return Qt.alpha(Qt.tint(base, Qt.alpha(c, 0.9 * fan)), a);
    }

    onWantHChanged: {
        if (wantH >= keepH)
            keepH = wantH;
        else
            shrink.restart();
    }

    Timer {
        id: shrink

        interval: 340
        onTriggered: popups.keepH = popups.wantH
    }

    // Keeps the window mapped while the last toast is still leaving
    Timer {
        id: linger

        interval: 340
    }

    Connections {
        target: NotificationServer

        function onActiveChanged() {
            linger.restart();
        }
    }

    // Toasts show on whichever monitor has focus
    screen: Focus.screen
    color: "transparent"
    // Sits just under the bar, lined up with its right edge
    margins.top: Style.barGap + Style.barHeight + 8
    margins.right: Style.barGap + 2
    implicitWidth: toastW
    implicitHeight: Math.max(1, keepH)
    exclusiveZone: 0
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "qs-toasts"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    visible: NotificationServer.active.length > 0 || linger.running

    anchors {
        top: true
        right: true
    }

    ListView {
        id: list

        width: parent.width
        height: popups.stackH
        interactive: false
        spacing: Style.spaceMd

        // ScriptModel keeps a toast's delegate alive while the list around it
        // changes, so each toast can animate in, out and aside. Matching by
        // id means a notification that replaces another (a progress update,
        // say) is updated in place instead of leaving and coming back.
        // What did not fit is one more row, the "+N more" pill.
        model: ScriptModel {
            objectProp: "id"
            values: {
                const all = NotificationServer.active;
                const shown = all.slice(0, popups.maxShown);
                if (all.length > popups.maxShown)
                    shown.push({
                        "id": "more",
                        "more": true,
                        "count": all.length - popups.maxShown
                    });
                return shown;
            }
        }

        add: Transition {
            ParallelAnimation {
                NumberAnimation {
                    property: "opacity"
                    from: 0
                    to: 1
                    duration: Style.baseMs
                    easing.type: Style.easeMove
                }
                NumberAnimation {
                    property: "x"
                    from: 28
                    to: 0
                    duration: Style.moveMs
                    easing.type: Style.easeEnter
                }
            }
        }

        remove: Transition {
            ParallelAnimation {
                NumberAnimation {
                    property: "opacity"
                    to: 0
                    duration: Style.fadeMs
                }
                NumberAnimation {
                    property: "x"
                    to: 28
                    duration: Style.baseMs
                    easing.type: Style.easeExit
                }
            }
        }

        // The toasts under a leaving one glide up into its place
        displaced: Transition {
            NumberAnimation {
                property: "y"
                duration: Style.moveMs
                easing.type: Style.easeMove
            }
        }

        delegate: Item {
            id: toast

            required property var modelData

            // What an empty toast holds, so nothing reads a missing field
            readonly property var blank: ({
                    "id": -1,
                    "appName": "",
                    "appIcon": "",
                    "summary": "",
                    "body": "",
                    "image": "",
                    "critical": false,
                    "actions": [],
                    "expire": 0,
                    "time": 0,
                    "ref": null
                })
            // A copy taken when the toast is made, so the text is still there
            // while it slides out after being removed from the list
            property var notif: blank
            // This row is the "+N more" pill
            property bool more: false
            property int moreCount: 0

            readonly property bool critical: notif.critical === true
            readonly property color tint: critical ? Colors.critical : Colors.accent
            // The app's icon; the picture is separate, so the disc can fall
            // back to the icon (or the letter) if the picture will not load
            readonly property string icon: NotificationServer.appIconSource(notif)
            readonly property bool hasPicture: notif.image !== ""
            readonly property bool photo: hasPicture && toastPhoto.status !== Image.Error
            // How long it stays, in ms; 0 = until dismissed
            readonly property int ms: more ? 0 : NotificationServer.toastMs(notif)
            // "default" is the click on the toast itself, not a button
            readonly property bool hasDefault: notif.actions.some(a => a.id === "default")
            readonly property var buttons: notif.actions.filter(a => a.id !== "default" && a.text !== "").slice(0, 3)

            // Time left, 1 down to 0 (drives the ruler)
            property real remaining: 1
            // A glint round the edge, and a ring off the disc, 1 down to 0 / 0 up to 1
            property real glint: 0
            property real ping: 0
            // The arrival: 0 -> 1, and the ruler's dome 1 -> 0
            property real arrive: 0
            property real fan: 1
            // Radius of the ruler's arc right now
            readonly property real dialNow: 1 / (1 / popups.dialR + (1 / popups.rainbowR - 1 / popups.dialR) * fan)

            width: ListView.view ? ListView.view.width : popups.toastW
            height: more ? chip.height : card.implicitHeight

            function adopt() {
                const m = modelData;
                if (!m)
                    return;
                if (m.more === true) {
                    more = true;
                    moreCount = m.count;
                    return;
                }
                // Already holding this very notification (adopt runs more than once)
                if (notif.id === m.id && notif.time === m.time)
                    return;
                const replaced = notif !== blank;
                notif = m;
                restartLine();
                if (replaced)
                    noticeAnim.restart();
            }

            function restartLine() {
                lineAnim.stop();
                if (ms <= 0) {
                    remaining = 0;
                    return;
                }
                remaining = 1;
                lineAnim.duration = ms;
                lineAnim.restart();
            }

            // Click on the toast: its default action, else just dismiss
            function activate() {
                if (hasDefault)
                    NotificationServer.invokeAction(notif, "default");
                else
                    NotificationServer.dismissEntry(notif);
            }

            Component.onCompleted: {
                adopt();
                if (!more) {
                    arriveAnim.restart();
                    noticeAnim.restart();
                }
            }

            onModelDataChanged: adopt()

            // The clock. It stops while the pointer is over the toast, and
            // the toast goes when it runs out.
            NumberAnimation {
                id: lineAnim

                target: toast
                property: "remaining"
                from: 1
                to: 0
                easing.type: Easing.Linear
                paused: hover.hovered
                onRunningChanged: {
                    if (!running && toast.remaining <= 0.001 && toast.ms > 0 && !toast.more)
                        NotificationServer.dismissEntry(toast.notif);
                }
            }

            // Slides in: the ruler unfurls and its colours drain
            ParallelAnimation {
                id: arriveAnim

                NumberAnimation {
                    target: toast
                    property: "arrive"
                    from: 0
                    to: 1
                    duration: Style.enterMs + Style.fadeMs
                    easing.type: Style.easeEnter
                }
                NumberAnimation {
                    target: toast
                    property: "fan"
                    from: 1
                    to: 0
                    duration: Style.sweepMs
                    easing.type: Style.easeMove
                }
            }

            // Noticed: a glint round the edge and a ring off the disc. Also
            // played again when the notification is replaced.
            ParallelAnimation {
                id: noticeAnim

                NumberAnimation {
                    target: toast
                    property: "glint"
                    from: 1
                    to: 0
                    duration: Style.ambientMs
                    easing.type: Style.easeMove
                }
                NumberAnimation {
                    target: toast
                    property: "ping"
                    from: 0
                    to: 1
                    duration: Style.sweepMs
                    easing.type: Style.easeMove
                }
            }

            // ---- "+N more" -------------------------------------------------
            Item {
                id: chip

                visible: toast.more
                anchors.right: parent.right
                width: chipLabel.implicitWidth + 28
                height: 26

                Rectangle {
                    anchors.fill: parent
                    radius: height / 2
                    antialiasing: true
                    color: Style.card
                    border.width: 1
                    border.color: chipHover.hovered ? Qt.alpha(Colors.accent, 0.5) : Style.outline
                    scale: chipTap.pressed ? 0.96 : 1

                    Behavior on border.color {
                        ColorAnimation {
                            duration: Style.baseMs
                        }
                    }
                    Behavior on scale {
                        NumberAnimation {
                            duration: Style.pressMs
                            easing.type: Style.easePress
                        }
                    }
                }

                Txt {
                    id: chipLabel

                    anchors.centerIn: parent
                    text: "+" + toast.moreCount + " more"
                    color: chipHover.hovered ? Colors.foreground : Colors.muted
                    font.pixelSize: Style.fontSm

                    Behavior on color {
                        ColorAnimation {
                            duration: Style.baseMs
                        }
                    }
                }

                HoverHandler {
                    id: chipHover

                    cursorShape: Qt.PointingHandCursor
                }

                TapHandler {
                    id: chipTap

                    onTapped: Panels.toggleNotifications()
                }
            }

            // ---- The toast ---------------------------------------------------
            Rectangle {
                id: card

                visible: !toast.more
                anchors.fill: parent
                implicitHeight: popups.padTop + content.implicitHeight + (toast.buttons.length > 0 ? Style.spaceMd + Style.buttonCompact : 0) + popups.rulerH
                radius: Style.barRadius
                antialiasing: true
                // More solid than the bar: toasts sit over other windows' text
                color: Style.card
                border.width: 1
                border.color: toast.critical ? Qt.alpha(Colors.critical, 0.4 + 0.4 * toast.glint) : Qt.tint(Style.outline, Qt.alpha(Colors.accent, 0.7 * toast.glint))
                scale: clickArea.pressed ? 0.985 : 1

                Behavior on scale {
                    NumberAnimation {
                        duration: Style.pressMs
                        easing.type: Style.easePress
                    }
                }

                HoverHandler {
                    id: hover
                }

                // Light catching the top edge, as on the bar
                Rectangle {
                    anchors.top: parent.top
                    anchors.topMargin: 1
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: parent.width * 0.4
                    height: 1

                    gradient: Gradient {
                        orientation: Gradient.Horizontal

                        GradientStop {
                            position: 0
                            color: Qt.alpha(Colors.foreground, 0)
                        }
                        GradientStop {
                            position: 0.5
                            color: Qt.alpha(Colors.foreground, 0.12)
                        }
                        GradientStop {
                            position: 1
                            color: Qt.alpha(Colors.foreground, 0)
                        }
                    }
                }

                // Click on the words and the disc. It stops short of the close
                // mark and sits above the buttons, so nothing overlaps.
                MouseArea {
                    id: clickArea

                    x: 0
                    y: 0
                    width: card.width - popups.padX - popups.closeSize - Style.spaceMd
                    height: popups.padTop + content.implicitHeight + 6
                    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                    cursorShape: Qt.PointingHandCursor
                    onClicked: mouse => {
                        if (mouse.button === Qt.LeftButton)
                            toast.activate();
                        else
                            NotificationServer.dismissEntry(toast.notif);
                    }
                }

                RowLayout {
                    id: content

                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.leftMargin: popups.padX
                    anchors.rightMargin: popups.padX
                    anchors.topMargin: popups.padTop
                    spacing: Style.spaceLg

                    // ---- The disc: picture, app icon, or the app's first letter
                    Item {
                        id: disc

                        readonly property real appear: popups.clamp(toast.arrive * 1.6 - 0.2, 0, 1)

                        Layout.alignment: Qt.AlignTop
                        implicitWidth: popups.discSize
                        implicitHeight: popups.discSize
                        opacity: appear
                        scale: 0.55 + 0.45 * popups.backOut(appear)

                        // The ring that leaves it on arrival
                        Rectangle {
                            anchors.centerIn: parent
                            width: parent.width + 6 + 16 * toast.ping
                            height: width
                            radius: width / 2
                            color: "transparent"
                            antialiasing: true
                            visible: toast.ping > 0.001 && toast.ping < 0.999
                            border.width: 1.5
                            border.color: Qt.alpha(toast.tint, 0.5 * (1 - toast.ping))
                        }

                        // Glass, like the dial's discs: a hairline outline in the
                        // notification's colour
                        Rectangle {
                            anchors.fill: parent
                            radius: width / 2
                            antialiasing: true
                            color: Style.well
                            border.width: 1
                            border.color: Qt.alpha(toast.tint, 0.8)
                        }

                        // The soft tint inside the glass
                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: 1
                            radius: width / 2
                            antialiasing: true
                            color: Qt.alpha(toast.tint, Style.tintAlpha)
                        }

                        // Light catching the top edge
                        Rectangle {
                            anchors.top: parent.top
                            anchors.topMargin: 1
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: parent.width * 0.5
                            height: 1

                            gradient: Gradient {
                                orientation: Gradient.Horizontal

                                GradientStop {
                                    position: 0
                                    color: Qt.alpha(Colors.foreground, 0)
                                }
                                GradientStop {
                                    position: 0.5
                                    color: Qt.alpha(Colors.foreground, 0.12)
                                }
                                GradientStop {
                                    position: 1
                                    color: Qt.alpha(Colors.foreground, 0)
                                }
                            }
                        }

                        // The notification's own picture, in a circle
                        Photo {
                            id: toastPhoto

                            anchors.fill: parent
                            anchors.margins: 4
                            visible: toast.photo
                            radius: width / 2
                            source: toast.hasPicture ? toast.notif.image : ""
                        }

                        // The app's icon
                        Image {
                            id: appImg

                            anchors.fill: parent
                            anchors.margins: parent.width * 0.24
                            visible: toast.icon !== "" && !toast.photo && status === Image.Ready
                            source: toast.photo ? "" : toast.icon
                            sourceSize.width: 96
                            sourceSize.height: 96
                            fillMode: Image.PreserveAspectFit
                            asynchronous: true
                        }

                        // Or the app's first letter
                        Txt {
                            anchors.centerIn: parent
                            visible: toast.photo ? false : !(toast.icon !== "" && appImg.status === Image.Ready)
                            text: NotificationServer.initial(toast.notif.appName)
                            color: toast.critical ? Colors.critical : Colors.accent
                            font.pixelSize: parent.width * 0.4
                            font.bold: true
                        }
                    }

                    // ---- Words -------------------------------------------------
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 3

                        // Which app (and, when urgent, that it is)
                        Txt {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            text: (toast.critical ? "Urgent  ·  " : "") + toast.notif.appName
                            color: toast.critical ? Colors.critical : Colors.muted
                            font.pixelSize: Style.fontXs
                            font.letterSpacing: 1.4
                            font.capitalization: Font.AllUppercase
                        }

                        Txt {
                            Layout.fillWidth: true
                            visible: text !== ""
                            wrapMode: Text.Wrap
                            maximumLineCount: 2
                            elide: Text.ElideRight
                            text: toast.notif.summary
                            color: Colors.foreground
                            font.pixelSize: Style.fontBase
                            font.bold: true
                        }

                        Txt {
                            Layout.fillWidth: true
                            visible: text !== ""
                            wrapMode: Text.Wrap
                            maximumLineCount: 3
                            elide: Text.ElideRight
                            text: toast.notif.body
                            color: Colors.muted
                            font.pixelSize: Style.fontMd
                        }
                    }

                    // Close mark: always takes its space so nothing shifts on hover
                    IconButton {
                        Layout.alignment: Qt.AlignTop
                        size: popups.closeSize
                        glyph: Icons.close
                        glyphSize: 12
                        danger: true
                        active: hover.hovered
                        opacity: hover.hovered ? 1 : 0
                        onClicked: NotificationServer.dismissEntry(toast.notif)

                        Behavior on opacity {
                            NumberAnimation {
                                duration: Style.fadeMs
                            }
                        }
                    }
                }

                // ---- The notification's own actions --------------------------
                Row {
                    id: actionsRow

                    visible: toast.buttons.length > 0
                    x: popups.padX + popups.discSize + Style.spaceLg
                    y: popups.padTop + content.implicitHeight + Style.spaceMd
                    spacing: Style.spaceSm

                    Repeater {
                        model: toast.buttons

                        delegate: TextButton {
                            required property var modelData
                            required property int index

                            compact: true
                            primary: index === 0
                            text: modelData.text
                            onClicked: NotificationServer.invokeAction(toast.notif, modelData.id)
                        }
                    }
                }

                // ---- The ruler: the time left ---------------------------------
                // Curved like the dial's, hanging from its arc. The lit ticks
                // drain towards the left, the ones at the front rise like a
                // magnifier. Urgent ones are lit red and stay.
                Item {
                    id: ruler

                    readonly property real span: width - 60

                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: popups.rulerH
                    clip: true

                    Repeater {
                        model: popups.tickCount

                        delegate: Rectangle {
                            id: tick

                            required property int index

                            // 0 at the left end, 1 at the right
                            readonly property real frac: index / (popups.tickCount - 1)
                            readonly property bool major: index % 8 === 0
                            readonly property real s: (frac - 0.5) * ruler.span
                            readonly property real a: s / toast.dialNow
                            readonly property real rr: toast.dialNow - 6
                            readonly property bool lit: toast.critical || frac <= toast.remaining + 0.0001
                            // 1 at the front of the drain, fading to 0 a couple of ticks away
                            readonly property real near: toast.critical ? 0 : Math.exp(-Math.pow((frac - toast.remaining) / 0.07, 2))
                            // The ticks sweep in from the left as the toast arrives
                            readonly property real appear: popups.clamp(toast.arrive * 1.7 - frac * 0.7, 0, 1)
                            // The ends of the ruler fade out, like the dial's
                            readonly property real edge: popups.clamp((ruler.span / 2 - Math.abs(s)) / 70, 0, 1)

                            x: ruler.width / 2 + rr * Math.sin(a) - width / 2
                            y: 2 + toast.dialNow - rr * Math.cos(a)
                            width: major ? 2 : 1.5
                            height: (major ? 8 : 5) + 6 * near
                            radius: width / 2
                            antialiasing: true
                            transformOrigin: Item.Top
                            rotation: a * 180 / Math.PI
                            opacity: appear * edge
                            color: lit ? popups.spectral(toast.tint, frac, major ? 0.9 : 0.55, toast.fan) : popups.spectral(Colors.foreground, frac, major ? 0.3 : 0.14, toast.fan)
                        }
                    }
                }
            }
        }
    }
}
