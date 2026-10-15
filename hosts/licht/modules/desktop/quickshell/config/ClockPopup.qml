// Timer, Pomodoro, stopwatch and alarms in a card that grows out of the clock,
// like the calendar. The state lives in Clocks.qml; this file is only the
// interface.
//   - Right-click the clock (or click the time-left chip beside it) to open;
//     click anywhere else to close.
//   - The tabs along the top change view. Each view is the same card: a ring
//     with the time in it, a short curved ruler, the thing read out in words, a
//     strip of chips, and the few buttons.
//       Timer      the ring drains with the time left. The chips are lengths (the
//                  presets in Config.qml, plus whatever + / - makes); click one
//                  to set the timer to it (a running timer restarts with it).
//       Pomodoro   the ring drains with the phase. The chips are the cycle:
//                  focus (accent), breaks (green), the long break last. Done ones
//                  carry a tick; click one to switch to it (stopped).
//       Stopwatch  the ring sweeps once a minute. The last three laps are listed.
//       Alarms     the ring is the time until the selected alarm rings. The chips
//                  are the alarms, dim while off; click one to select it, "+" adds
//                  one an hour from now.
//   - The ruler is the countdown in miniature: the accent marker stands where the
//     time has got to and the ticks behind it are lit; on the stopwatch it is the
//     minute, on an alarm the day.
//   - It arrives as the calendar does: the ruler unfurls from a tight dome into
//     the calm arc, washed with the wallpaper's palette, and the rows rise in.
//   qs ipc call clock toggle | open | close | show <timer|pomodoro|stopwatch|alarms>
//                     timer <minutes> | pomodoro | stopwatch | alarm <HH:MM>
// Keys: 1 2 3 4 (Tab, Shift+Tab) change view      Esc close
//       Space (Enter) start or pause (alarms: turn on or off)
//       ← → previous / next chip (timer: only while it is stopped)
//       r reset   s skip the Pomodoro phase   m mark a lap   n add an alarm
//       - / +  shorten / lengthen the timer or move the alarm by 5 minutes
//       [ / ]  the same by 5 minutes on the timer, one hour on an alarm
//       d daily or once   Delete (Backspace, x) remove the alarm
// Holding Space, Enter, r, s, m, n, d, Delete or x does not repeat. - + [ ] and
// the arrows do.
// Nothing here runs while it is closed: the breath stops, and Clocks.qml ticks
// only for what is running.

import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Hyprland

