pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Services.Notifications

Singleton {
    id: root

    property bool doNotDisturb: false
    property var history: [] // full log, newest first (capped, see below)
    property var active: [] // currently-visible toast popups, newest first
    readonly property int maxHistory: 100
    // Arrived since the notification centre was last opened (drives the bell dot)
    property int unread: 0
    // Set by NotificationCenter while it is on screen: anything that arrives
    // then is seen right away, so it must not light the bell dot or pop a toast
    // (urgent ones still do).
    property bool centerOpen: false

    // Opening the centre means everything is being looked at: the toasts that
    // are still up go away (urgent ones stay until dismissed).
    onCenterOpenChanged: {
        if (centerOpen)
            active = active.filter(n => n.critical);
    }

    // History grouped by app, apps ordered by their newest notification. Every
    // group starts with a { header: true } row; the centre draws those as
    // section titles.
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

    // Until when do not disturb lasts (ms since epoch); 0 = until switched off
    property double dndUntil: 0

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

    Timer {
        interval: 15000
        repeat: true
        running: root.dndUntil > 0
        onTriggered: root.checkDnd()
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
            // `let`: swapped for a copy if the app takes the notification back
            let entry = {
                "id": notif.id,
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
                "time": Date.now(),
                "actions": (notif.actions || []).map(a => {
                    return ({
                            "id": a.identifier,
                            "text": a.text
                        });
                }),
                "expire": notif.expireTimeout,
                "ref": notif
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
            notif.closed.connect(reason => {
                root.active = root.active.filter(n => n.id !== entry.id || n.time !== entry.time);
                // The app took it back (or it expired). The entry stays in the
                // log, but it can no longer be acted on and its picture is
                // gone: swap in a copy without the ref, so whatever shows it
                // notices. When we closed it ourselves, release() has already
                // dropped the ref and there is nothing to do.
                const cur = entry;
                if (cur.ref === null)
                    return;
                const dead = Object.assign({}, cur, {
                    "ref": null
                });
                cur.ref = null;
                const at = root.history.indexOf(cur);
                if (at >= 0) {
                    const h = root.history.slice();
                    h[at] = dead;
                    root.history = h;
                }
                entry = dead;
            });
        }
    }
}
