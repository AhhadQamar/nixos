// Fuzzy matching for the search boxes: the typed letters have to appear in
// order, but not next to each other ("wlp" finds "wallpaper"). Runs of
// letters, word starts and a plain substring all score higher.

pragma Singleton
import QtQuick
import Quickshell

Singleton {
    // Score of one lower-cased word against lower-cased text; -1 = no match
    function one(t, q) {
        let ti = 0;
        let score = 0;
        let run = 0;
        let first = -1;
        for (let qi = 0; qi < q.length; qi++) {
            const at = t.indexOf(q.charAt(qi), ti);
            if (at < 0)
                return -1;
            if (first < 0)
                first = at;
            run = (at === ti && qi > 0) ? run + 1 : 0;
            score += 1 + run * 2;
            if (at === 0 || " /-_.".indexOf(t.charAt(at - 1)) >= 0)
                score += 3;
            ti = at + 1;
        }
        if (t.indexOf(q) >= 0)
            score += 10;
        return Math.max(0.001, score - Math.min(first, 20) * 0.1 - t.length * 0.01);
    }

    // Every word of `query` has to match `text`. An empty query matches
    // everything with score 0; -1 = no match, higher is better.
    function score(text, query) {
        const t = String(text).toLowerCase();
        const words = String(query).toLowerCase().split(/\s+/).filter(w => w !== "");
        if (words.length === 0)
            return 0;
        let total = 0;
        for (let i = 0; i < words.length; i++) {
            const s = one(t, words[i]);
            if (s < 0)
                return -1;
            total += s;
        }
        return total;
    }
}
