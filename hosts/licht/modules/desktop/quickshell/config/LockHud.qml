// LockHud.qml
// What the lock and the login screen show on one screen, in the shell's dial
// language (see PowerMenu.qml and the launcher). Lock.qml and Greeter.qml make
// one of these per screen and keep all the state, so both are the same design
// and every screen moves as one.
//
// "Rail". The backdrop is your wallpaper, blurred. The time is a poster on the
// left: the hour over the minutes, with a thin line under them that is the
// seconds. A borderless stage rises from the bottom edge. Across it runs the
// ruler, as a rail, and the glass discs hang from it:
//
//     meters           the lock disc          actions
//     battery, volume, brightness   (lock)    previous, play, next, suspend,
//                                              reboot, shutdown
//
// The dial turns: the selected disc swells, lifts to the marker on the rail and
// is read out below it (what it is, what state it is in). The lock disc is the
// home position; typing, a wrong password or Esc brings the dial back to it, so
// the password is never more than a key away and an error is always in view.
// The ruler is the state, as in Polkit: it drifts with the dial, answers each
// key you type, scans while PAM (or greetd) checks, flushes red on a wrong
// password and fills green from the middle to both edges on a right one, after
// which the dial curls away and the screen opens.
//
// What the discs do:
//   lock disc   shows the lock state. Press = submit what is typed.
//   battery     how full, charging or not, and the time left (the greeter has
//               UPower too, so both screens show it). Information only.
//   actions     whatever `lock.actions` offers. Destructive ones (critical)
//               ask for a second press: the disc turns red, a red line runs
//               down the time left, and it lets go after a few seconds.
//   meters      an action with `level` and `adjust` (volume, brightness): a ring
//               round the disc shows the value, Ctrl+Up / Down or the - and +
//               buttons change it.
// Under the readout is a row of compact buttons for the selected disc (- and +
// for a meter, the main action for the rest), and the password pill rests at
// the foot.
//
// Like the launcher it arrives as a rainbow: the discs and the ruler swing in
// from the left over a tight dome, washed with the wallpaper's colours, and
// unfurl into the calm dial. Closing plays it in reverse.
//
// Keys (the password field keeps focus, so typing is never affected):
//   type            the password        Enter    submit it
//   Tab, Shift+Tab  turn the dial       Ctrl+Left, Ctrl+Right   the same
//   Ctrl+Enter, Ctrl+Space   press the selected disc
//   Enter on an empty field  presses the selected disc (not the lock disc)
//   Ctrl+Up, Ctrl+Down       adjust a meter (volume, brightness)
//   Esc             back to the lock disc; again to clear the field
// Mouse: click a disc to turn to it, click it again to press it. The wheel
// turns the dial. The buttons under the readout do the same as the keys.
//
// It reads these from `lock` (the same names in Lock.qml and Greeter.qml):
//   password failed broken succeeded checking          what is going on
//   reveal spinIn fan breath shakeX scan ring turn     the animation clocks
//   tone flush okFill scanOn                           colour of the moment
//   hourText minuteText periodText dateText greeting   the clock and the hello
//   secFrac modeText goText wallpaper                  the seconds, the labels, the picture
//   actions nowActive nowTitle nowArtist nowProgress   what the discs and the player offer
//   dialIndex armed                                    which disc is selected (-1 = the
//                                                      lock disc), which waits for a second press
//   submit()                                           Enter was pressed
// It writes `password`, `dialIndex` and `armed` (all state stays in `lock`).
//
// Each entry of `actions` is { label, icon (a glyph), critical (optional, asks
// twice), enabled (optional), run() }, and may also carry, all optional:
//   key        a stable name, so the dial keeps its place when the list changes
//   head       the small line above the name in the readout (default "Action")
//   name()     the label right now (Play / Pause), glyph() the icon right now
//   sub()      the line under the name (what is playing, "Muted")
//   level()    0..1, makes it a meter (drawn to the left of the lock disc)
//   adjust(d)  d is +1 or -1; with level(), makes it adjustable
// Functions, not values, so a changing label never rebuilds the dial.

import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import Quickshell.Services.UPower

