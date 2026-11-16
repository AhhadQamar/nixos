pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications

// NotificationServer.qml
// Receives notifications and keeps what the rest of the shell shows of them: the
// toasts that are up (NotificationPopups.qml), the log (the notification centre,
// NotificationPanel.qml), do not disturb and the bell's counter.
//
// What it adds on top of the old server:
//   - the log survives a restart of the shell (what the apps sent as pictures and
//     buttons cannot, so those entries come back as plain text)
//   - snooze: an entry leaves the log for a while and comes back as a new toast
//   - the centre's own state (open, close, toggle) lives here, so the panel
//     window is only built while it is on screen
//   - helpers for what is in a notification: a code to copy, a link to open
//   - entries are identified by `key` (id and arrival time), not by the app's
//     id alone: an app that re-uses an id, or an id from a previous session,
//     can no longer remove the wrong entry
//   - removing several at once, and a whole app's, in one call
//
// Set persistHistory to false to keep nothing on disk. The log is written to
// $XDG_STATE_HOME/quickshell/notifications.json as plain text.

Singleton {
    id: root

    // ---- Settings -----------------------------------------------------------
    readonly property bool persistHistory: true
    readonly property int maxHistory: 100
    readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/quickshell"

    // ---- State --------------------------------------------------------------
    property bool doNotDisturb: false
    property var history: [] // full log, newest first (capped, see above)
    property var active: [] // currently-visible toast popups, newest first
    // Arrived since the notification centre was last opened (drives the bell dot)
    property int unread: 0
    // Set while the notification centre is on screen: anything that arrives
    // then is seen right away, so it must not light the bell dot or pop a toast
    // (urgent ones still do).
    property bool centerOpen: false
    // The centre's window exists (it stays until its closing animation ends)
    property bool shown: false
    // When the last click outside the centre closed it (see toggleCenter)
    property double closedAt: 0
    // Entries that arrived after this are "new" while the centre is open: it is
    // the moment the centre was last closed, as of the moment it was opened
    property double lastClosed: Date.now()
    property double newSince: 0
    // Until when do not disturb lasts (ms since epoch); 0 = until switched off
    property double dndUntil: 0

    // Opening the centre means everything is being looked at: the toasts that
    // are still up go away (urgent ones stay until dismissed).
    onCenterOpenChanged: {
        if (centerOpen)
            active = active.filter(n => n.critical);
    }

    onHistoryChanged: if (persistHistory)
        saveTimer.restart()

    // History grouped by app, apps ordered by their newest notification. Every
    // group starts with a { header: true } row. (The centre builds its own
    // grouping now, around what is shown; this stays for anything else that
    // wants it.)
    readonly property var grouped: {
        const order = [];
        // No prototype: an app called "constructor" or "toString" must not
        // collide with Object's own members
        const by = Object.create(null);
        for (const n of history) {
            if (by[n.appName] === undefined) {
                by[n.appName] = [];
                order.push(n.appName);
            }
            by[n.appName].push(n);
        }
        const out = [];
        for (const name of order) {
            out.push({
                "header": true,
                "id": "h:" + name,
                "appName": name,
                "count": by[name].length
            });
            for (const n of by[name])
                out.push(n);
        }
        return out;
    }

    function markRead() {
        unread = 0;
    }

    // How long a toast stays, in ms; 0 = until it is dismissed. Critical ones
    // stay (as the spec asks); otherwise the app's own timeout is honoured
    // within sane limits, and 5 s when it did not ask for one.
    // The toast itself runs the clock (see NotificationPopups.qml), so it can
    // hold it while the pointer is over it.
    function toastMs(entry) {
        if (entry.critical)
            return 0;
        const s = Number(entry.expire);
        return s > 0 ? Math.max(2000, Math.min(60000, s * 1000)) : 5000;
    }

    function dismissActive(id) {
        active = active.filter(n => {
            return n.id !== id;
        });
    }

    // Matched on id and arrival time, not on the object: a toast holds a copy
    // of its entry (it has passed through a list model), so `===` would never
    // match. A replacement that re-used the id has a later time, so it is not
    // dismissed by the toast it replaced.
    function dismissEntry(entry) {
        active = active.filter(n => !(n.id === entry.id && n.time === entry.time));
    }

    function dismissHistory(id) {
        for (const n of history) {
            if (n.id === id)
                release(n);
        }
        history = history.filter(n => {
            return n.id !== id;
        });
    }

    // Remove these entries from the log (and the toasts), telling their apps
    function dismissEntries(list) {
        const keys = {};
        for (const e of list)
            keys[e.key] = true;
        for (const n of history) {
            if (keys[n.key])
                release(n);
        }
        history = history.filter(n => !keys[n.key]);
        active = active.filter(n => !keys[n.key]);
    }

    function clearApp(appName) {
        dismissEntries(history.filter(n => n.appName === appName));
    }

    function clearHistory() {
        for (const n of history)
            release(n);
        history = [];
        unread = 0;
    }

    // Tell the app the user closed it, and let the server forget it. Safe on an
    // entry whose notification is already gone.
    // The entry's ref is dropped first, so the `closed` handler below can tell
    // "we closed it" from "the app took it back" and leave the log alone.
    function release(entry) {
        const r = entry ? entry.ref : null;
        if (!entry)
            return;
        entry.ref = null;
        try {
            if (r && typeof r.dismiss === "function")
                r.dismiss();
        } catch (e) {}
    }

    // Run one of the notification's actions. False when the app has already
    // taken the notification back.
    function invokeAction(entry, actionId) {
        const r = entry ? entry.ref : null;
        let done = false;
        // The app may have taken the notification back, which destroys the
        // object behind `ref`: never let that surface as a binding error.
        try {
            if (r) {
                const acts = r.actions || [];
                for (let i = 0; i < acts.length; i++) {
                    if (acts[i].identifier === actionId) {
                        acts[i].invoke();
                        done = true;
                        break;
                    }
                }
                if (!done && typeof r.invokeAction === "function") {
                    r.invokeAction(actionId);
                    done = true;
                }
            }
        } catch (e) {
            done = false;
        }
        dismissActive(entry.id);
        return done;
    }

    // ---- Snooze -------------------------------------------------------------
    // The entry stays in the log, hidden, with a time to come back at. When it
    // does it is a new notification: it goes to the top, lights the bell and
    // pops a toast like anything else that arrives.
    function snooze(list, minutes) {
        const until = Date.now() + minutes * 60000;
        const keys = {};
        for (const e of list)
            keys[e.key] = true;
        history = history.map(n => keys[n.key] ? Object.assign({}, n, {
                "snoozeUntil": until
            }) : n);
        active = active.filter(n => !keys[n.key]);
    }

    // Snooze until the next time the clock says `hour` o'clock
    function snoozeUntilHour(list, hour) {
        const d = new Date();
        d.setHours(hour, 0, 0, 0);
        if (d.getTime() <= Date.now() + 60000)
            d.setDate(d.getDate() + 1);
        snooze(list, Math.max(1, Math.round((d.getTime() - Date.now()) / 60000)));
    }

    function unsnooze(list) {
        const keys = {};
        for (const e of list)
            keys[e.key] = true;
        wake(history.filter(n => keys[n.key]));
    }

    function wakeDue() {
        const now = Date.now();
        wake(history.filter(n => n.snoozeUntil > 0 && n.snoozeUntil <= now));
    }

    function wake(due) {
        if (due.length === 0)
            return;
        const now = Date.now();
        const gone = {};
        for (const n of due)
            gone[n.key] = true;
        const woke = due.map((n, i) => Object.assign({}, n, {
                "snoozeUntil": 0,
                "time": now + i,
                "key": n.id + ":" + (now + i)
            }));
        history = woke.concat(history.filter(n => !gone[n.key])).slice(0, maxHistory);
        if (!centerOpen)
            unread += woke.length;
        const toasts = woke.filter(n => !doNotDisturb && (!centerOpen || n.critical));
        if (toasts.length > 0)
            active = toasts.concat(active.filter(n => !toasts.some(t => t.id === n.id)));
    }

    // ---- What is in a notification -------------------------------------------
    // Notification text is rendered by whatever shows it, and it comes from
    // other programs, so keep only the words: no tags, no entities.
    function plain(t) {
        // Blank-line runs are squeezed too: they would eat the few lines the
        // readout has
        return String(t).replace(/<[^>]*>/g, "").replace(/&nbsp;/g, " ").replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&quot;/g, "\"").replace(/&#39;|&apos;/g, "'").replace(/&amp;/g, "&").replace(/\r\n?/g, "\n").replace(/\n{3,}/g, "\n\n").trim();
    }

    // At most `n` characters, with an ellipsis when it was cut. Counts code
    // points, so an emoji is never split in half.
    function clip(t, n) {
        const a = Array.from(String(t));
        return a.length > n ? a.slice(0, n - 1).join("") + "\u2026" : String(t);
    }

    // First letter of an app's name for the letter badge (a whole emoji or
    // other astral character, not half a surrogate pair)
    function initial(name) {
        const a = Array.from(String(name));
        return a.length > 0 ? a[0].toUpperCase() : "?";
    }

    // A one-time code in the text ("Your code is 482913"), "" when there is none
    function codeOf(e) {
        const t = String(e.summary) + " " + String(e.body);
        let m = /(?:code|otp|pin|passcode|verification|password|token|one[- ]time)\D{0,30}?\b(\d{4,8})\b/i.exec(t);
        if (m)
            return m[1];
        m = /\b(\d{4,8})\b(?=\D{0,24}(?:is your|is the|as your|code|otp|verification))/i.exec(t);
        return m ? m[1] : "";
    }

    // The first link in the text, "" when there is none
    function linkOf(e) {
        const m = /(https?:\/\/[^\s<>"')\]]+)/.exec(String(e.body) + " " + String(e.summary));
        return m ? m[1].replace(/[.,;:!?]+$/, "") : "";
    }

    // The first line of the body, for a one-line preview
    function firstLine(e) {
        const lines = String(e.body).split("\n").map(l => l.trim()).filter(l => l !== "");
        return lines.length > 0 ? lines[0] : "";
    }

    // Icon to show for an entry: its picture, else its app icon, else the icon
    // of the app's desktop entry, else one named after the app, else ""
    // (the letter badge). Names the icon theme does not have are skipped, so
    // an app that sends a bad icon name still gets its real icon.
    function iconSource(entry) {
        if (entry.image !== "")
            return entry.image;
        return appIconSource(entry);
    }

    // The same without the notification's picture: what to show when there is
    // none, or when the picture will not load any more (the app took the
    // notification back and its image went with it). Worked out once per
    // entry (see onNotification): the icon theme is searched a few times
    // for it, and the centre asks for every entry whenever the list changes.
    function appIconSource(entry) {
        if (entry.iconApp !== undefined)
            return entry.iconApp;
        const i = entry.appIcon;
        if (i !== "" && i.charAt(0) === "/")
            return "file://" + i;
        const names = [i, entry.desktopIcon, String(entry.appName).toLowerCase(), String(entry.desktopEntry).toLowerCase()];
        for (const n of names) {
            if (n && n !== "") {
                const p = Quickshell.iconPath(n, true);
                if (p !== "")
                    return p;
            }
        }
        return "";
    }

    // The icon a desktop entry (or an app's name) maps to, "" when unknown
    function desktopIcon(id, appName) {
        for (const k of [id, appName]) {
            if (k && k !== "") {
                const d = DesktopEntries.heuristicLookup(k);
                if (d && d.icon)
                    return d.icon;
            }
        }
        return "";
    }

    // "now", "5m", "3h", "2d". Pass a ticking clock date as `now` to keep it fresh.
    function ago(ts, now) {
        const s = Math.max(0, Math.round((Number(now) - ts) / 1000));
        if (s < 60)
            return "now";
        const m = Math.floor(s / 60);
        if (m < 60)
            return m + "m";
        const h = Math.floor(m / 60);
        return h < 24 ? h + "h" : Math.floor(h / 24) + "d";
    }

    // ---- Do not disturb -----------------------------------------------------
    function toggleDnd() {
        if (doNotDisturb) {
            doNotDisturb = false;
            dndUntil = 0;
        } else {
            doNotDisturb = true;
            dndUntil = 0;
        }
    }

    // Silence toasts for a while; they still land in the centre
    function dndFor(minutes) {
        doNotDisturb = true;
        dndUntil = Date.now() + minutes * 60000;
    }

    // Ends a timed do-not-disturb whose time has passed. Checked against the
    // wall clock, not a single long timer: a timer does not count the time the
    // machine spent asleep, so after a suspend it would keep DND on for hours.
    function checkDnd() {
        if (dndUntil > 0 && Date.now() >= dndUntil) {
            doNotDisturb = false;
            dndUntil = 0;
        }
    }

    // ---- The centre ---------------------------------------------------------
    function openCenter() {
        if (centerOpen)
            return;
        newSince = lastClosed;
        centerOpen = true;
        shown = true;
        markRead();
        wakeDue();
    }

    function closeCenter() {
        if (!centerOpen)
            return;
        centerOpen = false;
        lastClosed = Date.now();
    }

    function toggleCenter() {
        // The click that closed the centre by landing outside it must not
        // reopen it when it lands on the bar item that toggles it
        if (!centerOpen && Date.now() - closedAt < 250)
            return;
        if (centerOpen)
            closeCenter();
        else
            openCenter();
    }

    // The window finished its leaving animation
    function panelGone() {
        if (!centerOpen)
            shown = false;
    }

    // ---- Kept between runs --------------------------------------------------
    // Text only: pictures and buttons belong to the app's live notification. A
    // restored entry gets an id of its own ("r:") so that a new notification with
    // the same number can never replace it.
    function saveHistory() {
        if (!persistHistory)
            return;
        stateFile.setText(JSON.stringify({
            "history": history.map(n => ({
                        "id": n.id,
                        "key": n.key,
                        "appName": n.appName,
                        "appIcon": n.appIcon,
                        "desktopEntry": n.desktopEntry,
                        "desktopIcon": n.desktopIcon,
                        "summary": n.summary,
                        "body": n.body,
                        "urgency": n.urgency,
                        "critical": n.critical,
                        "time": n.time,
                        "snoozeUntil": n.snoozeUntil || 0
                    }))
        }));
    }

    function restoreHistory(text) {
        let d = null;
        try {
            d = JSON.parse(text);
        } catch (e) {
            return;
        }
        if (!d || !Array.isArray(d.history))
            return;
        const have = {};
        for (const n of history)
            have[n.key] = true;
        const old = [];
        for (const o of d.history) {
            if (typeof o.summary !== "string" || typeof o.time !== "number" || have[o.key])
                continue;
            const e = {
                "id": "r:" + o.id,
                "key": String(o.key || (o.id + ":" + o.time)),
                "appName": String(o.appName || "Unknown"),
                "appIcon": String(o.appIcon || ""),
                "desktopEntry": String(o.desktopEntry || ""),
                "desktopIcon": String(o.desktopIcon || ""),
                "summary": o.summary,
                "body": String(o.body || ""),
                "urgency": o.urgency,
                "critical": o.critical === true,
                "image": "",
                "time": o.time,
                "actions": [],
                "expire": 0,
                "ref": null,
                "snoozeUntil": Number(o.snoozeUntil) || 0,
                "restored": true
            };
            e.iconApp = appIconSource(e);
            old.push(e);
        }
        // What arrived while this was loading stays on top
        history = history.concat(old).sort((a, b) => b.time - a.time).slice(0, maxHistory);
    }

    Component.onCompleted: Quickshell.execDetached(["mkdir", "-p", stateDir])

    FileView {
        id: stateFile

        path: root.stateDir + "/notifications.json"
        printErrors: false
        onLoaded: if (root.persistHistory)
            root.restoreHistory(text())
    }

    Timer {
        id: saveTimer

        interval: 1500
        onTriggered: root.saveHistory()
    }

    Timer {
        interval: 15000
        repeat: true
        running: root.dndUntil > 0
        onTriggered: root.checkDnd()
    }

    // Snoozed entries come back when their time is up
    Timer {
        interval: 15000
        repeat: true
        running: root.history.some(n => n.snoozeUntil > 0)
        onTriggered: root.wakeDue()
    }

    NotificationServer {
        id: server

        keepOnReload: true
        actionsSupported: true
        bodyMarkupSupported: false
        bodyHyperlinksSupported: false
        imageSupported: true
        persistenceSupported: true
        onNotification: notif => {
            notif.tracked = true;
            // A timed do-not-disturb that ran out while nothing was watching
            root.checkDnd();
            const time = Date.now();
            const entry = {
                "id": notif.id,
                "key": notif.id + ":" + time,
                "appName": notif.appName || "Unknown",
                "appIcon": notif.appIcon || "",
                "desktopEntry": notif.desktopEntry || "",
                "desktopIcon": root.desktopIcon(notif.desktopEntry, notif.appName),
                // Capped: a mail client can send a whole message, and every
                // entry is kept (and laid out) while it is in the log
                "summary": root.clip(root.plain(notif.summary || ""), 300),
                "body": root.clip(root.plain(notif.body || ""), 4000),
                "urgency": notif.urgency,
                "critical": notif.urgency === NotificationUrgency.Critical,
                "image": notif.image || "",
                "time": time,
                "actions": (notif.actions || []).map(a => {
                    return ({
                            "id": a.identifier,
                            "text": a.text
                        });
                }),
                "expire": notif.expireTimeout,
                "ref": notif,
                "snoozeUntil": 0
            };
            entry.iconApp = root.appIconSource(entry);
            // An app that replaces a notification re-uses its id: keep only
            // the newest copy
            const all = [entry].concat(root.history.filter(n => n.id !== entry.id));
            // What falls off the end of the log is let go of properly
            for (const old of all.slice(root.maxHistory))
                root.release(old);
            root.history = all.slice(0, root.maxHistory);
            if (!root.centerOpen)
                root.unread += 1;
            // Toasts: not in do-not-disturb, and not while the centre is open
            // (it is showing the new one anyway), except for urgent ones.
            if (!root.doNotDisturb && (!root.centerOpen || entry.critical))
                root.active = [entry].concat(root.active.filter(n => n.id !== entry.id));
            const key = entry.key;
            notif.closed.connect(reason => {
                root.active = root.active.filter(n => n.key !== key);
                // The app took it back (or it expired). The entry stays in the
                // log, but it can no longer be acted on and its picture is
                // gone: swap in a copy without the ref, so whatever shows it
                // notices. When we closed it ourselves, release() has already
                // dropped the ref and there is nothing to do. Found by key:
                // the entry may have been copied since (snoozed, say).
                const at = root.history.findIndex(n => n.key === key);
                if (at < 0 || root.history[at].ref === null)
                    return;
                root.history[at].ref = null;
                const h = root.history.slice();
                h[at] = Object.assign({}, root.history[at], {
                    "ref": null
                });
                root.history = h;
            });
        }
    }
}
