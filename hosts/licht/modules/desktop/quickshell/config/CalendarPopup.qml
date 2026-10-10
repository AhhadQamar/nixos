// Month calendar that drops down from the clock.
//   - Click the clock to open; click anywhere else to close.
//   - Arrows change month; click the month name to jump back to today.
//   - Footer shows the ISO week number of today.

import QtQuick
import Quickshell
import Quickshell.Hyprland

PopupWindow {
    id: pop

    // The bar window this hangs from, and the item it hangs under
    required property var barWindow
    required property Item target

    readonly property bool open: visible

    // Months away from the current one: 0 = this month, -1 = last month
    property int offset: 0
    property double closedAt: 0

    readonly property date today: clock.date
    readonly property date first: new Date(today.getFullYear(), today.getMonth() + offset, 1)
    // Blank cells before the 1st, with the week starting on Monday
    readonly property int lead: (first.getDay() + 6) % 7
    readonly property int days: new Date(first.getFullYear(), first.getMonth() + 1, 0).getDate()
    readonly property int cells: Math.ceil((lead + days) / 7) * 7

    function isoWeek(d) {
        const t = new Date(Date.UTC(d.getFullYear(), d.getMonth(), d.getDate()));
        t.setUTCDate(t.getUTCDate() + 4 - (t.getUTCDay() || 7));
        const y0 = new Date(Date.UTC(t.getUTCFullYear(), 0, 1));
        return Math.ceil(((t - y0) / 86400000 + 1) / 7);
    }

    function toggle() {
        if (visible) {
            visible = false;
            return;
        }
        // The click that closed us via the focus grab also lands on the clock
        if (Date.now() - closedAt < 200)
            return;
        offset = 0;
        anchor.rect = barWindow.contentItem.mapFromItem(target, 0, 0, target.width, target.height + 6);
        visible = true;
    }

    visible: false
    color: "transparent"
    implicitWidth: 276
    implicitHeight: card.implicitHeight
    anchor.window: barWindow
    anchor.edges: Edges.Bottom | Edges.Left
    anchor.gravity: Edges.Bottom | Edges.Right
    onVisibleChanged: if (visible)
        fadeIn.restart()

    SystemClock {
        id: clock

        precision: SystemClock.Minutes
    }

    HyprlandFocusGrab {
        windows: [pop]
        active: pop.visible
        onCleared: {
            pop.visible = false;
            pop.closedAt = Date.now();
        }
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

    component NavButton: Rectangle {
        id: btn

        property int glyph: 0

        signal clicked

        implicitWidth: 26
        implicitHeight: 26
        radius: 13
        color: nav.hovered ? Style.hoverFill : "transparent"

        Text {
            anchors.centerIn: parent
            text: String.fromCodePoint(btn.glyph)
            color: Colors.muted

            font {
                family: Style.fontFamily
                pixelSize: 16
            }
        }

        TapHandler {
            onTapped: btn.clicked()
        }
        HoverHandler {
            id: nav

            cursorShape: Qt.PointingHandCursor
        }
    }

    Rectangle {
        id: card

        anchors.fill: parent
        radius: Style.barRadius
        antialiasing: true
        color: Qt.alpha(Colors.background, 0.97)
        border.width: 1
        border.color: Style.outline
        implicitHeight: col.implicitHeight + 28

        Column {
            id: col

            x: 16
            y: 14
            width: parent.width - 32
            spacing: 8

            Item {
                width: parent.width
                height: 28

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: Qt.formatDate(pop.first, "MMMM yyyy")
                    textFormat: Text.PlainText
                    color: Colors.foreground

                    font {
                        family: Style.fontFamily
                        pixelSize: 14
                        bold: true
                    }

                    TapHandler {
                        onTapped: pop.offset = 0
                    }
                }

                Row {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2

                    NavButton {
                        glyph: 0xF0141
                        onClicked: pop.offset -= 1
                    }
                    NavButton {
                        glyph: 0xF0142
                        onClicked: pop.offset += 1
                    }
                }
            }

            Row {
                Repeater {
                    model: ["M", "T", "W", "T", "F", "S", "S"]

                    delegate: Text {
                        required property string modelData

                        width: 34
                        height: 22
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        text: modelData
                        color: Colors.muted

                        font {
                            family: Style.fontFamily
                            pixelSize: 11
                        }
                    }
                }
            }

            Grid {
                columns: 7

                Repeater {
                    model: pop.cells

                    delegate: Item {
                        required property int index

                        readonly property int dayNum: index - pop.lead + 1
                        readonly property bool inMonth: dayNum >= 1 && dayNum <= pop.days
                        readonly property bool isToday: pop.offset === 0 && inMonth && dayNum === pop.today.getDate()

                        width: 34
                        height: 32

                        Rectangle {
                            anchors.centerIn: parent
                            width: 30
                            height: 30
                            radius: 15
                            visible: parent.isToday
                            color: Qt.alpha(Colors.accent, 0.22)
                        }

                        Text {
                            anchors.centerIn: parent
                            visible: parent.inMonth
                            text: parent.dayNum
                            color: parent.isToday ? Colors.accent : Colors.foreground

                            font {
                                family: Style.fontFamily
                                pixelSize: 12
                                bold: parent.isToday
                            }
                        }
                    }
                }
            }

            Rectangle {
                width: parent.width
                height: 1
                color: Style.outline
            }

            Text {
                text: "Week " + pop.isoWeek(pop.today)
                textFormat: Text.PlainText
                color: Colors.muted

                font {
                    family: Style.fontFamily
                    pixelSize: 11
                }
            }
        }
    }
}
