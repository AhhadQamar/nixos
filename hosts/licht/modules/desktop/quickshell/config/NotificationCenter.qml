// Notification history, in the bar's style.
//   qs ipc call notifications toggle | open | close | clear | dnd
// Esc closes. DND silences new toasts but still records them here.

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

PanelWindow {
    id: center

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
    margins.top: Style.barGap + Style.barHeight + 8
    margins.right: Style.barGap + 2
    implicitWidth: 380
    implicitHeight: card.implicitHeight
    exclusiveZone: 0
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
    onVisibleChanged: if (visible) {
        fadeIn.restart();
        NotificationServer.markRead();
    }

    Connections {
        target: Panels

        function onToggleNotifications() {
            center.toggle();
        }
    }

    anchors {
        top: true
        right: true
    }

    IpcHandler {
        function toggle() {
            center.toggle();
        }

        function open() {
            center.open();
        }

        function close() {
            center.close();
        }

        function clear() {
            NotificationServer.clearHistory();
        }

        function dnd() {
            NotificationServer.toggleDnd();
        }

        target: "notifications"
    }

    // Keeps the "5m ago" labels current
    SystemClock {
        id: clock

        precision: SystemClock.Minutes
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
        focus: center.visible
        Keys.onEscapePressed: center.close()
    }

    // Round icon button, same input handling as the bar's stat items.
    // Transparent until hovered; tinted accent while switched on.
    component IconButton: Rectangle {
        id: btn

        property string glyph: ""
        property bool on: false
        property bool danger: false

        signal clicked

        implicitWidth: Style.itemHeight
        implicitHeight: Style.itemHeight
        radius: height / 2
        antialiasing: true
        color: on ? Qt.alpha(Colors.accent, 0.2) : (btnHover.hovered ? Style.hoverFill : "transparent")
        scale: btnTap.pressed ? 0.94 : 1

        Behavior on color {
            ColorAnimation {
                duration: 200
            }
        }
        Behavior on scale {
            NumberAnimation {
                duration: 100
                easing.type: Easing.OutQuad
            }
        }

        Text {
            anchors.centerIn: parent
            textFormat: Text.PlainText
            text: btn.glyph
            color: btn.on ? Colors.accent : (btn.danger && btnHover.hovered ? Colors.critical : (btnHover.hovered ? Colors.foreground : Colors.muted))

            Behavior on color {
                ColorAnimation {
                    duration: 200
                }
            }

            font {
                family: Style.fontFamily
                pixelSize: 14
            }
        }

        HoverHandler {
            id: btnHover

            cursorShape: Qt.PointingHandCursor
        }

        TapHandler {
            id: btnTap

            onTapped: btn.clicked()
        }
    }

    Rectangle {
        id: card

        anchors.fill: parent
        implicitHeight: content.implicitHeight + 28
        radius: Style.barRadius
        antialiasing: true
        // More solid than the bar: this panel sits over other windows' text
        color: Qt.alpha(Colors.background, 0.97)
        border.width: 1
        border.color: Style.outline

        ColumnLayout {
            id: content

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 14
            spacing: 10

            // ---- Header ---------------------------------------------------
            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 6
                spacing: 8

                Text {
                    Layout.minimumWidth: implicitWidth
                    textFormat: Text.PlainText
                    text: "Notifications"
                    color: Colors.foreground

                    font {
                        family: Style.fontFamily
                        pixelSize: 14
                        bold: true
                    }
                }

                Rectangle {
                    visible: NotificationServer.history.length > 0
                    width: 3
                    height: 3
                    radius: 1.5
                    color: Colors.muted
                }

                Text {
                    visible: NotificationServer.history.length > 0
                    textFormat: Text.PlainText
                    text: NotificationServer.history.length
                    color: Colors.muted

                    font {
                        family: Style.fontFamily
                        pixelSize: 13
                    }
                }

                Item {
                    Layout.fillWidth: true
                }

                IconButton {
                    glyph: NotificationServer.doNotDisturb ? "\uf1f6" : "\uf0f3"
                    on: NotificationServer.doNotDisturb
                    onClicked: {
                        NotificationServer.toggleDnd();
                        console.log("NotificationCenter: do not disturb is now " + (NotificationServer.doNotDisturb ? "on" : "off"));
                    }
                }

                IconButton {
                    visible: NotificationServer.history.length > 0
                    glyph: "\uf1f8"
                    danger: true
                    onClicked: NotificationServer.clearHistory()
                }
            }

            // ---- History --------------------------------------------------
            ListView {
                id: historyList

                Layout.fillWidth: true
                Layout.preferredHeight: NotificationServer.history.length === 0 ? 120 : Math.min(440, contentHeight)
                clip: true
                spacing: 6
                boundsBehavior: Flickable.StopAtBounds
                model: NotificationServer.history

                ColumnLayout {
                    anchors.centerIn: parent
                    visible: NotificationServer.history.length === 0
                    spacing: 6

                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        textFormat: Text.PlainText
                        text: NotificationServer.doNotDisturb ? "\uf1f6" : "\uf0f3"
                        color: Colors.muted

                        font {
                            family: Style.fontFamily
                            pixelSize: 26
                        }
                    }

                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        textFormat: Text.PlainText
                        text: "No notifications"
                        color: Colors.foreground

                        font {
                            family: Style.fontFamily
                            pixelSize: 13
                            bold: true
                        }
                    }

                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        textFormat: Text.PlainText
                        text: NotificationServer.doNotDisturb ? "Do not disturb is on." : "New ones will show up here."
                        color: Colors.muted

                        font {
                            family: Style.fontFamily
                            pixelSize: 12
                        }
                    }
                }

                delegate: Rectangle {
                    id: item

                    required property var modelData

                    readonly property bool critical: modelData.critical
                    readonly property string icon: NotificationServer.iconSource(modelData)

                    width: historyList.width
                    implicitHeight: row.implicitHeight + 24
                    radius: 12
                    antialiasing: true
                    color: itemHover.hovered ? Style.hoverFill : Qt.alpha(Colors.foreground, 0.05)

                    Behavior on color {
                        ColorAnimation {
                            duration: 200
                        }
                    }

                    HoverHandler {
                        id: itemHover
                    }

                    Rectangle {
                        visible: item.critical
                        anchors.left: parent.left
                        anchors.leftMargin: 6
                        anchors.verticalCenter: parent.verticalCenter
                        width: 2
                        height: parent.height - 24
                        radius: 1
                        color: Colors.critical
                    }

                    RowLayout {
                        id: row

                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.leftMargin: 16
                        anchors.rightMargin: 12
                        anchors.topMargin: 12
                        spacing: 12

                        Rectangle {
                            Layout.alignment: Qt.AlignTop
                            implicitWidth: 32
                            implicitHeight: 32
                            radius: 9
                            antialiasing: true
                            color: Style.hoverFill

                            Image {
                                anchors.fill: parent
                                anchors.margins: item.modelData.image !== "" ? 0 : 6
                                visible: item.icon !== ""
                                source: item.icon
                                sourceSize.width: 64
                                sourceSize.height: 64
                                fillMode: Image.PreserveAspectFit
                                asynchronous: true
                            }

                            Text {
                                anchors.centerIn: parent
                                visible: item.icon === ""
                                textFormat: Text.PlainText
                                text: item.modelData.appName.charAt(0).toUpperCase()
                                color: Colors.foreground

                                font {
                                    family: Style.fontFamily
                                    pixelSize: 14
                                    bold: true
                                }
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 3

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 8

                                Text {
                                    Layout.fillWidth: true
                                    textFormat: Text.PlainText
                                    elide: Text.ElideRight
                                    text: item.modelData.appName
                                    color: Colors.muted

                                    font {
                                        family: Style.fontFamily
                                        pixelSize: 11
                                    }
                                }

                                Text {
                                    textFormat: Text.PlainText
                                    text: NotificationServer.ago(item.modelData.time, clock.date)
                                    color: Colors.muted

                                    font {
                                        family: Style.fontFamily
                                        pixelSize: 11
                                    }
                                }
                            }

                            Text {
                                Layout.fillWidth: true
                                visible: text !== ""
                                textFormat: Text.PlainText
                                wrapMode: Text.Wrap
                                maximumLineCount: 2
                                elide: Text.ElideRight
                                text: item.modelData.summary
                                color: Colors.foreground

                                font {
                                    family: Style.fontFamily
                                    pixelSize: 13
                                    bold: true
                                }
                            }

                            Text {
                                Layout.fillWidth: true
                                visible: text !== ""
                                textFormat: Text.PlainText
                                wrapMode: Text.Wrap
                                maximumLineCount: 2
                                elide: Text.ElideRight
                                text: item.modelData.body
                                color: Colors.muted

                                font {
                                    family: Style.fontFamily
                                    pixelSize: 12
                                }
                            }
                        }

                        // Dismiss: takes its space always so nothing shifts on hover
                        Text {
                            Layout.alignment: Qt.AlignTop
                            textFormat: Text.PlainText
                            text: "\uf00d"
                            opacity: itemHover.hovered ? 1 : 0
                            color: removeArea.containsMouse ? Colors.critical : Colors.muted

                            Behavior on opacity {
                                NumberAnimation {
                                    duration: 150
                                }
                            }
                            Behavior on color {
                                ColorAnimation {
                                    duration: 200
                                }
                            }

                            font {
                                family: Style.fontFamily
                                pixelSize: 13
                            }

                            MouseArea {
                                id: removeArea

                                anchors.fill: parent
                                anchors.margins: -8
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: NotificationServer.dismissHistory(item.modelData.id)
                            }
                        }
                    }
                }
            }
        }
    }
}
