// NotificationServer.qml
// Singleton that receives all system notifications, keeps a rolling
// "active" list for toast popups and a full "history" list for the
// notification center. Import this from anywhere as `NotificationServer`.

import QtQuick
import Quickshell
import Quickshell.Services.Notifications
pragma Singleton

Singleton {
    id: root

    property bool doNotDisturb: false
    property var history: [] // full log, newest first (capped, see below)
    property var active: [] // currently-visible toast popups, newest first
    readonly property int maxHistory: 100

    function dismissActive(id) {
        active = active.filter((n) => {
            return n.id !== id;
        });
    }

    function dismissHistory(id) {
        history = history.filter((n) => {
            return n.id !== id;
        });
    }

    function clearHistory() {
        history = [];
    }

    function invokeAction(entry, actionId) {
        if (entry.ref)
            entry.ref.invokeAction(actionId);

        dismissActive(entry.id);
    }

    function toggleDnd() {
        doNotDisturb = !doNotDisturb;
    }

    NotificationServer {
        id: server

        keepOnReload: true
        actionsSupported: true
        bodyMarkupSupported: true
        bodyHyperlinksSupported: true
        imageSupported: true
        persistenceSupported: true
        onNotification: (notif) => {
            notif.tracked = true;
            const entry = {
                "id": notif.id,
                "appName": notif.appName || "Unknown",
                "appIcon": notif.appIcon || "",
                "summary": notif.summary || "",
                "body": notif.body || "",
                "urgency": notif.urgency,
                "image": notif.image || "",
                "time": Date.now(),
                "actions": (notif.actions || []).map((a) => {
                    return ({
                        "id": a.identifier,
                        "text": a.text
                    });
                }),
                "ref": notif
            };
            root.history = [entry].concat(root.history).slice(0, root.maxHistory);
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
            notif.closed.connect((reason) => {
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