PopupWindow {
    id: pop

    // The bar window this hangs from, and the item it hangs under
    required property var barWindow
    required property Item target

    readonly property bool open: visible

    // 0 timer, 1 Pomodoro, 2 stopwatch, 3 alarms
    property int view: 0
    // The selected alarm, as an index into Clocks.alarms (-1: the first by time)
    property int selAlarm: -1
    property double closedAt: 0
    // 1 = tight rainbow dome with spectral tint, 0 = the resting arc
    property real fan: 1
    // 0 -> 1 each time it opens: the rows rise in one after another
    property real intro: 1
    // A slow pulse (0..1) for the ring while something runs
    property real breath: 0

    readonly property int contentW: 288
    readonly property var viewLabels: ["Timer", "Pomodoro", "Stopwatch", "Alarms"]
    readonly property var viewNames: ["timer", "pomodoro", "stopwatch", "alarms"]
    readonly property var phaseNames: ({
            "focus": "Focus",
            "short": "Short break",
            "long": "Long break"
        })
    // The ruler's arc: the radius it rests at and the dome it arrives as
    readonly property real arcR: 520
    readonly property real domeR: 280
    readonly property real arcNow: 1 / (1 / arcR + (1 / domeR - 1 / arcR) * fan)
    // The strip of chips has the same height in every view, so the card never
    // changes height between tabs
    readonly property int stripH: 54
    // Only the bar on the screen that has focus answers the IPC calls
    readonly property bool focusedHere: barWindow.screen === Focus.screen

    // ---- What is on show ---------------------------------------------------
    // Alarm indexes in time order
    readonly property var alarmOrder: {
        const order = [];
        for (let i = 0; i < Clocks.alarms.length; i++)
            order.push(i);
        order.sort((a, b) => Clocks.alarms[a].min - Clocks.alarms[b].min);
        return order;
    }
    readonly property int alarmCur: {
        if (selAlarm >= 0 && selAlarm < Clocks.alarms.length)
            return selAlarm;
        return alarmOrder.length > 0 ? alarmOrder[0] : -1;
    }
    // The timer's chips: the presets and the current length, in order
    readonly property var timerMins: {
        const mins = [];
        for (const m of Config.timerPresets) {
            if (mins.indexOf(m) < 0)
                mins.push(m);
        }
        const now = Math.round(Clocks.tmrTotal / 60000);
        if (mins.indexOf(now) < 0)
            mins.push(now);
        mins.sort((a, b) => a - b);
        return mins;
    }
    // The Pomodoro chip the cycle is on right now
    readonly property int pomIndex: {
        const n = 2 * Config.pomodoroLongEvery;
        if (Clocks.pomPhase === "focus")
            return 2 * Clocks.pomCount;
        if (Clocks.pomPhase === "long")
            return n - 1;
        return Math.max(1, 2 * Clocks.pomCount - 1);
    }
    readonly property bool onBreak: view === 1 && Clocks.pomPhase !== "focus"
    readonly property color tint: onBreak ? Colors.success : Colors.accent

    // Refreshes "in 20 min" and the alarm ring each minute, while it is open
    SystemClock {
        id: clk

        precision: SystemClock.Minutes
        enabled: pop.visible
    }

    // The words, the ring and the marker for the view on show:
    // { time, sub, title, detail, frac, mark, dim }
    function describe() {
        void clk.date;
        const tm = d => Qt.formatTime(new Date(d), "h:mm AP");
        if (view === 0) {
            const running = Clocks.tmrRunning;
            const total = Clocks.tmrTotal;
            const state = running ? "running" : (Clocks.tmrLeft < total ? "paused" : "ready");
            return {
                "time": Clocks.fmt(Clocks.tmrLeft),
                "sub": state,
                "title": "Timer  ·  " + Clocks.fmtLength(total),
                "detail": running ? "Ends at " + tm(Clocks.tmrEndsAt) : "Space starts it",
                "frac": total > 0 ? Clocks.tmrLeft / total : 0,
                "mark": total > 0 ? 1 - Clocks.tmrLeft / total : 0,
                "dim": false
            };
        }
        if (view === 1) {
            const ph = Clocks.pomPhase;
            const total = Clocks.pomTotal;
            const state = Clocks.pomRunning ? "running" : (Clocks.pomLeft < total ? "paused" : "ready");
            const title = phaseName(ph) + (ph === "focus" ? "  ·  " + (Clocks.pomCount + 1) + " of " + Config.pomodoroLongEvery : "");
            const done = Clocks.pomToday + (Clocks.pomToday === 1 ? " session" : " sessions") + " today";
            return {
                "time": Clocks.fmt(Clocks.pomLeft),
                "sub": state,
                "title": title,
                "detail": "Next: " + phaseName(Clocks.pomNext()).toLowerCase() + "  ·  " + done,
                "frac": total > 0 ? Clocks.pomLeft / total : 0,
                "mark": total > 0 ? 1 - Clocks.pomLeft / total : 0,
                "dim": false
            };
        }
        if (view === 2) {
            const n = Clocks.laps.length;
            const el = Clocks.swElapsed;
            return {
                "time": Clocks.fmtWatch(el),
                "sub": Clocks.swRunning ? "running" : (el > 0 ? "stopped" : "ready"),
                "title": "Stopwatch",
                "detail": n + (n === 1 ? " lap" : " laps") + (n > 0 ? "  ·  last " + Clocks.fmtWatch(Clocks.laps[n - 1] - (n > 1 ? Clocks.laps[n - 2] : 0)) : ""),
                "frac": (el % 60000) / 60000,
                "mark": (el % 60000) / 60000,
                "dim": false
            };
        }
        const i = alarmCur;
        if (i < 0)
            return {
                "time": "--:--",
                "sub": "no alarms",
                "title": "Alarms",
                "detail": "Add one with +",
                "frac": 0,
                "mark": 0.5,
                "dim": true
            };
        const a = Clocks.alarms[i];
        const d = new Date();
        const diff = ((a.min - (d.getHours() * 60 + d.getMinutes())) % 1440 + 1440) % 1440;
        return {
            "time": Qt.formatTime(new Date(2000, 0, 1, Math.floor(a.min / 60), a.min % 60), "h:mm"),
            "sub": Qt.formatTime(new Date(2000, 0, 1, Math.floor(a.min / 60), a.min % 60), "AP"),
            "title": "Alarm  ·  " + (a.on ? "on" : "off") + "  ·  " + (a.daily ? "every day" : "once"),
            "detail": a.on ? Clocks.untilAlarm(a.min) : "Space turns it on",
            "frac": diff / 1440,
            "mark": a.min / 1440,
            "dim": !a.on
        };
    }

    function phaseName(p) {
        return phaseNames[p];
    }

    // Only worked out while the popup is open: a timer running behind a closed
    // popup would otherwise rebuild this (and the ruler ticks) every second
    readonly property var idle: ({
            "time": "",
            "sub": "",
            "title": "",
            "detail": "",
            "frac": 0,
            "mark": 0,
            "dim": false
        })
    readonly property var ro: visible ? describe() : idle

    // Label of the main button
    readonly property string mainLabel: {
        if (view === 0)
            return Clocks.tmrRunning ? "Pause" : (Clocks.tmrLeft < Clocks.tmrTotal ? "Resume" : "Start");
        if (view === 1)
            return Clocks.pomRunning ? "Pause" : (Clocks.pomLeft < Clocks.pomTotal ? "Resume" : "Start");
        if (view === 2)
            return Clocks.swRunning ? "Stop" : "Start";
        if (alarmCur < 0)
            return Clocks.alarms.length >= 8 ? "" : "Add alarm";
        return Clocks.alarms[alarmCur].on ? "Turn off" : "Turn on";
    }
    // Something is counting, so the ring breathes
    readonly property bool running: (view === 0 && Clocks.tmrRunning) || (view === 1 && Clocks.pomRunning) || (view === 2 && Clocks.swRunning)

    function clamp(v, a, b) {
        return Math.max(a, Math.min(b, v));
    }

    // The rows rise in one after another: 0 until `from`, 1 a little later
    function rise(from) {
        return clamp(intro * 2.2 - from, 0, 1);
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

    // ---- Doing things ------------------------------------------------------
    function setView(v) {
        const n = ((v % 4) + 4) % 4;
        if (n === view)
            return;
        view = n;
        slide.restart();
    }

    function pickTimer(min) {
        const was = Clocks.tmrRunning;
        Clocks.tmrSet(min * 60000);
        if (was)
            Clocks.tmrStart();
    }

    // Move one chip along (timer lengths, Pomodoro phases, alarms)
    function stepChip(dir) {
        if (view === 0) {
            if (Clocks.tmrRunning)
                return;
            const at = timerMins.indexOf(Math.round(Clocks.tmrTotal / 60000));
            const next = timerMins[clamp(at + dir, 0, timerMins.length - 1)];
            if (next !== undefined)
                pickTimer(next);
        } else if (view === 1) {
            switchPhase(clamp(pomIndex + dir, 0, 2 * Config.pomodoroLongEvery - 1));
        } else if (view === 3) {
            const at = alarmOrder.indexOf(alarmCur);
            if (at >= 0)
                selAlarm = alarmOrder[clamp(at + dir, 0, alarmOrder.length - 1)];
        }
    }

    // The phase of Pomodoro chip i, and the cycle count that goes with it
    function phaseOf(i) {
        const n = 2 * Config.pomodoroLongEvery;
        return i % 2 === 0 ? "focus" : (i === n - 1 ? "long" : "short");
    }

    function switchPhase(i) {
        const ph = phaseOf(i);
        Clocks.pomCount = ph === "focus" ? i / 2 : (ph === "long" ? 0 : (i + 1) / 2);
        Clocks.pomSetPhase(ph);
    }

    // Space / Enter: the main thing
    function activate() {
        if (view === 0)
            Clocks.tmrToggle();
        else if (view === 1)
            Clocks.pomToggle();
        else if (view === 2)
            Clocks.swToggle();
        else if (alarmCur < 0)
            addAlarm();
        else
            Clocks.alarmToggle(alarmCur);
    }

    function reset() {
        if (view === 0)
            Clocks.tmrReset();
        else if (view === 1)
            Clocks.pomReset();
        else if (view === 2)
            Clocks.swReset();
    }

    function skip() {
        if (view === 1)
            Clocks.pomSkip();
    }

    function mark() {
        if (view === 2)
            Clocks.swLap();
    }

    // + / - (small) and [ / ] (large): the timer's length, or an alarm's time
    function adjust(dir, big) {
        if (view === 0) {
            if (!Clocks.tmrRunning)
                Clocks.tmrAdjust(dir * (big ? 300000 : 60000));
        } else if (view === 3 && alarmCur >= 0) {
            Clocks.alarmSetMinute(alarmCur, Clocks.alarms[alarmCur].min + dir * (big ? 60 : 5));
        }
    }

    function addAlarm() {
        const d = new Date();
        const idx = Clocks.alarmAdd(((d.getHours() + 1) % 24) * 60, "");
        if (idx >= 0)
            selAlarm = idx;
    }

    function toggleDaily() {
        if (view === 3 && alarmCur >= 0)
            Clocks.alarmChange(alarmCur, {
                "daily": !Clocks.alarms[alarmCur].daily
            });
    }

    function removeAlarm() {
        if (view === 3 && alarmCur >= 0) {
            Clocks.alarmRemove(alarmCur);
            selAlarm = -1;
        }
    }

    // ---- Open and close ----------------------------------------------------
    // PanelLink calls this when another panel opens
    function close() {
        visible = false;
    }

    function toggle() {
        if (visible) {
            visible = false;
            return;
        }
        show();
    }

    // Open (on a view, if one is named)
    function show(which) {
        if (which !== undefined && which !== "") {
            const v = viewNames.indexOf(which);
            if (v >= 0)
                setView(v);
        }
        if (visible)
            return;
        // The click that closed us via the focus grab also lands on the clock
        if (Date.now() - closedAt < 200)
            return;
        selAlarm = -1;
        anchor.rect = barWindow.contentItem.mapFromItem(target, 0, 0, target.width, target.height + 6);
        visible = true;
    }

    // One overlay panel at a time: close when another one opens
    PanelLink {
        id: link

        win: pop
        name: "clock"
        barPopup: true
        idleMs: Style.popupIdleLongMs
        hovered: idleHover.hovered
    }

    Connections {
        target: Panels

        function onToggleClock() {
            if (pop.focusedHere)
                pop.toggle();
        }

        function onOpenClock(which) {
            if (pop.focusedHere)
                pop.show(which);
        }

        function onCloseClock() {
            pop.visible = false;
        }
    }

    visible: false
    color: "transparent"
    implicitWidth: contentW + 32
    implicitHeight: card.implicitHeight
    anchor.window: barWindow
    anchor.edges: Edges.Bottom | Edges.Left
    anchor.gravity: Edges.Bottom | Edges.Right
    onVisibleChanged: {
        // The stopwatch wants tenths while it is watched
        Clocks.watch(visible);
        if (visible) {
            fade.restart();
            fan = 1;
            intro = 0;
            openAnim.restart();
            keys.forceActiveFocus();
        }
    }

    // The ruler unfurls from a tight dome into the calm arc while the spectrum
    // drains out of it, and the rows rise in: the calendar's arrival
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

    // Slow breath, only while the popup is open
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

    HyprlandFocusGrab {
        windows: [pop]
        active: pop.visible
        onCleared: {
            pop.visible = false;
            pop.closedAt = Date.now();
        }
    }

    // The card grows out of the clock, which is at its top left corner
    CardFade {
        id: fade

        target: card
        fromScale: 0.94
    }

    // The view changed: the body slides in from the side
    ParallelAnimation {
        id: slide

        NumberAnimation {
            target: bodyShift
            property: "x"
            from: 14
            to: 0
            duration: Style.moveMs
            easing.type: Style.easeMove
        }
        NumberAnimation {
            target: body
            property: "opacity"
            from: 0.2
            to: 1
            duration: Style.moveMs
            easing.type: Style.easeMove
        }
    }

    // A small pill: a length, a Pomodoro phase, or an alarm
    component Chip: Rectangle {
        id: chip

        property string text: ""
        property bool selected: false
        // The current Pomodoro phase, or an alarm that is off
        property bool dim: false
        property bool done: false
        property color tone: Colors.accent

        signal clicked

        implicitHeight: 24
        implicitWidth: Math.max(30, label.implicitWidth + 16)
        radius: height / 2
        antialiasing: true
        scale: chipTap.pressed ? 0.94 : 1
        color: selected ? Qt.alpha(tone, Style.tintAlpha) : (chipHover.hovered ? Style.hoverFill : Style.well)
        border.width: 1
        border.color: selected ? Qt.alpha(tone, 0.8) : Style.outline

        Behavior on color {
            ColorAnimation {
                duration: Style.fadeMs
            }
        }
        Behavior on border.color {
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
            id: label

            anchors.centerIn: parent
            text: chip.done ? Icons.check : chip.text
            textFormat: Text.PlainText
            opacity: chip.dim ? 0.5 : 1
            color: chip.selected || chip.done ? chip.tone : Colors.foreground

            font {
                family: Style.fontFamily
                pixelSize: Style.fontSm
                bold: chip.selected
            }
        }

        TapHandler {
            id: chipTap

            onTapped: chip.clicked()
        }
        HoverHandler {
            id: chipHover

            cursorShape: Qt.PointingHandCursor
        }
    }

    Rectangle {
        id: card

        // For the idle close: it waits while the pointer is on the card
        HoverHandler {
            id: idleHover
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

        Item {
            id: keys

            anchors.fill: parent
            focus: pop.visible
            Keys.onPressed: event => {
                // Typing counts as activity for the idle close
                link.poke();
                const k = event.key;
                const shift = (event.modifiers & Qt.ShiftModifier) !== 0;
                const plain = event.modifiers === Qt.NoModifier;
                const oneShot = k === Qt.Key_Space || k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Escape || k === Qt.Key_Delete || k === Qt.Key_Backspace || k === Qt.Key_Tab || k === Qt.Key_Backtab || (k >= Qt.Key_1 && k <= Qt.Key_4) || k === Qt.Key_R || k === Qt.Key_S || k === Qt.Key_M || k === Qt.Key_N || k === Qt.Key_D || k === Qt.Key_X;
                if (event.isAutoRepeat && oneShot) {
                    event.accepted = true;
                    return;
                }
                if (k === Qt.Key_Escape)
                    pop.visible = false;
                else if (k === Qt.Key_Tab)
                    pop.setView(pop.view + 1);
                else if (k === Qt.Key_Backtab || (shift && k === Qt.Key_Tab))
                    pop.setView(pop.view - 1);
                else if (plain && k >= Qt.Key_1 && k <= Qt.Key_4)
                    pop.setView(k - Qt.Key_1);
                else if (k === Qt.Key_Right || k === Qt.Key_Down)
                    pop.stepChip(1);
                else if (k === Qt.Key_Left || k === Qt.Key_Up)
                    pop.stepChip(-1);
                else if (k === Qt.Key_Space || k === Qt.Key_Return || k === Qt.Key_Enter)
                    pop.activate();
                else if (plain && k === Qt.Key_R)
                    pop.reset();
                else if (plain && k === Qt.Key_S)
                    pop.skip();
                else if (plain && k === Qt.Key_M)
                    pop.mark();
                else if (plain && k === Qt.Key_N && pop.view === 3)
                    pop.addAlarm();
                else if (plain && k === Qt.Key_D)
                    pop.toggleDaily();
                else if (k === Qt.Key_Minus || k === Qt.Key_Underscore)
                    pop.adjust(-1, false);
                else if (k === Qt.Key_Plus || k === Qt.Key_Equal)
                    pop.adjust(1, false);
                else if (k === Qt.Key_BracketLeft)
                    pop.adjust(-1, true);
                else if (k === Qt.Key_BracketRight)
                    pop.adjust(1, true);
                else if (k === Qt.Key_Delete || k === Qt.Key_Backspace || (plain && k === Qt.Key_X))
                    pop.removeAlarm();
                else
                    return;
                event.accepted = true;
            }
        }

        Column {
            id: col

            x: 16
            y: 14
            width: parent.width - 32
            spacing: Style.spaceMd

            // ---- Tabs ------------------------------------------------------
            Row {
                id: tabs

                spacing: Style.spaceXs
                opacity: pop.rise(0)

                Repeater {
                    model: pop.viewLabels

                    delegate: Rectangle {
                        id: tab

                        required property string modelData
                        required property int index

                        readonly property bool on: pop.view === index

                        height: 26
                        width: tabText.implicitWidth + 20
                        radius: height / 2
                        antialiasing: true
                        scale: tabTap.pressed ? 0.94 : 1
                        color: on ? Qt.alpha(Colors.accent, Style.tintAlpha) : (tabHover.hovered ? Style.hoverFill : "transparent")
                        border.width: 1
                        border.color: on ? Qt.alpha(Colors.accent, 0.6) : "transparent"

                        Behavior on color {
                            ColorAnimation {
                                duration: Style.fadeMs
                            }
                        }
                        Behavior on border.color {
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
                            id: tabText

                            anchors.centerIn: parent
                            text: tab.modelData
                            textFormat: Text.PlainText
                            color: tab.on ? Colors.accent : (tabHover.hovered ? Colors.foreground : Colors.muted)

                            Behavior on color {
                                ColorAnimation {
                                    duration: Style.fadeMs
                                }
                            }

                            font {
                                family: Style.fontFamily
                                pixelSize: Style.fontSm
                                bold: tab.on
                            }
                        }

                        TapHandler {
                            id: tabTap

                            onTapped: pop.setView(tab.index)
                        }
                        HoverHandler {
                            id: tabHover

                            cursorShape: Qt.PointingHandCursor
                        }
                    }
                }
            }

            // Everything under the tabs slides in when the view changes
            Column {
                id: body

                width: parent.width
                spacing: Style.spaceMd

                transform: Translate {
                    id: bodyShift
                }

                // ---- The ring: the time, in a glass disc ringed in the accent
                Item {
                    id: ringArea

                    width: parent.width
                    height: 124
                    opacity: pop.rise(0.1)
                    transform: Translate {
                        y: (1 - pop.rise(0.1)) * 8
                    }

                    Item {
                        id: ring

                        anchors.centerIn: parent
                        width: 124
                        height: 124

                        // Faint ring round the ring, breathing while it runs
                        Rectangle {
                            anchors.centerIn: parent
                            width: 124
                            height: 124
                            radius: 62
                            color: "transparent"
                            antialiasing: true
                            visible: pop.running
                            border.width: 1
                            border.color: Qt.alpha(pop.tint, 0.12 + 0.18 * pop.breath)
                        }

                        // The glass disc
                        Rectangle {
                            anchors.centerIn: parent
                            width: 112
                            height: 112
                            radius: 56
                            antialiasing: true
                            color: Style.well
                            border.width: 1
                            border.color: Style.outline

                            EdgeLight {
                                corner: parent.height
                            }
                        }

                        Shape {
                            anchors.fill: parent
                            layer.enabled: pop.visible
                            layer.samples: 4
                            opacity: pop.ro.dim ? 0.4 : 1

                            // The track
                            ShapePath {
                                strokeColor: Qt.alpha(Colors.foreground, 0.12)
                                strokeWidth: 2
                                fillColor: "transparent"

                                PathAngleArc {
                                    centerX: 62
                                    centerY: 62
                                    radiusX: 56
                                    radiusY: 56
                                    startAngle: -90
                                    sweepAngle: 359.9
                                }
                            }

                            // What is left (the stopwatch: how far round the minute)
                            ShapePath {
                                strokeColor: Qt.alpha(pop.tint, 0.95)
                                strokeWidth: 3
                                fillColor: "transparent"
                                capStyle: ShapePath.RoundCap

                                PathAngleArc {
                                    centerX: 62
                                    centerY: 62
                                    radiusX: 56
                                    radiusY: 56
                                    startAngle: -90
                                    sweepAngle: Math.min(359.9, 360 * pop.clamp(pop.ro.frac, 0, 1) * pop.intro)
                                }
                            }
                        }

                        Column {
                            anchors.centerIn: parent
                            spacing: 0

                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: pop.ro.time
                                textFormat: Text.PlainText
                                color: pop.ro.dim ? Colors.muted : Colors.foreground

                                font {
                                    family: Style.fontFamily
                                    pixelSize: pop.ro.time.length > 5 ? 20 : 28
                                    bold: true
                                }
                            }

                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: pop.ro.sub
                                textFormat: Text.PlainText
                                color: pop.running ? pop.tint : Colors.muted

                                Behavior on color {
                                    ColorAnimation {
                                        duration: Style.fadeMs
                                    }
                                }

                                font {
                                    family: Style.fontFamily
                                    pixelSize: Style.fontXs
                                    letterSpacing: 1.4
                                    capitalization: Font.AllUppercase
                                }
                            }
                        }
                    }
                }

                // ---- The ruler: the countdown in miniature -------------------
                // A short curved arc, the launcher's ruler. The accent marker
                // stands where the time has got to; the ticks behind it are lit
                // and the ones beside it rise like a magnifier.
                Item {
                    id: ruler

                    readonly property int count: 41
                    readonly property real inset: 10
                    readonly property real step: (width - inset * 2) / (count - 1)
                    // Where the marker is along the ruler, in pixels
                    property real markX: xOf(pop.clamp(pop.ro.mark, 0, 1) * (count - 1))

                    function xOf(i) {
                        return inset + i * step;
                    }

                    // How far a point at x sits below the top of the arc
                    function dropAt(x) {
                        const r = pop.arcNow;
                        return r - Math.sqrt(Math.max(0, r * r - (x - width / 2) * (x - width / 2)));
                    }

                    width: parent.width
                    height: 30

                    Behavior on markX {
                        // The stopwatch wraps round every minute: it must not
                        // glide all the way back
                        enabled: pop.view !== 2

                        NumberAnimation {
                            duration: Style.moveMs
                            easing.type: Style.easeEnter
                        }
                    }

                    Repeater {
                        model: ruler.count

                        delegate: Rectangle {
                            id: tick

                            required property int index

                            readonly property real tx: ruler.xOf(index)
                            readonly property real a: (tx - ruler.width / 2) / pop.arcNow
                            readonly property bool major: index % 5 === 0
                            readonly property real near: Math.max(0, 1 - Math.abs(tx - ruler.markX) / 34)
                            // Behind the marker: time already gone by
                            readonly property bool lit: tx <= ruler.markX
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
                            color: Qt.tint(pop.spectral(Colors.foreground, tx / ruler.width, major ? 0.5 : 0.3), Qt.alpha(pop.tint, Math.max(0.8 * near, lit ? 0.5 : 0)))
                        }
                    }

                    // The accent marker
                    Rectangle {
                        readonly property real a: (ruler.markX - ruler.width / 2) / pop.arcNow

                        x: ruler.markX - 1
                        y: 2 + ruler.dropAt(ruler.markX)
                        width: 2
                        height: 16
                        radius: 1
                        antialiasing: true
                        color: pop.tint
                        transformOrigin: Item.Top
                        rotation: a * 180 / Math.PI
                        opacity: pop.clamp(pop.intro * 2 - 0.5, 0, 1)
                    }
                }

                // ---- Read out in words, as the calendar's footer does --------
                Column {
                    width: parent.width
                    spacing: Style.spaceXs
                    opacity: pop.rise(0.4)

                    Text {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        text: pop.ro.title
                        textFormat: Text.PlainText
                        elide: Text.ElideRight
                        color: pop.running ? pop.tint : Colors.foreground

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
                        text: pop.ro.detail
                        textFormat: Text.PlainText
                        elide: Text.ElideRight
                        color: Colors.muted

                        font {
                            family: Style.fontFamily
                            pixelSize: Style.fontSm
                            letterSpacing: 1.4
                            capitalization: Font.AllUppercase
                        }
                    }
                }

                // ---- The strip: lengths, phases, alarms or laps ----------------
                Item {
                    id: strip

                    width: parent.width
                    height: pop.stripH
                    opacity: pop.rise(0.6)
                    transform: Translate {
                        y: (1 - pop.rise(0.6)) * 8
                    }

                    // Timer: the lengths
                    Flow {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: parent.width
                        spacing: Style.spaceXs
                        visible: pop.view === 0

                        Repeater {
                            model: pop.timerMins

                            delegate: Chip {
                                required property int modelData

                                text: modelData >= 60 && modelData % 60 === 0 ? modelData / 60 + "h" : String(modelData)
                                selected: modelData === Math.round(Clocks.tmrTotal / 60000)
                                onClicked: pop.pickTimer(modelData)
                            }
                        }
                    }

                    // Pomodoro: the cycle, in order
                    Row {
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: Style.spaceXs
                        visible: pop.view === 1

                        Repeater {
                            model: 2 * Config.pomodoroLongEvery

                            delegate: Chip {
                                id: phaseChip

                                required property int index

                                readonly property string phase: pop.phaseOf(index)

                                implicitWidth: (pop.contentW - (2 * Config.pomodoroLongEvery - 1) * Style.spaceXs) / (2 * Config.pomodoroLongEvery)
                                text: String(Math.round(Clocks.phaseMs(phase) / 60000))
                                tone: phase === "focus" ? Colors.accent : Colors.success
                                selected: index === pop.pomIndex
                                done: index < pop.pomIndex
                                onClicked: pop.switchPhase(index)
                            }
                        }
                    }

                    // Stopwatch: the last three laps, newest first
                    Column {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: parent.width
                        spacing: 2
                        visible: pop.view === 2

                        Repeater {
                            model: {
                                const laps = Clocks.laps;
                                const out = [];
                                for (let i = laps.length - 1; i >= 0 && out.length < 3; i--)
                                    out.push({
                                        "n": i + 1,
                                        "split": laps[i] - (i > 0 ? laps[i - 1] : 0),
                                        "total": laps[i]
                                    });
                                return out;
                            }

                            delegate: Item {
                                required property var modelData

                                width: parent.width
                                height: 16

                                Text {
                                    anchors.left: parent.left
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "Lap " + modelData.n
                                    textFormat: Text.PlainText
                                    color: Colors.muted

                                    font {
                                        family: Style.fontFamily
                                        pixelSize: Style.fontSm
                                    }
                                }

                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: Clocks.fmtWatch(modelData.split)
                                    textFormat: Text.PlainText
                                    color: Colors.foreground

                                    font {
                                        family: Style.fontFamily
                                        pixelSize: Style.fontMd
                                        bold: true
                                    }
                                }

                                Text {
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: Clocks.fmtWatch(modelData.total)
                                    textFormat: Text.PlainText
                                    color: Colors.muted

                                    font {
                                        family: Style.fontFamily
                                        pixelSize: Style.fontSm
                                    }
                                }
                            }
                        }

                        Text {
                            width: parent.width
                            horizontalAlignment: Text.AlignHCenter
                            visible: Clocks.laps.length === 0
                            topPadding: 16
                            text: "Laps show up here"
                            textFormat: Text.PlainText
                            color: Qt.alpha(Colors.muted, 0.7)

                            font {
                                family: Style.fontFamily
                                pixelSize: Style.fontSm
                            }
                        }
                    }

                    // Alarms: one chip each, and a "+" to add
                    Flow {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: parent.width
                        spacing: Style.spaceXs
                        visible: pop.view === 3

                        Repeater {
                            model: pop.alarmOrder

                            delegate: Chip {
                                required property int modelData

                                implicitWidth: 52
                                text: Qt.formatTime(new Date(2000, 0, 1, Math.floor(Clocks.alarms[modelData].min / 60), Clocks.alarms[modelData].min % 60), "h:mm")
                                selected: modelData === pop.alarmCur
                                dim: !Clocks.alarms[modelData].on
                                onClicked: pop.selAlarm = modelData
                            }
                        }

                        Chip {
                            visible: Clocks.alarms.length < 8
                            implicitWidth: 30
                            text: "+"
                            onClicked: pop.addAlarm()
                        }
                    }
                }

                // ---- The few things you can do ---------------------------------
                Row {
                    id: controls

                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: Style.spaceMd
                    // If the row is ever wider than the card it shrinks to fit
                    scale: Math.min(1, pop.contentW / Math.max(1, controls.implicitWidth))
                    opacity: pop.rise(0.8)
                    transform: Translate {
                        y: (1 - pop.rise(0.8)) * 8
                    }

                    IconButton {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: (pop.view === 0 && !Clocks.tmrRunning) || (pop.view === 3 && pop.alarmCur >= 0)
                        glyph: Icons.minus
                        onClicked: pop.adjust(-1, false)
                    }

                    TextButton {
                        compact: true
                        primary: true
                        visible: pop.mainLabel !== ""
                        text: pop.mainLabel
                        onClicked: pop.activate()
                    }

                    IconButton {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: (pop.view === 0 && !Clocks.tmrRunning) || (pop.view === 3 && pop.alarmCur >= 0)
                        glyph: Icons.plus
                        onClicked: pop.adjust(1, false)
                    }

                    TextButton {
                        compact: true
                        visible: pop.view === 2 && Clocks.swRunning
                        text: "Lap"
                        onClicked: pop.mark()
                    }

                    TextButton {
                        compact: true
                        visible: pop.view === 1
                        text: "Skip"
                        onClicked: pop.skip()
                    }

                    TextButton {
                        compact: true
                        visible: (pop.view === 0 && (Clocks.tmrRunning || Clocks.tmrLeft < Clocks.tmrTotal)) || (pop.view === 1 && (Clocks.pomRunning || Clocks.pomLeft < Clocks.pomTotal)) || (pop.view === 2 && Clocks.swElapsed > 0)
                        text: "Reset"
                        onClicked: pop.reset()
                    }

                    // An alarm: every day, or just the next time
                    TextButton {
                        compact: true
                        visible: pop.view === 3 && pop.alarmCur >= 0
                        primary: pop.alarmCur >= 0 && Clocks.alarms[pop.alarmCur].daily
                        text: pop.alarmCur >= 0 && Clocks.alarms[pop.alarmCur].daily ? "Daily" : "Once"
                        onClicked: pop.toggleDaily()
                    }

                    TextButton {
                        compact: true
                        visible: pop.view === 3 && pop.alarmCur >= 0
                        text: "Delete"
                        onClicked: pop.removeAlarm()
                    }
                }
            }
        }
    }
}
