// Screen backlight (sysfs): which device, how bright it is, and a way to
// change it. Shared by the bar and the volume / brightness pill.

pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property string device: ""
    property int max: 1
    property int current: 0

    readonly property bool available: device !== ""
    readonly property int percent: max > 0 ? Math.round(current / max * 100) : 0

    // delta is in percent, positive = brighter. Never goes fully black.
    function step(delta) {
        if (!available)
            return;
        Quickshell.execDetached(["brightnessctl", "-q", "-d", device, "--min-value=1", "set", Math.abs(delta) + "%" + (delta > 0 ? "+" : "-")]);
    }

    // Step 1: find the backlight device's name, e.g. "intel_backlight".
    Process {
        id: finder

        command: ["bash", "-c", "ls /sys/class/backlight | head -n1"]
        running: true

        stdout: StdioCollector {
            onStreamFinished: {
                const dev = text.trim();
                if (dev.length > 0) {
                    root.device = dev;
                    maxReader.running = true;
                }
            }
        }
    }

    // Step 2: its maximum value, to turn "current" into a percentage.
    Process {
        id: maxReader

        command: ["bash", "-c", "cat /sys/class/backlight/" + root.device + "/max_brightness"]

        stdout: StdioCollector {
            onStreamFinished: root.max = parseInt(text.trim()) || 1
        }
    }

    // Step 3: watch the "current brightness" file. The kernel updates it
    // whenever anything changes the brightness.
    FileView {
        id: file

        path: root.device.length > 0 ? "/sys/class/backlight/" + root.device + "/brightness" : ""
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.current = parseInt(file.text().trim()) || 0
    }
}
