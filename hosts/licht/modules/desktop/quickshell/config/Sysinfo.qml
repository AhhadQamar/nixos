// CPU load, memory in use and CPU temperature, polled every few seconds.
// Read by the bar's system item.
//
// No process is started per poll: /proc/stat and /proc/meminfo are read
// straight from Quickshell, and the temperature file is looked up once at
// startup (a shell scanning hwmon every three seconds was a dozen forks each
// time).

pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    // 0..1
    property real cpu: 0
    // GiB
    property real memUsed: 0
    property real memTotal: 0
    // Celsius, or -1 when the machine reports none
    property int temp: -1

    property var prev: null
    // The sysfs file holding the CPU temperature in millidegrees; "" until
    // found, and for good if the machine has none
    property string tempPath: ""

    readonly property int cpuPercent: Math.round(cpu * 100)
    readonly property real memFraction: memTotal > 0 ? memUsed / memTotal : 0

    // /proc/stat: the line that starts with "cpu " holds the totals
    function parseStat(text) {
        for (const line of text.split("\n")) {
            if (line.indexOf("cpu ") !== 0)
                continue;
            const f = line.trim().split(/\s+/).slice(1).map(Number);
            const idle = (f[3] || 0) + (f[4] || 0);
            let sum = 0;
            for (let i = 0; i < Math.min(8, f.length); i++)
                sum += f[i] || 0;
            if (prev && sum > prev.sum)
                cpu = Math.max(0, Math.min(1, 1 - (idle - prev.idle) / (sum - prev.sum)));
            prev = {
                "idle": idle,
                "sum": sum
            };
            return;
        }
    }

    // /proc/meminfo: "MemTotal:" and "MemAvailable:" in kB
    function parseMem(text) {
        let total = 0;
        let avail = 0;
        for (const line of text.split("\n")) {
            if (line.indexOf("MemTotal:") === 0)
                total = parseInt(line.split(/\s+/)[1]) || 0;
            else if (line.indexOf("MemAvailable:") === 0)
                avail = parseInt(line.split(/\s+/)[1]) || 0;
        }
        if (total > 0) {
            memTotal = total / 1048576;
            memUsed = (total - avail) / 1048576;
        }
    }

    // The temperature file: millidegrees
    function parseTemp(text) {
        const m = parseInt(text);
        temp = isNaN(m) || m <= 0 ? -1 : Math.round(m / 1000);
    }

    // Once: which file has the CPU temperature
    Process {
        running: true
        command: ["sh", "-c", `
            for h in /sys/class/hwmon/hwmon*; do
                case "$(cat "$h/name" 2>/dev/null)" in
                    coretemp|k10temp|zenpower|cpu_thermal)
                        if [ -r "$h/temp1_input" ]; then
                            echo "$h/temp1_input"
                            exit
                        fi
                        break
                        ;;
                esac
            done
            [ -r /sys/class/thermal/thermal_zone0/temp ] && echo /sys/class/thermal/thermal_zone0/temp
        `]

        stdout: StdioCollector {
            onStreamFinished: root.tempPath = text.trim()
        }
    }

    FileView {
        id: statFile

        path: "/proc/stat"
        onLoaded: root.parseStat(statFile.text())
    }

    FileView {
        id: memFile

        path: "/proc/meminfo"
        onLoaded: root.parseMem(memFile.text())
    }

    FileView {
        id: tempFile

        path: root.tempPath
        onLoaded: root.parseTemp(tempFile.text())
    }

    Timer {
        interval: 3000
        running: true
        repeat: true
        onTriggered: {
            statFile.reload();
            memFile.reload();
            if (root.tempPath !== "")
                tempFile.reload();
        }
    }
}
