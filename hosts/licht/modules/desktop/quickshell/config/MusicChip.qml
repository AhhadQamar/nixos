// Now-playing chip for the bar. Shows only while a track is loaded.
//   A small record spins while it plays; click it to play / pause.
//   hover: previous / play-pause / next appear      scroll: volume
//   click the title: open the music panel
// A thin line along the bottom shows how far into the track you are.

import QtQuick

Island {
    id: root

    padding: 8
    visible: Music.hasTrack

    Rectangle {
        id: pill

        anchors.verticalCenter: parent.verticalCenter
        implicitHeight: Style.itemHeight
        implicitWidth: row.implicitWidth + 24
        radius: height / 2
        antialiasing: true
        clip: true
        color: hover.hovered ? Qt.alpha(Colors.foreground, 0.1) : Qt.alpha(Colors.foreground, 0.06)

        Behavior on color {
            ColorAnimation {
                duration: 200
            }
        }
        Behavior on implicitWidth {
            NumberAnimation {
                duration: 160
                easing.type: Easing.OutCubic
            }
        }

        component Glyph: Item {
            id: g

            property int code: 0
            property bool strong: false

            signal clicked

            width: 22
            height: 22

            Text {
                anchors.centerIn: parent
                text: String.fromCodePoint(g.code)
                color: g.strong || gh.hovered ? Colors.accent : Colors.foreground

                font {
                    family: Style.fontFamily
                    pixelSize: g.strong ? 17 : 15
                }
            }

            TapHandler {
                onTapped: g.clicked()
            }
            HoverHandler {
                id: gh

                cursorShape: Qt.PointingHandCursor
            }
        }

        Row {
            id: row

            x: 6
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6

            // The record
            Item {
                id: disc

                anchors.verticalCenter: parent.verticalCenter
                width: 22
                height: 22

                RotationAnimator {
                    target: disc
                    from: 0
                    to: 360
                    duration: 5000
                    loops: Animation.Infinite
                    running: root.visible
                    paused: !Music.playing
                }

                Rectangle {
                    anchors.fill: parent
                    radius: width / 2
                    antialiasing: true
                    color: "#0b0b10"
                    border.width: 1
                    border.color: Qt.alpha("#ffffff", 0.12)
                }
                // One groove, and a bright edge so the spin is visible
                Rectangle {
                    anchors.centerIn: parent
                    width: 16
                    height: 16
                    radius: 8
                    color: "transparent"
                    border.width: 1
                    border.color: Qt.alpha("#ffffff", 0.08)
                }
                Rectangle {
                    x: parent.width - 6
                    y: parent.height / 2 - 1
                    width: 4
                    height: 2
                    radius: 1
                    color: Qt.alpha("#ffffff", 0.35)
                }
                Rectangle {
                    anchors.centerIn: parent
                    width: 10
                    height: 10
                    radius: 5
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
                visible: hover.hovered
                anchors.verticalCenter: parent.verticalCenter
                code: 0xF04AE
                onClicked: Music.prev()
            }
            Glyph {
                visible: hover.hovered
                anchors.verticalCenter: parent.verticalCenter
                strong: true
                code: Music.playing ? 0xF03E4 : 0xF040A
                onClicked: Music.playPause()
            }
            Glyph {
                visible: hover.hovered
                anchors.verticalCenter: parent.verticalCenter
                code: 0xF04AD
                onClicked: Music.next()
            }

            Item {
                id: label

                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(230, labelRow.implicitWidth)
                height: pill.height

                Row {
                    id: labelRow

                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 8

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.min(implicitWidth, 150)
                        text: Music.title
                        textFormat: Text.PlainText
                        elide: Text.ElideRight
                        color: Colors.foreground

                        font {
                            family: Style.fontFamily
                            pixelSize: 13
                        }
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: Music.artist !== ""
                        width: Math.min(implicitWidth, 80)
                        text: Music.artist
                        textFormat: Text.PlainText
                        elide: Text.ElideRight
                        color: Colors.muted

                        font {
                            family: Style.fontFamily
                            pixelSize: 12
                        }
                    }
                }

                TapHandler {
                    onTapped: Panels.toggleMusic()
                }
            }
        }

        // Progress
        Rectangle {
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            width: parent.width * Music.progress
            height: 2
            color: Colors.accent
            opacity: 0.8
        }

        HoverHandler {
            id: hover
        }
        WheelHandler {
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            onWheel: event => Music.setVolume(Music.volume + (event.angleDelta.y > 0 ? 5 : -5))
        }
    }
}
