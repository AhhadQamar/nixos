// Licht new tab: colours, clock, day ruler and search. No network requests are made
// until you submit a search.

// Colours come from the Firefox theme, which Pywalfox sets from the wallpaper, and
// follow it when it changes. Each colour tries a few theme keys in order; a key the
// theme does not have is skipped, and the fallbacks in newtab.css apply if none match.
function themeColour(value) {
  if (!value) return null;
  if (Array.isArray(value)) {
    return value.length === 4
      ? `rgba(${value[0]}, ${value[1]}, ${value[2]}, ${value[3]})`
      : `rgb(${value[0]}, ${value[1]}, ${value[2]})`;
  }
  return String(value);
}

function applyTheme(theme) {
  const colors = (theme && theme.colors) || {};
  const root = document.documentElement.style;
  const set = (name, keys) => {
    for (const key of keys) {
      const c = themeColour(colors[key]);
      if (c) { root.setProperty(name, c); return; }
    }
    root.removeProperty(name); // no match: the fallback from newtab.css stays
  };
  set("--bg", ["ntp_background", "frame", "toolbar"]);
  set("--fg", ["ntp_text", "toolbar_text", "tab_background_text", "bookmark_text"]);
  set("--accent", ["tab_line", "icons_attention", "tab_selected", "toolbar_field_highlight"]);
  set("--surface", ["toolbar_field", "toolbar", "popup"]);
}

if (typeof browser !== "undefined" && browser.theme) {
  browser.theme.getCurrent().then(applyTheme).catch(() => {});
  browser.theme.onUpdated.addListener(({ theme }) => applyTheme(theme));
}

const timeEl = document.getElementById("time");
const dateEl = document.getElementById("date");
const ruler = document.getElementById("ruler");
const nowEl = document.getElementById("now");
const input = document.getElementById("q");
const TICKS = 97; // 24 hours at 15 minutes, both ends included

for (let i = 0; i < TICKS; i++) {
  const t = document.createElement("div");
  t.className = "tick" + (i % 4 === 0 ? " hour" : "");
  t.style.setProperty("--i", i);
  ruler.appendChild(t);
}
const ticks = [...ruler.children];

function fraction(d) {
  return (d.getHours() * 60 + d.getMinutes()) / (24 * 60);
}

function paint(first) {
  const d = new Date();
  const hh = String(d.getHours()).padStart(2, "0");
  const mm = String(d.getMinutes()).padStart(2, "0");
  timeEl.innerHTML = hh + '<span class="colon">:</span>' + mm;
  dateEl.textContent = d.toLocaleDateString("en-GB", { weekday: "long", day: "numeric", month: "long", year: "numeric" });

  const f = fraction(d);
  nowEl.style.left = (f * 100) + "%";
  const lit = Math.floor(f * (TICKS - 1));
  ticks.forEach((t, i) => {
    const past = i <= lit;
    t.classList.toggle("past", past);
    if (first) t.classList.toggle("sweep", past);
  });
}
paint(true);
setInterval(() => paint(false), 20000);

// An address goes straight there; anything else is a Google search.
document.getElementById("search").addEventListener("submit", (e) => {
  const v = input.value.trim();
  if (!v) { e.preventDefault(); return; }
  if (/^https?:\/\//i.test(v) || (!/\s/.test(v) && /^[\w-]+(\.[\w-]+)+(:\d+)?(\/\S*)?$/.test(v))) {
    e.preventDefault();
    location.href = /^https?:\/\//i.test(v) ? v : "https://" + v;
  }
});

// Two keys of its own for this page: / focuses the search box, Escape leaves it.
addEventListener("keydown", (e) => {
  if (e.key === "/" && document.activeElement !== input) { e.preventDefault(); input.focus(); }
  else if (e.key === "Escape") { input.blur(); }
});
