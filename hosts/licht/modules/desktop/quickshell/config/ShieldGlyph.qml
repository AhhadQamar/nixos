// A shield, drawn: the VPN mark. On (`on`) it is solid with a check cut into
// it; off it is only the outline. It is the badge on the bar's network icon
// (NetGlyph.qml) and the icon of the VPN row in the network popup.
//
// Drawn on the same 16-unit grid as the other icons and written as `n * u`.
// The size is the Loader's or the parent's to set. The check keeps at least a
// 1px stroke so a small badge does not lose it.

import QtQuick
import QtQuick.Shapes

Glyph {
    id: root

    property bool on: false

    // The colour the check is cut in: the one on the accent
    readonly property color cut: Colors.onAccent

    Shape {
        anchors.fill: parent
        layer.enabled: true
        layer.samples: 4

        ShapePath {
            strokeWidth: Math.max(1, 1.5 * root.u)
            strokeColor: root.color
            joinStyle: ShapePath.RoundJoin
            // Solid when on; the fade is the colour's own alpha
            fillColor: Qt.alpha(root.color, root.on ? 1 : 0)

            Behavior on fillColor {
                ColorAnimation {
                    duration: Style.baseMs
                }
            }

            startX: 8 * root.u
            startY: 1.8 * root.u

            PathLine {
                x: 13.2 * root.u
                y: 3.6 * root.u
            }
            PathLine {
                x: 13.2 * root.u
                y: 8 * root.u
            }
            PathQuad {
                controlX: 13.2 * root.u
                controlY: 12 * root.u
                x: 8 * root.u
                y: 14.4 * root.u
            }
            PathQuad {
                controlX: 2.8 * root.u
                controlY: 12 * root.u
                x: 2.8 * root.u
                y: 8 * root.u
            }
            PathLine {
                x: 2.8 * root.u
                y: 3.6 * root.u
            }
            PathLine {
                x: 8 * root.u
                y: 1.8 * root.u
            }
        }

        // The check, cut out of the solid shield
        ShapePath {
            strokeWidth: Math.max(1, 1.5 * root.u)
            strokeColor: Qt.alpha(root.cut, root.on ? 1 : 0)
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin

            Behavior on strokeColor {
                ColorAnimation {
                    duration: Style.baseMs
                }
            }

            startX: 5.2 * root.u
            startY: 8 * root.u

            PathLine {
                x: 7.2 * root.u
                y: 10 * root.u
            }
            PathLine {
                x: 10.8 * root.u
                y: 5.9 * root.u
            }
        }
    }
}
