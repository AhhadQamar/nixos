// Centre of the bar: every monitor's workspaces, in the order the screens sit.
//   - The same strip on every bar. Each monitor's workspaces are a row of
//     small glass discs, with ONE continuous hairline ruler curving over all
//     of them (the dial in miniature, like the clock and the status icons).
//     This bar's own monitor is drawn bigger; the others are smaller and
//     dimmer.
//   - Click a disc to go there. Scroll over a monitor's group to step through
//     that monitor's workspaces.
//   - When the bar is tight, the other monitors fold to the workspace on
//     their screen plus a "+N" count (red if one of the N wants attention).
//   - Each special workspace (Super+S, the pypr terminal) has its own disc
//     after the groups, in the order of their names (see SpecialPill.qml). It
//     is selected on the bar of the monitor it is open on; click to toggle it.
//
// The special discs are the same on every bar, so moving focus between
// monitors changes nothing. To keep the workspace discs from shifting when
// one comes or goes, an empty spacer as wide as the special discs sits before
// the groups: the island stays symmetric, so the groups stay where they are.
//
// Each group has ONE highlight, a glider, that slides to whichever disc is
// active instead of every disc painting its own. It is the "selected" disc of
// the dial: accent outline and soft tint with a 2px underline under it while
// that monitor has the focus, a quiet grey while it does not. When it moves,
// the edge it is heading for leaves first and the other follows, so it
// stretches across the gap and then settles, the way the power menu's
// underline does. The discs tell it where they are (see WorkspacePill.qml);
// this file just draws it.
//
// The ruler is one scale across every monitor's discs and the special discs
// (see WorkspaceRuler.qml). Only the active workspace of each monitor has the
// effect: a 2px accent marker stands over it and follows the glider, and the
// ticks beside it rise like a magnifier. Hovering the other discs does nothing
// to the ruler. The marker over a monitor you are not working on is quieter.
// A special workspace that is open on this bar's monitor has the effect too: a
// marker stands over its disc (and glides to the next one if another is
// opened), quiet unless that monitor has the focus.
// Nothing loops, so a calm bar costs nothing.

import QtQuick

