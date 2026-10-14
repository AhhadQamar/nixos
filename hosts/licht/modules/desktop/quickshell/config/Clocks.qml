// Clocks backend: a Pomodoro, a countdown timer, a stopwatch and alarms. The
// interface lives in ClockPopup.qml; this file only keeps state and rings.
//
// Everything counts against absolute times (a countdown stores when it ends, a
// stopwatch when it started), so nothing drifts, a suspend does not stop it, and
// a reload of the shell picks up where it was: the state is written to
// ~/.local/state/quickshell/clock.json after every change (not every tick).
//
// Nothing polls while idle. The tick below only runs while a countdown is
// running (once a second, so the bar can show the time left), or while the
// panel is open and watching a running stopwatch (ten times a second). Alarms
// hang on a minute-aligned SystemClock that is switched off when no alarm is on.
// It also catches up on alarms that fell inside a suspend (up to 15 minutes).
//
// Settings (lengths, presets, the sound) are in Config.qml.

pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    // ---- Settings -------------------------------------------------------
    readonly property string statePath: (Quickshell.env("XDG_STATE_HOME") || Config.home + "/.local/state") + "/quickshell/clock.json"

    // ---- The tick -------------------------------------------------------
    // Milliseconds since the epoch, refreshed by the tick. Every "left" and
    // "elapsed" below is computed from it.
    property double now: Date.now()
    // How many clock popups are open (one per bar). Any open popup wants
    // smooth numbers; a counter, so one popup closing as another opens on a
    // second monitor does not switch the smooth ticking off.
    property int watchers: 0
    readonly property bool fast: watchers > 0

    // ---- Pomodoro -------------------------------------------------------
    // "focus", "short" or "long"
    property string pomPhase: "focus"
    // Focus sessions finished in the current cycle (0 .. longEvery - 1)
    property int pomCount: 0
    // Focus sessions finished today
    property int pomToday: 0
    property string pomDay: ""
    property bool pomRunning: false
    property double pomEndsAt: 0
    // What is left while it is not running
    property double pomPaused: Config.pomodoroFocusMin * 60000

    readonly property double pomTotal: phaseMs(pomPhase)
    readonly property double pomLeft: pomRunning ? Math.max(0, pomEndsAt - now) : pomPaused

    // ---- Timer ----------------------------------------------------------
    // The length that is set, and what is left while paused
    property double tmrTotal: Config.timerDefaultMin * 60000
    property bool tmrRunning: false
    property double tmrEndsAt: 0
    property double tmrPaused: Config.timerDefaultMin * 60000

    readonly property double tmrLeft: tmrRunning ? Math.max(0, tmrEndsAt - now) : tmrPaused

    // ---- Stopwatch ------------------------------------------------------
    property bool swRunning: false
    property double swStartedAt: 0
    // Time gathered before the current run
    property double swBase: 0
    // Lap marks as totals in ms, oldest first
    property var laps: []

    readonly property double swElapsed: swRunning ? swBase + Math.max(0, now - swStartedAt) : swBase

    // ---- Alarms ---------------------------------------------------------
    // [{ min: minute of the day, label, on, daily }]
    property var alarms: []
    property double lastAlarmCheck: 0

    readonly property bool anyAlarmOn: {
        for (let i = 0; i < alarms.length; i++) {
            if (alarms[i].on)
                return true;
        }
        return false;
    }

    // ---- What the bar shows ---------------------------------------------
    // Time left on whichever countdown is running (the Pomodoro first), or ""
    readonly property string badge: pomRunning ? fmt(pomLeft) : (tmrRunning ? fmt(tmrLeft) : "")
    readonly property bool busy: pomRunning || tmrRunning || swRunning

    // ---- Helpers --------------------------------------------------------
    function phaseMs(p) {
        if (p === "short")
            return Config.pomodoroShortMin * 60000;
        if (p === "long")
            return Config.pomodoroLongMin * 60000;
        return Config.pomodoroFocusMin * 60000;
    }

    function pad(n) {
        return n < 10 ? "0" + n : String(n);
    }

    // 1:05 or 1:02:03, rounded up so it reads 0:00 only when it is done
    function fmt(ms) {
        const total = Math.max(0, Math.ceil(ms / 1000));
        const h = Math.floor(total / 3600);
        const m = Math.floor((total % 3600) / 60);
        const s = total % 60;
        return h > 0 ? h + ":" + pad(m) + ":" + pad(s) : m + ":" + pad(s);
    }

    // A stopwatch reading: 1:05.3 or 1:02:03.4 (rounded down)
    function fmtWatch(ms) {
        const t = Math.max(0, Math.floor(ms / 100));
        const tenth = t % 10;
        const total = Math.floor(t / 10);
        const h = Math.floor(total / 3600);
        const m = Math.floor((total % 3600) / 60);
        const s = total % 60;
        return (h > 0 ? h + ":" + pad(m) : String(m)) + ":" + pad(s) + "." + tenth;
    }

    // "25 min", "1 h 30 min"
    function fmtLength(ms) {
        const m = Math.round(ms / 60000);
        if (m < 60)
            return m + " min";
        const h = Math.floor(m / 60);
        return m % 60 === 0 ? h + " h" : h + " h " + (m % 60) + " min";
    }

    // Minute of the day as "7:30 AM"
    function fmtDay(min) {
        const d = new Date(2000, 0, 1, Math.floor(min / 60), min % 60);
        return Qt.formatTime(d, "h:mm AP");
    }

    // How long until the next time the clock shows this minute of the day
    function untilAlarm(min) {
        const d = new Date();
        let diff = min - (d.getHours() * 60 + d.getMinutes());
        if (diff <= 0)
            diff += 1440;
        const h = Math.floor(diff / 60);
        const m = diff % 60;
        return h > 0 ? "in " + h + " h " + m + " min" : "in " + m + " min";
    }

    function fresh() {
        now = Date.now();
    }

    function today() {
        return Qt.formatDate(new Date(), "yyyy-MM-dd");
    }

    // ---- Ringing --------------------------------------------------------
    function ring(title, body) {
        Quickshell.execDetached(["notify-send", "-a", "Clock", "-u", "critical", "-i", "alarm-clock", title, body]);
        if (Config.clockSound.length > 0)
            Quickshell.execDetached(Array.prototype.slice.call(Config.clockSound));
    }

    // ---- Pomodoro -------------------------------------------------------
    function pomStart() {
        fresh();
        if (pomRunning)
            return;
        pomEndsAt = now + (pomPaused > 0 ? pomPaused : pomTotal);
        pomRunning = true;
        save();
    }

    function pomPause() {
        fresh();
        if (!pomRunning)
            return;
        pomPaused = Math.max(0, pomEndsAt - now);
        pomRunning = false;
        save();
    }

    function pomToggle() {
        if (pomRunning)
            pomPause();
        else
            pomStart();
    }

    // Back to the full length of this phase, stopped
    function pomReset() {
        pomRunning = false;
        pomPaused = pomTotal;
        save();
    }

    // Switch phase by hand (stops the clock)
    function pomSetPhase(p) {
        pomRunning = false;
        pomPhase = p;
        pomPaused = phaseMs(p);
        save();
    }

    // The phase that follows the current one
    function pomNext() {
        if (pomPhase === "focus")
            return (pomCount + 1) % Config.pomodoroLongEvery === 0 ? "long" : "short";
        return "focus";
    }

    // Move on to the next phase, counting a finished focus session
    function pomAdvance(finished) {
        const day = today();
        if (pomDay !== day) {
            pomDay = day;
            pomToday = 0;
        }
        const next = pomNext();
        if (pomPhase === "focus") {
            if (finished)
                pomToday += 1;
            pomCount = (pomCount + 1) % Config.pomodoroLongEvery;
        } else if (pomPhase === "long") {
            pomCount = 0;
        }
        pomPhase = next;
        pomPaused = phaseMs(next);
        if (finished && Config.pomodoroAutoStart) {
            pomEndsAt = Date.now() + pomPaused;
            pomRunning = true;
        } else {
            pomRunning = false;
        }
        save();
    }

    function pomSkip() {
        pomAdvance(false);
    }

    function pomFinish() {
        const was = pomPhase;
        pomAdvance(true);
        if (was === "focus")
            ring("Focus session done", pomPhase === "long" ? "Time for a long break (" + Config.pomodoroLongMin + " min)." : "Time for a short break (" + Config.pomodoroShortMin + " min).");
        else
            ring("Break is over", "Ready for the next focus session (" + Config.pomodoroFocusMin + " min).");
    }

    // ---- Timer ----------------------------------------------------------
    function tmrStart() {
        fresh();
        if (tmrRunning)
            return;
        if (tmrPaused <= 0)
            tmrPaused = tmrTotal;
        tmrEndsAt = now + tmrPaused;
        tmrRunning = true;
        save();
    }

    function tmrPause() {
        fresh();
        if (!tmrRunning)
            return;
        tmrPaused = Math.max(0, tmrEndsAt - now);
        tmrRunning = false;
        save();
    }

    function tmrToggle() {
        if (tmrRunning)
            tmrPause();
        else
            tmrStart();
    }

    function tmrReset() {
        tmrRunning = false;
        tmrPaused = tmrTotal;
        save();
    }

    // Set the length (stops the timer): from one minute to a day
    function tmrSet(ms) {
        tmrRunning = false;
        tmrTotal = Math.max(60000, Math.min(86400000, Math.round(ms / 60000) * 60000));
        tmrPaused = tmrTotal;
        save();
    }

    // Change the length by a step while it is not running
    function tmrAdjust(deltaMs) {
        if (tmrRunning)
            return;
        tmrSet(tmrTotal + deltaMs);
    }

    function tmrFinish() {
        tmrRunning = false;
        tmrPaused = tmrTotal;
        save();
        ring("Timer finished", fmtLength(tmrTotal) + " are up.");
    }

    // ---- Stopwatch ------------------------------------------------------
    function swToggle() {
        fresh();
        if (swRunning) {
            swBase = swElapsed;
            swRunning = false;
        } else {
            swStartedAt = now;
            swRunning = true;
        }
        save();
    }

    function swLap() {
        fresh();
        if (!swRunning)
            return;
        const next = laps.slice();
        next.push(swElapsed);
        laps = next;
        save();
    }

    function swReset() {
        swRunning = false;
        swBase = 0;
        laps = [];
        save();
    }

    function swRemoveLap(i) {
        if (i < 0 || i >= laps.length)
            return;
        const next = laps.slice();
        next.splice(i, 1);
        laps = next;
        save();
    }

    // ---- Alarms ---------------------------------------------------------
    function alarmAdd(min, label) {
        if (alarms.length >= 8)
            return -1;
        const next = alarms.slice();
        next.push({
            "min": ((min % 1440) + 1440) % 1440,
            "label": label || "",
            "on": true,
            "daily": false
        });
        alarms = next;
        save();
        return next.length - 1;
    }

    function alarmChange(i, patch) {
        if (i < 0 || i >= alarms.length)
            return;
        const next = alarms.slice();
        next[i] = Object.assign({}, next[i], patch);
        alarms = next;
        save();
    }

    function alarmToggle(i) {
        if (i >= 0 && i < alarms.length)
            alarmChange(i, {
                "on": !alarms[i].on
            });
    }

    function alarmSetMinute(i, min) {
        alarmChange(i, {
            "min": ((Math.round(min) % 1440) + 1440) % 1440
        });
    }

    function alarmRemove(i) {
        if (i < 0 || i >= alarms.length)
            return;
        const next = alarms.slice();
        next.splice(i, 1);
        alarms = next;
        save();
    }

    // Ring every alarm whose minute has come since the last look
    function checkAlarms() {
        const stamp = Math.floor(Date.now() / 60000);
        const last = lastAlarmCheck > 0 && stamp - lastAlarmCheck <= 15 ? lastAlarmCheck : stamp - 1;
        lastAlarmCheck = stamp;
        let changed = false;
        const next = alarms.slice();
        for (let i = 0; i < next.length; i++) {
            const a = next[i];
            if (!a.on)
                continue;
            for (let s = last + 1; s <= stamp; s++) {
                const d = new Date(s * 60000);
                if (d.getHours() * 60 + d.getMinutes() === a.min) {
                    ring(a.label !== "" ? a.label : "Alarm", fmtDay(a.min));
                    if (!a.daily) {
                        next[i] = Object.assign({}, a, {
                            "on": false
                        });
                        changed = true;
                    }
                    break;
                }
            }
        }
        if (changed) {
            alarms = next;
            save();
        }
    }

    // ---- Countdowns -----------------------------------------------------
    function check() {
        const t = Date.now();
        now = t;
        if (pomRunning && t >= pomEndsAt)
            pomFinish();
        if (tmrRunning && t >= tmrEndsAt)
            tmrFinish();
    }

    // A popup tells us when it opens (true) and closes (false)
    function watch(open) {
        watchers = Math.max(0, watchers + (open ? 1 : -1));
        fresh();
    }

    Timer {
        interval: root.fast ? 100 : 1000
        repeat: true
        running: root.pomRunning || root.tmrRunning || (root.swRunning && root.fast)
        onTriggered: root.check()
    }

    // While no alarm is on the clock below is off and nothing is checked. When
    // the first one is switched on, start looking from now, or an alarm set for
    // a minute that already passed would ring at once.
    onAnyAlarmOnChanged: {
        if (anyAlarmOn)
            lastAlarmCheck = Math.floor(Date.now() / 60000);
    }

    SystemClock {
        precision: SystemClock.Minutes
        enabled: root.anyAlarmOn
        onDateChanged: root.checkAlarms()
    }

    // ---- Saving and loading ---------------------------------------------
    property bool loaded: false
    property bool saveAgain: false

    function save() {
        if (!loaded)
            return;
        saveDelay.restart();
    }

    function snapshot() {
        return JSON.stringify({
            "pomPhase": pomPhase,
            "pomCount": pomCount,
            "pomToday": pomToday,
            "pomDay": pomDay,
            "pomRunning": pomRunning,
            "pomEndsAt": pomEndsAt,
            "pomPaused": pomPaused,
            "tmrTotal": tmrTotal,
            "tmrRunning": tmrRunning,
            "tmrEndsAt": tmrEndsAt,
            "tmrPaused": tmrPaused,
            "swRunning": swRunning,
            "swStartedAt": swStartedAt,
            "swBase": swBase,
            "laps": laps,
            "alarms": alarms
        });
    }

    function restore(text) {
        try {
            const s = JSON.parse(text);
            if (s.pomPhase === "focus" || s.pomPhase === "short" || s.pomPhase === "long")
                pomPhase = s.pomPhase;
            pomCount = Math.max(0, Math.min(Config.pomodoroLongEvery - 1, Number(s.pomCount) || 0));
            pomDay = String(s.pomDay || "");
            pomToday = pomDay === today() ? Number(s.pomToday) || 0 : 0;
            pomEndsAt = Number(s.pomEndsAt) || 0;
            pomPaused = Number(s.pomPaused) || phaseMs(pomPhase);
            pomRunning = s.pomRunning === true && pomEndsAt > 0;
            tmrTotal = Number(s.tmrTotal) || tmrTotal;
            tmrEndsAt = Number(s.tmrEndsAt) || 0;
            tmrPaused = Number(s.tmrPaused) || tmrTotal;
            tmrRunning = s.tmrRunning === true && tmrEndsAt > 0;
            swStartedAt = Number(s.swStartedAt) || 0;
            swBase = Number(s.swBase) || 0;
            swRunning = s.swRunning === true && swStartedAt > 0;
            laps = Array.isArray(s.laps) ? s.laps.map(Number) : [];
            const list = [];
            if (Array.isArray(s.alarms)) {
                for (let i = 0; i < s.alarms.length && i < 8; i++) {
                    const a = s.alarms[i];
                    list.push({
                        "min": Math.max(0, Math.min(1439, Number(a.min) || 0)),
                        "label": String(a.label || ""),
                        "on": a.on === true,
                        "daily": a.daily === true
                    });
                }
            }
            alarms = list;
        } catch (e) {
            console.warn("Clocks: could not read " + statePath + ": " + e);
        }
        finishLoading();
    }

    function finishLoading() {
        loaded = true;
        lastAlarmCheck = Math.floor(Date.now() / 60000);
        // Something may have run out while the shell was not running: ring once
        check();
    }

    FileView {
        id: stateFile

        path: root.statePath
        onLoaded: root.restore(stateFile.text())
        onLoadFailed: root.finishLoading()
    }

    Timer {
        id: saveDelay

        interval: 300
        onTriggered: {
            if (writer.running) {
                root.saveAgain = true;
                return;
            }
            writer.command = ["sh", "-c", 'mkdir -p "$(dirname "$2")" && printf "%s" "$1" > "$2.tmp" && mv -f "$2.tmp" "$2"', "sh", root.snapshot(), root.statePath];
            writer.running = true;
        }
    }

    Process {
        id: writer

        stderr: StdioCollector {
            onStreamFinished: if (text.trim() !== "")
                console.warn("Clocks: saving failed: " + text.trim())
        }

        onRunningChanged: {
            if (!running && root.saveAgain) {
                root.saveAgain = false;
                saveDelay.restart();
            }
        }
    }
}
