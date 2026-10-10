// Workspace and monitor data for the bar (Workspaces.qml, WorkspacePill.qml).
//
// Workspace ids come in blocks of SlotLayout.slotsPerMonitor per monitor
// (eDP-1 1..10, DP-1 11..20, ...), pinned by hypr/config/modules/workspaces.lua.
//
// Most things here are properties, not functions. A property is worked out
// once per change and shared by every bar and every pill; a function called
// from each pill's binding would redo the same work once per pill.

pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Hyprland

Singleton {
    id: root

    // id -> workspace, for every real workspace. Special ones (the scratchpad)
    // have negative ids and are left out.
    readonly property var byId: {
        const map = {};
        const all = Hyprland.workspaces.values;
        for (let i = 0; i < all.length; i++) {
            if (all[i].id >= 1)
                map[all[i].id] = all[i];
        }
        return map;
    }

    // How many pills a monitor's row needs: the highest id in use, rounded up
    // to a whole block. It is a plain number on purpose. A Repeater given a
    // number only adds or removes pills at the end when it changes, while a
    // Repeater given a fresh array rebuilds every pill (losing hover and
    // animations) each time the array is re-made.
    readonly property int idCount: {
        let top = 0;
        for (const id in byId)
            top = Math.max(top, Number(id));
        return Math.max(1, SlotLayout.blockOf(top) + 1) * SlotLayout.slotsPerMonitor;
    }

    // Monitor names in the order the screens sit: left to right, then top to
    // bottom. Only changes when a screen is plugged in or moved.
    readonly property var monitorNames: {
        const all = Hyprland.monitors.values;
        const list = [];
        for (let i = 0; i < all.length; i++)
            list.push(all[i]);
        list.sort((a, b) => ((a.x ?? 0) - (b.x ?? 0)) || ((a.y ?? 0) - (b.y ?? 0)));
        return list.map(m => m.name);
    }

    // monitor name -> { shown, rest, urgent }
    //   shown:  workspaces worth drawing (on screen, holding windows, or urgent)
    //   rest:   how many of those are not the one on screen
    //   urgent: one of the others wants attention
    readonly property var summary: {
        const out = {};
        for (const id in byId) {
            const ws = byId[id];
            const name = ws.monitor?.name;
            if (!name)
                continue;
            if (out[name] === undefined)
                out[name] = {
                    shown: 0,
                    rest: 0,
                    urgent: false
                };
            const s = out[name];
            const urgent = (ws.urgent ?? false) && !ws.active;
            if (ws.active || urgent || windowsIn(ws.id).length > 0) {
                s.shown++;
                if (!ws.active)
                    s.rest++;
            }
            if (urgent)
                s.urgent = true;
        }
        return out;
    }

    // monitor name -> true while it holds workspaces from more than one block.
    // That happens when a screen is unplugged and its workspaces move over:
    // two different "3"s would then sit side by side in the bar.
    readonly property var mixed: {
        const firstBlock = {};
        const out = {};
        for (const id in byId) {
            const name = byId[id].monitor?.name;
            if (!name)
                continue;
            const block = SlotLayout.blockOf(Number(id));
            if (firstBlock[name] === undefined)
                firstBlock[name] = block;
            else if (firstBlock[name] !== block)
                out[name] = true;
        }
        return out;
    }

    function monitorByName(name) {
        const all = Hyprland.monitors.values;
        for (let i = 0; i < all.length; i++) {
            if (all[i].name === name)
                return all[i];
        }
        return null;
    }

    function windowsIn(wsId) {
        return (WindowTracker.byWorkspace ?? ({}))[wsId] ?? [];
    }

    // Slot number for the bar. Gets a superscript block marker only while a
    // monitor is showing more than one block, so the common case stays clean.
    function labelOn(name, id) {
        const base = SlotLayout.labelFor(id);
        return mixed[name] ? base + SlotLayout.superscript(SlotLayout.blockOf(id) + 1) : base;
    }

    // Windows parked on special workspaces (the Super+S scratchpad, pypr
    // terminal), newest focus first.
    function scratchWindows() {
        const map = WindowTracker.byWorkspace ?? ({});
        const out = [];
        for (const id in map) {
            if (Number(id) < 0)
                out.push(...map[id]);
        }
        out.sort((a, b) => a.focusRank - b.focusRank);
        return out;
    }

    // Show / hide the special workspace a window lives on. Hyprland runs a
    // Lua config here, so hyprctl dispatch takes a Lua expression, not the
    // old "togglespecialworkspace magic" string.
    function toggleScratch(win) {
        const name = win && win.wsName ? win.wsName.replace(/^special:/, "") : "magic";
        Hyprland.dispatch("hl.dsp.workspace.toggle_special(" + JSON.stringify(name) + ")");
    }

    // Wheel down = next workspace on that monitor, up = previous, like the
    // Super+scroll bind. Stops at the ends; activating also focuses it.
    function stepOn(name, delta) {
        const list = [];
        let at = 0;
        for (const id in byId) {
            const ws = byId[id];
            if (ws.monitor?.name !== name)
                continue;
            if (ws.active)
                at = list.length;
            list.push(ws);
        }
        const next = Math.max(0, Math.min(list.length - 1, at + delta));
        if (list.length > 0 && next !== at)
            list[next].activate();
    }
}
