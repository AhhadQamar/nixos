// System updater panel, in the bar's card style.
//   qs ipc call sysupd toggle | open | close | check | preview | apply | cancel
// Keys: r check   p preview   a apply (press twice)   c cancel   1 2 3 tabs   esc close
// State and actions live in Updater.qml; this file is only the interface.

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland

PanelWindow {
    id: panel

    // 0 = updates, 1 = generations, 2 = log
    property int tab: 0
    readonly property int topGap: Math.round(Screen.height / 8)

    function toggle() {
        visible = !visible;
    }

    function open() {
        visible = true;
    }

    function close() {
        visible = false;
    }

    visible: false
    color: "transparent"
    margins.top: topGap
    implicitWidth: 560
    implicitHeight: card.implicitHeight
    exclusiveZone: 0
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
    onVisibleChanged: if (visible) {
        fadeIn.restart();
        Updater.refreshMeta();
    }

    anchors {
        top: true
    }

    IpcHandler {
        function toggle() {
            panel.toggle();
        }

        function open() {
            panel.open();
        }

        function close() {
            panel.close();
        }

        function check() {
            panel.open();
            Updater.check();
        }

        function preview() {
            panel.open();
            Updater.preview();
        }

        function apply() {
            panel.open();
            Updater.apply();
        }

        function cancel() {
            Updater.cancel();
        }

        target: "sysupd"
    }

    Connections {
        target: Panels

        function onToggleUpdater() {
            panel.toggle();
        }
    }

    // Follow long-running work in the log
    Connections {
        target: Updater

        function onPhaseChanged() {
            if (Updater.phase === "building" || Updater.phase === "applying" || Updater.phase === "cleaning")
                panel.tab = 2;
        }
    }

    HyprlandFocusGrab {
        windows: [panel]
        active: panel.visible
        onCleared: panel.close()
    }

    ParallelAnimation {
        id: fadeIn

        NumberAnimation {
            target: card
            property: "opacity"
            from: 0
            to: 1
            duration: 140
            easing.type: Easing.OutCubic
        }
        NumberAnimation {
            target: card
            property: "scale"
            from: 0.97
            to: 1
            duration: 140
            easing.type: Easing.OutCubic
        }
    }

    Item {
        anchors.fill: parent
        focus: panel.visible
        Keys.onPressed: event => {
            if (event.key === Qt.Key_Escape)
                panel.close();
            else if (event.key === Qt.Key_R)
                Updater.check();
            else if (event.key === Qt.Key_P)
                Updater.preview();
            else if (event.key === Qt.Key_A)
                Updater.apply();
            else if (event.key === Qt.Key_C)
                Updater.cancel();
            else if (event.key === Qt.Key_1)
                panel.tab = 0;
            else if (event.key === Qt.Key_2)
                panel.tab = 1;
            else if (event.key === Qt.Key_3)
                panel.tab = 2;
        }
    }

    // ---- Small pieces ---------------------------------------------------
    component T: Text {
        color: Colors.foreground
        textFormat: Text.PlainText
        elide: Text.ElideRight

        font {
            family: Style.fontFamily
            pixelSize: 13
        }
    }

    component Btn: Rectangle {
        id: btn

        property string text: ""
        property bool primary: false

        signal clicked

        implicitHeight: 32
        implicitWidth: label.implicitWidth + 30
        radius: 16
        antialiasing: true
        opacity: enabled ? 1 : 0.4
        scale: tap.pressed ? 0.97 : 1
        color: primary ? Qt.alpha(Colors.accent, hov.hovered ? 0.3 : 0.2) : (hov.hovered ? Style.hoverFill : Qt.alpha(Colors.foreground, 0.06))

        Behavior on color {
            ColorAnimation {
                duration: 150
            }
        }

        T {
            id: label

            anchors.centerIn: parent
            text: btn.text
            color: btn.primary ? Colors.accent : Colors.foreground
            font.bold: btn.primary
        }

        TapHandler {
            id: tap

            onTapped: btn.clicked()
        }
        HoverHandler {
            id: hov

            cursorShape: Qt.PointingHandCursor
        }
    }

    component Tab: Rectangle {
        id: tabItem

        required property int index
        property string text: ""

        implicitHeight: 28
        implicitWidth: tl.implicitWidth + 26
        radius: 14
        color: panel.tab === index ? Qt.alpha(Colors.accent, 0.18) : (th.hovered ? Style.hoverFill : "transparent")

        T {
            id: tl

            anchors.centerIn: parent
            text: tabItem.text
            color: panel.tab === tabItem.index ? Colors.accent : Colors.muted
        }

        TapHandler {
            onTapped: panel.tab = tabItem.index
        }
        HoverHandler {
            id: th

            cursorShape: Qt.PointingHandCursor
        }
    }

    // A one-line heads-up under the summary
    component Note: Rectangle {
        id: note

        property string text: ""
        property color tint: Colors.muted

        implicitHeight: 34
        radius: 10
        color: Qt.alpha(tint, 0.12)

        T {
            anchors.verticalCenter: parent.verticalCenter
            x: 12
            width: parent.width - 24
            text: note.text
            color: note.tint
            font.pixelSize: 12
        }
    }

    // ---- Card -----------------------------------------------------------
    Rectangle {
        id: card

        anchors.fill: parent
        radius: Style.barRadius
        antialiasing: true
        color: Qt.alpha(Colors.background, 0.97)
        border.width: 1
        border.color: Style.outline
        implicitHeight: body.implicitHeight + 36

        Column {
            id: body

            x: 18
            y: 18
            width: parent.width - 36
            spacing: 12

            // Header: title, status, recheck
            Item {
                width: parent.width
                height: 32

                T {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "System"
                    font.pixelSize: 16
                    font.bold: true
                }

                Row {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 10

                    T {
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.min(implicitWidth, 300)
                        text: Updater.summary
                        color: Updater.error !== "" ? Colors.critical : (Updater.busy || Updater.available ? Colors.accent : Colors.muted)
                        horizontalAlignment: Text.AlignRight
                    }

                    Btn {
                        text: "Check"
                        visible: !Updater.cancellable
                        enabled: !Updater.busy
                        onClicked: Updater.check()
                    }
                    Btn {
                        text: "Cancel"
                        visible: Updater.cancellable
                        onClicked: Updater.cancel()
                    }
                }
            }

            // Moving bar while something is running; it always takes its
            // space so the card does not jump when work starts or stops
            Rectangle {
                width: parent.width
                height: 3
                radius: 1.5
                clip: true
                color: Qt.alpha(Colors.foreground, 0.06)

                Rectangle {
                    id: sweep

                    width: parent.width * 0.3
                    height: parent.height
                    radius: 1.5
                    color: Colors.accent
                    opacity: Updater.busy ? 1 : 0

                    Behavior on opacity {
                        NumberAnimation {
                            duration: 200
                        }
                    }

                    SequentialAnimation on x {
                        running: Updater.busy
                        loops: Animation.Infinite

                        NumberAnimation {
                            from: -sweep.width
                            to: sweep.parent.width
                            duration: 1100
                            easing.type: Easing.InOutQuad
                        }
                    }
                }
            }

            Row {
                spacing: 4

                Tab {
                    index: 0
                    text: "Updates"
                }
                Tab {
                    index: 1
                    text: "Generations"
                }
                Tab {
                    index: 2
                    text: "Log"
                }
            }

            // ---- Updates tab ----------------------------------------------
            Column {
                width: parent.width
                spacing: 8
                visible: panel.tab === 0

                Note {
                    width: parent.width
                    visible: Updater.rebootPending
                    text: "Reboot needed: the running kernel differs from the installed one"
                    tint: Colors.accent
                }
                Note {
                    width: parent.width
                    visible: Updater.dirtyFiles > 0
                    text: Updater.dirtyFiles + " uncommitted change" + (Updater.dirtyFiles === 1 ? "" : "s") + " in " + Updater.flakeDir
                    tint: Colors.muted
                }
                Note {
                    width: parent.width
                    visible: Updater.failedUnits > 0
                    text: Updater.failedUnits + " failed systemd unit" + (Updater.failedUnits === 1 ? "" : "s")
                    tint: Colors.critical
                }

                // Nothing to do
                Item {
                    width: parent.width
                    height: 96
                    visible: !Updater.available

                    Column {
                        anchors.centerIn: parent
                        spacing: 4

                        T {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: Updater.error !== "" ? "Could not check" : "Everything is up to date"
                            font.pixelSize: 14
                        }
                        T {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: Updater.lastChecked !== "" ? "Last checked " + Updater.lastChecked : "Not checked yet"
                            color: Colors.muted
                            font.pixelSize: 12
                        }
                        T {
                            anchors.horizontalCenter: parent.horizontalCenter
                            visible: Updater.currentGen !== null
                            text: Updater.currentGen ? "Running generation #" + Updater.currentGen.id + ", built " + Updater.age(Updater.currentGen.time) : ""
                            color: Colors.muted
                            font.pixelSize: 12
                        }
                    }
                }

                // Flake inputs that moved
                Repeater {
                    model: Updater.changes

                    delegate: Rectangle {
                        required property var modelData

                        width: parent.width
                        height: 38
                        radius: 10
                        color: Qt.alpha(Colors.foreground, 0.05)

                        T {
                            x: 12
                            anchors.verticalCenter: parent.verticalCenter
                            text: parent.modelData.name
                            font.bold: true
                        }
                        T {
                            anchors.centerIn: parent
                            text: parent.modelData.from + "  →  " + parent.modelData.to
                            color: Colors.muted
                            font.pixelSize: 12
                        }
                        T {
                            anchors.right: parent.right
                            anchors.rightMargin: 12
                            anchors.verticalCenter: parent.verticalCenter
                            visible: parent.modelData.days > 0
                            text: "+" + parent.modelData.days + "d"
                            color: Colors.accent
                            font.pixelSize: 12
                        }
                    }
                }

                // Package preview
                Row {
                    visible: Updater.previewed
                    spacing: 18

                    T {
                        text: "↑ " + Updater.upgraded + " upgraded"
                        color: Colors.accent
                    }
                    T {
                        text: "+ " + Updater.added + " added"
                        color: Colors.success
                    }
                    T {
                        text: "− " + Updater.removed + " removed"
                        color: Colors.critical
                    }
                }

                ListView {
                    width: parent.width
                    height: Math.min(contentHeight, 220)
                    visible: Updater.previewed && Updater.diff.length > 0
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    model: Updater.diff

                    delegate: Item {
                        required property var modelData

                        width: ListView.view.width
                        height: 26

                        T {
                            x: 4
                            anchors.verticalCenter: parent.verticalCenter
                            text: parent.modelData.kind === "add" ? "+" : parent.modelData.kind === "rem" ? "−" : "↑"
                            color: parent.modelData.kind === "add" ? Colors.success : parent.modelData.kind === "rem" ? Colors.critical : Colors.accent
                        }
                        T {
                            x: 24
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width * 0.38
                            text: parent.modelData.name
                            font.pixelSize: 12
                        }
                        T {
                            x: parent.width * 0.38 + 30
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width * 0.62 - 120
                            text: parent.modelData.change
                            color: Colors.muted
                            font.pixelSize: 12
                        }
                        T {
                            anchors.right: parent.right
                            anchors.rightMargin: 4
                            anchors.verticalCenter: parent.verticalCenter
                            text: parent.modelData.size
                            color: Colors.muted
                            font.pixelSize: 12
                        }
                    }
                }

                Note {
                    width: parent.width
                    visible: Updater.kernelChange
                    text: "Includes a new kernel: reboot after applying"
                    tint: Colors.accent
                }

                Row {
                    spacing: 8

                    Btn {
                        text: "Preview packages"
                        enabled: Updater.available && !Updater.busy
                        onClicked: Updater.preview()
                    }
                    Btn {
                        primary: true
                        enabled: !Updater.busy
                        text: Updater.applyArmed ? "Press again to confirm" : (Updater.available ? "Apply update" : "Rebuild & switch")
                        onClicked: Updater.apply()
                    }
                }
            }

            // ---- Generations tab ------------------------------------------
            Column {
                width: parent.width
                spacing: 8
                visible: panel.tab === 1

                ListView {
                    width: parent.width
                    height: Math.min(contentHeight, 300)
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    model: Updater.generations

                    delegate: Rectangle {
                        id: gen

                        required property var modelData

                        width: ListView.view.width
                        height: 40
                        radius: 10
                        color: modelData.current ? Qt.alpha(Colors.accent, 0.12) : "transparent"

                        T {
                            x: 12
                            anchors.verticalCenter: parent.verticalCenter
                            text: "#" + parent.modelData.id
                            font.bold: true
                        }
                        HoverHandler {
                            id: genHover
                        }

                        T {
                            x: 60
                            anchors.verticalCenter: parent.verticalCenter
                            text: Qt.formatDateTime(new Date(parent.modelData.time), "d MMM yyyy, h:mm AP")
                            font.pixelSize: 12
                        }
                        T {
                            x: 225
                            anchors.verticalCenter: parent.verticalCenter
                            width: 180
                            text: (parent.modelData.version || "") + (parent.modelData.kernel ? "  ·  linux " + parent.modelData.kernel : "")
                            color: Colors.muted
                            font.pixelSize: 12
                        }
                        T {
                            anchors.right: parent.right
                            anchors.rightMargin: 12
                            anchors.verticalCenter: parent.verticalCenter
                            visible: parent.modelData.current
                            text: "current"
                            color: Colors.accent
                            font.pixelSize: 12
                        }

                        // Roll back: shown on hover, or while waiting for the second press
                        Rectangle {
                            readonly property bool armed: Updater.rollbackArmed === gen.modelData.id

                            visible: !gen.modelData.current && !Updater.busy && (genHover.hovered || armed)
                            anchors.right: parent.right
                            anchors.rightMargin: 8
                            anchors.verticalCenter: parent.verticalCenter
                            implicitHeight: 26
                            implicitWidth: rbLabel.implicitWidth + 22
                            radius: 13
                            color: armed ? Qt.alpha(Colors.critical, 0.25) : Qt.alpha(Colors.foreground, 0.1)

                            T {
                                id: rbLabel

                                anchors.centerIn: parent
                                text: parent.armed ? "Press again" : "Switch to"
                                font.pixelSize: 12
                            }

                            TapHandler {
                                onTapped: Updater.rollback(gen.modelData.id)
                            }
                        }
                    }
                }

                Btn {
                    enabled: !Updater.busy
                    text: Updater.cleanArmed ? "Press again to confirm" : "Remove generations older than " + Updater.keepDays + " days"
                    onClicked: Updater.collect()
                }
            }

            // ---- Log tab --------------------------------------------------
            Rectangle {
                width: parent.width
                height: 300
                radius: 10
                visible: panel.tab === 2
                color: Qt.alpha(Colors.foreground, 0.05)
                clip: true

                Flickable {
                    id: flick

                    anchors.fill: parent
                    anchors.margins: 10
                    contentHeight: logText.implicitHeight
                    boundsBehavior: Flickable.StopAtBounds
                    onContentHeightChanged: contentY = Math.max(0, contentHeight - height)

                    Text {
                        id: logText

                        width: flick.width
                        wrapMode: Text.WrapAnywhere
                        textFormat: Text.PlainText
                        color: Updater.logLines.length > 0 ? Colors.foreground : Colors.muted
                        text: Updater.logLines.length > 0 ? Updater.logLines.join("\n") : "Nothing yet. Build and apply output shows up here."

                        font {
                            family: Style.fontFamily
                            pixelSize: 11
                        }
                    }
                }
            }

            Btn {
                visible: panel.tab === 2
                enabled: Updater.logLines.length > 0
                text: "Copy log"
                onClicked: Quickshell.execDetached(["wl-copy", Updater.logLines.join("\n")])
            }

            // Key hints
            T {
                text: "r check  ·  p preview  ·  a apply  ·  c cancel  ·  1 2 3 tabs  ·  esc close"
                color: Colors.muted
                font.pixelSize: 11
            }
        }
    }
}