Island {
    id: root

    property string targetMonitor: ""
    // Width the bar can spare for this island
    property real maxWidth: 100000

    padding: 4
    spacing: Style.spaceMd

    // Rough width of everything if nothing were folded. Estimated from the
    // data rather than measured, so folding can never feed back into it. The
    // special discs count twice: once for them, once for the spacer that
    // mirrors them.
    readonly property bool compactOthers: {
        let w = 16 + 2 * dock.width;
        for (let i = 0; i < Spaces.monitorNames.length; i++) {
            const name = Spaces.monitorNames[i];
            const shown = Spaces.summary[name]?.shown ?? 0;
            w += name === targetMonitor ? 40 * shown + 86 : 30 * shown + 32;
        }
        return w > maxWidth;
    }

    // Touchpads send many small deltas, so add them up and step once per
    // notch's worth (120). The running total belongs to one monitor and is
    // dropped after a pause, so half a scroll over one screen cannot tip a
    // later scroll, or another screen, into an extra step.
    property real wheelAcc: 0
    property string wheelOn: ""

    function wheel(name, dy) {
        if (name !== wheelOn) {
            wheelOn = name;
            wheelAcc = 0;
        }
        wheelAcc += dy;
        wheelIdle.restart();
        if (Math.abs(wheelAcc) >= 120) {
            Spaces.stepOn(name, wheelAcc < 0 ? 1 : -1);
            wheelAcc = 0;
        }
    }

    // Every special workspace seen so far, by short name, in name order. Names
    // are only ever added: a special workspace that is gone keeps its disc,
    // which shrinks away, so it can grow back later without a pop.
    function syncSpecials() {
        const names = Spaces.specialNames;
        for (let i = 0; i < names.length; i++) {
            let at = 0;
            while (at < specialModel.count && specialModel.get(at).specName < names[i])
                at++;
            if (at < specialModel.count && specialModel.get(at).specName === names[i])
                continue;
            specialModel.insert(at, {
                "specName": names[i]
            });
        }
    }

    Component.onCompleted: syncSpecials()

    Timer {
        id: wheelIdle

        interval: 400
        onTriggered: root.wheelAcc = 0
    }

    ListModel {
        id: specialModel
    }

    Connections {
        target: Spaces

        function onSpecialNamesChanged() {
            root.syncSpecials();
        }
    }

    // As wide as the special discs, on the other side of the groups
    Item {
        id: balance

        visible: dock.width > 0.5
        width: dock.width
        height: 1
    }

    // One group per monitor. The model is just the list of names, so the
    // groups stay put while workspaces come and go inside them.
    Repeater {
        id: groups

        model: Spaces.monitorNames

        delegate: Item {
            id: group

            required property string modelData

            readonly property bool isLocal: modelData === root.targetMonitor
            readonly property bool folded: !isLocal && root.compactOthers
            readonly property var info: Spaces.summary[modelData] ?? ({
                    shown: 0,
                    rest: 0,
                    urgent: false
                })
            // Height of a disc here; the glider is the same
            readonly property real pillH: isLocal ? Style.discSize : Style.discSize - 4
            // Room between the group's ends and its first / last disc
            readonly property int pad: Style.spaceMd

            // ---- The glider's state ---------------------------------------
            // The active pill writes these three (it has Bindings aimed at
            // this group). markX is its left edge in this group's row.
            property real markX: 0
            property real markW: 0
            property bool markFocused: false
            // Where the glider's two edges are, easing towards the mark
            property real edgeL: 0
            property real edgeR: 0
            // Which way it last moved: the leading edge is the quick one
            property bool goingRight: true
            // Off for the first moments, so the glider appears in place
            // instead of sliding in from the left when the bar starts
            property bool settled: false

            function followMark() {
                // The pill has no width yet: nothing to follow
                if (markW < 1)
                    return;
                const left = markX;
                const right = markX + markW;
                const move = (left + right) - (edgeL + edgeR);
                // Ignore the small drifts of a pill that is only resizing
                if (Math.abs(move) > 6)
                    goingRight = move > 0;
                edgeL = left;
                edgeR = right;
            }

            onMarkXChanged: followMark()
            onMarkWChanged: followMark()

            Behavior on edgeL {
                enabled: group.settled

                NumberAnimation {
                    duration: group.goingRight ? Style.moveMs : Style.fadeMs
                    easing.type: Style.easeMove
                }
            }

            Behavior on edgeR {
                enabled: group.settled

                NumberAnimation {
                    duration: group.goingRight ? Style.fadeMs : Style.moveMs
                    easing.type: Style.easeMove
                }
            }

            Timer {
                interval: 600
                running: true
                onTriggered: group.settled = true
            }

            visible: info.shown > 0
            implicitHeight: Style.barHeight
            implicitWidth: pills.implicitWidth + pad * 2

            // ---- The glider ---------------------------------------------------
            // Declared before the pills, so it sits behind their icons.
            Rectangle {
                id: glider

                visible: group.markW > 0
                x: group.edgeL
                width: Math.max(0, group.edgeR - group.edgeL)
                height: group.pillH
                anchors.verticalCenter: parent.verticalCenter
                radius: height / 2
                antialiasing: true
                color: group.markFocused ? Qt.alpha(Colors.accent, Style.tintAlpha) : Style.hoverFill
                border.width: 1
                border.color: group.markFocused ? Qt.alpha(Colors.accent, 0.6) : Qt.alpha(Colors.foreground, 0.22)

                Behavior on color {
                    ColorAnimation {
                        duration: Style.baseMs
                    }
                }
                Behavior on border.color {
                    ColorAnimation {
                        duration: Style.baseMs
                    }
                }

                EdgeLight {
                    corner: glider.height
                }

                // The accent underline, under the disc: only on the monitor
                // you are working on
                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: parent.bottom
                    anchors.topMargin: Style.spaceXs
                    width: 14
                    height: 2
                    radius: 1
                    color: Colors.accent
                    opacity: group.markFocused ? 1 : 0

                    Behavior on opacity {
                        NumberAnimation {
                            duration: Style.baseMs
                        }
                    }
                }
            }

            Row {
                id: pills

                anchors.centerIn: parent
                spacing: Style.spaceSm

                // A pill for every possible id; each decides for itself
                // whether it belongs here (see WorkspacePill.qml)
                Repeater {
                    model: Spaces.idCount

                    delegate: WorkspacePill {
                        required property int index

                        anchors.verticalCenter: parent.verticalCenter
                        wsId: index + 1
                        monitorName: group.modelData
                        local: group.isLocal
                        compact: group.folded
                        pillH: group.pillH
                        tracker: group
                    }
                }

                // What the fold hides
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: group.folded && group.info.rest > 0
                    leftPadding: 4
                    rightPadding: 4
                    textFormat: Text.PlainText
                    text: "+" + group.info.rest
                    color: group.info.urgent ? Colors.critical : Colors.muted

                    font {
                        family: Style.fontFamily
                        pixelSize: Style.fontSm
                    }
                }
            }

            WheelHandler {
                acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                onWheel: event => root.wheel(group.modelData, event.angleDelta.y)
            }
        }
    }

    // ---- The ruler -----------------------------------------------------------
    // One { x, o } per monitor's group, in the island's pixels: where the
    // marker stands (the middle of that group's glider, so it travels with it)
    // and how visible it is. A monitor with no active workspace on the bar has
    // none (o = 0); one you are not working on is quiet.
    property int marksRev: 0

    // The special workspace open on this bar's monitor has the effect too: the
    // marker stands over its disc, and glides to the next one if another is
    // opened. Where the marker wants to be (-1 when no special is open), and
    // where it is: it snaps in place the first time, instead of sweeping in
    // from wherever it was last.
    readonly property real specTarget: {
        marksRev;
        for (let i = 0; i < specials.count; i++) {
            const p = specials.itemAt(i);
            if (p && p.isOpen && p.shown)
                return track.x + dock.x + p.x + p.width / 2;
        }
        return -1;
    }
    // Quiet unless the monitor it is open on is the one you are working on
    readonly property real specLevel: {
        marksRev;
        for (let i = 0; i < specials.count; i++) {
            const p = specials.itemAt(i);
            if (p && p.isOpen && p.shown)
                return p.accented ? 1 : 0.4;
        }
        return 0;
    }
    property real specX: 0
    property bool specGlide: false

    // Whether the marker is already showing over a special disc
    property bool specShown: false

    onSpecTargetChanged: {
        if (specTarget < 0)
            return;
        if (specShown) {
            specX = specTarget;
        } else {
            specGlide = false;
            specX = specTarget;
            specGlide = true;
            specShown = true;
        }
    }

    onSpecLevelChanged: {
        if (specLevel === 0)
            specShown = false;
    }

    Behavior on specX {
        enabled: root.specGlide

        NumberAnimation {
            duration: Style.moveMs
            easing.type: Style.easeEnter
        }
    }

    readonly property var marks: {
        marksRev;
        const out = [];
        for (let i = 0; i < groups.count; i++) {
            const g = groups.itemAt(i);
            if (g && g.visible && g.markW > 0) {
                out.push({
                    "x": track.x + g.x + (g.edgeL + g.edgeR) / 2 - rulerX,
                    "o": g.markFocused ? 1 : 0.4
                });
            } else {
                out.push({
                    "x": 0,
                    "o": 0
                });
            }
        }
        // The last mark is the open special workspace's
        out.push({
            "x": specX - rulerX,
            "o": specLevel
        });
        return out;
    }

    // Where the ruler runs, in the island's pixels: from the first group to
    // the end of the special discs, so it does not run over the empty spacer
    // that only keeps the groups centred
    readonly property real rulerX: track.x + (balance.visible ? balance.width + spacing : 0)
    readonly property real rulerW: Math.max(0, track.x + track.width - rulerX)

    Connections {
        target: groups

        function onItemAdded() {
            root.marksRev++;
        }
        function onItemRemoved() {
            root.marksRev++;
        }
    }

    Connections {
        target: specials

        function onItemAdded() {
            root.marksRev++;
        }
        function onItemRemoved() {
            root.marksRev++;
        }
    }

    // Across the whole island, over the discs (a child of the island itself,
    // not of the row the groups sit in, so it takes no room)
    WorkspaceRuler {
        parent: root
        x: root.rulerX
        width: root.rulerW
        y: 2
        marks: root.marks
    }

    // ---- The special workspaces ---------------------------------------------
    // One disc each, after the groups. The same on every bar; each disc
    // decides for itself whether it is selected here (see SpecialPill.qml).
    Row {
        id: dock

        visible: width > 0.5
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.spaceSm

        Repeater {
            id: specials

            model: specialModel

            // specName arrives from the model's role of the same name
            delegate: SpecialPill {
                monitorName: root.targetMonitor
            }
        }
    }
}
