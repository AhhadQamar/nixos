// The three screenshot modes, drawn: Region (four corner brackets), Window (a
// window with its title bar) and Screen (a monitor on its stand). Used on the
// discs of Screenshot.qml.
//
// Same rules as the other drawn icons (see Glyph.qml): a 16-unit grid written
// as `n * u`, 1.5px strokes, round caps and joins. The size is the parent's to
// set; `kind` picks the picture ("region", "window" or "screen").

import QtQuick
import QtQuick.Shapes

Glyph {
    id: root

    property string kind: "region"

    readonly property real lw: Math.max(1, 1.5 * u)

    // A rounded rectangle as a polyline: four corner arcs of a few points each
    function roundRect(x0, y0, x1, y1, r) {
        const pts = [];
        const corners = [[x1 - r, y0 + r, -90], [x1 - r, y1 - r, 0], [x0 + r, y1 - r, 90], [x0 + r, y0 + r, 180]];
        for (let c = 0; c < 4; c++) {
            for (let i = 0; i <= 4; i++) {
                const a = (corners[c][2] + 90 * i / 4) * Math.PI / 180;
                pts.push(Qt.point((corners[c][0] + r * Math.cos(a)) * u, (corners[c][1] + r * Math.sin(a)) * u));
            }
        }
        pts.push(pts[0]);
        return pts;
    }

    function line(a, b, c, d) {
        return [Qt.point(a * u, b * u), Qt.point(c * u, d * u)];
    }

    // Region: the corners of a selection
    Shape {
        anchors.fill: parent
        visible: root.kind === "region"
        layer.enabled: visible
        layer.samples: 4

        Stroke {
            strokeColor: root.color
            strokeWidth: root.lw

            PathPolyline {
                path: [Qt.point(2.5 * root.u, 6 * root.u), Qt.point(2.5 * root.u, 2.5 * root.u), Qt.point(6 * root.u, 2.5 * root.u)]
            }
        }
        Stroke {
            strokeColor: root.color
            strokeWidth: root.lw

            PathPolyline {
                path: [Qt.point(10 * root.u, 2.5 * root.u), Qt.point(13.5 * root.u, 2.5 * root.u), Qt.point(13.5 * root.u, 6 * root.u)]
            }
        }
        Stroke {
            strokeColor: root.color
            strokeWidth: root.lw

            PathPolyline {
                path: [Qt.point(13.5 * root.u, 10 * root.u), Qt.point(13.5 * root.u, 13.5 * root.u), Qt.point(10 * root.u, 13.5 * root.u)]
            }
        }
        Stroke {
            strokeColor: root.color
            strokeWidth: root.lw

            PathPolyline {
                path: [Qt.point(6 * root.u, 13.5 * root.u), Qt.point(2.5 * root.u, 13.5 * root.u), Qt.point(2.5 * root.u, 10 * root.u)]
            }
        }
    }

    // Window: a frame with a title bar
    Shape {
        anchors.fill: parent
        visible: root.kind === "window"
        layer.enabled: visible
        layer.samples: 4

        Stroke {
            strokeColor: root.color
            strokeWidth: root.lw

            PathPolyline {
                path: root.roundRect(2, 2.5, 14, 13.5, 2)
            }
        }
        Stroke {
            strokeColor: root.color
            strokeWidth: root.lw

            PathPolyline {
                path: root.line(2, 6.2, 14, 6.2)
            }
        }
    }

    // Screen: a monitor on its stand
    Shape {
        anchors.fill: parent
        visible: root.kind === "screen"
        layer.enabled: visible
        layer.samples: 4

        Stroke {
            strokeColor: root.color
            strokeWidth: root.lw

            PathPolyline {
                path: root.roundRect(1.8, 2.5, 14.2, 10.8, 1.6)
            }
        }
        Stroke {
            strokeColor: root.color
            strokeWidth: root.lw

            PathPolyline {
                path: root.line(8, 10.8, 8, 13.2)
            }
        }
        Stroke {
            strokeColor: root.color
            strokeWidth: root.lw

            PathPolyline {
                path: root.line(5.4, 13.6, 10.6, 13.6)
            }
        }
    }
}
