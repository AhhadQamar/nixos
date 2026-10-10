// ScreenTime.qml
// Screen time panel in the clipboard / night light style, backed by `screentime panel` (modules/shell/screentime).
//
//   qs ipc call screentime toggle          open / close
//   qs ipc call screentime show week       open on day | week | month
//
// Keys:  esc close   ← → (h l) previous / next period   1 2 3 day / week / month
//        t jump to today   a show more / fewer apps   click an app for its windows

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

PanelWindow {
    id: panel

    // ---- Settings -------------------------------------------------------
    // Daily goal in minutes. 0 hides every goal marker.
    readonly property int dailyGoalMinutes: 360

    // ---- State ----------------------------------------------------------
    property string range: "day"
    property int offset: 0
    property string expandedApp: ""
    property bool showAll: false
    property int hoverIndex: -1
    property bool loadFailed: false
    property bool pendingRefresh: false
    // "range:offset" -> payload from `screentime panel`, so switching back and
    // forth is instant while a fresh copy loads in the background.
    property var cache: ({})

    readonly property var emptyView: ({
            "total": 0,
            "prev_total": 0,
            "avg": 0,
            "label": "",
            "sublabel": "",
            "vs": "",
            "apps": [],
            "app_count": 0,
            "categories": [],
            "days": [],
            "hours": new Array(24).fill(0),
            "sessions": 0,
            "longest": 0,
            "first": "",
            "last": "",
            "now": null,
            "any_data": true,
            "has_older": false
        })
    readonly property string cacheKey: range + ":" + offset
    readonly property bool ready: cache[cacheKey] !== undefined
    readonly property var view: cache[cacheKey] || emptyView

    // ---- Derived --------------------------------------------------------
    readonly property bool dayView: range === "day"
    readonly property bool hasData: ready && view.total > 0
    readonly property real goalSec: dailyGoalMinutes * 60
    readonly property bool overGoal: dayView && goalSec > 0 && view.total > goalSec

    readonly property bool hasDelta: view.prev_total > 0 && view.total > 0
    readonly property real deltaPct: hasDelta ? (view.total - view.prev_total) / view.prev_total * 100 : 0
    readonly property color deltaColor: Math.abs(deltaPct) < 2 ? Colors.muted : (deltaPct < 0 ? Colors.success : Colors.critical)

    // Chart: 24 hours for a day, one bar per day otherwise
    readonly property var bars: dayView ? view.hours : view.days.map(function (d) {
        return d[1];
    })
    readonly property real barMax: Math.max(1, Math.max.apply(null, bars))
    readonly property bool goalInRange: !dayView && goalSec > 0 && goalSec <= barMax * 1.6
    // A day's hour bar is "share of that hour", so its scale is fixed at 60 minutes.
    readonly property real chartMax: dayView ? 3600 : (goalInRange ? Math.max(barMax, goalSec) : barMax)
    readonly property int peakIndex: {
        let best = -1;
        let top = 0;
        for (let i = 0; i < bars.length; i++) {
            if (bars[i] > top) {
                top = bars[i];
                best = i;
            }
        }
        return best;
    }
    readonly property string readoutLabel: {
        if (hoverIndex >= 0 && hoverIndex < bars.length)
            return dayView ? pad2(hoverIndex) + ":00 to " + pad2((hoverIndex + 1) % 24) + ":00" : dayAt(hoverIndex);
        if (peakIndex < 0)
            return "";
        return dayView ? "Busiest around " + pad2(peakIndex) + ":00" : "Busiest day, " + dayAt(peakIndex);
    }
    readonly property string readoutValue: {
        const i = hoverIndex >= 0 && hoverIndex < bars.length ? hoverIndex : peakIndex;
        return i < 0 ? "" : fmt(bars[i]);
    }

    readonly property var visibleApps: view.apps.slice(0, showAll ? 12 : 6)
    readonly property real topAppSec: view.apps.length > 0 ? Math.max(1, view.apps[0].sec) : 1

    readonly property var statTiles: dayView ? [
        {
            "v": view.first !== "" ? view.first + "\u2013" + view.last : "None",
            "k": "Active"
        },
        {
            "v": fmt(view.longest),
            "k": "Longest stretch"
        },
        {
            "v": String(view.sessions),
            "k": "Sessions"
        },
        {
            "v": String(view.app_count),
            "k": "Apps used"
        }
    ] : [
        {
            "v": fmt(view.avg),
            "k": "Daily average"
        },
        {
            "v": dayAt(peakIndex) !== "" ? dayAt(peakIndex) : "None",
            "k": "Busiest day"
        },
        {
            "v": fmt(view.longest),
            "k": "Longest stretch"
        },
        {
            "v": String(view.sessions),
            "k": "Sessions"
        }
    ]

    readonly property string heroSub: {
        if (!ready)
            return "";
        if (!dayView)
            return "average " + fmt(view.avg) + " a day";
        if (goalSec <= 0)
            return "screen time";
        return overGoal ? "over your " + fmt(goalSec) + " goal by " + fmt(view.total - goalSec) : fmt(goalSec - view.total) + " left of your " + fmt(goalSec) + " goal";
    }

    // ---- Helpers --------------------------------------------------------
    function pad2(n) {
        return (n < 10 ? "0" : "") + n;
    }

    function fmt(sec) {
        const m = Math.round(sec / 60);
        if (sec > 0 && m === 0)
            return "<1m";
        const h = Math.floor(m / 60);
        if (h > 0)
            return h + "h " + pad2(m % 60) + "m";
        return m + "m";
    }

    // Date label for bar i of a week / month view ("" while data is switching)
    function dayAt(i) {
        if (i < 0 || i >= view.days.length)
            return "";
        return Qt.formatDate(new Date(view.days[i][0] + "T00:00:00"), "ddd d MMM");
    }

    // One colour per category, stable across periods (index from screentime.py)
    function catColor(idx) {
        const palette = [Colors.color4, Colors.color2, Colors.color3, Colors.color5, Colors.color6, Colors.color1, Colors.color7];
        return idx < palette.length ? palette[idx] : Colors.muted;
    }

    function isCurrent(i) {
        if (offset !== 0)
            return false;
        return dayView ? i === new Date().getHours() : i === bars.length - 1;
    }

    function showAxis(i) {
        if (dayView)
            return i % 6 === 0;
        if (range === "week")
            return true;
        return i % 5 === 0 || i === bars.length - 1;
    }

    function axisLabel(i) {
        if (dayView)
            return pad2(i);
        if (i >= view.days.length)
            return "";
        const d = new Date(view.days[i][0] + "T00:00:00");
        return range === "week" ? Qt.formatDate(d, "ddd") : String(d.getDate());
    }

    // ---- Actions --------------------------------------------------------
    function refresh() {
        if (fetcher.running) {
            pendingRefresh = true;
            return;
        }
        fetcher.command = ["screentime", "panel", range, String(offset)];
        fetcher.running = true;
    }

    function resetUi() {
        expandedApp = "";
        hoverIndex = -1;
    }

    function setRange(r) {
        if (r === range)
            return;
        range = r;
        offset = 0;
        resetUi();
        refresh();
    }

    // dir: 1 = one period back, -1 = one period forward
    function step(dir) {
        const next = offset + dir;
        if (next < 0 || (dir > 0 && !view.has_older))
            return;
        offset = next;
        resetUi();
        refresh();
    }

    function goToday() {
        if (offset === 0)
            return;
        offset = 0;
        resetUi();
        refresh();
    }

    function open() {
        offset = 0;
        resetUi();
        visible = true;
        refresh();
        keys.forceActiveFocus();
        fadeIn.restart();
    }

    function close() {
        visible = false;
    }

    function toggle() {
        if (visible)
            close();
        else
            open();
    }

    // ---- Window ---------------------------------------------------------
    // Anchored to the top edge only and exactly as tall as the card, like the
    // clipboard manager. This one is a tall panel, so it sits a little higher
    // (screen height / 8) and is capped at the screen height: past that the
    // card scrolls.
    readonly property int topGap: Math.round(Screen.height / 8)

    visible: false
    color: "transparent"
    margins.top: topGap
    implicitWidth: 560
    implicitHeight: Math.min(card.implicitHeight, Screen.height - topGap - 40)
    exclusiveZone: 0
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

    anchors {
        top: true
    }

    IpcHandler {
        function toggle() {
            panel.toggle();
        }

        function open() {
            panel.open();
        }

        function close() {
            panel.close();
        }

        function show(r: string): void {
            if (r !== "day" && r !== "week" && r !== "month")
                return;
            panel.range = r;
            panel.open();
        }

        target: "screentime"
    }

    // Keep numbers fresh while the panel is open
    Timer {
        interval: 15000
        repeat: true
        running: panel.visible
        onTriggered: panel.refresh()
    }

    Process {
        id: fetcher

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(text);
                    const c = Object.assign({}, panel.cache);
                    c[d.range + ":" + d.offset] = d;
                    panel.cache = c;
                    panel.loadFailed = false;
                } catch (e) {
                    panel.loadFailed = true;
                }
            }
        }
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0)
                panel.loadFailed = true;
            if (panel.pendingRefresh) {
                panel.pendingRefresh = false;
                panel.refresh();
            }
        }
    }

    // Keyboard handling
    Item {
        id: keys

        anchors.fill: parent
        focus: panel.visible
        Keys.onPressed: event => {
            const k = event.key;
            if (k === Qt.Key_Escape)
                panel.close();
            else if (k === Qt.Key_Left || k === Qt.Key_H)
                panel.step(1);
            else if (k === Qt.Key_Right || k === Qt.Key_L)
                panel.step(-1);
            else if (k === Qt.Key_1)
                panel.setRange("day");
            else if (k === Qt.Key_2)
                panel.setRange("week");
            else if (k === Qt.Key_3)
                panel.setRange("month");
            else if (k === Qt.Key_T || k === Qt.Key_Home)
                panel.goToday();
            else if (k === Qt.Key_A)
                panel.showAll = !panel.showAll;
        }
    }

    // ---- Small building blocks --------------------------------------------
    // Text in the shell font. Every label below uses this, so none of them
    // can fall back to the system default font.
    component Txt: Text {
        textFormat: Text.PlainText
        font.family: Style.fontFamily
    }

    // Keyboard hint
    component KeyCap: Rectangle {
        id: cap

        property string label: ""

        implicitWidth: Math.max(20, capText.implicitWidth + 12)
        implicitHeight: 20
        radius: 5
        color: Colors.surfaceAlt

        Txt {
            id: capText

            anchors.centerIn: parent
            text: cap.label
            color: Colors.foreground
            opacity: 0.75
            font.pixelSize: 10
            font.bold: true
        }
    }

    // Round arrow button for the period navigation. Dimmed and inert when
    // there is nowhere to go.
    component IconButton: Rectangle {
        id: btn

        property string glyph: ""
        property bool active: true

        signal clicked

        implicitWidth: Style.itemHeight
        implicitHeight: Style.itemHeight
        radius: height / 2
        antialiasing: true
        color: active && btnHover.hovered ? Style.hoverFill : "transparent"
        opacity: active ? 1.0 : 0.3
        scale: active && btnTap.pressed ? 0.94 : 1

        Behavior on color {
            ColorAnimation {
                duration: 200
            }
        }
        Behavior on scale {
            NumberAnimation {
                duration: 100
                easing.type: Easing.OutQuad
            }
        }

        Txt {
            anchors.centerIn: parent
            text: btn.glyph
            color: btn.active && btnHover.hovered ? Colors.foreground : Colors.muted
            font.pixelSize: 16
        }

        HoverHandler {
            id: btnHover

            cursorShape: btn.active ? Qt.PointingHandCursor : Qt.ArrowCursor
        }

        TapHandler {
            id: btnTap

            onTapped: if (btn.active)
                btn.clicked()
        }
    }

    ParallelAnimation {
        id: fadeIn

        NumberAnimation {
            target: card
            property: "opacity"
            from: 0
            to: 1
            duration: 140
            easing.type: Easing.OutCubic
        }

        NumberAnimation {
            target: card
            property: "scale"
            from: 0.97
            to: 1
            duration: 140
            easing.type: Easing.OutCubic
        }
    }

    // ---- The card -------------------------------------------------------
    Rectangle {
        id: card

        anchors.fill: parent
        implicitHeight: content.implicitHeight + 28
        radius: Style.barRadius
        antialiasing: true
        // More solid than the bar: this card sits over other windows' text
        color: Qt.alpha(Colors.background, 0.97)
        border.width: 1
        border.color: Style.outline

        Flickable {
            id: flick

            anchors.fill: parent
            anchors.margins: 14
            contentWidth: width
            contentHeight: content.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            interactive: contentHeight > height

            ColumnLayout {
                id: content

                width: flick.width
                spacing: 12

                // ---- Title + range switch --------------------------------
                RowLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: 6
                    spacing: 2

                    Txt {
                        text: "Screen time"
                        color: Colors.foreground
                        font.pixelSize: 14
                        font.bold: true
                    }

                    Item {
                        Layout.fillWidth: true
                    }

                    // Day / Week / Month: transparent pills, accent-tinted
                    // while selected (same as the Inbox mode buttons)
                    Repeater {
                        model: ["day", "week", "month"]

                        delegate: Rectangle {
                            id: seg

                            required property string modelData

                            readonly property bool active: panel.range === modelData

                            implicitWidth: segText.implicitWidth + 24
                            implicitHeight: Style.itemHeight
                            radius: height / 2
                            antialiasing: true
                            color: active ? Qt.alpha(Colors.accent, 0.2) : (segHover.hovered ? Style.hoverFill : "transparent")
                            scale: segTap.pressed ? 0.94 : 1

                            Behavior on color {
                                ColorAnimation {
                                    duration: 200
                                }
                            }
                            Behavior on scale {
                                NumberAnimation {
                                    duration: 100
                                    easing.type: Easing.OutQuad
                                }
                            }

                            Txt {
                                id: segText

                                anchors.centerIn: parent
                                text: seg.modelData.charAt(0).toUpperCase() + seg.modelData.slice(1)
                                color: seg.active ? Colors.accent : (segHover.hovered ? Colors.foreground : Colors.muted)
                                font.pixelSize: 13

                                Behavior on color {
                                    ColorAnimation {
                                        duration: 200
                                    }
                                }
                            }

                            HoverHandler {
                                id: segHover

                                cursorShape: Qt.PointingHandCursor
                            }

                            TapHandler {
                                id: segTap

                                onTapped: panel.setRange(seg.modelData)
                            }
                        }
                    }
                }

                // ---- Period navigation ------------------------------------
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10

                    IconButton {
                        glyph: "\uf104"
                        active: panel.view.has_older
                        onClicked: panel.step(1)
                    }

                    // Click the title to jump back to the present
                    Item {
                        Layout.fillWidth: true
                        implicitHeight: titleCol.implicitHeight

                        ColumnLayout {
                            id: titleCol

                            anchors.centerIn: parent
                            spacing: 1

                            Txt {
                                Layout.alignment: Qt.AlignHCenter
                                text: panel.view.label
                                color: Colors.foreground
                                font.pixelSize: 14
                                font.bold: true
                            }

                            Txt {
                                Layout.alignment: Qt.AlignHCenter
                                text: panel.view.sublabel
                                color: Colors.muted
                                font.pixelSize: 11
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: panel.offset > 0 ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onClicked: panel.goToday()
                        }
                    }

                    IconButton {
                        glyph: "\uf105"
                        active: panel.offset > 0
                        onClicked: panel.step(-1)
                    }
                }

                // ---- Total, comparison, current app ------------------------
                RowLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: 6
                    Layout.rightMargin: 6
                    spacing: 14

                    ColumnLayout {
                        spacing: 0

                        Txt {
                            text: panel.ready ? panel.fmt(panel.view.total) : "\u2013"
                            color: panel.overGoal ? Colors.critical : Colors.foreground
                            font.pixelSize: 40
                            font.bold: true
                        }

                        Txt {
                            text: panel.heroSub
                            color: panel.overGoal ? Colors.critical : Colors.muted
                            font.pixelSize: 12
                        }
                    }

                    Item {
                        Layout.fillWidth: true
                    }

                    ColumnLayout {
                        Layout.alignment: Qt.AlignTop | Qt.AlignRight
                        spacing: 6

                        // vs the previous period
                        ColumnLayout {
                            visible: panel.hasDelta
                            Layout.alignment: Qt.AlignRight
                            spacing: 3

                            Rectangle {
                                Layout.alignment: Qt.AlignRight
                                implicitWidth: deltaText.implicitWidth + 20
                                implicitHeight: 24
                                radius: height / 2
                                antialiasing: true
                                color: Qt.alpha(panel.deltaColor, 0.16)

                                Txt {
                                    id: deltaText

                                    anchors.centerIn: parent
                                    text: Math.abs(panel.deltaPct) < 2 ? "about the same" : (panel.deltaPct < 0 ? "\u25bc " : "\u25b2 ") + Math.round(Math.abs(panel.deltaPct)) + "%" + (panel.deltaPct < 0 ? " less" : " more")
                                    color: panel.deltaColor
                                    font.pixelSize: 12
                                    font.bold: true
                                }
                            }

                            Txt {
                                Layout.alignment: Qt.AlignRight
                                text: "than " + panel.view.vs
                                color: Colors.muted
                                font.pixelSize: 11
                            }
                        }

                        // what is on screen right now
                        Rectangle {
                            id: nowChip

                            visible: !!panel.view.now
                            Layout.alignment: Qt.AlignRight
                            Layout.maximumWidth: 220
                            implicitWidth: nowRow.implicitWidth + 20
                            implicitHeight: 26
                            radius: height / 2
                            antialiasing: true
                            color: Style.hoverFill

                            RowLayout {
                                id: nowRow

                                anchors.centerIn: parent
                                spacing: 7

                                Rectangle {
                                    width: 8
                                    height: 8
                                    radius: 4
                                    color: Colors.success

                                    SequentialAnimation on opacity {
                                        running: panel.visible && nowChip.visible
                                        loops: Animation.Infinite

                                        NumberAnimation {
                                            to: 0.25
                                            duration: 900
                                            easing.type: Easing.InOutSine
                                        }

                                        NumberAnimation {
                                            to: 1.0
                                            duration: 900
                                            easing.type: Easing.InOutSine
                                        }
                                    }
                                }

                                Txt {
                                    text: panel.view.now ? panel.view.now.name : ""
                                    color: Colors.foreground
                                    font.pixelSize: 12
                                    font.bold: true
                                }

                                Txt {
                                    Layout.maximumWidth: 110
                                    visible: text !== ""
                                    text: panel.view.now ? panel.view.now.title : ""
                                    elide: Text.ElideRight
                                    color: Colors.muted
                                    font.pixelSize: 12
                                }
                            }
                        }
                    }
                }

                // ---- Goal progress (single day) -----------------------------
                // Same track and fill as the volume / brightness OSD
                Rectangle {
                    visible: panel.dayView && panel.goalSec > 0
                    Layout.fillWidth: true
                    Layout.leftMargin: 6
                    Layout.rightMargin: 6
                    Layout.topMargin: -4
                    implicitHeight: 6
                    radius: 3
                    antialiasing: true
                    color: Style.hoverFill

                    Rectangle {
                        width: parent.width * Math.min(1, panel.view.total / Math.max(1, panel.goalSec))
                        height: parent.height
                        radius: 3
                        antialiasing: true
                        color: panel.overGoal ? Colors.critical : Colors.accent

                        Behavior on width {
                            NumberAnimation {
                                duration: 220
                                easing.type: Easing.OutCubic
                            }
                        }
                        Behavior on color {
                            ColorAnimation {
                                duration: 200
                            }
                        }
                    }
                }

                // ---- Empty / error states -----------------------------------
                ColumnLayout {
                    visible: panel.ready && !panel.hasData || panel.loadFailed
                    Layout.fillWidth: true
                    Layout.topMargin: 10
                    Layout.bottomMargin: 10
                    spacing: 6

                    Txt {
                        Layout.alignment: Qt.AlignHCenter
                        text: panel.loadFailed ? "Couldn't read screen time data" : (panel.view.any_data ? "Nothing recorded for this period" : "No data yet")
                        color: Colors.foreground
                        font.pixelSize: 14
                        font.bold: true
                    }

                    Txt {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WordWrap
                        text: panel.loadFailed ? "Run `screentime panel day 0` in a terminal to see the error." : (panel.view.any_data ? "Use the arrows to look at another day." : "The logger starts with Hyprland. To start it now, run `screentime log` in a terminal.")
                        color: Colors.muted
                        font.pixelSize: 12
                    }
                }

                // ---- Activity chart ------------------------------------------
                ColumnLayout {
                    visible: panel.hasData
                    Layout.fillWidth: true
                    Layout.leftMargin: 6
                    Layout.rightMargin: 6
                    spacing: 8

                    RowLayout {
                        Layout.fillWidth: true

                        Txt {
                            text: panel.readoutLabel
                            color: Colors.muted
                            elide: Text.ElideRight
                            font.pixelSize: 12
                            Layout.fillWidth: true
                        }

                        Txt {
                            text: panel.readoutValue
                            color: Colors.foreground
                            font.pixelSize: 12
                            font.bold: true
                        }
                    }

                    Item {
                        id: chart

                        readonly property real plotHeight: height - 18

                        Layout.fillWidth: true
                        Layout.preferredHeight: 100

                        RowLayout {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            height: chart.plotHeight
                            spacing: panel.bars.length > 7 ? 3 : 10

                            Repeater {
                                model: panel.bars

                                delegate: Item {
                                    id: col

                                    required property int index
                                    required property var modelData

                                    readonly property bool current: panel.isCurrent(index)
                                    readonly property bool over: !panel.dayView && panel.goalSec > 0 && modelData > panel.goalSec
                                    readonly property bool hot: panel.hoverIndex === index

                                    Layout.fillWidth: true
                                    Layout.fillHeight: true

                                    // faint track so empty hours still read as part of the strip
                                    Rectangle {
                                        anchors.fill: parent
                                        radius: 4
                                        antialiasing: true
                                        color: Style.hoverFill
                                    }

                                    Rectangle {
                                        anchors.bottom: parent.bottom
                                        width: parent.width
                                        height: col.modelData > 0 ? Math.max(4, parent.height * Math.min(1, col.modelData / panel.chartMax)) : 0
                                        radius: 4
                                        antialiasing: true
                                        color: col.over ? Colors.critical : Colors.accent
                                        opacity: col.current || col.hot ? 1.0 : 0.62

                                        Behavior on height {
                                            NumberAnimation {
                                                duration: 200
                                                easing.type: Easing.OutCubic
                                            }
                                        }

                                        Behavior on opacity {
                                            NumberAnimation {
                                                duration: 100
                                            }
                                        }
                                    }

                                    Txt {
                                        visible: panel.showAxis(col.index)
                                        anchors.top: parent.bottom
                                        anchors.topMargin: 5
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        text: panel.axisLabel(col.index)
                                        color: col.current ? Colors.foreground : Colors.muted
                                        font.pixelSize: 10
                                        font.bold: col.current
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        onEntered: panel.hoverIndex = col.index
                                        onExited: if (panel.hoverIndex === col.index)
                                            panel.hoverIndex = -1
                                    }
                                }
                            }
                        }

                        // Goal line across the daily bars
                        Rectangle {
                            visible: panel.goalInRange
                            anchors.left: parent.left
                            anchors.right: parent.right
                            y: chart.plotHeight * (1 - panel.goalSec / panel.chartMax)
                            height: 1
                            color: Colors.critical
                            opacity: 0.6

                            Txt {
                                anchors.right: parent.right
                                anchors.bottom: parent.top
                                anchors.bottomMargin: 2
                                text: "goal " + panel.fmt(panel.goalSec)
                                color: Colors.critical
                                font.pixelSize: 10
                            }
                        }
                    }
                }

                // ---- Where the time went (categories) ------------------------
                ColumnLayout {
                    visible: panel.hasData
                    Layout.fillWidth: true
                    Layout.leftMargin: 6
                    Layout.rightMargin: 6
                    spacing: 10

                    Row {
                        id: catBar

                        Layout.fillWidth: true
                        spacing: 2

                        Repeater {
                            model: panel.view.categories

                            delegate: Rectangle {
                                id: seg2

                                required property var modelData

                                width: Math.max(4, (catBar.width - (panel.view.categories.length - 1) * catBar.spacing) * modelData.sec / Math.max(1, panel.view.total))
                                height: 8
                                radius: 4
                                antialiasing: true
                                color: panel.catColor(modelData.idx)

                                Behavior on width {
                                    NumberAnimation {
                                        duration: 200
                                        easing.type: Easing.OutCubic
                                    }
                                }
                            }
                        }
                    }

                    Flow {
                        Layout.fillWidth: true
                        Layout.preferredHeight: childrenRect.height
                        spacing: 16

                        Repeater {
                            model: panel.view.categories

                            delegate: Row {
                                id: legend

                                required property var modelData

                                spacing: 6

                                Txt {
                                    text: "\u25cf"
                                    color: panel.catColor(legend.modelData.idx)
                                    font.pixelSize: 11
                                }

                                Txt {
                                    text: legend.modelData.name
                                    color: Colors.foreground
                                    font.pixelSize: 12
                                }

                                Txt {
                                    text: panel.fmt(legend.modelData.sec)
                                    color: Colors.muted
                                    font.pixelSize: 12
                                }
                            }
                        }
                    }
                }

                // ---- Apps -------------------------------------------------------
                // Same rows as the clipboard history: a soft fill on hover,
                // and the 2px accent marker standing at the left of the one
                // that is expanded.
                ColumnLayout {
                    visible: panel.hasData
                    Layout.fillWidth: true
                    spacing: 2

                    Repeater {
                        model: panel.visibleApps

                        delegate: Rectangle {
                            id: row

                            required property var modelData

                            readonly property bool expanded: panel.expandedApp === modelData.class
                            readonly property color tint: panel.catColor(modelData.cat)

                            Layout.fillWidth: true
                            implicitHeight: rowContent.implicitHeight + 16
                            radius: Math.min(16, height / 2)
                            antialiasing: true
                            clip: true
                            color: rowArea.containsMouse || expanded ? Style.hoverFill : "transparent"

                            Behavior on implicitHeight {
                                NumberAnimation {
                                    duration: 150
                                    easing.type: Easing.OutCubic
                                }
                            }

                            Behavior on color {
                                ColorAnimation {
                                    duration: 120
                                }
                            }

                            MouseArea {
                                id: rowArea

                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: panel.expandedApp = row.expanded ? "" : row.modelData.class
                            }

                            // Selection marker, level with the first line
                            Rectangle {
                                visible: row.expanded
                                anchors.left: parent.left
                                anchors.leftMargin: 4
                                y: 8 + 15 - height / 2
                                width: 2
                                height: 16
                                radius: 1
                                color: row.tint
                            }

                            ColumnLayout {
                                id: rowContent

                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.margins: 8
                                anchors.leftMargin: 12
                                anchors.rightMargin: 12
                                spacing: 8

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 10

                                    // Round badge in the app's category colour
                                    Rectangle {
                                        implicitWidth: 30
                                        implicitHeight: 30
                                        radius: 15
                                        antialiasing: true
                                        color: Qt.alpha(row.tint, 0.2)

                                        Txt {
                                            anchors.centerIn: parent
                                            text: row.modelData.name.charAt(0).toUpperCase()
                                            color: row.tint
                                            font.pixelSize: 14
                                            font.bold: true
                                        }
                                    }

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 5

                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: 8

                                            Txt {
                                                text: row.modelData.name
                                                color: Colors.foreground
                                                elide: Text.ElideRight
                                                font.pixelSize: 13
                                                Layout.fillWidth: true
                                            }

                                            Txt {
                                                text: panel.fmt(row.modelData.sec)
                                                color: Colors.foreground
                                                font.pixelSize: 12
                                                font.bold: true
                                            }

                                            Txt {
                                                text: Math.round(row.modelData.sec / Math.max(1, panel.view.total) * 100) + "%"
                                                color: Colors.muted
                                                font.pixelSize: 11
                                                horizontalAlignment: Text.AlignRight
                                                Layout.preferredWidth: 32
                                            }

                                            Txt {
                                                text: row.expanded ? "\uf106" : "\uf107"
                                                color: Colors.muted
                                                font.pixelSize: 13
                                            }
                                        }

                                        Rectangle {
                                            Layout.fillWidth: true
                                            implicitHeight: 3
                                            radius: 2
                                            antialiasing: true
                                            color: Style.hoverFill

                                            Rectangle {
                                                width: parent.width * row.modelData.sec / panel.topAppSec
                                                height: parent.height
                                                radius: 2
                                                antialiasing: true
                                                color: row.tint

                                                Behavior on width {
                                                    NumberAnimation {
                                                        duration: 200
                                                        easing.type: Easing.OutCubic
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }

                                // The windows behind this app, biggest first
                                Repeater {
                                    model: row.expanded ? row.modelData.titles : []

                                    delegate: RowLayout {
                                        id: titleRow

                                        required property var modelData

                                        Layout.fillWidth: true
                                        Layout.leftMargin: 40
                                        spacing: 8

                                        Txt {
                                            text: titleRow.modelData[0] !== "" ? titleRow.modelData[0] : "(untitled)"
                                            color: Colors.foreground
                                            opacity: 0.85
                                            elide: Text.ElideRight
                                            font.pixelSize: 12
                                            Layout.fillWidth: true
                                        }

                                        Txt {
                                            text: panel.fmt(titleRow.modelData[1])
                                            color: Colors.muted
                                            font.pixelSize: 11
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Txt {
                        visible: panel.view.apps.length > 6
                        Layout.alignment: Qt.AlignHCenter
                        Layout.topMargin: 4
                        text: panel.showAll ? "Show fewer" : "Show more"
                        color: moreArea.containsMouse ? Colors.accent : Colors.muted
                        font.pixelSize: 12

                        Behavior on color {
                            ColorAnimation {
                                duration: 200
                            }
                        }

                        MouseArea {
                            id: moreArea

                            anchors.fill: parent
                            anchors.margins: -6
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: panel.showAll = !panel.showAll
                        }
                    }
                }

                // ---- Summary strip ----------------------------------------------
                Rectangle {
                    visible: panel.hasData
                    Layout.fillWidth: true
                    Layout.preferredHeight: 58
                    radius: 18
                    antialiasing: true
                    color: Style.hoverFill

                    RowLayout {
                        anchors.fill: parent
                        spacing: 0

                        Repeater {
                            model: panel.statTiles

                            delegate: Item {
                                id: tileItem

                                required property int index
                                required property var modelData

                                Layout.fillWidth: true
                                Layout.preferredWidth: 1
                                Layout.fillHeight: true

                                ColumnLayout {
                                    anchors.centerIn: parent
                                    spacing: 2

                                    Txt {
                                        Layout.alignment: Qt.AlignHCenter
                                        text: tileItem.modelData.v
                                        color: Colors.foreground
                                        font.pixelSize: 14
                                        font.bold: true
                                    }

                                    Txt {
                                        Layout.alignment: Qt.AlignHCenter
                                        text: tileItem.modelData.k
                                        color: Colors.muted
                                        font.pixelSize: 11
                                    }
                                }

                                Rectangle {
                                    visible: tileItem.index > 0
                                    anchors.left: parent.left
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 1
                                    height: parent.height * 0.5
                                    color: Style.outline
                                }
                            }
                        }
                    }
                }

                // ---- Key hints ----------------------------------------------------
                RowLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: 6
                    spacing: 6

                    KeyCap {
                        label: "\u2190 \u2192"
                    }

                    Txt {
                        text: "period"
                        color: Colors.muted
                        rightPadding: 8
                        font.pixelSize: 11
                    }

                    KeyCap {
                        label: "1 2 3"
                    }

                    Txt {
                        text: "range"
                        color: Colors.muted
                        rightPadding: 8
                        font.pixelSize: 11
                    }

                    KeyCap {
                        label: "t"
                    }

                    Txt {
                        text: "today"
                        color: Colors.muted
                        rightPadding: 8
                        font.pixelSize: 11
                    }

                    KeyCap {
                        label: "a"
                    }

                    Txt {
                        text: "more apps"
                        color: Colors.muted
                        rightPadding: 8
                        font.pixelSize: 11
                    }

                    KeyCap {
                        label: "esc"
                    }

                    Txt {
                        text: "close"
                        color: Colors.muted
                        font.pixelSize: 11
                    }

                    Item {
                        Layout.fillWidth: true
                    }
                }
            }
        }
    }
}
