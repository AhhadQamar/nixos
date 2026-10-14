// Workspace and monitor data for the bar (Workspaces.qml, WorkspacePill.qml).
//
// Everything here is read from WindowTracker.snapshot, the one picture of
// Hyprland the bar takes (see WindowTracker.qml), so no two answers can come
// from different moments. Quickshell's own model is used for exactly two
// things it is good at: which workspaces want attention (`urgentIds`), and
// switching to one (`activate`).
//
// Workspace ids come in blocks of SlotLayout.slotsPerMonitor per monitor
// (eDP-1 1..10, DP-1 11..20, ...), pinned by hypr/config/modules/workspaces.lua.
// Special workspaces (the Super+S scratchpad, ...) have negative ids and are
// named; the bar knows them by their short name ("magic").
//
// Most things here are properties, not functions. A property is worked out
// once per change and shared by every bar and every pill; a function called
// from each pill's binding would redo the same work once per pill. The ones
// that are functions only look something up.

pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Hyprland

Singleton {
    id: root

    readonly property var snap: WindowTracker.snapshot
    // monitor name -> { name, active, special, focused } (see WindowTracker)
    readonly property var monitors: snap.monitors
    // Short names of the special workspaces that exist, sorted by name
    readonly property var specialNames: snap.specials
    // One shared empty list: `?? []` would make a new one every time, and a
    // new list is a "change" to everything bound to it
    readonly property var none: []

    // Where the last `places` was kept, so an unchanged entry can be reused.
    // Only its field is changed, never the property, so it notifies nobody.
    readonly property var _memo: ({
            places: ({})
        })

    // id -> { id, monitor, active, focused }, for every regular workspace.
    //   active:  the workspace on screen on its monitor. It stays so while a
    //            special workspace is open over it.
    //   focused: active on the monitor you are working on, and no special
    //            workspace open over it (then the focus is on that one).
    // An entry is the same object as last time while it says the same thing,
    // so a pill only re-evaluates when ITS workspace changed.
    readonly property var places: {
        const all = snap.workspaces;
        const fresh = {};
        for (const id in all) {
            const w = all[id];
            if (w.id < 1)
                continue;
            const m = monitors[w.monitor];
            const active = m !== undefined && m.active === w.id;
            fresh[id] = {
                "id": w.id,
                "monitor": w.monitor,
                "active": active,
                "focused": active && m.focused && m.special === ""
            };
        }
        const kept = WindowTracker.settle(_memo.places, fresh);
        _memo.places = kept;
        return kept;
    }

    // id -> true for the workspaces that want attention (Quickshell tracks it)
    readonly property var urgentIds: {
        const out = {};
        const all = Hyprland.workspaces.values;
        for (let i = 0; i < all.length; i++) {
            if (all[i].urgent ?? false)
                out[all[i].id] = true;
        }
        return out;
    }

    // How many pills a monitor's row needs: the highest id in use, rounded up
    // to a whole block. It is a plain number on purpose. A Repeater given a
    // number only adds or removes pills at the end when it changes, while a
    // Repeater given a fresh array rebuilds every pill (losing hover and
    // animations) each time the array is re-made.
    readonly property int idCount: {
        let top = 0;
        for (const id in places)
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
        for (const id in places) {
            const p = places[id];
            if (!p.monitor)
                continue;
            if (out[p.monitor] === undefined)
                out[p.monitor] = {
                    shown: 0,
                    rest: 0,
                    urgent: false
                };
            const s = out[p.monitor];
            const urgent = urgentIds[id] === true && !p.active;
            if (p.active || urgent || windowsIn(p.id).length > 0) {
                s.shown++;
                if (!p.active)
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
        for (const id in places) {
            const name = places[id].monitor;
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

    function windowsIn(wsId) {
        return snap.windows[wsId] ?? none;
    }

    // Windows on the special workspace called `name` (short name)
    function specialWindows(name) {
        const all = snap.workspaces;
        for (const id in all) {
            if (all[id].name === "special:" + name)
                return snap.windows[id] ?? none;
        }
        return none;
    }

    // Short name of the special workspace open over `monitorName`, or ""
    function openSpecial(monitorName) {
        return monitors[monitorName]?.special ?? "";
    }

    // Slot number for the bar. Gets a superscript block marker only while a
    // monitor is showing more than one block, so the common case stays clean.
    function labelOn(name, id) {
        const base = SlotLayout.labelFor(id);
        return mixed[name] ? base + SlotLayout.superscript(SlotLayout.blockOf(id) + 1) : base;
    }

    // Show / hide a special workspace by its short name. Hyprland runs a Lua
    // config here, so hyprctl dispatch takes a Lua expression, not the old
    // "togglespecialworkspace magic" string.
    function toggleSpecial(name) {
        Hyprland.dispatch("hl.dsp.workspace.toggle_special(" + JSON.stringify(name) + ")");
    }

    // Go to a regular workspace (this also focuses its monitor)
    function activate(id) {
        const all = Hyprland.workspaces.values;
        for (let i = 0; i < all.length; i++) {
            if (all[i].id === id) {
                all[i].activate();
                return;
            }
        }
    }

    // Wheel down = next workspace on that monitor, up = previous, like the
    // Super+scroll bind. Stops at the ends; activating also focuses it.
    function stepOn(name, delta) {
        const list = [];
        let at = 0;
        for (const id in places) {
            const p = places[id];
            if (p.monitor !== name)
                continue;
            if (p.active)
                at = list.length;
            list.push(p.id);
        }
        const next = Math.max(0, Math.min(list.length - 1, at + delta));
        if (list.length > 0 && next !== at)
            activate(list[next]);
    }
}
