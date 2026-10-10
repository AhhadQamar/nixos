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
    // then is seen right away, so it must not light the bell dot.
    property bool centerOpen: false

    function markRead() {
        unread = 0;
    }

    function dismissActive(id) {
        active = active.filter(n => {
            return n.id !== id;
        });
    }

    function dismissHistory(id) {
        history = history.filter(n => {
            return n.id !== id;
        });
    }

    function clearHistory() {
        history = [];
        unread = 0;
    }

    function invokeAction(entry, actionId) {
        if (entry.ref)
            entry.ref.invokeAction(actionId);

        dismissActive(entry.id);
    }

    // Notification text is rendered by whatever shows it, and it comes from
    // other programs, so keep only the words: no tags, no entities.
    function plain(t) {
        return String(t).replace(/<[^>]*>/g, "").replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&quot;/g, "\"").replace(/&#39;|&apos;/g, "'").replace(/&amp;/g, "&").trim();
    }

    // Icon to show for an entry: its picture, else its app icon, else "" (letter badge).
    function iconSource(entry) {
        if (entry.image !== "")
            return entry.image;
        const i = entry.appIcon;
        if (i === "")
            return "";
        if (i.charAt(0) === "/")
            return "file://" + i;
        return Quickshell.iconPath(i, "dialog-information");
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

    function toggleDnd() {
        doNotDisturb = !doNotDisturb;
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
            const entry = {
                "id": notif.id,
                "appName": notif.appName || "Unknown",
                "appIcon": notif.appIcon || "",
                "summary": root.plain(notif.summary || ""),
                "body": root.plain(notif.body || ""),
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
                "ref": notif
            };
            root.history = [entry].concat(root.history).slice(0, root.maxHistory);
            if (!root.centerOpen)
                root.unread += 1;
            if (!root.doNotDisturb) {
                root.active = [entry].concat(root.active);
                const timeout = entry.urgency === NotificationUrgency.Critical ? 10000 : 5000;
                const t = timerComp.createObject(root, {
                    "interval": timeout
                });
                t.triggered.connect(() => {
                    root.dismissActive(entry.id);
                    t.destroy();
                });
                t.start();
            }
            notif.closed.connect(reason => {
                root.dismissActive(entry.id);
            });
        }
    }

    Component {
        id: timerComp

        Timer {
            repeat: false
        }
    }
}
