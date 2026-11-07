{
  config,
  pkgs,
  lib,
  ...
}: let
  # DRM video (Netflix, Prime Video, Spotify web) needs Google's proprietary
  # Widevine blob. Off by default; set to true and rebuild to get it.
  # (allowUnfree is already on in system/nix.nix.)
  enableDRM = false;

  # Dark mode for every website (Qt's "force dark"): pages that are light get
  # darkened, and pages that already have a dark theme are left alone.
  # It can mangle some images; set to false to see sites as their authors made
  # them. Changing it needs a full restart of qutebrowser.
  forceDarkPages = true;

  # true:  reopen last session's tabs on start (the start page then only shows
  #        in NEW tabs). false: every launch begins with the start page.
  restoreTabs = false;

  # --- New-tab page -----------------------------------------------------------
  homeDir = config.home.homeDirectory;

  # One tile per quickmark, so the Nix list stays the single source of truth.
  tiles = lib.concatStringsSep "\n" (lib.mapAttrsToList (name: url: ''
    <a class="tile" href="${url}"><span class="dot">${lib.toUpper (builtins.substring 0 1 name)}</span><span>${name}</span></a>'')
  config.programs.qutebrowser.quickmarks);

  # Colours come from pywal's own ~/.cache/wal/colors.css, so the page follows
  # the wallpaper with no extra work. Fallbacks apply if that file is missing.
  startPageHtml = ''
    <!doctype html>
    <html lang="en">
    <head>
    <meta charset="utf-8">
    <title>New tab</title>
    <link rel="icon" href="data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 32 32'%3E%3Ccircle cx='16' cy='16' r='9' fill='none' stroke='%23b8b8b8' stroke-width='3'/%3E%3C/svg%3E">
    <link rel="stylesheet" href="file://${homeDir}/.cache/wal/colors.css">
    <style>
      html, body { height: 100%; margin: 0; }
      body {
        background: var(--background, #141414);
        color: var(--foreground, #dddddd);
        font-family: "JetBrainsMono Nerd Font", monospace;
        display: flex; flex-direction: column; align-items: center; justify-content: center;
      }
      #time { font-size: 72px; font-weight: 600; letter-spacing: -2px; line-height: 1.1; }
      #date { opacity: 0.55; margin: 4px 0 32px; }
      form { width: min(560px, 86vw); margin-bottom: 28px; }
      input {
        width: 100%; box-sizing: border-box; padding: 14px 22px;
        border-radius: 999px; border: 1px solid var(--color8, #444444);
        background: transparent; color: inherit; font: inherit; font-size: 16px; outline: none;
        background: color-mix(in srgb, var(--foreground, #dddddd) 5%, transparent);
      }
      input:focus { border-color: var(--color4, #8899cc); }
      input::placeholder { color: inherit; opacity: 0.45; }
      .tiles { display: flex; flex-wrap: wrap; justify-content: center; max-width: 640px; margin-bottom: 26px; }
      .tile {
        display: flex; flex-direction: column; align-items: center;
        width: 96px; padding: 14px 6px; margin: 4px 6px; border-radius: 14px;
        color: inherit; text-decoration: none; font-size: 12px;
      }
      .tile { border: 1px solid transparent; }
      .tile:hover {
        background: rgba(255, 255, 255, 0.07);
        background: color-mix(in srgb, var(--foreground, #dddddd) 8%, transparent);
        border-color: color-mix(in srgb, var(--color4, #8899cc) 45%, transparent);
      }
      .dot {
        width: 44px; height: 44px; border-radius: 50%; margin-bottom: 8px;
        display: flex; align-items: center; justify-content: center;
        font-size: 18px; font-weight: 700;
        background: var(--color4, #667799); color: var(--background, #111111);
      }
      .hint { opacity: 0.4; font-size: 12px; }
    </style>
    </head>
    <body>
    <div id="time"></div>
    <div id="date"></div>
    <form action="https://www.google.com/search" method="get">
      <input name="q" type="text" placeholder="Search Google" autocomplete="off">
    </form>
    <div class="tiles">
    ${tiles}
    </div>
    <div class="hint">gi search here &middot; o open &middot; f follow a link &middot; b tabs</div>
    <script>
      function tick() {
        var d = new Date();
        document.getElementById("time").textContent =
          d.toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" });
        document.getElementById("date").textContent =
          d.toLocaleDateString([], { weekday: "long", day: "numeric", month: "long" });
      }
      tick();
      setInterval(tick, 10000);
    </script>
    </body>
    </html>
  '';

  # Lives in the Nix store, so the path always exists and is always readable.
  startPageFile = pkgs.writeText "startpage.html" startPageHtml;
  startPage = "file://${startPageFile}";

  # --- Userscripts (qutebrowser's built-in Greasemonkey support) -------------

  # Stand-in for "Absolute Enable Right Click & Copy": sites that block
  # selecting, copying or the context menu stop being able to.
  selectionScript = pkgs.writeText "enable-selection-and-copy.user.js" ''
    // ==UserScript==
    // @name         Enable text selection and copy
    // @match        *://*/*
    // @run-at       document-start
    // @grant        none
    // ==/UserScript==
    (function () {
      "use strict";
      function editable(el) {
        return !!el && !!el.closest &&
          !!el.closest("input, textarea, [contenteditable]:not([contenteditable=false])");
      }
      ["contextmenu", "selectstart", "copy"].forEach(function (name) {
        window.addEventListener(name, function (e) {
          if (!editable(document.activeElement) && !editable(e.target)) {
            e.stopImmediatePropagation();
          }
        }, true);
      });
      function addStyle() {
        var s = document.createElement("style");
        s.textContent = "*{-webkit-user-select:text!important;user-select:text!important}";
        (document.head || document.documentElement).appendChild(s);
      }
      if (document.documentElement) {
        addStyle();
      } else {
        new MutationObserver(function (_, obs) {
          if (document.documentElement) { obs.disconnect(); addStyle(); }
        }).observe(document, { childList: true });
      }
    })();
  '';

  # Stand-in for "Unhook": no home-page feed, no Shorts, no recommendation
  # sidebar, no end cards. Search and subscriptions still work.
  # YouTube renames elements now and then; if a rule stops working, delete it.
  unhookScript = pkgs.writeText "youtube-unhook.user.js" ''
    // ==UserScript==
    // @name         YouTube unhook
    // @match        *://www.youtube.com/*
    // @match        *://m.youtube.com/*
    // @run-at       document-start
    // @grant        none
    // ==/UserScript==
    (function () {
      "use strict";
      var css = [
        "ytd-browse[page-subtype=home] ytd-rich-grid-renderer",
        "ytd-reel-shelf-renderer",
        "ytd-rich-shelf-renderer[is-shorts]",
        "ytd-guide-entry-renderer:has(a[title=Shorts])",
        "ytd-mini-guide-entry-renderer[aria-label=Shorts]",
        "#related",
        "ytd-watch-next-secondary-results-renderer",
        ".ytp-endscreen-content",
        ".ytp-ce-element"
      ].join(",") + "{display:none!important}";
      function addStyle() {
        var s = document.createElement("style");
        s.textContent = css;
        (document.head || document.documentElement).appendChild(s);
      }
      if (document.documentElement) {
        addStyle();
      } else {
        new MutationObserver(function (_, obs) {
          if (document.documentElement) { obs.disconnect(); addStyle(); }
        }).observe(document, { childList: true });
      }
      // A Shorts link opens as a normal video page instead.
      function leaveShorts() {
        var m = location.pathname.match(/^\/shorts\/([\w-]+)/);
        if (m) location.replace("/watch?v=" + m[1]);
      }
      leaveShorts();
      window.addEventListener("yt-navigate-finish", leaveShorts);
    })();
  '';

  # Re-reads the pywal palette in a running qutebrowser. Does nothing when
  # qutebrowser is closed, so it never opens a stray window.
  walReload = pkgs.writeShellScript "qute-wal-reload" ''
    for sock in "$XDG_RUNTIME_DIR"/qutebrowser/ipc-*; do
      if [ -S "$sock" ]; then
        exec ${config.programs.qutebrowser.package}/bin/qutebrowser ':config-source'
      fi
    done
  '';

  # Fills logins from `pass` (set up in ../pass). The script is pass-fill.sh next
  # to this file; here it gets the tools it needs on its PATH.
  passTools = [
    config.programs.password-store.package
    pkgs.gnupg
    pkgs.fuzzel
    pkgs.coreutils
    pkgs.findutils
    pkgs.gnused
  ];
  passFill = pkgs.writeShellScript "qute-pass-fill" ''
    export PATH=${lib.makeBinPath passTools}:$PATH
    ${builtins.readFile ./pass-fill.sh}
  '';
in {
  # Makes `spawn --userscript qute-pass-fill ...` work by name.
  xdg.dataFile."qutebrowser/userscripts/qute-pass-fill".source = passFill;

  programs.qutebrowser = {
    enable = true;
    package = pkgs.qutebrowser.override {enableWideVine = enableDRM;};

    # Everything is declared here; nothing set through :set is kept.
    loadAutoconfig = false;

    greasemonkey = [selectionScript unhookScript];

    searchEngines = {
      DEFAULT = "https://www.google.com/search?q={}";
      ddg = "https://duckduckgo.com/?q={}"; # o ddg <terms> when you want a private search
      yt = "https://www.youtube.com/results?search_query={}";
      gh = "https://github.com/search?q={}";
      w = "https://en.wikipedia.org/w/index.php?search={}";
      np = "https://search.nixos.org/packages?query={}";
      no = "https://search.nixos.org/options?query={}";
      nw = "https://wiki.nixos.org/index.php?search={}";
      hm = "https://home-manager-options.extranix.com/?query={}";
    };

    quickmarks = {
      nixpkgs = "https://github.com/NixOS/nixpkgs";
      home-manager = "https://github.com/nix-community/home-manager";
      nixwiki = "https://wiki.nixos.org";
      github = "https://github.com";
      youtube = "https://www.youtube.com";
    };

    aliases = {
      rl = "config-source"; # :rl reloads this config
      ff = "spawn firefox {url}"; # :ff opens the page in Firefox
      dl = "spawn dl {url}"; # :dl sends the URL to your aria2 panel
      mpv = "spawn mpv {url}"; # :mpv plays the page in mpv
    };

    settings = {
      # --- Privacy (same intent as the Firefox policies) ---
      content = {
        autoplay = false; # no autoplaying audio/video
        geolocation = false; # sites cannot ask for location
        notifications.enabled = false; # ...or for notifications
        dns_prefetch = false; # no prefetching of links you have not clicked
        register_protocol_handler = false; # sites cannot claim mailto: etc.
        pdfjs = true; # open PDFs in the browser instead of downloading them
        javascript.clipboard = "access"; # makes "Copy" buttons on sites work
        cookies.accept = "no-3rdparty";
        webrtc_ip_handling_policy = "default-public-interface-only"; # no local IP leak
        headers = {
          do_not_track = true;
          referer = "same-domain"; # other sites only see "you came from the internet"
        };

        # Built-in ad/tracker blocking: Adblock engine plus hosts lists.
        # Run :adblock-update once after the first start.
        blocking = {
          enabled = true;
          method = "both";
          adblock.lists = [
            "https://easylist.to/easylist/easylist.txt"
            "https://easylist.to/easylist/easyprivacy.txt"
            "https://raw.githubusercontent.com/uBlockOrigin/uAssets/master/filters/filters.txt"
            "https://raw.githubusercontent.com/uBlockOrigin/uAssets/master/filters/privacy.txt"
            "https://raw.githubusercontent.com/uBlockOrigin/uAssets/master/filters/badware.txt"
            "https://raw.githubusercontent.com/uBlockOrigin/uAssets/master/filters/unbreak.txt"
            "https://raw.githubusercontent.com/uBlockOrigin/uAssets/master/filters/quick-fixes.txt"
            "https://raw.githubusercontent.com/uBlockOrigin/uAssets/master/filters/annoyances-cookies.txt"
            "https://raw.githubusercontent.com/uBlockOrigin/uAssets/master/filters/annoyances-others.txt"
          ];
          # qutebrowser's built-in hosts lists are long dead; use a maintained one.
          hosts.lists = ["https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts"];
        };
      };

      # --- Things a normal browser is expected to do ---
      input.insert_mode.auto_load = true; # focused text box on page load: start typing at once

      # File upload dialogs open yazi in kitty instead of a Qt dialog.
      # Enter picks the file, q cancels.
      fileselect = {
        handler = "external";
        single_file.command = ["kitty" "yazi" "--chooser-file={}"];
        multiple_files.command = ["kitty" "yazi" "--chooser-file={}"];
        folder.command = ["kitty" "yazi" "--cwd-file={}"];
      };
      # Ctrl-e in a text box edits its content in Neovim.
      editor.command = ["kitty" "nvim" "{file}" "-c" "normal {line}G{column0}l"];

      # --- Tabs and windows ---
      tabs = {
        new_position = {
          related = "next"; # new tabs open next to the current one, as in Firefox
          unrelated = "next";
        };
        position = "left"; # vertical strip, like your collapsed Firefox sidebar
        width = 52; # strip width in pixels; raise it if icons look cramped
        show = "always"; # always visible, so the page never jumps sideways
        favicons.show = "always";
        favicons.scale = 1.3; # slightly larger site icons
        indicator.width = 0; # no loading bar; the status bar already shows progress
        pinned.shrink = false;
        title.format_pinned = ""; # icon only
        last_close = "close"; # closing the last tab closes the window
        select_on_remove = "last-used"; # closing a tab returns to the one you used before
        mousewheel_switching = false; # scrolling over the tab bar does not switch tabs
        title.format = ""; # icon only. Hover a tab for its title, or press b for the list
      };
      auto_save.session = restoreTabs; # see restoreTabs at the top
      scrolling = {
        smooth = true;
        bar = "when-searching"; # no scrollbar except while searching a page
      };

      downloads = {
        location.directory = "${config.home.homeDirectory}/Downloads";
        location.prompt = false; # save straight to Downloads
        position = "bottom";
        remove_finished = 8000; # finished downloads disappear after 8 seconds
      };
      url = {
        start_pages = [startPage]; # new tabs and :home open the page defined above
        default_page = startPage;
      };
      colors.webpage.preferred_color_scheme = "dark";
      colors.webpage.darkmode.enabled = forceDarkPages;

      # Status bar: the tab count and history arrows are redundant with the sidebar.
      statusbar.widgets = ["keypress" "search_match" "url" "scroll" "progress"];

      # The command/completion popup: fits its entries, no scrollbar, quick on big histories.
      completion = {
        shrink = true;
        height = "35%";
        scrollbar.width = 0;
        web_history.max_items = 2000;
      };

      # Link hints: capital letters, no border, rounded.
      hints = {
        uppercase = true;
        border = "none";
        radius = 4;
      };
      keyhint = {
        delay = 250; # the "which key" popup appears after a short pause
        radius = 4;
      };
      prompt.radius = 4;

      # Same font as the bar, for tabs, status bar, prompts and completion.
      fonts = {
        default_family = "JetBrainsMono Nerd Font";
        default_size = "11pt";
      };
    };

    # Tridactyl-style keys, so muscle memory carries over from Firefox.
    keyBindings = {
      normal = {
        "J" = "tab-prev"; # qutebrowser's default is the other way round
        "K" = "tab-next";
        "d" = "tab-close";
        "<Ctrl-t>" = "open -t"; # new tab with the start page
        "b" = "cmd-set-text -s :tab-select";
        "<Ctrl-d>" = "scroll-page 0 0.5";
        "<Ctrl-u>" = "scroll-page 0 -0.5";

        # , = act on this page      ; = act on a link (labels appear, type one)
        ",m" = "spawn mpv {url}"; # play in mpv (YouTube etc. via yt-dlp)
        ";m" = "hint links spawn mpv {hint-url}";
        ",a" = "spawn dl {url}"; # add to your aria2 downloads panel
        ";a" = "hint links spawn dl {hint-url}";
        ",f" = "spawn firefox {url}"; # escape hatch: open this page in Firefox
        ";f" = "hint links spawn firefox {hint-url}";

        # Quick toggles for a broken page (temporary, per session).
        ",j" = "config-cycle -p -t content.javascript.enabled ;; reload";
        ",b" = "config-cycle -p -t content.blocking.enabled ;; reload";
        ",r" = "config-source";

        # Logins from pass. Click (or gi) into the username box first.
        ",p" = "spawn --userscript qute-pass-fill both"; # username, Tab, password
        ",u" = "spawn --userscript qute-pass-fill user"; # username only
        ",P" = "spawn --userscript qute-pass-fill pass"; # password only
        ",o" = "spawn --userscript qute-pass-fill otp"; # 2FA code
      };
      command = {
        "<Ctrl-j>" = "completion-item-focus next";
        "<Ctrl-k>" = "completion-item-focus prev";
      };
    };

    extraConfig = ''
      # Global Privacy Control, as in Firefox. A dict, so it lives here rather
      # than in `settings`, where Home Manager would split it into keys.
      c.content.headers.custom = {"Sec-GPC": "1"}

      # Roomier tab rows and status bar.
      c.tabs.padding = {"top": 12, "bottom": 12, "left": 16, "right": 16}
      c.tabs.indicator.padding = {"top": 0, "bottom": 0, "left": 0, "right": 0}
      c.statusbar.padding = {"top": 3, "bottom": 3, "left": 6, "right": 6}
      c.hints.padding = {"top": 2, "bottom": 2, "left": 5, "right": 5}

      # Colours come from pywal (the same palette as the bar and Firefox), but
      # are adjusted so text stays readable whatever the wallpaper is. If pywal
      # has not run yet, a built-in dark palette is used instead.
      import colorsys
      import json
      import os

      FALLBACK = {
          "special": {"background": "#16161a", "foreground": "#d8d8de"},
          "colors": {
              "color1": "#e06c75", "color2": "#98c379", "color3": "#e5c07b",
              "color4": "#7aa2f7", "color5": "#bb9af7", "color6": "#56b6c2",
              "color8": "#5c6370",
          },
      }

      def load_wal():
          path = os.path.expanduser("~/.cache/wal/colors.json")
          try:
              with open(path) as f:
                  return json.load(f)
          except (OSError, ValueError):
              return None

      def rgb(h):
          h = h.lstrip("#")
          return [int(h[i:i + 2], 16) for i in (0, 2, 4)]

      def mix(c1, c2, t):
          a, b = rgb(c1), rgb(c2)
          return "#%02x%02x%02x" % tuple(round(x + (y - x) * t) for x, y in zip(a, b))

      def lum(h):
          def ch(v):
              v /= 255
              return v / 12.92 if v <= 0.03928 else ((v + 0.055) / 1.055) ** 2.4
          r, g, b = [ch(v) for v in rgb(h)]
          return 0.2126 * r + 0.7152 * g + 0.0722 * b

      def contrast(a, b):
          hi, lo = max(lum(a), lum(b)), min(lum(a), lum(b))
          return (hi + 0.05) / (lo + 0.05)

      def sat(h):
          return colorsys.rgb_to_hsv(*[v / 255 for v in rgb(h)])[1]

      def readable(c, against, ratio):
          # Nudge colour c toward white or black until it reads clearly on `against`.
          target = "#ffffff" if lum(against) < 0.4 else "#000000"
          for i in range(11):
              cand = mix(c, target, i / 10)
              if contrast(cand, against) >= ratio:
                  return cand
          return target

      w = load_wal() or FALLBACK
      cols = w["colors"]
      bg = w["special"]["background"]
      fg = w["special"]["foreground"]
      dark = lum(bg) < 0.4

      def on(c):
          # Text colour for use on top of c: the theme's bg or fg if either is
          # clearly readable, otherwise plain black or white.
          for cand in (bg, fg):
              if contrast(cand, c) >= 4.5:
                  return cand
          return "#000000" if contrast("#000000", c) >= contrast("#ffffff", c) else "#ffffff"

      # Surfaces, from the darkest frame to raised panels.
      strip = mix(bg, "#000000", 0.3 if dark else 0.06)  # tab strip, status bar
      panel = mix(bg, fg, 0.06)  # popups, prompts, menus
      row_a = mix(bg, fg, 0.03)  # completion rows, alternating
      row_b = mix(bg, fg, 0.08)

      # Accent: pywal's color4, or the most colourful of color1-6 if that one is grey.
      base = cols["color4"]
      if sat(base) < 0.25:
          base = max((cols["color%d" % i] for i in range(1, 7)), key=sat)
      accent = readable(base, bg, 3.0)
      on_accent = on(accent)
      dim = readable(mix(fg, bg, 0.45), strip, 3.5)  # secondary text
      ok = readable(cols["color2"], strip, 4.5)
      warn = readable(cols["color3"], strip, 4.5)
      err = readable(cols["color1"], strip, 4.5)
      sel = mix(strip, accent, 0.25)  # selected tab

      # Status bar and command line
      c.colors.statusbar.normal.bg = strip
      c.colors.statusbar.normal.fg = fg
      c.colors.statusbar.insert.bg = accent
      c.colors.statusbar.insert.fg = on_accent
      c.colors.statusbar.command.bg = strip
      c.colors.statusbar.command.fg = fg
      c.colors.statusbar.passthrough.bg = warn
      c.colors.statusbar.passthrough.fg = on(warn)
      c.colors.statusbar.caret.bg = warn
      c.colors.statusbar.caret.fg = on(warn)
      c.colors.statusbar.private.bg = mix(strip, accent, 0.4)
      c.colors.statusbar.private.fg = fg
      c.colors.statusbar.command.private.bg = mix(strip, accent, 0.4)
      c.colors.statusbar.command.private.fg = fg
      c.colors.statusbar.url.fg = fg
      c.colors.statusbar.url.hover.fg = accent
      c.colors.statusbar.url.success.http.fg = fg
      c.colors.statusbar.url.success.https.fg = ok
      c.colors.statusbar.url.error.fg = err
      c.colors.statusbar.url.warn.fg = warn
      c.colors.statusbar.progress.bg = accent

      # Tab strip
      c.colors.tabs.bar.bg = strip
      c.colors.tabs.odd.bg = strip
      c.colors.tabs.even.bg = strip
      c.colors.tabs.odd.fg = dim
      c.colors.tabs.even.fg = dim
      c.colors.tabs.selected.odd.bg = sel
      c.colors.tabs.selected.even.bg = sel
      c.colors.tabs.selected.odd.fg = fg
      c.colors.tabs.selected.even.fg = fg
      c.colors.tabs.pinned.odd.bg = strip
      c.colors.tabs.pinned.even.bg = strip
      c.colors.tabs.pinned.odd.fg = dim
      c.colors.tabs.pinned.even.fg = dim
      c.colors.tabs.pinned.selected.odd.bg = sel
      c.colors.tabs.pinned.selected.even.bg = sel
      c.colors.tabs.pinned.selected.odd.fg = fg
      c.colors.tabs.pinned.selected.even.fg = fg
      c.colors.tabs.indicator.start = accent
      c.colors.tabs.indicator.stop = ok
      c.colors.tabs.indicator.error = err

      # Completion popup (: and o)
      c.colors.completion.fg = fg
      c.colors.completion.odd.bg = row_a
      c.colors.completion.even.bg = row_b
      c.colors.completion.category.bg = strip
      c.colors.completion.category.fg = accent
      c.colors.completion.category.border.top = strip
      c.colors.completion.category.border.bottom = strip
      c.colors.completion.item.selected.bg = accent
      c.colors.completion.item.selected.fg = on_accent
      c.colors.completion.item.selected.border.top = accent
      c.colors.completion.item.selected.border.bottom = accent
      c.colors.completion.item.selected.match.fg = on_accent
      c.colors.completion.match.fg = accent

      # Link hints
      c.colors.hints.bg = accent
      c.colors.hints.fg = on_accent
      c.colors.hints.match.fg = mix(on_accent, accent, 0.55)

      # Messages
      c.colors.messages.info.bg = panel
      c.colors.messages.info.fg = fg
      c.colors.messages.info.border = panel
      c.colors.messages.warning.bg = warn
      c.colors.messages.warning.fg = on(warn)
      c.colors.messages.warning.border = warn
      c.colors.messages.error.bg = err
      c.colors.messages.error.fg = on(err)
      c.colors.messages.error.border = err

      # Permission prompts, downloads, key hints, context menu
      c.colors.prompts.bg = panel
      c.colors.prompts.fg = fg
      c.colors.prompts.border = "1px solid " + accent
      c.colors.prompts.selected.bg = accent
      c.colors.downloads.bar.bg = strip
      c.colors.downloads.start.bg = accent
      c.colors.downloads.start.fg = on_accent
      c.colors.downloads.stop.bg = ok
      c.colors.downloads.stop.fg = on(ok)
      c.colors.downloads.error.bg = err
      c.colors.downloads.error.fg = on(err)
      c.colors.keyhint.bg = panel
      c.colors.keyhint.fg = fg
      c.colors.keyhint.suffix.fg = accent
      c.colors.contextmenu.menu.bg = panel
      c.colors.contextmenu.menu.fg = fg
      c.colors.contextmenu.selected.bg = accent
      c.colors.contextmenu.selected.fg = on_accent
    '';
  };

  # Follow the wallpaper: when `wal -i` rewrites the palette, tell a running
  # qutebrowser to re-read it, like Pywalfox does for Firefox.
  systemd.user.paths.qute-wal = {
    Unit.Description = "Watch the pywal palette for qutebrowser";
    Path.PathChanged = "%h/.cache/wal/colors.json";
    Install.WantedBy = ["default.target"];
  };
  systemd.user.services.qute-wal = {
    Unit.Description = "Reload qutebrowser colours";
    Service = {
      Type = "oneshot";
      ExecStart = "${walReload}";
    };
  };
}
