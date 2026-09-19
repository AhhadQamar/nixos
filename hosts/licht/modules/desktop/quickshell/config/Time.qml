import QtQuick
import Quickshell
pragma Singleton

Singleton {
    id: root

    readonly property string time: Qt.formatDateTime(clock.date, 'h:mm AP')

    SystemClock {
        id: clock

        precision: SystemClock.Seconds
    }

}
