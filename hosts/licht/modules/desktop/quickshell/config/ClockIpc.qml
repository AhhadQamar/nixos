// The IPC door to the clock popup (ClockPopup.qml, one per bar). Opening and
// closing goes through Panels, and the bar on the focused screen answers; the
// rest drives Clocks.qml directly.
//   qs ipc call clock toggle | open | close | show <timer|pomodoro|stopwatch|alarms>
//                     timer <minutes> | pomodoro | stopwatch | alarm <HH:MM>
//   timer      start a countdown of that many minutes
//   pomodoro   start or pause the Pomodoro
//   stopwatch  start or stop the stopwatch
//   alarm      add an alarm at that time (24-hour, "07:30")
//
//   qs ipc call focus toggle | start | stop | status
//   toggle     start a focus session (a Pomodoro), or pause the running one
//   start      start one now, ending a break early
//   stop       end the session and put the clock back to the full length
//   status     "off", or the phase and the time left ("focus 18:32")
//   Toasts are held back while a focus session runs (Config.qml).

import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    // Touch Clocks at startup so its state loads and alarms ring even if the
    // bar's time-left chip is ever removed
    Component.onCompleted: Clocks.fresh()

    IpcHandler {
        function toggle(): void {
            Panels.toggleClock();
        }

        function open(): void {
            Panels.openClock("");
        }

        function close(): void {
            Panels.closeClock();
        }

        function show(which: string): void {
            Panels.openClock(which);
        }

        function timer(minutes: int): void {
            if (minutes < 1)
                return;
            Clocks.tmrSet(minutes * 60000);
            Clocks.tmrStart();
        }

        function pomodoro(): void {
            Clocks.pomToggle();
        }

        function stopwatch(): void {
            Clocks.swToggle();
        }

        function alarm(time: string): void {
            const m = /^(\d{1,2}):(\d{2})$/.exec(time.trim());
            if (m === null || Number(m[1]) > 23 || Number(m[2]) > 59)
                return;
            Clocks.alarmAdd(Number(m[1]) * 60 + Number(m[2]), "");
        }

        target: "clock"
    }

    IpcHandler {
        function toggle(): void {
            if (Clocks.focusing)
                Clocks.pomPause();
            else
                start();
        }

        function start(): void {
            if (Clocks.pomPhase !== "focus")
                Clocks.pomSetPhase("focus");
            Clocks.pomStart();
        }

        function stop(): void {
            Clocks.pomReset();
        }

        function status(): string {
            return Clocks.pomRunning ? Clocks.pomPhase + " " + Clocks.fmt(Clocks.pomLeft) : "off";
        }

        target: "focus"
    }
}
