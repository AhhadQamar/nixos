import QtQuick
import QtQuick.Shapes

// Screenshot's feathered backing: a soft dark ellipse, centred on the bottom
// edge of its parent, that keeps the words and the scale readable without a
// visible panel edge. `h` is how tall it rises (the stage's height);
// `strength` scales every alpha.
Shape {
    id: shade

    property real h: parent.height
    property real strength: 1
    // Vertical squash of the ellipse. The default makes it rise `h` above the
    // bottom edge; a panel can set its own (a fixed 0.62 for a low, wide one).
    property real yScale: h * 0.96 / r
    readonly property real r: parent.width * 0.5

    x: parent.width / 2 - r
    y: parent.height - r
    width: r * 2
    height: r * 2
    layer.enabled: true
    layer.samples: 4
    transform: Scale {
        origin.x: shade.r
        origin.y: shade.r
        yScale: shade.yScale
    }

    ShapePath {
        strokeColor: "transparent"
        startX: 0
        startY: shade.r

        fillGradient: RadialGradient {
            centerX: shade.r
            centerY: shade.r
            centerRadius: shade.r
            focalX: shade.r
            focalY: shade.r

            GradientStop {
                position: 0
                color: Qt.alpha(Colors.background, 0.88 * shade.strength)
            }
            GradientStop {
                position: 0.55
                color: Qt.alpha(Colors.background, 0.6 * shade.strength)
            }
            GradientStop {
                position: 1
                color: Qt.alpha(Colors.background, 0)
            }
        }

        PathArc {
            x: shade.r * 2
            y: shade.r
            radiusX: shade.r
            radiusY: shade.r
        }
        PathArc {
            x: 0
            y: shade.r
            radiusX: shade.r
            radiusY: shade.r
        }
    }
}
