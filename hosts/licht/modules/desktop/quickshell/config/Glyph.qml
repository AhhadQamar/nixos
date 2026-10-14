// The base of every drawn icon in the status discs (BatteryGlyph.qml and its
// siblings). StatItem loads one of them into its disc; this file is only what
// they all share, so each icon file can stay about its picture.
//
// Icons are drawn on a 16-unit grid and written as `n * u`. `u` is how many
// pixels one grid unit is: 1 in a plain disc (a 16px box), 0.875 when the disc
// also draws its ring (a 14px box, so the picture clears the ring). Multiplying
// by `u`, rather than scaling the item, keeps the 1.5px strokes exactly 1.5px
// and keeps GPU layers sharp (a scaled layer is a stretched, blurry texture).
//
// The size is not set here: StatItem's Loader gives this item its box, and a
// Loader resizes whatever it loads to its own size.

import QtQuick

Item {
    id: root

    // The icon's colour. StatItem's `iconColor` is passed in, so the rules for
    // it (muted when off, critical when hot...) stay in SystemStats.
    property color color: Colors.foreground

    // Pixels per grid unit, and the stroke weight: the same 1.5px as the ring
    // and the ruler ticks
    readonly property real u: width / 16
    readonly property real sw: 1.5

    // A colour change is a short fade, never a jump. A Behavior watches one
    // property and animates every change to it.
    Behavior on color {
        ColorAnimation {
            duration: Style.baseMs
        }
    }
}