Item {
    id: dial

    // The lock this screen shows (Lock.qml): every screen reads the same state
    required property var lock

    // ---- Settings -------------------------------------------------------
    // The ruler and the glow use the whole width; the words keep to a narrower
    // column in the middle
    readonly property int contentW: Math.min(820, Math.round(width * 0.9))
    readonly property int discBig: 84
    readonly property int discSmall: 56
    // Pixels per slot: how far apart the discs sit on the dial
    readonly property real stepPx: 92
    // The rail floats this far above the middle of the selected disc
    readonly property int lift: discBig / 2 + 42
    readonly property int topY: lift + 18
    readonly property int tickGap: 12
    // The ticks fade out well before the edge of a wide screen, so the number
    // is capped
    readonly property int tickN: Math.min(220, Math.ceil(Math.min(width, 2200) / tickGap) + 24)
    // A gentle arc across the screen: wide enough that its edges drop only a
    // little, whatever the screen
    readonly property real dialR: Math.max(900, width * 1.6)
    // The dome the dial starts as when it opens (and ends as when it closes)
    readonly property real rainbowR: 360
    // How long a pending confirmation stays armed, in ms
    readonly property int armMs: 3000

    // Radius of the dial right now: curvature eases from the dome to the dial
    readonly property real dialNow: 1 / (1 / dialR + (1 / rainbowR - 1 / dialR) * lock.fan)

    // ---- Layout of the stage ----------------------------------------------
    readonly property int readoutTop: topY + discBig / 2 + 44
    readonly property int readoutH: 72
    readonly property int buttonsY: readoutTop + readoutH + 14
    readonly property int pillH: Style.fieldHeight
    readonly property int pillY: buttonsY + Style.buttonCompact + 16
    readonly property int foot: Style.panelFoot + Style.spaceXl * 2
    readonly property real bodyH: pillY + pillH + foot
    readonly property real stageTop: height - bodyH
    // The poster clock fits above the stage, whatever the screen
    readonly property int heroSize: Math.round(clamp(Math.min(height * 0.2, (stageTop - 170) / 2.1), 56, 240))
    readonly property int marginX: Math.round(Math.max(40, width * 0.05))
    // The background colour with a breath of the accent, for the washes
    readonly property color wash: Qt.tint(Colors.background, Qt.alpha(Colors.accent, 0.08))

    // ---- Helpers --------------------------------------------------------
    function clamp(v, a, b) {
        return Math.max(a, Math.min(b, v));
    }

    function mod(a, b) {
        return ((a % b) + b) % b;
    }

    // Ease-out with a small overshoot for the arrival of a disc (0..1 in,
    // about 1.04 at the peak): the shell's `pop`, kept gentle.
    function backOut(t) {
        const c1 = 0.8;
        const u = t - 1;
        return 1 + (c1 + 1) * u * u * u + c1 * u * u;
    }

    // Staggered arrival: 0 until `from`, 1 at `to` (in reveal units).
    function stage_(from, to) {
        return clamp((lock.reveal - from) / (to - from), 0, 1);
    }

    // `base` washed with one of the palette's colours, chosen by screen
    // position x (colour1 on the left through colour6 on the right). The wash
    // is `fan` strong, so it only shows while the dial is arriving or leaving.
    function spectral(base, x, a) {
        const ramp = [Colors.color1, Colors.color2, Colors.color3, Colors.color4, Colors.color5, Colors.color6];
        const t = (clamp((x - stage.width / 2) / (stage.width * 0.34), -1, 1) * 0.5 + 0.5) * (ramp.length - 1);
        const i = Math.min(ramp.length - 2, Math.floor(t));
        const c = Qt.tint(ramp[i], Qt.alpha(ramp[i + 1], t - i));
        return Qt.alpha(Qt.tint(base, Qt.alpha(c, 0.9 * lock.fan)), a);
    }

    function fmtTime(sec) {
        const m = Math.round(sec / 60);
        const h = Math.floor(m / 60);
        return h > 0 ? h + " h " + (m % 60) + " min" : m + " min";
    }

    // What an action says about itself right now (see the header)
    function labelOf(e) {
        return typeof e.name === "function" ? e.name() : e.label;
    }

    function glyphOf(e) {
        return typeof e.glyph === "function" ? e.glyph() : e.icon;
    }

    function levelOf(e) {
        return typeof e.level === "function" ? clamp(e.level(), 0, 1) : -1;
    }

    function subOf(e) {
        return typeof e.sub === "function" ? e.sub() : (e.sub || "");
    }

    // ---- Battery (read the same way as the bar) ---------------------------
    readonly property var bat: UPower.displayDevice
    readonly property bool hasBattery: bat?.isPresent ?? false
    readonly property real batLevel: {
        const p = bat?.percentage ?? 0;
        return p > 1 ? p / 100 : p;
    }
    readonly property int batPercent: Math.round(batLevel * 100)
    readonly property bool charging: bat ? bat.state === UPowerDeviceState.Charging : false
    // Green while charging, red at 15% and under, the accent otherwise
    readonly property color batTint: charging ? Colors.success : (batPercent <= 15 ? Colors.critical : Colors.accent)

    // ---- The discs --------------------------------------------------------
    // Meters (battery, then every action that has a level) go left of the lock
    // disc, everything else right of it
    readonly property var acts: lock.actions || []
    readonly property var items: {
        const left = [];
        const right = [];
        for (let i = 0; i < acts.length; i++) {
            const a = acts[i];
            (typeof a.level === "function" ? left : right).push({
                "kind": "act",
                "entry": a
            });
        }
        if (hasBattery)
            left.unshift({
                "kind": "battery"
            });
        return left.concat([
            {
                "kind": "home"
            }
        ], right);
    }
    readonly property int homeIndex: Math.max(0, items.findIndex(it => it.kind === "home"))
    // The selected disc. lock.dialIndex is -1 for the lock disc, so the dial
    // opens on it whatever else is on the rail.
    readonly property int sel: lock.dialIndex < 0 ? homeIndex : Math.min(lock.dialIndex, items.length - 1)
    // Where the dial is turned to, in slots. It glides.
    property real pos: sel
    // The selected disc, as the readout and the buttons need it
    readonly property var cur: items[sel]
    readonly property string curKind: cur ? cur.kind : "home"
    readonly property var curEntry: cur && cur.kind === "act" ? cur.entry : null
    readonly property bool curCritical: curEntry !== null && curEntry.critical === true
    readonly property bool curAdjusts: curEntry !== null && typeof curEntry.adjust === "function"
    readonly property bool curRuns: curEntry !== null && typeof curEntry.run === "function"
    readonly property bool armedNow: curKind === "act" && lock.armed === sel
    // 0..1 for a disc with a level (the ring round it), -1 for the others
    readonly property real curLevel: curKind === "battery" ? (hasBattery ? batLevel : -1) : (curEntry !== null ? levelOf(curEntry) : -1)
    readonly property color curTint: curKind === "home" ? lock.tone : (curCritical ? Colors.critical : (curKind === "battery" ? batTint : Colors.accent))
    // Where the selected disc is on the dial right now (swing included)
    readonly property real selA: (sel - pos - lock.spinIn) * stepPx / dialNow
    readonly property real selX: stage.cx + dialNow * Math.sin(selA) + lock.shakeX
    readonly property real selY: topY + dialNow * (1 - Math.cos(selA)) - 8
    // How the readout changes when the dial turns: it slides in from the side
    // the dial came from
    property real swap: 1
    property real readShift: 0
    property int lastSel: -1
    // The key of the selected disc, so it stays selected when the list changes
    property string selKey: "home"
    // Wheel steps add up, so a touchpad turns the dial one slot per notch
    property real wheelAcc: 0
    // 1 right after arming, running down to 0 as the confirmation lapses
    property real armLeft: 0

    // ---- What the readout says --------------------------------------------
    readonly property string headText: {
        if (curKind === "home")
            return lock.greeting;
        if (curKind === "battery")
            return "Battery";
        return curEntry.head || (curCritical ? "Power" : "Action");
    }
    readonly property string titleText: {
        if (curKind === "home")
            return lock.succeeded ? "Unlocked" : lock.modeText;
        if (curKind === "battery")
            return hasBattery ? batPercent + "%" : "No battery";
        return curLevel >= 0 ? Math.round(curLevel * 100) + "%" : labelOf(curEntry);
    }
    // The line under the name; a refusal, a pending second press and a
    // check win over the usual line
    readonly property string detailText: {
        if (curKind === "home") {
            if (lock.succeeded)
                return "";
            return lock.broken ? "Could not check the password." : (lock.failed ? "Incorrect password. Try again." : (lock.checking ? "Checking…" : ""));
        }
        if (curKind === "battery") {
            if (!hasBattery)
                return "";
            const t = charging ? (bat?.timeToFull ?? 0) : (bat?.timeToEmpty ?? 0);
            if (charging)
                return t > 0 ? "Charging  ·  " + fmtTime(t) + " to full" : "Charging";
            return t > 0 ? "On battery  ·  " + fmtTime(t) + " left" : "On battery";
        }
        if (armedNow)
            return "Press again to " + labelOf(curEntry).toLowerCase();
        return subOf(curEntry);
    }
    readonly property bool detailRed: armedNow || (curKind === "home" && (lock.failed || lock.broken))
    // The main button under the readout (empty hides it)
    readonly property string mainText: {
        if (curKind === "home")
            return lock.goText;
        if (curKind === "act" && curRuns)
            return armedNow ? "Press again" : labelOf(curEntry);
        return "";
    }
    readonly property bool mainEnabled: {
        if (lock.succeeded)
            return false;
        if (curKind === "home")
            return lock.password !== "" && !lock.checking;
        return curEntry !== null && curEntry.enabled !== false;
    }

    // ---- Turning the dial ---------------------------------------------------
    function select(i) {
        if (lock.succeeded || i < 0 || i >= items.length)
            return;
        lock.armed = -1;
        lock.dialIndex = i === homeIndex ? -1 : i;
    }

    function goHome() {
        select(homeIndex);
    }

    // dir: +1 = right, -1 = left. Keys wrap round, the wheel stops at the ends.
    function turnBy(dir, wrap) {
        const n = items.length;
        select(wrap ? (sel + dir + n) % n : clamp(sel + dir, 0, n - 1));
    }

    // Click: turn to a disc, or press the one that is already selected
    function activate(i) {
        if (i !== sel)
            select(i);
        else
            press(i);
    }

    // Press a disc. The design never unlocks anything itself: the lock disc
    // only asks the lock to check what is typed.
    function press(i) {
        const it = items[i];
        if (!it || lock.succeeded)
            return;
        if (it.kind === "home") {
            lock.submit();
            return;
        }
        if (it.kind !== "act")
            return;
        const a = it.entry;
        if (a.enabled === false || typeof a.run !== "function")
            return;
        // Destructive ones ask for a second press
        if (a.critical === true && lock.armed !== i) {
            lock.armed = i;
            return;
        }
        lock.armed = -1;
        a.run();
    }

    function adjust(dir) {
        if (lock.succeeded || !curAdjusts)
            return;
        curEntry.adjust(dir);
    }

    // Enter. What is typed always goes to the lock. On an empty field there is
    // nothing to submit, so Enter presses the selected disc (and Ctrl+Enter
    // always does).
    function enter(ctrl) {
        if (ctrl || (curKind !== "home" && lock.password === ""))
            press(sel);
        else
            lock.submit();
    }

    function back() {
        if (sel !== homeIndex)
            goHome();
        else if (pw.text !== "")
            pw.text = "";
    }

    Behavior on pos {
        NumberAnimation {
            duration: Style.moveMs
            easing.type: Style.easeMove
        }
    }

    onSelChanged: {
        const it = items[sel];
        selKey = it ? (it.kind === "act" ? (it.entry.key || it.entry.label) : it.kind) : "home";
        readShift = sel > lastSel ? 14 : -14;
        lastSel = sel;
        swapAnim.restart();
    }

    // The list changed (a track started, say): keep the same disc selected, and
    // let go of any pending confirmation
    onItemsChanged: {
        lock.armed = -1;
        if (lock.dialIndex < 0)
            return;
        const j = items.findIndex(it => (it.kind === "act" ? (it.entry.key || it.entry.label) : it.kind) === selKey);
        lock.dialIndex = j >= 0 && j !== homeIndex ? j : -1;
    }

    NumberAnimation {
        id: swapAnim

        target: dial
        property: "swap"
        from: 0
        to: 1
        duration: Style.baseMs
        easing.type: Style.easeMove
    }

    // A pending confirmation lapses after a few seconds, and a red line under
    // the readout shows how long is left
    Timer {
        interval: dial.armMs
        running: dial.lock.armed >= 0
        onTriggered: dial.lock.armed = -1
    }

    NumberAnimation {
        id: armAnim

        target: dial
        property: "armLeft"
        from: 1
        to: 0
        duration: dial.armMs
        easing.type: Easing.Linear
    }

    Connections {
        function onPasswordChanged() {
            // Every screen's field follows the one shared password, so what is
            // typed on one shows on the other
            if (pw.text !== dial.lock.password)
                pw.text = dial.lock.password;
            // Typing means "let me in": the dial comes back to the lock disc
            if (dial.lock.password !== "" && dial.sel !== dial.homeIndex)
                dial.goHome();
        }

        // A refusal is read out on the lock disc, so the dial returns to it
        function onFailedChanged() {
            if (dial.lock.failed)
                dial.goHome();
        }

        function onBrokenChanged() {
            if (dial.lock.broken)
                dial.goHome();
        }

        function onArmedChanged() {
            if (dial.lock.armed >= 0) {
                armAnim.restart();
            } else {
                armAnim.stop();
                dial.armLeft = 0;
            }
        }

        target: dial.lock
    }

    // ---- Shared pieces ----------------------------------------------------
    // Text with the soft outline in the background colour, so it reads on any
    // wallpaper
    component HudText: Txt {
        style: Text.Outline
        styleColor: Qt.alpha(Colors.background, 0.8)
    }

    // Light catching the top edge, as on the bar
    component TopLight: Rectangle {
        height: 1

        gradient: Gradient {
            orientation: Gradient.Horizontal

            GradientStop {
                position: 0
                color: Qt.alpha(Colors.foreground, 0)
            }
            GradientStop {
                position: 0.5
                color: Qt.alpha(Colors.foreground, 0.12)
            }
            GradientStop {
                position: 1
                color: Qt.alpha(Colors.foreground, 0)
            }
        }
    }

    // ---- Backdrop: the wallpaper, blurred ---------------------------------
    // A blurred picture needs no detail, so the image is read and blurred at a
    // quarter of the screen size and scaled up: the same look for a sixteenth
    // of the work, which matters on a laptop's integrated graphics.
    Item {
        id: backdrop

        width: Math.round(dial.width / 4)
        height: Math.round(dial.height / 4)
        scale: 4
        transformOrigin: Item.TopLeft
        // Fades in once it has loaded; until then the surface's own
        // background colour shows
        opacity: wall.status === Image.Ready ? 1 : 0
        layer.enabled: true
        layer.effect: MultiEffect {
            blurEnabled: true
            blur: 1
            blurMax: 12
        }

        Behavior on opacity {
            NumberAnimation {
                duration: Style.baseMs
            }
        }

        Image {
            id: wall

            anchors.fill: parent
            source: dial.lock.wallpaper !== "" ? "file://" + dial.lock.wallpaper : ""
            asynchronous: true
            fillMode: Image.PreserveAspectCrop
            sourceSize: Qt.size(backdrop.width, backdrop.height)
        }
    }

    // A wash of the background colour over it: lighter at the top, darker
    // toward the foot where the stage needs the calm
    Rectangle {
        anchors.fill: parent

        gradient: Gradient {
            GradientStop {
                position: 0
                color: Qt.alpha(dial.wash, 0.3)
            }
            GradientStop {
                position: 0.55
                color: Qt.alpha(dial.wash, 0.5)
            }
            GradientStop {
                position: 1
                color: Qt.alpha(dial.wash, 0.82)
            }
        }
    }

    // A second, sideways wash behind the poster clock, so its digits read on
    // any wallpaper
    Rectangle {
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        width: Math.round(dial.width * 0.55)
        opacity: dial.stage_(0.1, 0.7)

        gradient: Gradient {
            orientation: Gradient.Horizontal

            GradientStop {
                position: 0
                color: Qt.alpha(dial.wash, 0.4)
            }
            GradientStop {
                position: 1
                color: Qt.alpha(dial.wash, 0)
            }
        }
    }

    // ---- The poster: the time, on the left ----------------------------------
    // The hour over the minutes, the seconds as a thin line, then the day and
    // (on the lock) what is playing.
    Item {
        id: hero

        x: dial.marginX
        y: Math.max(Style.panelTop, Math.round((dial.stageTop - height) / 2))
        width: Math.max(220, heroCol.implicitWidth)
        height: heroCol.implicitHeight
        // Clicks pass through
        enabled: false
        opacity: dial.stage_(0.2, 0.75)
        transform: Translate {
            y: (1 - dial.stage_(0.2, 0.75)) * 24
        }

        Column {
            id: heroCol

            spacing: 0

            // Which screen this is
            Row {
                height: 28
                spacing: Style.spaceMd

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 6
                    height: width
                    radius: width / 2
                    color: dial.lock.tone
                    opacity: 0.5 + 0.5 * dial.lock.breath
                }

                HudText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: dial.lock.modeText
                    color: Qt.alpha(Colors.foreground, 0.7)
                    font.pixelSize: Style.fontSm
                    font.letterSpacing: 2
                    font.capitalization: Font.AllUppercase
                }
            }

            // The digits sit in boxes a little shorter than the type, so the
            // two lines stack tightly
            HudText {
                height: Math.round(dial.heroSize * 0.86)
                verticalAlignment: Text.AlignVCenter
                text: dial.lock.hourText
                color: Colors.foreground
                font.pixelSize: dial.heroSize
            }

            HudText {
                height: Math.round(dial.heroSize * 0.86)
                verticalAlignment: Text.AlignVCenter
                text: dial.lock.minuteText
                color: Qt.alpha(Colors.foreground, 0.5)
                font.pixelSize: dial.heroSize
            }

            // The seconds: a line that fills once a minute. It steps once a
            // second like a watch; the wrap back to zero snaps.
            Item {
                id: secLine

                property real fill: dial.lock.secFrac

                width: Math.round(dial.heroSize * 1.2)
                height: 22

                Behavior on fill {
                    enabled: dial.lock.secFrac > 0.005

                    NumberAnimation {
                        duration: Style.moveMs
                        easing.type: Style.easeMove
                    }
                }

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width
                    height: 2
                    radius: 1
                    color: Qt.alpha(Colors.foreground, 0.15)

                    Rectangle {
                        width: parent.width * dial.clamp(secLine.fill, 0, 1)
                        height: parent.height
                        radius: 1
                        color: dial.lock.tone
                    }
                }
            }

            HudText {
                text: dial.lock.periodText + "  ·  " + dial.lock.dateText
                color: Qt.alpha(Colors.foreground, 0.85)
                font.pixelSize: Style.fontMd
                font.letterSpacing: 3
                font.capitalization: Font.AllUppercase
            }

            // What is playing (the lock only), with a thin line for how far
            // through it is
            Item {
                width: Math.min(420, dial.width - dial.marginX * 2)
                height: dial.lock.nowActive === true ? 44 : 0
                visible: dial.lock.nowActive === true

                HudText {
                    id: nowText

                    y: 18
                    width: parent.width
                    elide: Text.ElideRight
                    text: (dial.lock.nowArtist ? dial.lock.nowArtist + "  ·  " : "") + dial.lock.nowTitle
                    color: Qt.alpha(Colors.foreground, 0.8)
                    font.pixelSize: Style.fontMd
                }

                Rectangle {
                    y: nowText.y + nowText.implicitHeight + 6
                    width: 160
                    height: 2
                    radius: 1
                    color: Qt.alpha(Colors.foreground, 0.15)

                    Rectangle {
                        width: parent.width * dial.clamp(dial.lock.nowProgress, 0, 1)
                        height: parent.height
                        radius: 1
                        color: dial.lock.tone
                    }
                }
            }
        }
    }

    // ---- Stage ------------------------------------------------------------
    Item {
        id: stage

        readonly property real cx: width / 2

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        width: dial.width
        height: dial.bodyH
        clip: true
        opacity: Math.min(1, dial.lock.reveal * 3)
        transform: Translate {
            y: (1 - dial.lock.reveal) * (stage.height + 40)
        }

        // Pressing anywhere on the stage gives the keyboard back to the
        // password field; the wheel turns the dial
        MouseArea {
            anchors.fill: parent
            onPressed: pw.forceActiveFocus()
            onWheel: wheel => {
                dial.wheelAcc += wheel.angleDelta.y !== 0 ? wheel.angleDelta.y : wheel.angleDelta.x;
                if (Math.abs(dial.wheelAcc) >= 120) {
                    dial.turnBy(dial.wheelAcc < 0 ? 1 : -1, false);
                    dial.wheelAcc = 0;
                }
            }
        }

        // Feathered backing: a soft dark ellipse keeps the words and the
        // scale readable over any wallpaper without a visible panel edge. It
        // sits in the middle column, not the whole width.
        Item {
            anchors.horizontalCenter: parent.horizontalCenter
            width: dial.contentW
            height: parent.height

            StageShade {
                yScale: 0.62
            }
        }

        // Low light on the horizon, wide as the screen, in the colour of the
        // moment: the accent, red after a refusal, green once it has worked.
        Shape {
            id: horizon

            readonly property real r: stage.width * 0.4

            x: stage.cx - r
            y: stage.height - r
            width: r * 2
            height: r * 2
            layer.enabled: true
            layer.samples: 4
            transform: Scale {
                origin.x: horizon.r
                origin.y: horizon.r
                yScale: 0.42
            }

            ShapePath {
                strokeColor: "transparent"
                startX: 0
                startY: horizon.r

                fillGradient: RadialGradient {
                    centerX: horizon.r
                    centerY: horizon.r
                    centerRadius: horizon.r
                    focalX: horizon.r
                    focalY: horizon.r

                    GradientStop {
                        position: 0
                        color: Qt.alpha(dial.lock.tone, 0.16)
                    }
                    GradientStop {
                        position: 0.5
                        color: Qt.alpha(dial.lock.tone, 0.06)
                    }
                    GradientStop {
                        position: 1
                        color: Qt.alpha(dial.lock.tone, 0)
                    }
                }

                PathArc {
                    x: horizon.r * 2
                    y: horizon.r
                    radiusX: horizon.r
                    radiusY: horizon.r
                }
                PathArc {
                    x: 0
                    y: horizon.r
                    radiusX: horizon.r
                    radiusY: horizon.r
                }
            }
        }

        // ---- The rail: fine ticks curving across the screen above the discs,
        // pointing down at them. The ones by the middle rise like a magnifier;
        // the rest of the ruler shows the state (a scan while checking, red
        // after a refusal, green filling outward from the middle on success).
        // It drifts with the dial at half speed, and typing turns it. -------
        Repeater {
            model: dial.tickN

            delegate: Rectangle {
                id: tick

                required property int index

                // The rail is concentric with the dial, a little outside it
                readonly property real rr: dial.dialNow + dial.lift
                readonly property real s: (index - dial.tickN / 2) * dial.tickGap - dial.mod((dial.pos + dial.lock.spinIn) * dial.stepPx * 0.5 + dial.lock.turn, dial.tickGap * 10)
                readonly property real a: s / rr
                readonly property bool major: index % 10 === 0
                // The magnifier by the middle, and the scan going past
                readonly property real near: Math.max(0, 1 - Math.abs(s) / 90)
                readonly property real wave: Math.max(0, 1 - Math.abs(x - stage.cx - dial.lock.scan * stage.width / 2) / 90) * dial.lock.scanOn
                readonly property real hot: Math.max(near, wave)
                // 1 once the green has reached this tick
                readonly property real okMix: dial.clamp((dial.lock.okFill * 1.35 - Math.abs(x - stage.cx) / (stage.width / 2)) / 0.35, 0, 1)
                // Ticks the state is lighting get more solid
                readonly property real solid: {
                    const rest = major ? 0.46 : 0.28;
                    return rest + (1 - rest) * Math.max(0.7 * hot, 0.6 * dial.lock.flush, 0.85 * okMix);
                }
                readonly property color hue: Qt.tint(Qt.tint(Qt.tint(Colors.foreground, Qt.alpha(Colors.accent, 0.7 * hot)), Qt.alpha(Colors.critical, 0.85 * dial.lock.flush)), Qt.alpha(Colors.success, 0.95 * okMix))

                x: stage.cx + rr * Math.sin(a) - 0.75
                y: dial.topY + dial.dialNow - rr * Math.cos(a)
                width: 1.5
                height: (major ? 9 : 5) + 6 * hot + 4 * okMix
                radius: 0.75
                antialiasing: true
                visible: Math.abs(a) < 1.2 && y < stage.height - 60
                transformOrigin: Item.Top
                rotation: a * 180 / Math.PI
                color: dial.spectral(hue, x, solid)
                opacity: dial.clamp((stage.cx - Math.abs(x - stage.cx)) / 240, 0, 1) * dial.clamp(dial.lock.reveal * 2 - Math.abs(x - stage.cx) / stage.cx * 0.9, 0, 1)
            }
        }

        // The middle of the rail: the 2px marker, in the colour of the moment,
        // pointing down at the selected disc
        Rectangle {
            x: stage.cx - 1
            y: dial.topY - dial.lift - 3
            width: 2
            height: 14
            radius: 1
            color: dial.curTint
            opacity: dial.clamp(dial.lock.reveal * 2 - 0.5, 0, 1)
        }

        // ---- The discs --------------------------------------------------
        Repeater {
            model: dial.items

            delegate: Item {
                id: slot

                required property int index
                required property var modelData

                readonly property string kind: modelData.kind
                readonly property var entry: modelData.entry ?? null
                readonly property bool current: index === dial.sel
                readonly property bool armed: kind === "act" && dial.lock.armed === index
                readonly property bool critical: entry !== null && entry.critical === true
                readonly property bool off: entry !== null && entry.enabled === false
                // Accent on the selected one only; red for the destructive ones
                // and for a refusal
                readonly property color tint: critical ? Colors.critical : (kind === "home" ? dial.lock.tone : (kind === "battery" ? dial.batTint : Colors.accent))
                // Slots from the middle (swing included)
                readonly property real k0: index - dial.pos
                readonly property real k: k0 - dial.lock.spinIn
                readonly property real a: k * dial.stepPx / dial.dialNow
                // 0 at rest, 1 when selected. Animated, so the disc swells.
                property real grow: current ? 1 : 0
                readonly property real sz: dial.discSmall + (dial.discBig - dial.discSmall) * grow
                readonly property real px: stage.cx + dial.dialNow * Math.sin(a) + dial.lock.shakeX
                // The selected one also lifts toward the rail
                readonly property real py: dial.topY + dial.dialNow * (1 - Math.cos(a)) - 8 * grow
                // The discs arrive in a left-to-right wave, each with a small
                // overshoot, and leave the same way
                readonly property real appear: dial.clamp((dial.lock.reveal - index * 0.04) / 0.42, 0, 1)
                // Only the discs near the middle are drawn
                readonly property real reach: dial.clamp((4.6 - Math.abs(k0)) / 1.6, 0, 1)
                readonly property real edge: dial.clamp((stage.cx - Math.abs(px - stage.cx)) / 105, 0, 1)
                // 0..1 for a disc with a level, -1 for the others
                readonly property real lvl: kind === "battery" ? (dial.hasBattery ? dial.batLevel : -1) : (entry !== null ? dial.levelOf(entry) : -1)
                // 0 under the pointer: a gentle lift
                property real hover: area.containsMouse && !current ? 1 : 0
                // 0..1 while the ring round a newly selected disc expands
                property real ping: 0

                visible: opacity > 0.01
                width: sz
                height: sz
                x: px - sz / 2
                y: py - sz / 2
                z: current ? 20 : 10 - Math.abs(k0)
                opacity: appear * edge * reach * (off ? 0.4 : (dial.lock.succeeded && !current ? 0.5 : 1))
                scale: 0.55 + 0.45 * dial.backOut(appear)
                // Tilts along the dial, and rises from below as it arrives
                rotation: a * 180 / Math.PI * 0.6
                transform: Translate {
                    id: nudge

                    y: (1 - slot.appear) * 30 - 3 * slot.hover
                }

                Behavior on hover {
                    NumberAnimation {
                        duration: Style.baseMs
                        easing.type: Style.easeMove
                    }
                }

                // Swells with a little overshoot, settles back without one
                Behavior on grow {
                    NumberAnimation {
                        duration: Style.moveMs
                        easing.type: slot.current ? Style.easePop : Style.easeMove
                        easing.overshoot: 1.2
                    }
                }

                // The dial turned to this one: a ring leaves it
                onCurrentChanged: if (current && dial.lock.reveal > 0.8)
                    pingAnim.restart()

                NumberAnimation {
                    id: pingAnim

                    target: slot
                    property: "ping"
                    from: 0
                    to: 1
                    duration: Style.sweepMs
                    easing.type: Style.easeMove
                }

                // A small shake when it arms, so the second press is noticed
                onArmedChanged: if (armed)
                    nudgeAnim.restart()

                SequentialAnimation {
                    id: nudgeAnim

                    NumberAnimation {
                        target: nudge
                        property: "x"
                        to: -4
                        duration: 50
                    }
                    NumberAnimation {
                        target: nudge
                        property: "x"
                        to: 4
                        duration: 80
                    }
                    NumberAnimation {
                        target: nudge
                        property: "x"
                        to: 0
                        duration: 110
                        easing.type: Style.easeMove
                    }
                }

                // Ring that leaves a newly selected disc
                Rectangle {
                    anchors.centerIn: parent
                    width: parent.width + 14 + 34 * slot.ping
                    height: width
                    radius: width / 2
                    color: "transparent"
                    antialiasing: true
                    visible: slot.ping > 0.001 && slot.ping < 0.999
                    border.width: 1.5
                    border.color: Qt.alpha(slot.armed ? Colors.critical : slot.tint, 0.5 * (1 - slot.ping))
                }

                // Ring that leaves the lock disc on a refusal (red) and on
                // success (green)
                Rectangle {
                    anchors.centerIn: parent
                    width: parent.width + 14 + 34 * dial.lock.ring
                    height: width
                    radius: width / 2
                    color: "transparent"
                    antialiasing: true
                    visible: slot.kind === "home" && dial.lock.ring > 0.001 && dial.lock.ring < 0.999
                    border.width: 1.5
                    border.color: Qt.alpha(dial.lock.tone, 0.5 * (1 - dial.lock.ring))
                }

                // Breathing ring round the selected disc; red while armed
                Rectangle {
                    anchors.centerIn: parent
                    width: parent.width + 14
                    height: width
                    radius: width / 2
                    color: "transparent"
                    antialiasing: true
                    visible: slot.grow > 0.05
                    border.width: 1
                    border.color: slot.armed ? Qt.alpha(Colors.critical, 0.35 + 0.45 * dial.lock.breath) : Qt.alpha(slot.tint, slot.grow * (0.2 + 0.2 * dial.lock.breath))
                }

                // Everything that can be pressed sits in here, so the press
                // shrink never changes the area the mouse reacts to
                Item {
                    anchors.fill: parent
                    scale: area.pressed ? 0.94 : 1

                    Behavior on scale {
                        NumberAnimation {
                            duration: Style.pressMs
                            easing.type: Style.easePress
                        }
                    }

                    // Glass, like the bar: one flat surface with a hairline
                    // outline. The outline takes the palette wash while the
                    // dial is arriving, and the tint once selected. Armed, it
                    // reddens.
                    Rectangle {
                        anchors.fill: parent
                        radius: width / 2
                        antialiasing: true
                        color: slot.armed ? Qt.tint(Style.card, Qt.alpha(Colors.critical, 0.3)) : Style.card
                        border.width: 1
                        border.color: slot.grow > 0.45 ? dial.spectral(slot.tint, slot.px, 0.6 + 0.4 * slot.grow) : dial.spectral(slot.critical ? Colors.critical : Colors.foreground, slot.px, slot.critical ? 0.45 : 0.2)
                    }

                    // The soft tint inside the glass, on the selected disc
                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: 1
                        radius: width / 2
                        antialiasing: true
                        color: Qt.alpha(slot.tint, Style.tintAlpha * slot.grow)
                    }

                    TopLight {
                        anchors.top: parent.top
                        anchors.topMargin: 1
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: parent.width * 0.5
                    }

                    // The shell's hover fill
                    Rectangle {
                        anchors.fill: parent
                        radius: width / 2
                        antialiasing: true
                        color: area.containsMouse ? Style.hoverFill : "transparent"

                        Behavior on color {
                            ColorAnimation {
                                duration: Style.baseMs
                            }
                        }
                    }

                    // A glyph: the lock (a tick once it has worked) or the
                    // action's own. It stays upright while the disc tilts with
                    // the dial, and breathes while the password is checked.
                    Txt {
                        anchors.centerIn: parent
                        anchors.verticalCenterOffset: slot.lvl >= 0 ? -4 : 0
                        visible: slot.kind !== "battery"
                        rotation: -slot.rotation
                        text: slot.kind === "act" ? dial.glyphOf(slot.entry) : (dial.lock.succeeded ? Icons.check : Icons.lock)
                        color: slot.kind === "home" ? slot.tint : (slot.critical ? Colors.critical : (slot.current ? Colors.accent : Colors.foreground))
                        opacity: slot.kind === "home" && dial.lock.checking ? 0.45 + 0.55 * dial.lock.breath : (slot.current || slot.critical ? 1 : 0.9)
                        font.pixelSize: 22 + 8 * slot.grow

                        Behavior on color {
                            ColorAnimation {
                                duration: Style.baseMs
                            }
                        }
                    }

                    // The battery, drawn: an outline, a nub, and the charge
                    // inside
                    Item {
                        anchors.centerIn: parent
                        width: 30
                        height: 14
                        visible: slot.kind === "battery"
                        rotation: -slot.rotation
                        scale: 0.9 + 0.2 * slot.grow

                        Rectangle {
                            width: 27
                            height: parent.height
                            radius: 3
                            color: "transparent"
                            border.width: 1
                            border.color: Qt.alpha(slot.tint, 0.85)

                            Rectangle {
                                x: 2
                                y: 2
                                width: Math.max(2, (parent.width - 4) * Math.max(0, slot.lvl))
                                height: parent.height - 4
                                radius: 1.5
                                color: slot.tint
                            }
                        }

                        Rectangle {
                            x: 28
                            anchors.verticalCenter: parent.verticalCenter
                            width: 2
                            height: 6
                            radius: 1
                            color: Qt.alpha(slot.tint, 0.85)
                        }
                    }

                    // A small bar of the level, on a meter that is not selected
                    // (the selected one has the ring)
                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: parent.height - 15
                        width: 20
                        height: 2
                        radius: 1
                        visible: slot.kind === "act" && slot.lvl >= 0 && !slot.current
                        color: Qt.alpha(Colors.foreground, 0.18)

                        Rectangle {
                            width: parent.width * Math.max(0, slot.lvl)
                            height: parent.height
                            radius: 1
                            color: Qt.alpha(Colors.foreground, 0.7)
                        }
                    }
                }

                MouseArea {
                    id: area

                    anchors.fill: parent
                    hoverEnabled: true
                    enabled: !dial.lock.succeeded
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        dial.activate(slot.index);
                        pw.forceActiveFocus();
                    }
                }
            }
        }

        // The value of the selected disc, as a ring round it (volume,
        // brightness, battery). One shape, which follows the selection.
        Shape {
            id: levelRing

            readonly property real r: dial.discBig / 2 + 13

            x: dial.selX - r - 2
            y: dial.selY - r - 2
            width: (r + 2) * 2
            height: width
            visible: dial.curLevel >= 0 && opacity > 0.01
            opacity: dial.stage_(0.3, 0.8)
            layer.enabled: visible
            layer.samples: 4

            ShapePath {
                strokeColor: Qt.alpha(Colors.foreground, 0.14)
                strokeWidth: 2
                fillColor: "transparent"

                PathAngleArc {
                    centerX: levelRing.r + 2
                    centerY: levelRing.r + 2
                    radiusX: levelRing.r
                    radiusY: levelRing.r
                    startAngle: -90
                    sweepAngle: 359.9
                }
            }

            ShapePath {
                strokeColor: Qt.alpha(dial.curTint, 0.9)
                strokeWidth: 2
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap

                PathAngleArc {
                    centerX: levelRing.r + 2
                    centerY: levelRing.r + 2
                    radiusX: levelRing.r
                    radiusY: levelRing.r
                    startAngle: -90
                    sweepAngle: 359.9 * Math.max(0.001, dial.curLevel)
                }
            }
        }

        // Underline under the selected disc; it breathes with the ring.
        Rectangle {
            width: 20 + 10 * dial.lock.breath
            height: 2
            radius: 1
            color: dial.curTint
            x: dial.selX - width / 2
            y: dial.selY + dial.discBig / 2 + 8
            rotation: dial.selA * 180 / Math.PI
            opacity: dial.clamp(dial.lock.reveal * 2 - 0.6, 0, 1)
        }

        // ---- The readout: the selected disc, in words ----------------------
        Item {
            id: readout

            x: stage.cx - width / 2
            y: dial.readoutTop
            width: Math.min(560, stage.width - 48)
            height: dial.readoutH
            // Clicks pass through to the stage
            enabled: false
            opacity: (0.3 + 0.7 * dial.swap) * dial.stage_(0.25, 0.8)
            transform: Translate {
                x: dial.readShift * (1 - dial.swap)
                y: (1 - dial.stage_(0.25, 0.8)) * 12
            }

            Column {
                width: parent.width
                spacing: Style.spaceXs

                // What it is: a small head line (the greeting, on the lock disc)
                HudText {
                    width: parent.width
                    height: 14
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    elide: Text.ElideRight
                    text: dial.headText
                    // Brighter than the muted grey, with a thin outline in the
                    // background colour: it stays readable over any wallpaper
                    color: Qt.alpha(Colors.foreground, 0.78)
                    font.pixelSize: Style.fontSm
                    font.letterSpacing: 1.4
                    font.capitalization: Font.AllUppercase
                }

                // Its name or its value
                HudText {
                    width: parent.width
                    height: 30
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    elide: Text.ElideRight
                    text: dial.titleText
                    color: dial.lock.succeeded ? Colors.success : (dial.armedNow || dial.curCritical ? Colors.critical : Colors.foreground)
                    // A dial read-out, so the size is a one-off
                    font.pixelSize: 22
                    font.bold: true
                    font.letterSpacing: -0.2

                    Behavior on color {
                        ColorAnimation {
                            duration: Style.baseMs
                        }
                    }
                }

                // How it is, or what went wrong. The line is always there, so
                // the dial never jumps.
                HudText {
                    width: parent.width
                    height: 18
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    elide: Text.ElideRight
                    text: dial.detailText
                    color: dial.detailRed ? Colors.critical : Colors.muted
                    font.pixelSize: Style.fontMd

                    Behavior on color {
                        ColorAnimation {
                            duration: Style.baseMs
                        }
                    }
                }
            }
        }

        // The red line that runs down while a second press is awaited
        Rectangle {
            x: stage.cx - width / 2
            y: dial.readoutTop + dial.readoutH + 2
            width: 120
            height: 2
            radius: 1
            color: Style.outline
            opacity: dial.armedNow ? 1 : 0
            visible: opacity > 0.01

            Behavior on opacity {
                NumberAnimation {
                    duration: Style.baseMs
                }
            }

            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                width: parent.width * dial.armLeft
                height: parent.height
                radius: 1
                color: Colors.critical
            }
        }

        // ---- Under the readout: the few things you can do ------------------
        Row {
            id: buttons

            x: stage.cx - width / 2
            y: dial.buttonsY
            height: Style.buttonCompact
            spacing: Style.spaceMd
            // If the row is ever wider than the stage it shrinks to fit
            scale: Math.min(1, (stage.width - 32) / Math.max(1, buttons.implicitWidth))
            opacity: dial.stage_(0.35, 0.9) * (dial.lock.succeeded ? 0.4 : 1)
            transform: Translate {
                y: (1 - dial.stage_(0.35, 0.9)) * 12
            }

            TextButton {
                compact: true
                glyph: Icons.minus
                visible: dial.curAdjusts
                enabled: !dial.lock.succeeded
                onClicked: {
                    dial.adjust(-1);
                    pw.forceActiveFocus();
                }
            }

            TextButton {
                compact: true
                minWidth: 92
                visible: dial.mainText !== ""
                enabled: dial.mainEnabled
                // The lock disc's button is the accent one; so is any
                // harmless action. A destructive one is red, and rings in red
                // while it waits for its second press.
                primary: !dial.curCritical
                danger: dial.curCritical
                armed: dial.armedNow
                busy: dial.curKind === "home" && dial.lock.checking
                text: dial.mainText
                onClicked: {
                    dial.press(dial.sel);
                    pw.forceActiveFocus();
                }
            }

            TextButton {
                compact: true
                glyph: Icons.plus
                visible: dial.curAdjusts
                enabled: !dial.lock.succeeded
                onClicked: {
                    dial.adjust(1);
                    pw.forceActiveFocus();
                }
            }
        }

        // ---- The password pill, at the foot -------------------------------
        // The shell's SearchField on a glass backing, so it reads on any
        // wallpaper.
        Item {
            id: pill

            // Dimmed once it has worked
            property real dim: dial.lock.succeeded ? 0.5 : 1

            x: stage.cx - width / 2
            y: dial.pillY
            width: Math.min(340, stage.width - 48)
            height: dial.pillH
            opacity: dial.stage_(0.4, 0.95) * dim
            transform: Translate {
                y: (1 - dial.stage_(0.4, 0.95)) * 10
            }

            Behavior on dim {
                NumberAnimation {
                    duration: Style.moveMs
                    easing.type: Style.easeMove
                }
            }

            Rectangle {
                anchors.fill: parent
                radius: height / 2
                antialiasing: true
                color: Style.surface
                border.width: 1
                // Red after a refusal (the field is empty again, so the
                // field's own edge does not cover it)
                border.color: (dial.lock.failed || dial.lock.broken) ? Qt.alpha(Colors.critical, 0.7) : Style.outline

                Behavior on border.color {
                    ColorAnimation {
                        duration: Style.baseMs
                    }
                }
            }

            TopLight {
                anchors.top: parent.top
                anchors.topMargin: 1
                anchors.horizontalCenter: parent.horizontalCenter
                width: parent.width - parent.height
            }

            SearchField {
                id: pw

                anchors.fill: parent
                glyph: Icons.lock
                // The refusal is also said here, where the eye is
                placeholder: dial.lock.broken ? "Could not check" : (dial.lock.failed ? "Incorrect password" : (dial.lock.checking ? "Checking…" : "Password"))
                // The lock breathes while PAM checks
                busy: dial.lock.checking
                clearable: false

                // Every screen's field follows the one shared password (see
                // the Connections above)
                onTextChanged: {
                    if (text !== dial.lock.password)
                        dial.lock.password = text;
                }
                // None of these keys type anything, so the password is never
                // disturbed. Return is handled here and not as onReturnPressed,
                // which would swallow Ctrl+Return first.
                Keys.onPressed: event => {
                    const k = event.key;
                    const ctrl = (event.modifiers & Qt.ControlModifier) !== 0;
                    if (k === Qt.Key_Tab || (ctrl && k === Qt.Key_Right))
                        dial.turnBy(1, true);
                    else if (k === Qt.Key_Backtab || (ctrl && k === Qt.Key_Left))
                        dial.turnBy(-1, true);
                    else if (ctrl && k === Qt.Key_Up)
                        dial.adjust(1);
                    else if (ctrl && k === Qt.Key_Down)
                        dial.adjust(-1);
                    else if (k === Qt.Key_Return || k === Qt.Key_Enter)
                        dial.enter(ctrl);
                    else if (ctrl && k === Qt.Key_Space)
                        dial.press(dial.sel);
                    else if (k === Qt.Key_Escape)
                        dial.back();
                    else
                        return;
                    event.accepted = true;
                }
            }

            // A password field is a TextInput that hides what you type and
            // takes no suggestions. Read-only rather than disabled, so it
            // keeps the cursor.
            Binding {
                target: pw.input
                property: "echoMode"
                value: TextInput.Password
            }
            Binding {
                target: pw.input
                property: "readOnly"
                value: dial.lock.checking || dial.lock.succeeded
            }

            Component.onCompleted: {
                pw.input.passwordCharacter = "•";
                pw.input.inputMethodHints = Qt.ImhSensitiveData | Qt.ImhNoPredictiveText;
                pw.forceActiveFocus();
            }
        }
    }
}
