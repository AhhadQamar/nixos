// Shared sizes, surface colours, shape, type and motion for the whole shell.
// Use these instead of writing numbers into a component.
//
// Surfaces: `surface` is the bar's glass, `card` the more solid glass of every
// panel. (Colors.raised / raisedAlt are the opaque fills that sit on top of
// them: key caps, chips, wells.)
//
// Shape (radius): radiusXs 4 key caps and tiny chips, radiusSm 8 buttons and
// small wells, radiusMd 10 chips and inner cards, radiusLg 14 rows, highlights
// and popups that sit in a card, radiusXl 16 the bar and every panel card. A
// shape inside another steps down at least one size. A pill is `height / 2`,
// not a token, so it stays a pill at any height.
//
// Space: spaceXs 4, spaceSm 6, spaceMd 8, spaceLg 12, spaceXl 16.
//
// Type (all in the shell font): fontXs 10 captions, fontSm 11 hints and
// details, fontMd 12 body, fontBase 13, fontLg 14 titles in a card, fontXl 16.
// Bigger sizes (dial read-outs, hero numbers) are one-offs and stay where they
// are used.
//
// Controls: TextButton and SearchField are the shared text button and search
// pill, and Icons holds every glyph (Material Design, from the Nerd Font).
//
// Motion is one small vocabulary, so every panel, popup and bar item moves
// the same way. Use these instead of writing numbers into a component:
//
//   pressMs    100   scale on press
//   fadeMs     150   opacity: things appearing or going on hover
//   baseMs     200   colour changes, small size changes, most exits
//   moveMs     260   sliding, growing, shrinking and gliding
//   enterMs    340   panels and indicators arriving
//   sweepMs    600   one-off long sequences: a glint along a bar, a fan-out
//   ambientMs  800   slow breaths and loops
//
// and the easings that go with them: press, move, enter, exit (leaving),
// ambient (a loop that breathes) and pop (a small overshoot, for something
// that appears with a flourish). Reach for `easeEnter` on anything that
// arrives and `easeExit` on anything that leaves: it is quick at the start
// of leaving, so things get out of the way.

pragma Singleton
import QtQuick
import Quickshell

Singleton {
    readonly property string fontFamily: "JetBrainsMono Nerd Font"

    readonly property int barHeight: 44
    readonly property int barRadius: radiusXl
    readonly property int barGap: 8
    // A bar popup left alone this long closes itself (see PanelLink.qml). The
    // pointer over it, or a key or the wheel used in it, starts the count again.
    // popupIdleMs is for the ones you glance at (calendar, tray and volume
    // menus); popupIdleLongMs for the ones you work in (the clock panel, Wi-Fi),
    // where a pause to read or think is normal.
    readonly property int popupIdleMs: 4000
    readonly property int popupIdleLongMs: 8000
    readonly property int itemHeight: 28
    readonly property int discSize: 24
    // ---- Shape, space and type -------------------------------------------
    readonly property int radiusXs: 4
    readonly property int radiusSm: 8
    readonly property int radiusMd: 10
    readonly property int radiusLg: 14
    readonly property int radiusXl: 16

    readonly property int spaceXs: 4
    readonly property int spaceSm: 6
    readonly property int spaceMd: 8
    readonly property int spaceLg: 12
    readonly property int spaceXl: 16

    readonly property int fontXs: 10
    readonly property int fontSm: 11
    readonly property int fontMd: 12
    readonly property int fontBase: 13
    readonly property int fontLg: 14
    readonly property int fontXl: 16

    // ---- Surfaces ---------------------------------------------------------
    readonly property color surface: Qt.alpha(Colors.background, 0.92)
    readonly property color outline: Qt.alpha(Colors.foreground, 0.1)

    // One grey ladder for everything that sits inside a card: `well` is a
    // resting fill (rows, wells, resting buttons and fields), `hoverFill` is
    // hover and focus, `strongFill` is a button under the pointer on a row that
    // is already hovered. Do not write other grey strengths into a component.
    readonly property color well: Qt.alpha(Colors.foreground, 0.05)
    readonly property color hoverFill: Qt.alpha(Colors.foreground, 0.09)
    readonly property color strongFill: Qt.alpha(Colors.foreground, 0.14)

    // Alpha for an accent or danger tint: `tintAlpha` for a soft tint (notes,
    // chips), `selectedAlpha` for the highlight under a selected tab or an `on`
    // button. Use as Qt.alpha(Colors.accent, Style.tintAlpha).
    readonly property real tintAlpha: 0.14
    readonly property real selectedAlpha: 0.2

    // Panels sit over other windows' text, so they are more solid than the bar
    readonly property color card: Qt.alpha(Colors.background, 0.97)

    // ---- Panels -----------------------------------------------------------
    // Padding between a panel card's edge and its content.
    readonly property int cardPad: 18
    // Where a top-anchored panel opens: an eighth of the way down the screen.
    function panelTop(screenHeight) {
        return Math.round(screenHeight / 8);
    }

    // ---- Controls ---------------------------------------------------------
    // TextButton: height, label padding (both sides together) and the compact
    // height used on rows. SearchField: height.
    readonly property int buttonHeight: 32
    readonly property int buttonCompact: 28
    readonly property int buttonPad: 32
    readonly property int fieldHeight: 36

    // The record in the music chip is a physical object, so it stays black and
    // its highlights stay white whatever the wallpaper does.
    readonly property color vinyl: "#0b0b10"
    readonly property color vinylLight: "#ffffff"

    // ---- Motion ---------------------------------------------------------
    readonly property int pressMs: 100
    readonly property int fadeMs: 150
    readonly property int baseMs: 200
    readonly property int moveMs: 260
    readonly property int enterMs: 340
    readonly property int sweepMs: 600
    readonly property int ambientMs: 800

    readonly property int easePress: Easing.OutQuad
    readonly property int easeMove: Easing.OutCubic
    readonly property int easeEnter: Easing.OutQuint
    readonly property int easeExit: Easing.InCubic
    readonly property int easeAmbient: Easing.InOutSine
    readonly property int easePop: Easing.OutBack
}
