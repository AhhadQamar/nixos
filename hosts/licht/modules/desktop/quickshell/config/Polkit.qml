// Polkit agent: answers "Authentication is required to ..." prompts (pkexec,
// the system updater, GNOME Disks, ...) with a small dial in the shell's
// language, in place of polkit-gnome's GTK window. Quickshell registers itself
// with polkit and hands each request over as a flow.
// A borderless stage rises from the bottom edge over a soft scrim: one glass
// disc on the dial, holding the icon of whatever is asking (a lock if it has
// none) and ringed in the accent, with the fine ruler curving over it. Below
// the ruler the middle reads out what is being asked: "Authentication
// required" (with a friendlier name for actions this shell knows), polkit's
// own words in full, and who you would be authenticating as. Under that: show
// what you type, Switch (when polkit offers several administrators), Cancel
// and Authenticate. The password pill sits at the foot.
// The ruler is the state. It scans while polkit checks, flushes red on a wrong
// password (and the disc shakes), and fills green from the middle on a right
// one, after which the dial curls away. A message that needs more lines lifts
// the dial to make room.
//   There are no IPC commands: polkit starts it. Test it with:  pkexec true
//   Enter authenticates, Esc cancels.
// Mouse: the eye shows what you type, Switch steps to the next administrator.
//        A click on the dimmed screen does nothing but send a ring out of the
//        disc, so it is clear the prompt is waiting for an answer.
//
// Like the launcher it arrives as a rainbow: the disc and the ruler swing in
// from the left over a tight dome, washed with the wallpaper's colours, and
// unfurl into the calm dial. Closing plays it in reverse.
//
// It is modal on purpose, so a stray click can't cancel it: the window covers
// the whole screen, bar included, and takes the keyboard. It does not use
// PanelLink: the system updater asks for a password while its own panel is
// open, and a prompt must never close the panel that asked for it (or be
// closed by another one while it waits for an answer).
//
// Only one polkit agent can serve a session. Remove polkit-gnome (see the
// notes that came with this file) or this one will not register.

import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Services.Polkit

