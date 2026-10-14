// Now-playing chip for the bar. Shows only while a track is loaded.
//   A small record spins while it plays; click it to play / pause.
//   hover: previous / play-pause / next unfold beside it      scroll: volume
//   click the title (or right-click anywhere on the chip): open the music panel
// On a narrow bar the bar tells it how much room there is (maxWidth): the
// artist goes first, then the title, then it is just the record, and below
// that it hides, so it never runs into the workspaces.
//
// The dial in miniature, like the rest of the bar: a glass capsule with the
// record in it, and a short hairline ruler curving over it that IS the
// progress. The ticks behind the accent marker are lit, the marker stands
// where the track has got to, and the ticks beside it rise like a magnifier.
// Under the pointer the capsule takes the accent (outline, soft tint, a
// breathing ring and a 2px underline); the breath only runs while hovered.
//
// Motion: the three buttons grow out of the record on hover and fold back in
// when the pointer leaves; when the track changes the title and artist slide
// in from the right.

import QtQuick

Item {
    id: root

    // Room the bar can give this chip (set by Bar.qml)
    property real maxWidth: 100000
    // Room between the chip's ends and its glass
    readonly property int padding: Style.spaceMd
    // A bare record: its glass plus the padding (Bar.qml reserves the same)
    readonly property real fixedWidth: Style.discSize + padding * 2
    // Transport button width, and what hover adds (three buttons and gaps)
    readonly property int glyphW: 20
    // What is left for the title and artist
    readonly property real labelRoom: Math.max(0, maxWidth - fixedWidth - Style.spaceMd - (hover.hovered ? 3 * glyphW + 3 * Style.spaceSm : 0))
    // 0..1..0 while hovered: the ring and underline breathe with it
    property real breath: 0

    implicitHeight: Style.barHeight
    implicitWidth: glass.implicitWidth + padding * 2
    visible: Music.hasTrack && maxWidth >= fixedWidth

    // A new track: the label slides in
    Connections {
        target: Music

        function onTitleChanged() {
            swap.restart();
        }
    }

    ParallelAnimation {
        id: swap

        NumberAnimation {
            target: labelShift
            property: "x"
            from: 12
            to: 0
            duration: Style.moveMs
            easing.type: Style.easeMove
        }
        NumberAnimation {
            target: labelRow
            property: "opacity"
            from: 0
            to: 1
            duration: Style.moveMs
            easing.type: Style.easeMove
        }
    }

    // Breath, only while the pointer is on the chip
    SequentialAnimation {
        running: hover.hovered
        loops: Animation.Infinite

        NumberAnimation {
            target: root
            property: "breath"
            from: 0
            to: 1
            duration: Style.ambientMs * 2
            easing.type: Style.easeAmbient
        }
        NumberAnimation {
            target: root
            property: "breath"
            from: 1
            to: 0
            duration: Style.ambientMs * 2
            easing.type: Style.easeAmbient
        }
    }

    // The progress, as a ruler over the glass
    BarRuler {
        id: ruler

        anchors.left: glass.left
        anchors.right: glass.right
        y: 2
        markX: inset + Music.progress * (width - inset * 2)
        fillX: markX
    }

    // Ring round the capsule under the pointer; it breathes
    Rectangle {
        anchors.centerIn: glass
        width: glass.width + 4
        height: glass.height + 4
        radius: height / 2
        color: "transparent"
        antialiasing: true
        visible: hover.hovered
        border.width: 1
        border.color: Qt.alpha(Colors.accent, 0.2 + 0.2 * root.breath)
    }

    Rectangle {
        id: glass

        x: root.padding
        anchors.verticalCenter: parent.verticalCenter
        implicitHeight: Style.discSize
        // The record has 3px round it; the end gets more when a title follows
        implicitWidth: row.implicitWidth + 3 + (label.visible ? Style.spaceLg : 3)
        radius: height / 2
        antialiasing: true
        clip: true
        color: hover.hovered ? Qt.alpha(Colors.accent, Style.tintAlpha) : Style.well
        border.width: 1
        border.color: hover.hovered ? Qt.alpha(Colors.accent, 0.6) : Style.outline

        Behavior on color {
            ColorAnimation {
                duration: Style.baseMs
            }
        }
        Behavior on border.color {
            ColorAnimation {
                duration: Style.baseMs
            }
        }
        Behavior on implicitWidth {
            NumberAnimation {
                duration: Style.fadeMs
                easing.type: Style.easeMove
            }
        }

        EdgeLight {
            corner: glass.height
        }

        // A transport button. `shown` grows it from nothing and fades it in;
        // at width 0 it is hidden, so Row leaves no gap for it.
        component Glyph: Item {
            id: g

            property int code: 0
            property bool strong: false
            property bool shown: false

            signal clicked

            width: shown ? root.glyphW : 0
            height: root.glyphW
            visible: width > 0.5
            opacity: shown ? 1 : 0
            scale: gTap.pressed ? 0.88 : 1

            Behavior on width {
                NumberAnimation {
                    duration: Style.baseMs
                    easing.type: Style.easeMove
                }
            }
            Behavior on opacity {
                NumberAnimation {
                    duration: Style.fadeMs
                }
            }
            Behavior on scale {
                NumberAnimation {
                    duration: Style.pressMs
                    easing.type: Style.easePress
                }
            }

            Text {
                anchors.centerIn: parent
                text: String.fromCodePoint(g.code)
                color: g.strong || gh.hovered ? Colors.accent : Colors.foreground

                Behavior on color {
                    ColorAnimation {
                        duration: Style.fadeMs
                    }
                }

                font {
                    family: Style.fontFamily
                    pixelSize: g.strong ? Style.fontXl : Style.fontLg
                }
            }

            TapHandler {
                id: gTap

                onTapped: g.clicked()
            }
            HoverHandler {
                id: gh

                cursorShape: Qt.PointingHandCursor
            }
        }

        Row {
            id: row

            x: 3
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.spaceSm

            // The record
            Item {
                id: disc

                anchors.verticalCenter: parent.verticalCenter
                width: 18
                height: 18

                // `paused` may only be set on a running animation, so it is
                // only asked for while it runs
                RotationAnimator {
                    target: disc
                    from: 0
                    to: 360
                    duration: 5000
                    loops: Animation.Infinite
                    running: root.visible
                    paused: running && !Music.playing
                }

                Rectangle {
                    anchors.fill: parent
                    radius: width / 2
                    antialiasing: true
                    color: Style.vinyl
                    border.width: 1
                    border.color: Qt.alpha(Style.vinylLight, 0.12)
                }
                // One groove, and a bright edge so the spin is visible
                Rectangle {
                    anchors.centerIn: parent
                    width: 13
                    height: 13
                    radius: 6.5
                    color: "transparent"
                    border.width: 1
                    border.color: Qt.alpha(Style.vinylLight, 0.08)
                }
                Rectangle {
                    x: parent.width - 5
                    y: parent.height / 2 - 1
                    width: 3
                    height: 2
                    radius: 1
                    color: Qt.alpha(Style.vinylLight, 0.35)
                }
                Rectangle {
                    anchors.centerIn: parent
                    width: 8
                    height: 8
                    radius: 4
                    antialiasing: true

                    gradient: Gradient {
                        GradientStop {
                            position: 0
                            color: Qt.lighter(Colors.accent, 1.25)
                        }
                        GradientStop {
                            position: 1
                            color: Qt.darker(Colors.accent, 1.6)
                        }
                    }
                }

                TapHandler {
                    onTapped: Music.playPause()
                }
                HoverHandler {
                    cursorShape: Qt.PointingHandCursor
                }
            }

            Glyph {
                shown: hover.hovered
                anchors.verticalCenter: parent.verticalCenter
                code: 0xF04AE
                onClicked: Music.prev()
            }
            Glyph {
                shown: hover.hovered
                anchors.verticalCenter: parent.verticalCenter
                strong: true
                code: Music.playing ? 0xF03E4 : 0xF040A
                onClicked: Music.playPause()
            }
            Glyph {
                shown: hover.hovered
                anchors.verticalCenter: parent.verticalCenter
                code: 0xF04AD
                onClicked: Music.next()
            }

            Item {
                id: label

                anchors.verticalCenter: parent.verticalCenter
                visible: root.labelRoom >= 44
                width: labelRow.implicitWidth
                height: glass.height

                Row {
                    id: labelRow

                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Style.spaceMd

                    transform: Translate {
                        id: labelShift
                    }

                    Text {
                        id: titleText

                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.min(implicitWidth, 150, root.labelRoom)
                        text: Music.title
                        textFormat: Text.PlainText
                        elide: Text.ElideRight
                        color: Colors.foreground

                        font {
                            family: Style.fontFamily
                            pixelSize: Style.fontMd
                        }
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: Music.artist !== "" && root.labelRoom - titleText.width - 8 >= 40
                        width: Math.min(implicitWidth, 80, root.labelRoom - titleText.width - 8)
                        text: Music.artist
                        textFormat: Text.PlainText
                        elide: Text.ElideRight
                        color: Colors.muted

                        font {
                            family: Style.fontFamily
                            pixelSize: Style.fontSm
                        }
                    }
                }

                TapHandler {
                    onTapped: Panels.toggleMusic()
                }
            }
        }
    }

    // Underline under the capsule while the pointer is on it; it breathes
    // with the ring
    Item {
        anchors.horizontalCenter: glass.horizontalCenter
        anchors.top: glass.bottom
        anchors.topMargin: Style.spaceXs
        width: 20
        height: 2
        opacity: hover.hovered ? 1 : 0
        visible: opacity > 0.01

        Behavior on opacity {
            NumberAnimation {
                duration: Style.fadeMs
            }
        }

        Rectangle {
            anchors.centerIn: parent
            width: 12 + 8 * root.breath
            height: 2
            radius: 1
            color: Colors.accent
            opacity: 0.55 + 0.4 * root.breath
        }
    }

    // The whole bar-high column answers to the pointer, not just the glass
    HoverHandler {
        id: hover
    }
    // Always a way to the panel, even when the title is hidden
    TapHandler {
        acceptedButtons: Qt.RightButton
        onTapped: Panels.toggleMusic()
    }
    WheelHandler {
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: event => Music.setVolume(Music.volume + (event.angleDelta.y > 0 ? 5 : -5))
    }
}
