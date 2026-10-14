// A tiny calculator for the launcher: + - * / % ^ and parentheses. It is a
// real parser (no eval), so whatever is typed can never run as code.

pragma Singleton
import QtQuick
import Quickshell

Singleton {
    // Value of a plain calculation like "2*(3+4)^2/5", or NaN when the text
    // is not one (letters, no operator, unbalanced brackets, divide by zero...).
    function evaluate(text) {
        const s = String(text).replace(/^\s*=/, "").replace(/\u00d7/g, "*").replace(/\u00f7/g, "/");
        const toks = [];
        let i = 0;
        while (i < s.length) {
            const c = s.charAt(i);
            if (c === " ") {
                i++;
            } else if ((c >= "0" && c <= "9") || c === ".") {
                let j = i;
                while (j < s.length && ((s.charAt(j) >= "0" && s.charAt(j) <= "9") || s.charAt(j) === "."))
                    j++;
                const n = Number(s.slice(i, j));
                if (isNaN(n))
                    return NaN;
                toks.push({
                    "n": n
                });
                i = j;
            } else if ("+-*/%^()".indexOf(c) >= 0) {
                toks.push({
                    "o": c
                });
                i++;
            } else {
                return NaN;
            }
        }
        if (toks.length === 0)
            return NaN;

        let p = 0;
        let binary = 0;
        let bad = false;
        const peek = () => p < toks.length ? toks[p].o : undefined;

        function atom() {
            const t = toks[p];
            if (!t) {
                bad = true;
                return 0;
            }
            if (t.n !== undefined) {
                p++;
                return t.n;
            }
            if (t.o === "(") {
                p++;
                const v = expr();
                if (peek() !== ")") {
                    bad = true;
                    return 0;
                }
                p++;
                return v;
            }
            bad = true;
            return 0;
        }
        function power() {
            const base = atom();
            if (peek() === "^") {
                p++;
                binary++;
                return Math.pow(base, unary());
            }
            return base;
        }
        function unary() {
            if (peek() === "-") {
                p++;
                return -unary();
            }
            if (peek() === "+") {
                p++;
                return unary();
            }
            return power();
        }
        function term() {
            let v = unary();
            while (!bad && (peek() === "*" || peek() === "/" || peek() === "%")) {
                const op = toks[p].o;
                p++;
                binary++;
                const r = unary();
                v = op === "*" ? v * r : (op === "/" ? v / r : v % r);
            }
            return v;
        }
        function expr() {
            let v = term();
            while (!bad && (peek() === "+" || peek() === "-")) {
                const op = toks[p].o;
                p++;
                binary++;
                const r = term();
                v = op === "+" ? v + r : v - r;
            }
            return v;
        }

        const result = expr();
        if (bad || p !== toks.length || binary === 0 || !isFinite(result))
            return NaN;
        return result;
    }

    // 3.0000000000000004 -> "3", 1/3 -> "0.333333333333"
    function format(v) {
        return String(Number(v.toPrecision(12)));
    }
}
