// A hairline for the drawn icons: a ShapePath that is already set to the
// house style (1.5px, round caps and joins, no fill). Use it inside a Shape
// and give it a colour and a path:
//
//     Shape {
//         Stroke {
//             strokeColor: root.color
//             PathPolyline { path: [Qt.point(0, 0), Qt.point(8, 8)] }
//         }
//     }
//
// Only what an icon needs to differ is set where it is used.

import QtQuick.Shapes

ShapePath {
    strokeWidth: 1.5
    fillColor: "transparent"
    capStyle: ShapePath.RoundCap
    joinStyle: ShapePath.RoundJoin
}
