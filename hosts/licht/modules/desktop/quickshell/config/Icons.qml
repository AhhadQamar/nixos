pragma Singleton
import QtQuick
import Quickshell

// Every icon in the shell is a Material Design glyph from the Nerd Font
// (the Nerd Fonts `md-` range, U+F0001 and up). Use these names instead of
// writing a codepoint or a character into a component:
//
//     Txt (text: Icons.search)
//
// A glyph's colour and size come from the Text that shows it. Bar modules that
// pick a glyph by state (battery, volume, wifi) keep their own codepoint tables
// and call String.fromCodePoint on them; they are Material too.
//
// ADDING AN ICON: see the bottom of this file.
//
// IMPORTANT: keep the pragma above the comments and never write curly braces
// in any comment above it. Quickshell scans the top of the file for
// "pragma Singleton" and stops at the first line containing a brace, so a
// brace in the header makes Icons a plain type and every Icons.xxx is undefined.

Singleton {
    // search, search fields (md-magnify)
    readonly property string search: String.fromCodePoint(0xF0349)
    // close, clear (md-close)
    readonly property string close: String.fromCodePoint(0xF0156)
    // done, selected (md-check)
    readonly property string check: String.fromCodePoint(0xF012C)
    // download (md-download)
    readonly property string download: String.fromCodePoint(0xF01DA)
    // upload (md-upload)
    readonly property string upload: String.fromCodePoint(0xF0552)
    // retry, reload (md-refresh)
    readonly property string refresh: String.fromCodePoint(0xF0450)
    // pause (md-pause)
    readonly property string pause: String.fromCodePoint(0xF03E4)
    // play, resume (md-play)
    readonly property string play: String.fromCodePoint(0xF040A)
    // warning, error (md-alert_outline)
    readonly property string warning: String.fromCodePoint(0xF002A)
    // history, time (md-clock_outline)
    readonly property string clock: String.fromCodePoint(0xF0150)
    // add (md-plus)
    readonly property string plus: String.fromCodePoint(0xF0415)
    // remove one (md-minus)
    readonly property string minus: String.fromCodePoint(0xF0374)
    // paste (md-content_paste)
    readonly property string paste: String.fromCodePoint(0xF0192)
    // copy (md-content_copy)
    readonly property string copy: String.fromCodePoint(0xF018F)
    // delete (md-delete_outline)
    readonly property string trash: String.fromCodePoint(0xF09E7)
    // expand (md-chevron_down)
    readonly property string chevronDown: String.fromCodePoint(0xF0140)
    // previous (md-chevron_left)
    readonly property string chevronLeft: String.fromCodePoint(0xF0141)
    // next (md-chevron_right)
    readonly property string chevronRight: String.fromCodePoint(0xF0142)
    // move up (md-arrow_up)
    readonly property string arrowUp: String.fromCodePoint(0xF005D)
    // move down (md-arrow_down)
    readonly property string arrowDown: String.fromCodePoint(0xF0045)
    // open in another app (md-open_in_new)
    readonly property string openExternal: String.fromCodePoint(0xF03CC)
    // folder (md-folder_outline)
    readonly property string folder: String.fromCodePoint(0xF0256)
    // open the folder (md-folder_open_outline)
    readonly property string folderOpen: String.fromCodePoint(0xF0DCF)
    // image (md-image_outline)
    readonly property string image: String.fromCodePoint(0xF0976)
    // colour (md-palette_outline)
    readonly property string palette: String.fromCodePoint(0xF0E0C)
    // link (md-link)
    readonly property string link: String.fromCodePoint(0xF0337)
    // note, text (md-file_document_outline)
    readonly property string file: String.fromCodePoint(0xF09EE)
    // daily note, dates (md-calendar_month_outline)
    readonly property string calendar: String.fromCodePoint(0xF0E18)
    // task (md-checkbox_marked_outline)
    readonly property string checkbox: String.fromCodePoint(0xF0135)
    // notifications (md-bell_outline)
    readonly property string bell: String.fromCodePoint(0xF009C)
    // do not disturb (md-bell_off_outline)
    readonly property string bellOff: String.fromCodePoint(0xF0A91)
    // a package (md-cube_outline)
    readonly property string pkg: String.fromCodePoint(0xF01A7)
    // locked (md-lock)
    readonly property string lock: String.fromCodePoint(0xF033E)
    // a group (md-account_group)
    readonly property string group: String.fromCodePoint(0xF0849)
    // show (md-eye)
    readonly property string eye: String.fromCodePoint(0xF0208)
    // hide (md-eye_off)
    readonly property string eyeOff: String.fromCodePoint(0xF0209)

    // bluetooth, a device that reports no kind (md-bluetooth)
    readonly property string bluetooth: String.fromCodePoint(0xF00AF)
    // headphones, headsets (md-headphones)
    readonly property string headphones: String.fromCodePoint(0xF02CB)
    // speakers and other audio (md-speaker)
    readonly property string speaker: String.fromCodePoint(0xF04C3)
    // keyboards (md-keyboard)
    readonly property string keyboard: String.fromCodePoint(0xF030C)
    // mice (md-mouse)
    readonly property string mouse: String.fromCodePoint(0xF037D)
    // game controllers (md-gamepad-variant)
    readonly property string gamepad: String.fromCodePoint(0xF02B5)
    // phones (md-cellphone)
    readonly property string cellphone: String.fromCodePoint(0xF011C)
    // computers (md-laptop)
    readonly property string laptop: String.fromCodePoint(0xF0322)

    // ---- Adding an icon -------------------------------------------------
    // 1. Find the glyph on https://pictogrammers.com/library/mdi/ (or the
    //    Nerd Fonts cheat sheet, search "md-") and copy its codepoint,
    //    e.g. heart-outline is F02D5. Codepoints from F0001 up are the ones
    //    this file uses.
    // 2. Add one line above, same shape as the others:
    //        readonly property string heart: String.fromCodePoint(0xF02D5)
    // 3. Use it anywhere: Txt (text: Icons.heart). Txt already sets the font.
    // Always show icons through Txt (or IconButton), never a bare Text, or
    // the glyph falls back to a font that does not have it.
}
