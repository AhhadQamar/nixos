// Month calendar that grows out of the clock.
//   - Click the clock to open; click anywhere else to close.
//   - Arrows change month (the month slides the way you are going); click the
//     month name, or the "Today" chip that appears when you are away from the
//     current month, to jump back.
//   - Always six rows, so the card never changes height between months. The
//     days either side of the month are shown dim; click one to go there.
//   - Hover a day: one highlight glides between days, and the footer says
//     which week it is in and how far away it is ("in 4 days", "Yesterday").
//     With the pointer elsewhere it shows today.
//   - The dial's language, in miniature: bar-style glass with a light catching
//     its top edge, today as a glass disc ringed in the accent, and under the
//     days a short curved ruler with one tick per day of the month. The accent
//     marker stands on the day the footer talks about and glides as you hover,
//     the ticks beside it rise like a magnifier, and the footer reads the day
//     out. It arrives as the launcher's rainbow, quickened: the ruler unfurls
//     from a tight dome into the calm arc, washed with the wallpaper's palette,
//     and the days rise in one after another.

import QtQuick
import Quickshell
import Quickshell.Hyprland

PopupWindow {
    id: pop

    // The bar window this hangs from, and the item it hangs under
    required property var barWindow
    required property var target

    readonly property bool open: visible

    // Months away from the current one: 0 = this month, -1 = last month
    property int offset: 0
    property double closedAt: 0
    // Which way the month last moved, for the slide: 1 = forward, -1 = back
    property int slideDir: 1
    // The day under the pointer (0..41), -1 for none. lastHover remembers the
    // last one, so the highlight can fade out where it was.
    property int hoverIndex: -1
    property int lastHover: 0
    // 1 = tight rainbow dome with spectral tint, 0 = the resting arc
    property real fan: 1
    // 0 -> 1 each time it opens: the days rise in one after another
    property real intro: 1
    // A slow pulse (0..1) for the ring round today
    property real breath: 0

    readonly property date today: clock.date
    readonly property date first: new Date(today.getFullYear(), today.getMonth() + offset, 1)
    // Blank cells before the 1st, with the week starting on Monday
    readonly property int lead: (first.getDay() + 6) % 7
    // Six rows of seven, always
    readonly property int cells: 42
    // The day the footer talks about
    readonly property date shownDate: hoverIndex >= 0 ? cellDate(hoverIndex) : today
    // Days in the month on show, and which tick the marker stands on (-1 when
    // the day the footer talks about is in another month)
    readonly property int dim: new Date(first.getFullYear(), first.getMonth() + 1, 0).getDate()
    readonly property int markDay: shownDate.getMonth() === first.getMonth() && shownDate.getFullYear() === first.getFullYear() ? shownDate.getDate() - 1 : -1
    // The ruler's arc: the radius it rests at and the dome it arrives as
    readonly property real arcR: 520
    readonly property real domeR: 280
    readonly property real arcNow: 1 / (1 / arcR + (1 / domeR - 1 / arcR) * fan)

    onHoverIndexChanged: if (hoverIndex >= 0)
        lastHover = hoverIndex

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

    function isoWeek(d) {
        const t = new Date(Date.UTC(d.getFullYear(), d.getMonth(), d.getDate()));
        t.setUTCDate(t.getUTCDate() + 4 - (t.getUTCDay() || 7));
        const y0 = new Date(Date.UTC(t.getUTCFullYear(), 0, 1));
        return Math.ceil(((t - y0) / 86400000 + 1) / 7);
    }

    // The date in cell i. Days before the 1st and after the end of the month
    // come out right on their own: Date rolls them into the neighbouring month.
    function cellDate(i) {
        return new Date(first.getFullYear(), first.getMonth(), i - lead + 1);
    }

    function sameDay(a, b) {
        return a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate();
    }

    // "Today", "Tomorrow", "in 4 days", "3 days ago"
    function relative(d) {
        const t0 = new Date(today.getFullYear(), today.getMonth(), today.getDate());
        const n = Math.round((d - t0) / 86400000);
        if (n === 0)
            return "Today";
        if (n === 1)
            return "Tomorrow";
        if (n === -1)
            return "Yesterday";
        return n > 0 ? "in " + n + " days" : (-n) + " days ago";
    }

    function go(delta) {
        slideDir = delta > 0 ? 1 : -1;
        offset += delta;
        slide.restart();
    }

    function goToday() {
        if (offset !== 0)
            go(-offset);
    }

    // PanelLink calls this when another panel (the clock popup too) opens
    function close() {
        visible = false;
    }

    function toggle() {
        if (visible) {
            visible = false;
            return;
        }
        // The click that closed us via the focus grab also lands on the clock
        if (Date.now() - closedAt < 200)
            return;
        offset = 0;
        hoverIndex = -1;
        // Under the date, not the whole capsule: the card's top left corner
        // sits where the date starts, so it reads as growing out of it
        anchor.rect = barWindow.contentItem.mapFromItem(target, target.dateLeft, 0, target.width - target.dateLeft, target.height + 6);
        visible = true;
    }

    // One overlay panel at a time: close when another one opens
    PanelLink {
        id: link

        win: pop
        name: "calendar"
        idleMs: Style.popupIdleMs
        hovered: idleHover.hovered
    }

    visible: false
    color: "transparent"
    implicitWidth: 276
    implicitHeight: card.implicitHeight
    anchor.window: barWindow
    anchor.edges: Edges.Bottom | Edges.Left
    anchor.gravity: Edges.Bottom | Edges.Right
    onVisibleChanged: if (visible) {
        fade.restart();
        fan = 1;
        intro = 0;
        openAnim.restart();
    }

    // The ruler unfurls from a tight dome into the calm arc while the spectrum
    // drains out of it, and the days rise in: the launcher's arrival, quickened
    ParallelAnimation {
        id: openAnim

        NumberAnimation {
            target: pop
            property: "fan"
            to: 0
            duration: Style.sweepMs + Style.fadeMs
            easing.type: Style.easeMove
        }
        NumberAnimation {
            target: pop
            property: "intro"
            to: 1
            duration: Style.enterMs + Style.baseMs
            easing.type: Style.easeMove
        }
    }

    // Slow breath for the ring round today
    SequentialAnimation {
        running: pop.visible
        loops: Animation.Infinite

        NumberAnimation {
            target: pop
            property: "breath"
            from: 0
            to: 1
            duration: Style.ambientMs * 2
            easing.type: Style.easeAmbient
        }
        NumberAnimation {
            target: pop
            property: "breath"
            from: 1
            to: 0
            duration: Style.ambientMs * 2
            easing.type: Style.easeAmbient
        }
    }

    SystemClock {
        id: clock

        precision: SystemClock.Minutes
        // Only an open calendar needs the date; it catches up the moment it opens
        enabled: pop.visible
    }

    HyprlandFocusGrab {
        windows: [pop]
        active: pop.visible
        onCleared: {
            pop.visible = false;
            pop.closedAt = Date.now();
        }
    }

    // The card grows out of the date, which is at its top left corner
    CardFade {
        id: fade

        target: card
        fromScale: 0.94
    }

    // The month changed: the title and the days slide in from the side you
    // are going towards
    ParallelAnimation {
        id: slide

        NumberAnimation {
            target: gridShift
            property: "x"
            from: 18 * pop.slideDir
            to: 0
            duration: Style.moveMs
            easing.type: Style.easeMove
        }
        NumberAnimation {
            target: gridArea
            property: "opacity"
            from: 0.2
            to: 1
            duration: Style.moveMs
            easing.type: Style.easeMove
        }
        NumberAnimation {
            target: titleShift
            property: "x"
            from: 10 * pop.slideDir
            to: 0
            duration: Style.moveMs
            easing.type: Style.easeMove
        }
        NumberAnimation {
            target: title
            property: "opacity"
            from: 0.2
            to: 1
            duration: Style.moveMs
            easing.type: Style.easeMove
        }
    }

    component NavButton: Rectangle {
        id: btn

        property int glyph: 0

        signal clicked

        implicitWidth: 26
        implicitHeight: 26
        radius: 13
        antialiasing: true
        color: nav.hovered ? Style.hoverFill : "transparent"
        scale: navTap.pressed ? 0.88 : 1

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

        Text {
            anchors.centerIn: parent
            text: String.fromCodePoint(btn.glyph)
            color: nav.hovered ? Colors.foreground : Colors.muted

            Behavior on color {
                ColorAnimation {
                    duration: Style.fadeMs
                }
            }

            font {
                family: Style.fontFamily
                pixelSize: Style.fontXl
            }
        }

        TapHandler {
            id: navTap

            onTapped: btn.clicked()
        }
        HoverHandler {
            id: nav

            cursorShape: Qt.PointingHandCursor
        }
    }

    Rectangle {
        id: card

        // For the idle close: it waits while the pointer is on the card
        HoverHandler {
            id: idleHover
        }

        // Keys: esc closes, left / right (or h / l, PgUp / PgDn) turn the month,
        // t or Home comes back to today. Every key counts as activity for the
        // idle close.
        Item {
            anchors.fill: parent
            focus: pop.visible
            Keys.onPressed: event => {
                const k = event.key;
                if (k === Qt.Key_Escape)
                    pop.close();
                else if (k === Qt.Key_Left || k === Qt.Key_H || k === Qt.Key_PageUp)
                    pop.go(-1);
                else if (k === Qt.Key_Right || k === Qt.Key_L || k === Qt.Key_PageDown)
                    pop.go(1);
                else if (k === Qt.Key_T || k === Qt.Key_Home)
                    pop.goToday();
                else
                    return;
                link.poke();
                event.accepted = true;
            }
        }

        // The wheel turns the month, a notch at a time (a touchpad sends many
        // small steps, so they add up to a notch first)
        WheelHandler {
            property real acc: 0

            onWheel: event => {
                acc += event.angleDelta.y;
                link.poke();
                if (Math.abs(acc) >= 120) {
                    pop.go(acc < 0 ? 1 : -1);
                    acc = 0;
                }
            }
        }

        anchors.fill: parent
        radius: Style.barRadius
        antialiasing: true
        color: Style.card
        border.width: 1
        border.color: Style.outline
        implicitHeight: col.implicitHeight + 28
        transformOrigin: Item.TopLeft

        // Light catching the top edge, as on the bar
        Rectangle {
            anchors.top: parent.top
            anchors.topMargin: 1
            anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width - Style.barRadius * 2
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

            x: 16
            y: 14
            width: parent.width - 32
            spacing: Style.spaceMd

            // ---- Month and arrows ------------------------------------------
            Item {
                width: parent.width
                height: 28

                Text {
                    id: title

                    anchors.verticalCenter: parent.verticalCenter
                    text: Qt.formatDate(pop.first, "MMMM yyyy")
                    textFormat: Text.PlainText
                    color: pop.offset !== 0 && titleHover.hovered ? Colors.accent : Colors.foreground

                    transform: Translate {
                        id: titleShift
                    }

                    Behavior on color {
                        ColorAnimation {
                            duration: Style.fadeMs
                        }
                    }

                    font {
                        family: Style.fontFamily
                        pixelSize: Style.fontLg
                        bold: true
                    }

                    TapHandler {
                        onTapped: pop.goToday()
                    }
                    HoverHandler {
                        id: titleHover

                        cursorShape: pop.offset !== 0 ? Qt.PointingHandCursor : Qt.ArrowCursor
                    }
                }

                Row {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2

                    // "Today": grows in while you are away from this month
                    Rectangle {
                        id: todayChip

                        property real presence: pop.offset !== 0 ? 1 : 0

                        anchors.verticalCenter: parent.verticalCenter
                        visible: width > 0.5
                        clip: true
                        implicitHeight: 22
                        implicitWidth: (chipText.implicitWidth + 18) * presence
                        radius: height / 2
                        antialiasing: true
                        opacity: presence
                        scale: chipTap.pressed ? 0.92 : 1
                        color: chipHover.hovered ? Qt.alpha(Colors.accent, 0.26) : Qt.alpha(Colors.accent, 0.16)

                        Behavior on presence {
                            NumberAnimation {
                                duration: Style.baseMs
                                easing.type: Style.easeMove
                            }
                        }
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

                        Text {
                            id: chipText

                            anchors.centerIn: parent
                            text: "Today"
                            textFormat: Text.PlainText
                            color: Colors.accent

                            font {
                                family: Style.fontFamily
                                pixelSize: Style.fontSm
                                weight: Font.Medium
                            }
                        }

                        TapHandler {
                            id: chipTap

                            onTapped: pop.goToday()
                        }
                        HoverHandler {
                            id: chipHover

                            cursorShape: Qt.PointingHandCursor
                        }
                    }

                    NavButton {
                        anchors.verticalCenter: parent.verticalCenter
                        glyph: 0xF0141
                        onClicked: pop.go(-1)
                    }
                    NavButton {
                        anchors.verticalCenter: parent.verticalCenter
                        glyph: 0xF0142
                        onClicked: pop.go(1)
                    }
                }
            }

            // ---- Weekdays --------------------------------------------------
            Row {
                Repeater {
                    model: ["M", "T", "W", "T", "F", "S", "S"]

                    delegate: Text {
                        required property string modelData
                        required property int index

                        width: 34
                        height: 22
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        text: modelData
                        color: Colors.muted
                        // The weekend sits a little further back
                        opacity: index >= 5 ? 0.6 : 1

                        font {
                            family: Style.fontFamily
                            pixelSize: Style.fontSm
                        }
                    }
                }
            }

            // ---- The days --------------------------------------------------
            Item {
                id: gridArea

                width: 34 * 7
                height: 32 * 6

                transform: Translate {
                    id: gridShift
                }

                // One highlight for the whole grid, gliding between days
                Rectangle {
                    id: hoverDot

                    x: (pop.lastHover % 7) * 34 + 2
                    y: Math.floor(pop.lastHover / 7) * 32 + 1
                    width: 30
                    height: 30
                    radius: 15
                    antialiasing: true
                    color: Style.hoverFill
                    opacity: pop.hoverIndex >= 0 ? 1 : 0

                    // Fading in from nothing, it appears in place instead of
                    // sliding over from wherever it last was
                    Behavior on x {
                        enabled: hoverDot.opacity > 0.05

                        NumberAnimation {
                            duration: Style.fadeMs
                            easing.type: Style.easeMove
                        }
                    }
                    Behavior on y {
                        enabled: hoverDot.opacity > 0.05

                        NumberAnimation {
                            duration: Style.fadeMs
                            easing.type: Style.easeMove
                        }
                    }
                    Behavior on opacity {
                        NumberAnimation {
                            duration: Style.fadeMs
                        }
                    }
                }

                Grid {
                    columns: 7

                    Repeater {
                        model: pop.cells

                        delegate: Item {
                            id: cell

                            required property int index

                            readonly property date day: pop.cellDate(index)
                            readonly property bool inMonth: day.getMonth() === pop.first.getMonth()
                            readonly property bool isToday: pop.sameDay(day, pop.today)
                            readonly property bool weekend: index % 7 >= 5

                            // The days rise in one after another when it opens
                            readonly property real inP: pop.clamp(pop.intro * 1.8 - 0.15 - Math.floor(index / 7) * 0.1 - (index % 7) * 0.012, 0, 1)

                            width: 34
                            height: 32
                            opacity: inP
                            transform: Translate {
                                y: (1 - cell.inP) * 8
                            }

                            // Today: a glass disc ringed in the accent, which breathes
                            Rectangle {
                                anchors.centerIn: parent
                                width: 36
                                height: 36
                                radius: 18
                                color: "transparent"
                                antialiasing: true
                                visible: cell.isToday
                                border.width: 1
                                border.color: Qt.alpha(Colors.accent, 0.12 + 0.18 * pop.breath)
                            }

                            Rectangle {
                                anchors.centerIn: parent
                                width: 30
                                height: 30
                                radius: 15
                                antialiasing: true
                                visible: cell.isToday
                                color: Qt.alpha(Colors.accent, Style.tintAlpha)
                                border.width: 1
                                border.color: Qt.alpha(Colors.accent, 0.9)
                            }

                            Text {
                                anchors.centerIn: parent
                                text: cell.day.getDate()
                                color: cell.isToday ? Colors.accent : (cell.inMonth ? (cell.weekend ? Qt.alpha(Colors.foreground, 0.7) : Colors.foreground) : Qt.alpha(Colors.muted, 0.45))

                                font {
                                    family: Style.fontFamily
                                    pixelSize: Style.fontMd
                                    bold: cell.isToday
                                }
                            }

                            // A day from the next or previous month takes you there
                            TapHandler {
                                enabled: !cell.inMonth
                                onTapped: pop.go(cell.day < pop.first ? -1 : 1)
                            }
                            HoverHandler {
                                cursorShape: cell.inMonth ? Qt.ArrowCursor : Qt.PointingHandCursor
                                onHoveredChanged: {
                                    if (hovered)
                                        pop.hoverIndex = cell.index;
                                    else if (pop.hoverIndex === cell.index)
                                        pop.hoverIndex = -1;
                                }
                            }
                        }
                    }
                }
            }

            // ---- The ruler: one tick per day of the month -------------------
            // A short curved arc, the launcher's ruler in miniature. The accent
            // marker stands on the day the footer talks about and glides when
            // that changes; the ticks beside it rise like a magnifier.
            Item {
                id: ruler

                // Where the marker is along the ruler, in pixels
                property real markX: pop.markDay >= 0 ? xOf(pop.markDay) : width / 2
                readonly property real inset: 10
                readonly property real step: pop.dim > 1 ? (width - inset * 2) / (pop.dim - 1) : 0

                function xOf(i) {
                    return inset + i * step;
                }

                // How far a point at x sits below the top of the arc
                function dropAt(x) {
                    const r = pop.arcNow;
                    return r - Math.sqrt(Math.max(0, r * r - (x - width / 2) * (x - width / 2)));
                }

                width: parent.width
                height: 38

                Behavior on markX {
                    enabled: pop.markDay >= 0

                    NumberAnimation {
                        duration: Style.moveMs
                        easing.type: Style.easeEnter
                    }
                }

                Repeater {
                    model: pop.dim

                    delegate: Rectangle {
                        id: tick

                        required property int index

                        readonly property real tx: ruler.xOf(index)
                        readonly property real a: (tx - ruler.width / 2) / pop.arcNow
                        readonly property bool major: (index + 1) % 7 === 0 || index === 0
                        // The ticks near the marker rise
                        readonly property real near: pop.markDay >= 0 ? Math.max(0, 1 - Math.abs(tx - ruler.markX) / 34) : 0
                        readonly property real arrive: pop.clamp(pop.intro * 2 - 0.3 - Math.abs(tx - ruler.width / 2) / ruler.width * 0.6, 0, 1)

                        x: tx - 0.75
                        y: 4 + ruler.dropAt(tx)
                        width: 1.5
                        height: (major ? 8 : 5) + 6 * near
                        radius: 0.75
                        antialiasing: true
                        transformOrigin: Item.Top
                        rotation: a * 180 / Math.PI
                        opacity: arrive
                        color: Qt.tint(pop.spectral(Colors.foreground, tx / ruler.width, major ? 0.5 : 0.3), Qt.alpha(Colors.accent, 0.8 * near))
                    }
                }

                // The accent marker, standing on the shown day
                Rectangle {
                    readonly property real a: (ruler.markX - ruler.width / 2) / pop.arcNow

                    visible: pop.markDay >= 0
                    x: ruler.markX - 1
                    y: 2 + ruler.dropAt(ruler.markX)
                    width: 2
                    height: 16
                    radius: 1
                    antialiasing: true
                    color: Colors.accent
                    transformOrigin: Item.Top
                    rotation: a * 180 / Math.PI
                    opacity: pop.clamp(pop.intro * 2 - 0.5, 0, 1)
                }
            }

            // ---- Footer: the day under the pointer, read out ----------------
            // The way the dial reads out its middle: the day in full, and under
            // it the week and how far away it is. It is today's accent while
            // it shows today.
            Column {
                width: parent.width
                spacing: Style.spaceXs
                opacity: pop.clamp(pop.intro * 2 - 0.4, 0, 1)

                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: Qt.formatDate(pop.shownDate, "dddd d MMMM")
                    textFormat: Text.PlainText
                    elide: Text.ElideRight
                    color: pop.sameDay(pop.shownDate, pop.today) ? Colors.accent : Colors.foreground

                    Behavior on color {
                        ColorAnimation {
                            duration: Style.fadeMs
                        }
                    }

                    font {
                        family: Style.fontFamily
                        pixelSize: Style.fontLg
                        bold: true
                    }
                }

                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: "Week " + pop.isoWeek(pop.shownDate) + "  \u00b7  " + pop.relative(pop.shownDate)
                    textFormat: Text.PlainText
                    elide: Text.ElideRight
                    color: pop.hoverIndex >= 0 ? Qt.alpha(Colors.foreground, 0.78) : Colors.muted

                    Behavior on color {
                        ColorAnimation {
                            duration: Style.fadeMs
                        }
                    }

                    font {
                        family: Style.fontFamily
                        pixelSize: Style.fontSm
                        letterSpacing: 1.4
                        capitalization: Font.AllUppercase
                    }
                }
            }
        }
    }
}
