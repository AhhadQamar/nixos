// System tray: the first few icons sit in the bar as small glass discs, the
// rest fold into a "+N" disc that opens a small list. Hides itself when
// nothing is in the tray.
//
// The bar part is the dial in miniature, like the clock and the status
// cluster: a short hairline ruler curves over the discs, and the disc under
// the pointer is the "selected" one: accent outline and soft tint, a breathing
// ring and a 2px underline, with the ruler's accent marker gliding over it.
// The "+N" disc grows in and shrinks away as the count changes, and takes the
// accent (with a breathing underline) while the list is open.
//
// The folded list is a popup under the chip, in the dial's language, in
// miniature (the calendar's): bar-style glass with a light catching its top
// edge, the apps as small glass discs in a row (six to a row at most), and
// under them a short curved ruler. The ruler's tall ticks stand under the
// discs; the accent marker stands under the one the pointer is on and glides
// when it moves, and the ticks beside it rise like a magnifier. Below, the
// footer reads the app out: its name, and where it is in the list. Left click
// on a disc activates the app (or opens its menu), right click opens its
// menu, middle click is the secondary action (see TrayIcon).
// It arrives as the launcher's rainbow, quickened: the ruler unfurls from a
// tight dome into the calm arc, washed with the wallpaper's palette, and the
// discs rise in one after another. Click anywhere else to close it.

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Services.SystemTray

