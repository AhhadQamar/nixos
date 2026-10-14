// Text in the shell font, so no label can fall back to the system default.

import QtQuick

Text {
    textFormat: Text.PlainText
    font.family: Style.fontFamily
}
