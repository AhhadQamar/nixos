// System updater panel, in the bar's card style.
//   qs ipc call sysupd toggle | open | close | check | preview | apply | test | cancel
// Keys: r check   p preview   a apply (press twice)   t test   c cancel
//       1 2 3 tabs   esc close
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

    // The one colour and glyph that sum up the state (header circle)
    readonly property color tint: Updater.error !== "" ? Colors.critical : (Updater.busy || Updater.available ? Colors.accent : Colors.success)
    readonly property int glyph: Updater.busy ? 0xF04E6 : (Updater.error !== "" ? 0xF05D6 : (Updater.available ? 0xF06B0 : 0xF05E1))
    // Longest "days behind", so the little bars share a scale
    readonly property int maxDays: Updater.changes.reduce((m, c) => Math.max(m, c.days), 1)

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
    implicitWidth: 580
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

        function test() {
            panel.open();
            Updater.tryOut();
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

    // Follow a build or a switch in the log. Deleting generations stays on the
    // list so you can watch it shrink.
    Connections {
        target: Updater

        function onPhaseChanged() {
            if (Updater.phase === "building" || Updater.phase === "applying")
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
            else if (event.key === Qt.Key_T)
                Updater.tryOut();
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
        // Red, for the second press of something destructive
        property bool danger: false

        signal clicked

        implicitHeight: 32
        implicitWidth: label.implicitWidth + 30
        radius: 16
        antialiasing: true
        opacity: enabled ? 1 : 0.4
        scale: tap.pressed ? 0.97 : 1
        color: danger ? Qt.alpha(Colors.critical, hov.hovered ? 0.34 : 0.24) : (primary ? Qt.alpha(Colors.accent, hov.hovered ? 0.3 : 0.2) : (hov.hovered ? Style.hoverFill : Qt.alpha(Colors.foreground, 0.06)))

        Behavior on color {
            ColorAnimation {
                duration: 150
            }
        }
        Behavior on scale {
            NumberAnimation {
                duration: 100
                easing.type: Easing.OutQuad
            }
        }

        T {
            id: label

            anchors.centerIn: parent
            text: btn.text
            color: btn.danger ? Colors.critical : (btn.primary ? Colors.accent : Colors.foreground)
            font.bold: btn.primary || btn.danger
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

    // Smaller button for rows. `glyph` shows an icon instead of text.
    component Mini: Rectangle {
        id: mini

        property string text: ""
        property bool glyph: false
        property bool danger: false

        signal clicked

        implicitHeight: 28
        implicitWidth: glyph ? 28 : mlabel.implicitWidth + 24
        radius: 14
        antialiasing: true
        color: danger ? Qt.alpha(Colors.critical, 0.26) : (mh.hovered ? Qt.alpha(Colors.foreground, 0.16) : Qt.alpha(Colors.foreground, 0.09))

        T {
            id: mlabel

            anchors.centerIn: parent
            text: mini.text
            color: mini.danger ? Colors.critical : Colors.foreground
            font.pixelSize: mini.glyph ? 15 : 12
            font.bold: mini.danger
        }

        TapHandler {
            onTapped: mini.clicked()
        }
        HoverHandler {
            id: mh

            cursorShape: Qt.PointingHandCursor
        }
    }

    component Tab: Rectangle {
        id: tabItem

        required property int index
        property string text: ""
        property int count: 0

        implicitHeight: 28
        radius: 11
        color: panel.tab === index ? Qt.alpha(Colors.accent, 0.18) : (th.hovered ? Style.hoverFill : "transparent")

        Row {
            anchors.centerIn: parent
            spacing: 6

            T {
                anchors.verticalCenter: parent.verticalCenter
                text: tabItem.text
                color: panel.tab === tabItem.index ? Colors.accent : Colors.muted
                font.bold: panel.tab === tabItem.index
            }

            Rectangle {
                visible: tabItem.count > 0
                anchors.verticalCenter: parent.verticalCenter
                implicitWidth: Math.max(18, cnt.implicitWidth + 10)
                implicitHeight: 16
                radius: 8
                color: Qt.alpha(Colors.foreground, 0.1)

                T {
                    id: cnt

                    anchors.centerIn: parent
                    text: tabItem.count
                    color: Colors.muted
                    font.pixelSize: 10
                }
            }
        }

        TapHandler {
            onTapped: panel.tab = tabItem.index
        }
        HoverHandler {
            id: th

            cursorShape: Qt.PointingHandCursor
        }
    }

    // A one-line heads-up
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

    component Chip: Rectangle {
        id: chip

        property string text: ""
        property color tint: Colors.muted

        implicitHeight: 26
        implicitWidth: ctext.implicitWidth + 22
        radius: 13
        color: Qt.alpha(tint, 0.14)

        T {
            id: ctext

            anchors.centerIn: parent
            text: chip.text
            color: chip.tint
            font.pixelSize: 12
        }
    }

    component Rule: Rectangle {
        height: 1
        color: Style.outline
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

            // Header: state circle, title and summary, check / cancel
            Item {
                width: parent.width
                height: 44

                Rectangle {
                    id: orb

                    width: 40
                    height: 40
                    radius: 20
                    anchors.verticalCenter: parent.verticalCenter
                    color: Qt.alpha(panel.tint, 0.16)

                    Behavior on color {
                        ColorAnimation {
                            duration: 250
                        }
                    }

                    Text {
                        id: orbGlyph

                        anchors.centerIn: parent
                        text: String.fromCodePoint(panel.glyph)
                        color: panel.tint

                        font {
                            family: Style.fontFamily
                            pixelSize: 20
                        }

                        NumberAnimation on rotation {
                            running: Updater.busy
                            from: 0
                            to: 360
                            duration: 1400
                            loops: Animation.Infinite
                            onRunningChanged: if (!running)
                                orbGlyph.rotation = 0
                        }
                    }
                }

                Column {
                    anchors.left: orb.right
                    anchors.leftMargin: 12
                    anchors.right: headBtns.left
                    anchors.rightMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2

                    T {
                        width: parent.width
                        text: "System"
                        font.pixelSize: 16
                        font.bold: true
                    }
                    T {
                        width: parent.width
                        text: Updater.summary + (Updater.lastChecked !== "" && !Updater.busy && Updater.error === "" ? " · checked " + Updater.lastChecked : "")
                        color: Updater.error !== "" ? Colors.critical : Colors.muted
                        font.pixelSize: 12
                    }
                }

                Row {
                    id: headBtns

                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter

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

            // Segmented tabs
            Rectangle {
                width: parent.width
                height: 36
                radius: 14
                color: Qt.alpha(Colors.foreground, 0.05)

                Row {
                    x: 4
                    y: 4
                    spacing: 2

                    Tab {
                        index: 0
                        width: (body.width - 8 - 4) / 3
                        text: "Updates"
                        count: Updater.count
                    }
                    Tab {
                        index: 1
                        width: (body.width - 8 - 4) / 3
                        text: "Generations"
                        count: Updater.generations.length
                    }
                    Tab {
                        index: 2
                        width: (body.width - 8 - 4) / 3
                        text: "Log"
                    }
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
                    visible: Updater.kernelChange
                    text: "Includes a new kernel: reboot after applying"
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

                // Flake inputs that moved, with how far behind each one was
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
                            width: 112
                            text: parent.modelData.name
                            font.bold: true
                        }
                        T {
                            x: 132
                            anchors.verticalCenter: parent.verticalCenter
                            text: parent.modelData.from + "  →  " + parent.modelData.to
                            color: Colors.muted
                            font.pixelSize: 12
                        }
                        Rectangle {
                            anchors.right: parent.right
                            anchors.rightMargin: 52
                            anchors.verticalCenter: parent.verticalCenter
                            visible: parent.modelData.days > 0
                            width: 70
                            height: 5
                            radius: 2.5
                            color: Qt.alpha(Colors.foreground, 0.1)

                            Rectangle {
                                width: Math.max(6, parent.width * parent.parent.modelData.days / panel.maxDays)
                                height: parent.height
                                radius: 2.5
                                color: Colors.accent
                            }
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
                    spacing: 8

                    Chip {
                        text: "↑ " + Updater.upgraded + " upgraded"
                        tint: Colors.accent
                    }
                    Chip {
                        text: "+ " + Updater.added + " added"
                        tint: Colors.success
                    }
                    Chip {
                        text: "− " + Updater.removed + " removed"
                        tint: Colors.critical
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

                Rule {
                    width: parent.width
                }

                Item {
                    width: parent.width
                    height: 32

                    Btn {
                        anchors.left: parent.left
                        text: "Preview packages"
                        enabled: Updater.available && !Updater.busy
                        onClicked: Updater.preview()
                    }

                    Row {
                        anchors.right: parent.right
                        spacing: 8

                        Btn {
                            text: "Test"
                            enabled: !Updater.busy
                            onClicked: Updater.tryOut()
                        }
                        Btn {
                            primary: true
                            enabled: !Updater.busy
                            text: Updater.applyArmed ? "Press again to confirm" : (Updater.available ? "Apply update" : "Rebuild & switch")
                            onClicked: Updater.apply()
                        }
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
                    height: Math.min(contentHeight, 330)
                    clip: true
                    spacing: 2
                    boundsBehavior: Flickable.StopAtBounds
                    model: Updater.generations

                    delegate: Rectangle {
                        id: gen

                        required property var modelData

                        readonly property bool armedSwitch: Updater.rollbackArmed === modelData.id
                        readonly property bool armedDelete: Updater.deleteArmed === modelData.id
                        // Roll back / delete show on hover, or while waiting for the second press
                        readonly property bool showActions: !modelData.current && !Updater.busy && (genHover.hovered || armedSwitch || armedDelete)

                        width: ListView.view.width
                        height: 54
                        radius: 12
                        color: modelData.current ? Qt.alpha(Colors.accent, 0.12) : (genHover.hovered ? Qt.alpha(Colors.foreground, 0.05) : "transparent")

                        HoverHandler {
                            id: genHover
                        }

                        Rectangle {
                            x: 14
                            anchors.verticalCenter: parent.verticalCenter
                            width: 10
                            height: 10
                            radius: 5
                            color: gen.modelData.current ? Colors.accent : Qt.alpha(Colors.foreground, 0.25)
                        }

                        T {
                            x: 38
                            anchors.verticalCenter: parent.verticalCenter
                            text: "#" + gen.modelData.id
                            font.bold: true
                        }

                        Column {
                            x: 88
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - 88 - 176
                            spacing: 2

                            T {
                                width: parent.width
                                text: Qt.formatDateTime(new Date(gen.modelData.time), "d MMM yyyy, h:mm AP")
                                font.pixelSize: 12
                            }
                            T {
                                width: parent.width
                                text: Updater.age(gen.modelData.time) + (gen.modelData.version ? "  ·  " + gen.modelData.version : "")
                                color: Colors.muted
                                font.pixelSize: 11
                            }
                        }

                        // Resting: kernel, or "current"
                        Rectangle {
                            visible: !gen.showActions && (gen.modelData.current || gen.modelData.kernel !== "")
                            anchors.right: parent.right
                            anchors.rightMargin: 12
                            anchors.verticalCenter: parent.verticalCenter
                            implicitHeight: 22
                            implicitWidth: kt.implicitWidth + 20
                            radius: 11
                            color: gen.modelData.current ? Qt.alpha(Colors.accent, 0.2) : Qt.alpha(Colors.foreground, 0.07)

                            T {
                                id: kt

                                anchors.centerIn: parent
                                text: gen.modelData.current ? "current" : "linux " + gen.modelData.kernel
                                color: gen.modelData.current ? Colors.accent : Colors.muted
                                font.pixelSize: 11
                            }
                        }

                        // Hover: switch to it, or delete it (two presses each)
                        Row {
                            visible: gen.showActions
                            anchors.right: parent.right
                            anchors.rightMargin: 10
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 6

                            Mini {
                                visible: !gen.armedDelete
                                text: gen.armedSwitch ? "Press again" : "Switch to"
                                danger: gen.armedSwitch
                                onClicked: Updater.rollback(gen.modelData.id)
                            }
                            Mini {
                                visible: !gen.armedSwitch
                                glyph: !gen.armedDelete
                                text: gen.armedDelete ? "Delete?" : String.fromCodePoint(0xF09E7)
                                danger: gen.armedDelete
                                onClicked: Updater.deleteGen(gen.modelData.id)
                            }
                        }
                    }
                }

                Rule {
                    width: parent.width
                }

                Item {
                    width: parent.width
                    height: 32

                    T {
                        anchors.verticalCenter: parent.verticalCenter
                        text: Updater.generations.length + (Updater.generations.length === 1 ? " generation" : " generations")
                        color: Colors.muted
                        font.pixelSize: 12
                    }

                    Row {
                        anchors.right: parent.right
                        spacing: 8

                        Btn {
                            enabled: !Updater.busy
                            text: Updater.cleanArmed ? "Press again to confirm" : "Remove older than " + Updater.keepDays + " days"
                            danger: Updater.cleanArmed
                            onClicked: Updater.collect()
                        }
                        Btn {
                            enabled: !Updater.busy && Updater.generations.length > 1
                            text: Updater.deleteAllArmed ? "Press again to confirm" : "Delete all but current"
                            danger: Updater.deleteAllArmed
                            onClicked: Updater.deleteAll()
                        }
                    }
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
                        text: Updater.logLines.length > 0 ? Updater.logLines.join("\n") : "Nothing yet. Build and switch output shows up here."

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
        }
    }
}