Item {
    id: root

    // Icons shown in the bar itself
    readonly property int maxInline: 2
    // status 0 = Passive: the app asked to be hidden (udiskie does this when no drive is attached)
    readonly property var items: SystemTray.items.values.filter(i => i.status !== 0)
    readonly property int count: items.length
    readonly property int extra: Math.max(0, count - maxInline)
    // Room between the ends and the first / last disc
    readonly property int padding: Style.spaceMd

    // The disc under the pointer (null when none is). Each disc reports in
    // through setLit; the ruler marker stands over it.
    property Item lit: null
    // Where its centre is, in the tray's own pixels (a binding, so it follows
    // the disc while it moves)
    readonly property real litX: lit ? row.x + lit.x + lit.disc.width / 2 : -1
    // The marker stays where it last stood while it fades out. The first
    // hover snaps it into place instead of sweeping in from the left edge.
    property real markX: 0
    property bool placed: false

    function setLit(it, on) {
        if (on)
            lit = it;
        else if (lit === it)
            lit = null;
    }

    onLitXChanged: {
        if (litX < 0)
            return;
        markX = litX;
        placed = true;
    }

    implicitHeight: Style.barHeight
    implicitWidth: row.implicitWidth + padding * 2
    visible: count > 0

    BarRuler {
        anchors.left: parent.left
        anchors.right: parent.right
        y: 2
        inset: root.padding
        markX: root.markX
        markOpacity: root.lit ? 1 : 0
        glide: root.placed
    }

    // The discs. The row is as tall as the bar, so its x is the tray's own.
    Row {
        id: row

        x: root.padding
        spacing: Style.spaceMd

        Repeater {
            model: root.items.slice(0, root.maxInline)

            delegate: TrayIcon {
                id: icon

                required property var modelData

                item: modelData
                onHoveredChanged: root.setLit(icon, hovered)
            }
        }

        // The "+N" disc
        Item {
            id: chip

            // 0 = gone, 1 = in place; the width follows it
            property real presence: root.extra > 0 ? 1 : 0
            readonly property bool hovered: hover.hovered
            readonly property Item disc: glass

            onHoveredChanged: root.setLit(chip, hovered)

            // Row skips invisible children, so a gone chip leaves no gap
            visible: width > 0.5
            clip: presence < 0.999
            implicitHeight: Style.barHeight
            implicitWidth: glass.implicitWidth * presence

            Behavior on presence {
                NumberAnimation {
                    duration: Style.moveMs
                    easing.type: Style.easeMove
                }
            }

            // Breath for the ring while the pointer is on it
            property real breath: 0

            SequentialAnimation {
                running: chip.hovered
                loops: Animation.Infinite

                NumberAnimation {
                    target: chip
                    property: "breath"
                    from: 0
                    to: 1
                    duration: Style.ambientMs * 2
                    easing.type: Style.easeAmbient
                }
                NumberAnimation {
                    target: chip
                    property: "breath"
                    from: 1
                    to: 0
                    duration: Style.ambientMs * 2
                    easing.type: Style.easeAmbient
                }
            }

            Rectangle {
                anchors.centerIn: glass
                width: glass.width + 4
                height: glass.height + 4
                radius: height / 2
                color: "transparent"
                antialiasing: true
                visible: chip.hovered && !more.visible
                border.width: 1
                border.color: Qt.alpha(Colors.accent, 0.2 + 0.2 * chip.breath)
            }

            Rectangle {
                id: glass

                anchors.verticalCenter: parent.verticalCenter
                implicitWidth: Math.max(Style.discSize, label.implicitWidth + Style.spaceXl)
                width: implicitWidth
                height: Style.discSize
                radius: height / 2
                antialiasing: true
                scale: chipTap.pressed ? 0.94 : 1
                // Lit while the list is open, or under the pointer
                readonly property bool lit: more.visible || chip.hovered
                color: lit ? Qt.alpha(Colors.accent, Style.tintAlpha) : Style.well
                border.width: 1
                border.color: lit ? Qt.alpha(Colors.accent, 0.6) : Style.outline

                Behavior on color {
                    ColorAnimation {
                        duration: Style.baseMs
                    }
                }
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

                EdgeLight {
                    corner: glass.height
                }

                Text {
                    id: label

                    anchors.centerIn: parent
                    text: "+" + root.extra
                    textFormat: Text.PlainText
                    color: glass.lit ? Colors.accent : Colors.muted

                    Behavior on color {
                        ColorAnimation {
                            duration: Style.baseMs
                        }
                    }

                    font {
                        family: Style.fontFamily
                        pixelSize: Style.fontSm
                    }
                }
            }

            // Underline under the disc: while the pointer is on it, and
            // while the list is open (it breathes with the list's pulse)
            Item {
                anchors.horizontalCenter: glass.horizontalCenter
                anchors.top: glass.bottom
                anchors.topMargin: Style.spaceXs
                width: 20
                height: 2
                opacity: glass.lit ? 1 : 0
                visible: opacity > 0.01

                Behavior on opacity {
                    NumberAnimation {
                        duration: Style.fadeMs
                    }
                }

                Rectangle {
                    readonly property real pulse: more.visible ? more.breath : chip.breath

                    anchors.centerIn: parent
                    width: 12 + 8 * pulse
                    height: 2
                    radius: 1
                    color: Colors.accent
                    opacity: 0.55 + 0.4 * pulse
                }
            }

            TapHandler {
                id: chipTap

                onTapped: more.toggle()
            }
            HoverHandler {
                id: hover

                cursorShape: Qt.PointingHandCursor
            }
        }
    }

    // ---- The folded list ---------------------------------------------------
    PopupWindow {
        id: more

        property double closedAt: 0
        // The disc under the pointer (0..n-1), -1 for none
        property int hoverIndex: -1
        // Where the marker last stood, in ruler steps from the middle, so it
        // fades out where it was
        property int lastK: 0
        // 1 = tight rainbow dome with spectral tint, 0 = the resting arc
        property real fan: 1
        // 0 -> 1 each time it opens: the discs rise in one after another
        property real intro: 1
        // A slow pulse (0..1) for the ring round the disc under the pointer
        property real breath: 0

        readonly property var rest: root.items.slice(root.maxInline)
        readonly property int n: rest.length
        // Discs to a row, and the cell each one has
        readonly property int perRow: 6
        readonly property int cols: Math.max(1, Math.min(n, perRow))
        readonly property int rows: Math.max(1, Math.ceil(n / perRow))
        readonly property int cellW: 40
        readonly property int cellH: 44
        // Wide enough for the footer's words as well as the discs
        readonly property int contentW: Math.max(cols * cellW, 148)
        // The disc under the pointer, if it is still in the list
        readonly property int shown: hoverIndex >= 0 && hoverIndex < n ? hoverIndex : -1
        readonly property var shownItem: shown >= 0 ? rest[shown] : null
        // The ruler's arc: the radius it rests at and the dome it arrives as
        readonly property real arcR: 420
        readonly property real domeR: 220
        readonly property real arcNow: 1 / (1 / arcR + (1 / domeR - 1 / arcR) * fan)

        // Where column c's disc stands on the ruler, in steps of one tick
        // (ten pixels) from the middle: the discs are centred, 40px apart
        function stepOfColumn(c) {
            return 4 * c - 2 * (cols - 1);
        }

        function clamp(v, a, b) {
            return Math.max(a, Math.min(b, v));
        }

        // `base` washed with one of the palette's colours, chosen by position f
        // across the ruler (0 = colour1 on the left, 1 = colour6 on the right).
        // The wash is `fan` strong, so it only shows while the ruler is arriving.
        function spectral(base, f, a) {
            const ramp = [Colors.color1, Colors.color2, Colors.color3, Colors.color4, Colors.color5, Colors.color6];
            const t = clamp(f, 0, 1) * (ramp.length - 1);
            const i = Math.min(ramp.length - 2, Math.floor(t));
            const c = Qt.tint(ramp[i], Qt.alpha(ramp[i + 1], t - i));
            return Qt.alpha(Qt.tint(base, Qt.alpha(c, 0.9 * fan)), a);
        }

        function toggle() {
            if (visible) {
                visible = false;
                return;
            }
            // The click that closed us via the focus grab also lands on the chip
            if (Date.now() - closedAt < 200)
                return;
            const win = root.QsWindow.window;
            anchor.rect = win.contentItem.mapFromItem(chip.disc, 0, 0, chip.disc.width, chip.disc.height + Style.spaceMd);
            visible = true;
        }

        function close() {
            visible = false;
        }

        visible: false
        color: "transparent"
        implicitWidth: contentW + 28
        implicitHeight: card.implicitHeight
        anchor.window: root.QsWindow.window
        anchor.edges: Edges.Bottom | Edges.Right
        anchor.gravity: Edges.Bottom | Edges.Left
        onVisibleChanged: if (visible) {
            fadeIn.restart();
            hoverIndex = -1;
            lastK = 0;
            fan = 1;
            intro = 0;
            openAnim.restart();
        }
        onShownChanged: if (shown >= 0)
            lastK = stepOfColumn(shown % perRow)
        // Everything folded out of the list (or back into the bar): nothing
        // left to show
        onNChanged: if (n === 0)
            visible = false

        // The ruler unfurls from a tight dome into the calm arc while the
        // spectrum drains out of it, and the discs rise in: the launcher's
        // arrival, quickened
        ParallelAnimation {
            id: openAnim

            NumberAnimation {
                target: more
                property: "fan"
                to: 0
                duration: Style.sweepMs + Style.fadeMs
                easing.type: Style.easeMove
            }
            NumberAnimation {
                target: more
                property: "intro"
                to: 1
                duration: Style.enterMs + Style.baseMs
                easing.type: Style.easeMove
            }
        }

        // Slow breath for the ring round the disc under the pointer
        SequentialAnimation {
            running: more.visible
            loops: Animation.Infinite

            NumberAnimation {
                target: more
                property: "breath"
                from: 0
                to: 1
                duration: Style.ambientMs * 2
                easing.type: Style.easeAmbient
            }
            NumberAnimation {
                target: more
                property: "breath"
                from: 1
                to: 0
                duration: Style.ambientMs * 2
                easing.type: Style.easeAmbient
            }
        }

        PanelLink {
            win: more
            name: "tray"
            idleMs: Style.popupIdleMs
            hovered: idleHover.hovered
        }

        HyprlandFocusGrab {
            windows: [more]
            active: more.visible
            onCleared: {
                more.visible = false;
                more.closedAt = Date.now();
            }
        }

        // The card grows out of the chip, which is at its top right corner
        CardFade {
            id: fadeIn

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
            Rectangle {
                anchors.top: parent.top
                anchors.topMargin: 1
                anchors.horizontalCenter: parent.horizontalCenter
                width: parent.width - Style.radiusXl * 2
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

            Column {
                id: col

                x: 14
                y: 14
                width: more.contentW
                spacing: Style.spaceMd

                // ---- The apps, as glass discs ------------------------------
                Item {
                    width: parent.width
                    height: more.rows * more.cellH

                    Grid {
                        anchors.horizontalCenter: parent.horizontalCenter
                        columns: more.cols

                        Repeater {
                            model: more.rest

                            delegate: TrayIcon {
                                id: disc

                                required property var modelData
                                required property int index

                                item: modelData
                                inList: true
                                menuWindow: root.QsWindow.window
                                menuAnchor: chip.disc
                                breath: more.breath
                                // The discs rise in one after another
                                arrive: more.clamp(more.intro * 1.8 - 0.15 - index * 0.08, 0, 1)
                                onTriggered: more.close()
                                onHoveredChanged: {
                                    if (hovered)
                                        more.hoverIndex = index;
                                    else if (more.hoverIndex === index)
                                        more.hoverIndex = -1;
                                }
                            }
                        }
                    }
                }

                // ---- The ruler -----------------------------------------------
                // A short curved arc with a tick every ten pixels, the
                // launcher's ruler in miniature. The tall ticks stand under
                // the discs. The accent marker stands under the disc the
                // pointer is on and glides when that changes; the ticks beside
                // it rise like a magnifier.
                Item {
                    id: ruler

                    // Ticks either side of the middle one
                    readonly property int half: Math.floor(width / 2 / 10)
                    // Where the marker is along the ruler, in pixels
                    property real markX: width / 2 + more.lastK * 10

                    // How far a point at x sits below the top of the arc
                    function dropAt(x) {
                        const r = more.arcNow;
                        return r - Math.sqrt(Math.max(0, r * r - (x - width / 2) * (x - width / 2)));
                    }

                    width: parent.width
                    height: 30

                    Behavior on markX {
                        enabled: more.shown >= 0

                        NumberAnimation {
                            duration: Style.moveMs
                            easing.type: Style.easeEnter
                        }
                    }

                    Repeater {
                        model: ruler.half * 2 + 1

                        delegate: Rectangle {
                            id: tick

                            required property int index

                            // Steps from the middle tick
                            readonly property int k: index - ruler.half
                            readonly property real tx: ruler.width / 2 + k * 10
                            readonly property real a: (tx - ruler.width / 2) / more.arcNow
                            // Under a disc: every fourth tick, from the first disc's
                            readonly property bool major: Math.abs(k) <= 2 * (more.cols - 1) && ((k + 2 * (more.cols - 1)) % 4 + 4) % 4 === 0
                            // The ticks near the marker rise
                            readonly property real near: more.shown >= 0 ? Math.max(0, 1 - Math.abs(tx - ruler.markX) / 40) : 0
                            readonly property real arrive: more.clamp(more.intro * 2 - 0.3 - Math.abs(tx - ruler.width / 2) / ruler.width * 0.6, 0, 1)

                            x: tx - 0.75
                            y: 4 + ruler.dropAt(tx)
                            width: 1.5
                            height: (major ? 8 : 4) + 6 * near
                            radius: 0.75
                            antialiasing: true
                            transformOrigin: Item.Top
                            rotation: a * 180 / Math.PI
                            opacity: arrive
                            color: Qt.tint(more.spectral(Colors.foreground, tx / ruler.width, major ? 0.5 : 0.3), Qt.alpha(Colors.accent, 0.8 * near))
                        }
                    }

                    // The accent marker, standing under the disc the pointer is on
                    Rectangle {
                        readonly property real a: (ruler.markX - ruler.width / 2) / more.arcNow

                        x: ruler.markX - 1
                        y: 2 + ruler.dropAt(ruler.markX)
                        width: 2
                        height: 16
                        radius: 1
                        antialiasing: true
                        color: Colors.accent
                        transformOrigin: Item.Top
                        rotation: a * 180 / Math.PI
                        opacity: more.shown >= 0 ? more.clamp(more.intro * 2 - 0.5, 0, 1) : 0

                        Behavior on opacity {
                            NumberAnimation {
                                duration: Style.fadeMs
                            }
                        }
                    }
                }

                // ---- Footer: the app under the pointer, read out -------------
                // The way the dial reads out its middle: the app's name, and
                // under it where it is in the list. With the pointer elsewhere
                // it says what the list is.
                Column {
                    width: parent.width
                    spacing: Style.spaceXs
                    opacity: more.clamp(more.intro * 2 - 0.4, 0, 1)

                    Txt {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                        text: more.shownItem ? (more.shownItem.title || more.shownItem.id) : "More in the tray"
                        color: more.shownItem ? (more.shownItem.status === 2 ? Colors.critical : Colors.foreground) : Colors.muted
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
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                        text: more.shownItem ? (more.shown + 1) + "/" + more.n + (more.shownItem.status === 2 ? "  \u00b7  needs attention" : "") : more.n + (more.n === 1 ? " app" : " apps")
                        color: more.shownItem ? Qt.alpha(Colors.foreground, 0.78) : Colors.muted
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
            }
        }
    }
}
