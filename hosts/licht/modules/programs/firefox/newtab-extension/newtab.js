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

// Any CSS colour as [r, g, b] between 0 and 1, read back from the browser so every
// format the theme uses (names, hex, rgb, arrays turned into rgb) is understood.
function rgbOf(css) {
  const probe = document.createElement("i");
  probe.style.color = css;
  document.body.appendChild(probe);
  const m = getComputedStyle(probe).color.match(/[\d.]+/g);
  probe.remove();
  return m ? m.slice(0, 3).map((v) => Number(v) / 255) : null;
}

// Saturation and brightness the way the Quickshell and Hyprland accent pick sees them.
function satVal([r, g, b]) {
  const max = Math.max(r, g, b), min = Math.min(r, g, b);
  return { s: max === 0 ? 0 : (max - min) / max, v: max };
}

// The base hue of the colour scheme: the hue of the accent colour. A grey accent has
// no hue, so then the page keeps its default (indigo) and stays colourful anyway.
function palette() {
  const rgb = rgbOf(getComputedStyle(document.documentElement).getPropertyValue("--accent").trim() || "#7aa2f7");
  if (!rgb) return;
  const [r, g, b] = rgb;
  const max = Math.max(r, g, b), min = Math.min(r, g, b), d = max - min;
  const l = (max + min) / 2;
  const s = d === 0 ? 0 : d / (1 - Math.abs(2 * l - 1));
  let h = 0;
  if (d) {
    h = max === r ? ((g - b) / d) % 6 : max === g ? (b - r) / d + 2 : (r - g) / d + 4;
    h = (h * 60 + 360) % 360;
  }
  document.documentElement.style.setProperty("--h", s > 0.2 ? Math.round(h) : 255);
}

// When the usual accent keys hold a grey, look at every colour in the theme and take the
// most saturated one nearest mid brightness: the same rule as the window border in Hyprland
// and the active workspace in Quickshell, so the page follows the wallpaper like they do.
function pickAccent(colors) {
  let best = null, bestScore = 0;
  for (const value of Object.values(colors)) {
    const css = themeColour(value);
    const rgb = css && rgbOf(css);
    if (!rgb) continue;
    const { s, v } = satVal(rgb);
    const score = s * (1 - Math.abs(v - 0.65));
    // Dark colours (backgrounds, shadows) are not accents, however saturated they are.
    if (s > 0.25 && v > 0.35 && score > bestScore) { best = css; bestScore = score; }
  }
  return best;
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
  // Only what the theme itself supplied counts here, not the fallback colour from newtab.css.
  const supplied = root.getPropertyValue("--accent").trim();
  const chosen = supplied && rgbOf(supplied);
  if (!chosen || satVal(chosen).s <= 0.25) {
    const picked = pickAccent(colors);
    if (picked) root.setProperty("--accent", picked);
  }
  palette();
}

if (typeof browser !== "undefined" && browser.theme) {
  browser.theme.getCurrent().then(applyTheme).catch(palette);
  browser.theme.onUpdated.addListener(({ theme }) => applyTheme(theme));
} else {
  palette(); // the copy used for new windows has no Firefox theme to read
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
  nowEl.style.setProperty("--i", f * (TICKS - 1));
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