Scope {
    id: root

    // ---- Settings -------------------------------------------------------
    readonly property real screenW: targetScreen ? targetScreen.width : 1920
    readonly property int stageW: Math.min(780, Math.round(screenW * 0.9))
    readonly property int topY: 62
    readonly property int ruleDrop: 50
    readonly property int ruleY: topY + ruleDrop
    readonly property real dialR: 900
    // The dome the dial starts as when it opens (and ends as when it closes)
    readonly property real rainbowR: 360
    // Pixels per slot: only turns the arrival swing (spinIn) into distance
    readonly property real stepPx: 76
    readonly property int discSize: 72
    readonly property int tickGap: 12
    readonly property int tickN: Math.ceil(stageW / tickGap) + 24
    // How long the green "Authenticated" state stays before the dial curls
    // away: the ticks take sweepMs to fill, then it rests a moment
    readonly property int holdMs: 700
    // Friendlier names for actions you know. Anything else is just
    // "Authentication required"; polkit's own message is always shown in full.
    readonly property var titles: ({
            "org.licht.sysupd.run": "Change the system",
            "org.freedesktop.policykit.exec": "Run a program as administrator"
        })

    // ---- State ----------------------------------------------------------
    property bool isOpen: false
    // 0 = hidden below the edge, 1 = in place
    property real reveal: 0
    // Slots the dial is swung to the left while arriving (and right when leaving)
    property real spinIn: 0
    // 1 = tight rainbow dome, 0 = the resting dial
    property real fan: 1
    // A slow pulse (0..1) for the disc's ring
    property real breath: 0
    // 0 -> 1 when a new request replaces the one on show: the words fade up
    property real swap: 1
    // Sideways offset of the disc while it shakes after a wrong password
    property real shakeX: 0
    // Where the scan along the ruler is (-1 = far left, 1 = far right)
    property real scan: -1
    // Password sent, waiting for polkit's answer
    property bool busy: false
    // The last attempt was refused
    property bool errorShown: false
    // Authenticated: green for a moment, then the dial curls away
    property bool succeeded: false
    // The eye button: show what you type
    property bool showPw: false
    // Opens on the monitor that has focus
    property var targetScreen: Focus.screen
    // Kept from the request, so the dialog still reads right while it leaves
    property string message: ""
    property string iconName: ""
    property string actionId: ""
    property string identityName: ""
    property bool identityGroup: false
    property int identityCount: 0

    // The colour of the moment: green once it has worked, red after a refusal
    property color tone: succeeded ? Colors.success : (errorShown ? Colors.critical : Colors.accent)
    // 0..1 red over the whole ruler while the refusal is on show
    property real flush: errorShown ? 1 : 0
    // 0..1 how far the green has filled the ruler outward from the middle
    property real okFill: succeeded ? 1 : 0
    // 0..1 how visible the scan is (only while polkit checks)
    property real scanOn: busy ? 1 : 0

    // Radius of the dial right now: curvature eases from the dome to the dial
    readonly property real dialNow: 1 / (1 / dialR + (1 / rainbowR - 1 / dialR) * fan)

    readonly property var flow: agent.flow
    readonly property string friendly: titles[actionId] ?? ""
    readonly property string head: succeeded ? "Authenticated" : "Authentication required" + (friendly !== "" ? "  ·  " + friendly : "")
    readonly property string iconPath: iconName !== "" ? Quickshell.iconPath(iconName, "") : ""
    readonly property string prompt: {
        const p = flow && flow.inputPrompt ? String(flow.inputPrompt) : "";
        const clean = p.replace(/:\s*$/, "").trim();
        return clean !== "" ? clean : "Password";
    }
    readonly property string status: errorShown ? "Incorrect password. Try again." : (flow && flow.supplementaryMessage ? String(flow.supplementaryMessage) : "")
    readonly property bool statusIsError: errorShown || (flow !== null && flow.supplementaryIsError === true)
    readonly property bool canSubmit: !busy && !succeeded && flow !== null && flow.isResponseRequired === true && pw.text !== ""

    // ---- Layout of what is under the dial ---------------------------------
    readonly property int readoutTop: ruleY + 30
    readonly property int actionsH: Style.buttonCompact
    readonly property int pillH: Style.fieldHeight
    readonly property int foot: 16
    readonly property real actionsY: readoutTop + readout.height + 14
    readonly property real pillY: actionsY + actionsH + 14
    // The height of the stage for what is on show right now. It glides, so a
    // longer message lifts the dial instead of the window being resized.
    property real bodyH: pillY + pillH + foot

    Behavior on bodyH {
        // Snaps while the dialog is hidden or arriving
        enabled: root.isOpen && root.reveal > 0.8

        NumberAnimation {
            duration: Style.moveMs
            easing.type: Style.easeMove
        }
    }

    Behavior on tone {
        ColorAnimation {
            duration: Style.baseMs
        }
    }
    Behavior on flush {
        NumberAnimation {
            duration: Style.baseMs
            easing.type: Style.easeMove
        }
    }
    Behavior on okFill {
        NumberAnimation {
            duration: Style.sweepMs
            easing.type: Style.easeMove
        }
    }
    Behavior on scanOn {
        NumberAnimation {
            duration: Style.fadeMs
        }
    }

    // The authentication worked: a ring leaves the disc
    onSucceededChanged: if (succeeded)
        pingAnim.restart()

    // ---- Helpers --------------------------------------------------------
    function clamp(v, a, b) {
        return Math.max(a, Math.min(b, v));
    }

    function mod(a, b) {
        return ((a % b) + b) % b;
    }

    // Ease-out with a small overshoot for the arrival of the disc (0..1 in,
    // about 1.04 at the peak): the shell's `pop`, kept gentle.
    function backOut(t) {
        const c1 = 0.8;
        const u = t - 1;
        return 1 + (c1 + 1) * u * u * u + c1 * u * u;
    }

    // Staggered arrival: 0 until `from`, 1 at `to` (in reveal units).
    function stage_(from, to) {
        return clamp((reveal - from) / (to - from), 0, 1);
    }

    // `base` washed with one of the palette's colours, chosen by screen
    // position x (colour1 on the left through colour6 on the right). The wash
    // is `fan` strong, so it only shows while the dial is arriving or leaving.
    function spectral(base, x, a) {
        const ramp = [Colors.color1, Colors.color2, Colors.color3, Colors.color4, Colors.color5, Colors.color6];
        const t = (clamp((x - stage.width / 2) / (stage.width * 0.34), -1, 1) * 0.5 + 0.5) * (ramp.length - 1);
        const i = Math.min(ramp.length - 2, Math.floor(t));
        const c = Qt.tint(ramp[i], Qt.alpha(ramp[i + 1], t - i));
        return Qt.alpha(Qt.tint(base, Qt.alpha(c, 0.9 * fan)), a);
    }

    // "unix-user:licht" -> "licht"
    function identLabel(id) {
        if (!id)
            return "";
        const raw = id.displayName || id.string || "";
        return String(raw).replace(/^unix-(user|group|netgroup):/, "");
    }

    function identIsGroup(id) {
        if (!id)
            return false;
        if (id.isGroup === true)
            return true;
        return /^unix-(group|netgroup):/.test(String(id.string || ""));
    }

    function refreshIdentity() {
        const f = agent.flow;
        if (!f)
            return;
        identityName = identLabel(f.selectedIdentity);
        identityGroup = identIsGroup(f.selectedIdentity);
        identityCount = f.identities ? f.identities.length : 0;
    }

    function snapshot() {
        const f = agent.flow;
        if (!f)
            return;
        message = f.message || "";
        iconName = f.iconName || "";
        actionId = f.actionId || "";
        refreshIdentity();
    }

    // Polkit may offer several administrators: step to the next one
    function cycleIdentity() {
        const f = agent.flow;
        if (!f || !f.identities || f.identities.length < 2 || busy)
            return;
        const cur = identLabel(f.selectedIdentity);
        let at = -1;
        for (let i = 0; i < f.identities.length; i++) {
            if (identLabel(f.identities[i]) === cur)
                at = i;
        }
        f.selectedIdentity = f.identities[(at + 1) % f.identities.length];
        busy = false;
        errorShown = false;
        pw.text = "";
        pw.forceActiveFocus();
    }

    // ---- Actions --------------------------------------------------------
    function submit() {
        if (!canSubmit)
            return;
        busy = true;
        errorShown = false;
        agent.flow.submit(pw.text);
    }

    function cancel() {
        if (agent.flow)
            agent.flow.cancelAuthenticationRequest();
        close();
    }

    // Polkit wants an answer: empty the field and put the cursor in it
    function promptReady() {
        busy = false;
        pw.text = "";
        pw.forceActiveFocus();
    }

    function open() {
        closeTimer.stop();
        if (isOpen) {
            pw.forceActiveFocus();
            return;
        }
        targetScreen = Focus.screen;
        closeAnim.stop();
        // Fully hidden: start from the dome. Re-opened while it was still
        // leaving: carry on from where it is instead of snapping away first.
        if (reveal <= 0.001) {
            reveal = 0;
            spinIn = 3.2;
            fan = 1;
        }
        isOpen = true;
        openAnim.restart();
        pw.forceActiveFocus();
    }

    function close() {
        closeTimer.stop();
        if (!isOpen)
            return;
        isOpen = false;
        busy = false;
        openAnim.stop();
        closeAnim.restart();
    }

    // A request starts (also for each queued one after the last finished)
    function begin() {
        const showing = isOpen;
        succeeded = false;
        busy = false;
        errorShown = false;
        showPw = false;
        snapshot();
        // A queued request replaces the words of the one on show
        if (showing)
            swapAnim.restart();
        open();
        if (agent.flow && agent.flow.isResponseRequired)
            promptReady();
    }

    // The request is over; after a success the dialog lingers for a moment
    function finish() {
        if (succeeded)
            closeTimer.restart();
        else
            close();
    }

    // ---- Polkit ---------------------------------------------------------
    PolkitAgent {
        id: agent

        onAuthenticationRequestStarted: root.begin()
        onIsActiveChanged: {
            if (!isActive)
                root.finish();
        }
    }

    Connections {
        target: agent.flow

        function onAuthenticationFailed() {
            root.busy = false;
            root.errorShown = true;
            pw.text = "";
            shake.restart();
            pingAnim.restart();
            pw.forceActiveFocus();
        }

        function onAuthenticationSucceeded() {
            root.busy = false;
            root.succeeded = true;
        }

        // The daemon gave up on it (the program that asked went away)
        function onAuthenticationRequestCancelled() {
            root.close();
        }

        function onIsResponseRequiredChanged() {
            if (agent.flow && agent.flow.isResponseRequired)
                root.promptReady();
        }

        function onSelectedIdentityChanged() {
            root.refreshIdentity();
        }
    }

    Timer {
        id: closeTimer

        interval: root.holdMs
        onTriggered: root.close()
    }

    // Tell the log whether anything is actually listening for prompts
    Timer {
        id: regTimer

        interval: 3000
        running: true
        onTriggered: {
            if (agent.isRegistered)
                console.log("Polkit: authentication agent registered");
            else
                console.warn("Polkit: the agent did not register. Another polkit agent (polkit-gnome?) is probably running.");
        }
    }

    Component.onCompleted: {
        // A reload while a prompt was open
        if (agent.isActive)
            begin();
    }

    // Rises smoothly. The disc and the ruler swing in from the left over a
    // tight dome and unfurl into the dial while the colour drains out of them.
    ParallelAnimation {
        id: openAnim

        // Settled: a ring leaves the disc, to say it is waiting
        onStopped: if (root.isOpen && root.reveal > 0.99)
            pingAnim.restart()

        NumberAnimation {
            target: root
            property: "reveal"
            to: 1
            duration: Style.sweepMs
            easing.type: Style.easeEnter
        }
        NumberAnimation {
            target: root
            property: "spinIn"
            to: 0
            duration: Style.sweepMs + Style.moveMs
            easing.type: Style.easeEnter
        }
        NumberAnimation {
            target: root
            property: "fan"
            to: 0
            duration: Style.sweepMs + Style.ambientMs / 2
            easing.type: Style.easeMove
        }
    }

    // Leaving: the dial curls back into the dome and sweeps off right.
    ParallelAnimation {
        id: closeAnim

        NumberAnimation {
            target: root
            property: "reveal"
            to: 0
            duration: Style.moveMs + Style.fadeMs
            easing.type: Style.easeExit
        }
        NumberAnimation {
            target: root
            property: "spinIn"
            to: -3.2
            duration: Style.moveMs + Style.fadeMs
            easing.type: Style.easeExit
        }
        NumberAnimation {
            target: root
            property: "fan"
            to: 1
            duration: Style.moveMs + Style.fadeMs
            easing.type: Style.easeExit
        }
    }

    // Slow breath for the ring around the disc.
    SequentialAnimation {
        running: root.isOpen
        loops: Animation.Infinite

        NumberAnimation {
            target: root
            property: "breath"
            from: 0
            to: 1
            duration: Style.ambientMs * 2
            easing.type: Style.easeAmbient
        }
        NumberAnimation {
            target: root
            property: "breath"
            from: 1
            to: 0
            duration: Style.ambientMs * 2
            easing.type: Style.easeAmbient
        }
    }

    // Polkit is checking: a bright patch runs along the ruler and back
    SequentialAnimation {
        running: root.busy && root.isOpen
        loops: Animation.Infinite

        NumberAnimation {
            target: root
            property: "scan"
            to: 1.15
            duration: Style.sweepMs + Style.ambientMs
            easing.type: Style.easeAmbient
        }
        NumberAnimation {
            target: root
            property: "scan"
            to: -1.15
            duration: Style.sweepMs + Style.ambientMs
            easing.type: Style.easeAmbient
        }
    }

    // A new request replaces the words on show: they fade up
    NumberAnimation {
        id: swapAnim

        target: root
        property: "swap"
        from: 0
        to: 1
        duration: Style.baseMs
        easing.type: Style.easeMove
    }

    // A ring leaves the disc: on arriving, on a click on the scrim, on a
    // refusal (red) and on success (green)
    NumberAnimation {
        id: pingAnim

        target: disc
        property: "ping"
        from: 0
        to: 1
        duration: Style.sweepMs
        easing.type: Style.easeMove
    }

    // A wrong password: the disc shakes
    SequentialAnimation {
        id: shake

        NumberAnimation {
            target: root
            property: "shakeX"
            to: -9
            duration: Style.pressMs
            easing.type: Style.easePress
        }
        NumberAnimation {
            target: root
            property: "shakeX"
            to: 8
            duration: Style.pressMs
            easing.type: Style.easeAmbient
        }
        NumberAnimation {
            target: root
            property: "shakeX"
            to: -5
            duration: Style.pressMs
            easing.type: Style.easeAmbient
        }
        NumberAnimation {
            target: root
            property: "shakeX"
            to: 3
            duration: Style.pressMs
            easing.type: Style.easeAmbient
        }
        NumberAnimation {
            target: root
            property: "shakeX"
            to: 0
            duration: Style.pressMs
            easing.type: Style.easePress
        }
    }

    // ---- The window -----------------------------------------------------
    PanelWindow {
        id: win

        visible: root.isOpen || root.reveal > 0.001
        screen: root.targetScreen
        color: "transparent"
        // Cover the bar as well, so nothing else looks clickable
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "qs-polkit"
        // Exclusive, so the password goes here and nowhere else
        WlrLayershell.keyboardFocus: root.isOpen ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }

        // The scrim: a soft wash of the background colour. Clicks stop here
        // (the dialog is modal) and send a ring out of the disc.
        Rectangle {
            anchors.fill: parent
            color: Qt.alpha(Qt.tint(Colors.background, Qt.alpha(Colors.accent, 0.08)), 0.55)
            opacity: root.reveal

            MouseArea {
                anchors.fill: parent
                onClicked: {
                    pingAnim.restart();
                    pw.forceActiveFocus();
                }
            }
        }

        // ---- Stage ------------------------------------------------------
        Item {
            id: stage

            readonly property real cx: width / 2

            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            width: root.stageW
            height: root.bodyH
            clip: true
            opacity: Math.min(1, root.reveal * 3)
            transform: Translate {
                y: (1 - root.reveal) * (stage.height + 40)
            }

            // Pressing anywhere on the stage gives the keyboard back to the
            // password field
            MouseArea {
                anchors.fill: parent
                onPressed: pw.forceActiveFocus()
            }

            // Feathered backing: a soft dark ellipse keeps the words and the
            // scale readable over any wallpaper without a visible panel edge.
            StageShade {
                id: scrimShape
                yScale: 0.62
            }

            // Low light on the horizon in the colour of the moment: the
            // accent, red after a refusal, green once it has worked.
            Shape {
                id: horizon

                readonly property real r: stage.width * 0.46

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
                            color: Qt.alpha(root.tone, 0.18)
                        }
                        GradientStop {
                            position: 0.5
                            color: Qt.alpha(root.tone, 0.07)
                        }
                        GradientStop {
                            position: 1
                            color: Qt.alpha(root.tone, 0)
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

            // ---- The ruler: fine ticks curving over the disc. The ones by
            // the middle rise like a magnifier; the rest of the ruler shows
            // the state (a scan while checking, red after a refusal, green
            // filling outward from the middle on success) --------------------
            Repeater {
                // Not kept around while the dialog is hidden
                model: win.visible ? root.tickN : 0

                delegate: Rectangle {
                    id: tick

                    required property int index

                    readonly property real s: (index - root.tickN / 2) * root.tickGap - root.mod(-root.spinIn * root.stepPx * 0.5, root.tickGap * 10)
                    readonly property real a: s / root.dialNow
                    readonly property real rr: root.dialNow - root.ruleDrop
                    readonly property bool major: index % 10 === 0
                    // The magnifier by the middle, and the scan going past
                    readonly property real near: Math.max(0, 1 - Math.abs(s) / 90)
                    readonly property real wave: Math.max(0, 1 - Math.abs(x - stage.cx - root.scan * stage.width / 2) / 90) * root.scanOn
                    readonly property real hot: Math.max(near, wave)
                    // 1 once the green has reached this tick
                    readonly property real okMix: root.clamp((root.okFill * 1.35 - Math.abs(x - stage.cx) / (stage.width / 2)) / 0.35, 0, 1)
                    // Ticks the state is lighting get more solid
                    readonly property real solid: {
                        const rest = major ? 0.46 : 0.28;
                        return rest + (1 - rest) * Math.max(0.7 * hot, 0.6 * root.flush, 0.85 * okMix);
                    }
                    readonly property color hue: Qt.tint(Qt.tint(Qt.tint(Colors.foreground, Qt.alpha(Colors.accent, 0.7 * hot)), Qt.alpha(Colors.critical, 0.85 * root.flush)), Qt.alpha(Colors.success, 0.95 * okMix))

                    x: stage.cx + rr * Math.sin(a) - 0.75
                    y: root.topY + root.dialNow - rr * Math.cos(a)
                    width: 1.5
                    height: (major ? 9 : 5) + 6 * hot + 4 * okMix
                    radius: 0.75
                    antialiasing: true
                    visible: Math.abs(a) < 1.2
                    transformOrigin: Item.Top
                    rotation: a * 180 / Math.PI
                    color: root.spectral(hue, x, solid)
                    opacity: root.clamp((stage.cx - Math.abs(x - stage.cx)) / 90, 0, 1) * root.clamp(root.reveal * 2 - Math.abs(x - stage.cx) / stage.cx * 0.9, 0, 1)
                }
            }

            // The middle of the ruler: the 2px marker, in the colour of the moment
            Rectangle {
                x: stage.cx - 1
                y: root.ruleY - 3
                width: 2
                height: 16
                radius: 1
                color: root.tone
                opacity: root.clamp(root.reveal * 2 - 0.5, 0, 1)
            }

            // ---- The disc: the app's icon, or a lock -----------------------
            Item {
                id: disc

                // Swung left while arriving, right while leaving
                readonly property real s: -root.spinIn * root.stepPx
                readonly property real a: s / root.dialNow
                readonly property real px: stage.cx + root.dialNow * Math.sin(a)
                // It lifts a little off the dial, like a selected disc
                readonly property real py: root.topY + root.dialNow * (1 - Math.cos(a)) - 5
                readonly property real appear: root.stage_(0.1, 0.6)
                readonly property real edge: root.clamp((stage.cx - Math.abs(px - stage.cx)) / 90, 0, 1)
                // 0..1 while the ring leaves the disc
                property real ping: 0

                width: root.discSize
                height: root.discSize
                x: px - width / 2 + root.shakeX
                y: py - height / 2
                z: 20
                opacity: appear * edge
                scale: 0.55 + 0.45 * root.backOut(appear)
                // Tilts along the dial, and rises from below as it arrives
                rotation: a * 180 / Math.PI * 0.6
                transform: Translate {
                    y: (1 - disc.appear) * 30
                }

                // Ring that leaves the disc.
                Rectangle {
                    anchors.centerIn: parent
                    width: parent.width + 14 + 34 * disc.ping
                    height: width
                    radius: width / 2
                    color: "transparent"
                    antialiasing: true
                    visible: disc.ping > 0.001 && disc.ping < 0.999
                    border.width: 1.5
                    border.color: Qt.alpha(root.tone, 0.5 * (1 - disc.ping))
                }

                // Breathing ring around the disc.
                Rectangle {
                    anchors.centerIn: parent
                    width: parent.width + 12
                    height: width
                    radius: width / 2
                    color: "transparent"
                    antialiasing: true
                    border.width: 1
                    border.color: Qt.alpha(root.tone, 0.25 + 0.25 * root.breath)
                }

                // Glass, like the bar: one flat surface with a hairline
                // outline in the colour of the moment (washed with the
                // palette while the dial arrives).
                Rectangle {
                    anchors.fill: parent
                    radius: width / 2
                    antialiasing: true
                    color: Style.card
                    border.width: 1
                    border.color: root.spectral(root.tone, disc.px, 0.9)
                }

                // The soft tint inside the glass
                Rectangle {
                    anchors.fill: parent
                    anchors.margins: 1
                    radius: width / 2
                    antialiasing: true
                    color: Qt.alpha(root.tone, Style.tintAlpha)
                }

                // Light catching the top edge, as on the bar
                Rectangle {
                    anchors.top: parent.top
                    anchors.topMargin: 1
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: parent.width * 0.5
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

                // The icon of whatever is asking; it stays upright while the
                // disc tilts with the dial
                IconImage {
                    anchors.centerIn: parent
                    width: Math.round(disc.width * 0.56)
                    height: width
                    visible: root.iconPath !== "" && !root.succeeded
                    source: root.iconPath
                    rotation: -disc.rotation
                }

                // Or a lock; a tick once it has worked
                Txt {
                    anchors.centerIn: parent
                    visible: root.iconPath === "" || root.succeeded
                    text: root.succeeded ? Icons.check : Icons.lock
                    color: root.tone
                    font.pixelSize: disc.width * 0.38
                    rotation: -disc.rotation
                }
            }

            // Underline under the disc; it breathes with the ring.
            Rectangle {
                width: 20 + 10 * root.breath
                height: 2
                radius: 1
                color: root.tone
                x: disc.px - width / 2 + root.shakeX
                y: disc.py + root.discSize / 2 + 6
                rotation: disc.a * 180 / Math.PI
                opacity: root.clamp(root.reveal * 2 - 0.6, 0, 1)
            }

            // ---- The middle: what is being asked ---------------------------
            Item {
                id: readout

                x: stage.cx - width / 2
                y: root.readoutTop
                width: Math.min(520, stage.width - 48)
                height: readCol.implicitHeight
                // Clicks pass through to the stage
                enabled: false
                opacity: (0.25 + 0.75 * root.swap) * root.stage_(0.25, 0.8)
                transform: Translate {
                    y: (1 - root.stage_(0.25, 0.8)) * 12 + (1 - root.swap) * 6
                }

                Column {
                    id: readCol

                    width: parent.width
                    spacing: Style.spaceXs

                    // What it is, and what the shell calls it
                    Txt {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                        text: root.head
                        // Brighter than the muted grey, with a thin outline in
                        // the background colour: it stays readable over any
                        // wallpaper
                        color: root.succeeded ? Colors.success : Qt.alpha(Colors.foreground, 0.78)
                        style: Text.Outline
                        styleColor: Qt.alpha(Colors.background, 0.85)
                        font.pixelSize: Style.fontSm
                        font.letterSpacing: 1.4
                        font.capitalization: Font.AllUppercase
                    }

                    // Polkit's own words, in full: this is what you are
                    // agreeing to
                    Txt {
                        width: parent.width
                        height: visible ? implicitHeight : 0
                        horizontalAlignment: Text.AlignHCenter
                        visible: text !== ""
                        wrapMode: Text.Wrap
                        maximumLineCount: 4
                        elide: Text.ElideRight
                        lineHeight: 1.2
                        text: root.message
                        color: Colors.foreground
                        style: Text.Outline
                        styleColor: Qt.alpha(Colors.background, 0.8)
                        font.pixelSize: Style.fontLg
                        font.bold: true
                    }

                    // Who would authenticate, and the machine-readable action
                    // for those who check
                    Item {
                        width: parent.width
                        height: subRow.implicitHeight
                        visible: root.identityName !== "" || root.actionId !== ""

                        Row {
                            id: subRow

                            anchors.horizontalCenter: parent.horizontalCenter
                            spacing: Style.spaceSm

                            Txt {
                                anchors.verticalCenter: parent.verticalCenter
                                visible: root.identityName !== "" && root.identityGroup
                                text: Icons.group
                                color: Qt.alpha(Colors.foreground, 0.78)
                                style: Text.Outline
                                styleColor: Qt.alpha(Colors.background, 0.8)
                                font.pixelSize: Style.fontMd
                            }

                            Txt {
                                anchors.verticalCenter: parent.verticalCenter
                                visible: root.identityName !== ""
                                text: "as"
                                color: Qt.alpha(Colors.foreground, 0.78)
                                style: Text.Outline
                                styleColor: Qt.alpha(Colors.background, 0.8)
                                font.pixelSize: Style.fontMd
                            }

                            Txt {
                                anchors.verticalCenter: parent.verticalCenter
                                visible: root.identityName !== ""
                                text: root.identityName
                                color: Colors.foreground
                                style: Text.Outline
                                styleColor: Qt.alpha(Colors.background, 0.8)
                                font.pixelSize: Style.fontMd
                                font.bold: true
                            }

                            Txt {
                                anchors.verticalCenter: parent.verticalCenter
                                visible: root.identityName !== "" && root.actionId !== ""
                                text: "·"
                                color: Qt.alpha(Colors.foreground, 0.78)
                                style: Text.Outline
                                styleColor: Qt.alpha(Colors.background, 0.8)
                                font.pixelSize: Style.fontMd
                            }

                            Txt {
                                anchors.verticalCenter: parent.verticalCenter
                                width: Math.min(implicitWidth, 280)
                                visible: root.actionId !== ""
                                elide: Text.ElideRight
                                text: root.actionId
                                color: Qt.alpha(Colors.foreground, 0.78)
                                style: Text.Outline
                                styleColor: Qt.alpha(Colors.background, 0.8)
                                font.pixelSize: Style.fontSm
                            }
                        }
                    }

                    // What went wrong, or what polkit has to add. The line is
                    // always there, so the dial never jumps.
                    Item {
                        width: parent.width
                        height: 18

                        Txt {
                            width: parent.width
                            height: parent.height
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            elide: Text.ElideRight
                            text: root.status
                            color: root.statusIsError ? Colors.critical : Colors.muted
                            style: Text.Outline
                            styleColor: Qt.alpha(Colors.background, 0.8)
                            font.pixelSize: Style.fontMd
                            opacity: root.status !== "" ? 1 : 0

                            Behavior on opacity {
                                NumberAnimation {
                                    duration: Style.fadeMs
                                }
                            }
                            Behavior on color {
                                ColorAnimation {
                                    duration: Style.baseMs
                                }
                            }
                        }
                    }
                }
            }

            // ---- Under the readout: the few things you can do ---------------
            Row {
                id: controls

                x: stage.cx - width / 2
                y: root.actionsY
                spacing: Style.spaceMd
                // The net under the stage width: if the row is still wider
                // than the stage it shrinks to fit
                scale: Math.min(1, (stage.width - 32) / Math.max(1, controls.implicitWidth))
                opacity: root.stage_(0.35, 0.9)
                transform: Translate {
                    y: (1 - root.stage_(0.35, 0.9)) * 10
                }

                // Show what you type
                IconButton {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: !root.busy && !root.succeeded && !(root.flow !== null && root.flow.responseVisible === true)
                    glyph: root.showPw ? Icons.eyeOff : Icons.eye
                    on: root.showPw
                    onClicked: {
                        root.showPw = !root.showPw;
                        pw.forceActiveFocus();
                    }
                }

                // Several administrators to choose from
                TextButton {
                    compact: true
                    visible: root.identityCount > 1
                    text: "Switch"
                    onClicked: root.cycleIdentity()
                }

                TextButton {
                    compact: true
                    enabled: !root.succeeded
                    text: "Cancel"
                    onClicked: root.cancel()
                }

                TextButton {
                    compact: true
                    primary: true
                    minWidth: 120
                    busy: root.busy
                    enabled: root.canSubmit
                    text: root.busy ? "Checking\u2026" : "Authenticate"
                    onClicked: root.submit()
                }
            }

            // ---- The password pill, at the foot ------------------------------
            // The shell's SearchField on a glass backing, so it reads on any
            // wallpaper.
            Item {
                id: pill

                // Dimmed once it has worked
                property real dim: root.succeeded ? 0.5 : 1

                x: stage.cx - width / 2
                y: root.pillY
                width: Math.min(340, stage.width - 48)
                height: root.pillH
                opacity: root.stage_(0.4, 0.95) * dim
                transform: Translate {
                    y: (1 - root.stage_(0.4, 0.95)) * 10
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
                    border.color: root.errorShown ? Qt.alpha(Colors.critical, 0.7) : Style.outline

                    Behavior on border.color {
                        ColorAnimation {
                            duration: Style.baseMs
                        }
                    }
                }

                // Light catching the top edge, as on the bar
                Rectangle {
                    anchors.top: parent.top
                    anchors.topMargin: 1
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: parent.width - parent.height
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

                SearchField {
                    id: pw

                    anchors.fill: parent
                    glyph: Icons.lock
                    placeholder: root.prompt
                    // The lock breathes while polkit checks
                    busy: root.busy
                    clearable: !root.busy && !root.succeeded

                    onTextChanged: {
                        if (text !== "")
                            root.errorShown = false;
                    }
                    Keys.onEscapePressed: root.cancel()
                    Keys.onReturnPressed: root.submit()
                    Keys.onEnterPressed: root.submit()
                }

                // A password field is a TextInput that hides what you type
                // (unless polkit says the answer is not secret, or you ask
                // to see it) and takes no suggestions. Read-only rather than
                // disabled, so it keeps the cursor.
                Binding {
                    target: pw.input
                    property: "echoMode"
                    value: root.showPw || (root.flow !== null && root.flow.responseVisible === true) ? TextInput.Normal : TextInput.Password
                }
                Binding {
                    target: pw.input
                    property: "readOnly"
                    value: root.busy || root.succeeded
                }

                Component.onCompleted: {
                    pw.input.passwordCharacter = "\u2022";
                    pw.input.inputMethodHints = Qt.ImhSensitiveData | Qt.ImhNoPredictiveText;
                }
            }
        }
    }
}
