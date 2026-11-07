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
in {
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
        position = "left"; # vertical tab list, like your Firefox sidebar
        width = 35; # sidebar width in pixels (use "15%" to scale with the window)
        show = "always"; # always visible, so the page never jumps sideways
        title.alignment = "left";
        favicons.show = "always";
        pinned.shrink = false; # pinned tabs keep their full row in a vertical list
        title.format_pinned = "{audio}{index} {current_title}";
        last_close = "close"; # closing the last tab closes the window
        select_on_remove = "last-used"; # closing a tab returns to the one you used before
        mousewheel_switching = false; # scrolling over the tab bar does not switch tabs
        title.format = "{audio}{index} {current_title}"; # speaker icon on tabs playing sound
      };
      auto_save.session = true; # reopen last tabs on start
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
        start_pages = ["about:blank"];
        default_page = "about:blank";
      };
      colors.webpage.preferred_color_scheme = "dark";

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
      c.tabs.padding = {"top": 5, "bottom": 5, "left": 8, "right": 8}
      c.statusbar.padding = {"top": 3, "bottom": 3, "left": 6, "right": 6}
      c.hints.padding = {"top": 2, "bottom": 2, "left": 5, "right": 5}

      # Colours come from pywal, the same palette as the bar and Firefox.
      import json
      import os

      def load_wal():
          path = os.path.expanduser("~/.cache/wal/colors.json")
          try:
              with open(path) as f:
                  return json.load(f)
          except (OSError, ValueError):
              return None

      w = load_wal()
      if w:
          bg = w["special"]["background"]
          fg = w["special"]["foreground"]
          accent = w["colors"]["color4"]
          dim = w["colors"]["color8"]
          ok = w["colors"]["color2"]
          warn = w["colors"]["color3"]
          err = w["colors"]["color1"]

          c.colors.statusbar.normal.bg = bg
          c.colors.statusbar.normal.fg = fg
          c.colors.statusbar.insert.bg = accent
          c.colors.statusbar.insert.fg = bg
          c.colors.statusbar.command.bg = bg
          c.colors.statusbar.command.fg = fg
          c.colors.statusbar.passthrough.bg = warn
          c.colors.statusbar.passthrough.fg = bg
          c.colors.statusbar.url.fg = fg
          c.colors.statusbar.url.success.https.fg = ok
          c.colors.statusbar.url.error.fg = err
          c.colors.statusbar.url.warn.fg = warn
          c.colors.statusbar.progress.bg = accent
          c.colors.statusbar.url.hover.fg = accent
          c.colors.statusbar.caret.bg = warn
          c.colors.statusbar.caret.fg = bg
          c.colors.statusbar.private.bg = dim
          c.colors.statusbar.private.fg = fg
          c.colors.statusbar.command.private.bg = dim
          c.colors.statusbar.command.private.fg = fg

          c.colors.tabs.bar.bg = bg
          c.colors.tabs.odd.bg = bg
          c.colors.tabs.even.bg = bg
          c.colors.tabs.odd.fg = dim
          c.colors.tabs.even.fg = dim
          c.colors.tabs.selected.odd.bg = accent
          c.colors.tabs.selected.even.bg = accent
          c.colors.tabs.selected.odd.fg = bg
          c.colors.tabs.selected.even.fg = bg

          c.colors.tabs.pinned.odd.bg = bg
          c.colors.tabs.pinned.even.bg = bg
          c.colors.tabs.pinned.odd.fg = dim
          c.colors.tabs.pinned.even.fg = dim
          c.colors.tabs.pinned.selected.odd.bg = accent
          c.colors.tabs.pinned.selected.even.bg = accent
          c.colors.tabs.pinned.selected.odd.fg = bg
          c.colors.tabs.pinned.selected.even.fg = bg
          c.colors.tabs.indicator.start = accent
          c.colors.tabs.indicator.stop = ok
          c.colors.tabs.indicator.error = err

          c.colors.completion.fg = fg
          c.colors.completion.odd.bg = bg
          c.colors.completion.even.bg = bg
          c.colors.completion.category.bg = bg
          c.colors.completion.category.fg = accent
          c.colors.completion.item.selected.bg = accent
          c.colors.completion.item.selected.fg = bg
          c.colors.completion.item.selected.match.fg = bg
          c.colors.completion.match.fg = warn
          c.colors.completion.category.border.top = bg
          c.colors.completion.category.border.bottom = bg
          c.colors.completion.item.selected.border.top = accent
          c.colors.completion.item.selected.border.bottom = accent

          c.colors.hints.bg = accent
          c.colors.hints.fg = bg
          c.colors.hints.match.fg = warn

          c.colors.messages.info.bg = bg
          c.colors.messages.info.fg = fg
          c.colors.messages.warning.bg = warn
          c.colors.messages.warning.fg = bg
          c.colors.messages.error.bg = err
          c.colors.messages.error.fg = bg
          c.colors.messages.info.border = bg
          c.colors.messages.warning.border = warn
          c.colors.messages.error.border = err

          # Permission questions, downloads, key hints and the context menu.
          c.colors.prompts.bg = bg
          c.colors.prompts.fg = fg
          c.colors.prompts.selected.bg = accent
          c.colors.prompts.border = "1px solid " + accent
          c.colors.downloads.bar.bg = bg
          c.colors.downloads.start.bg = accent
          c.colors.downloads.start.fg = bg
          c.colors.downloads.stop.bg = ok
          c.colors.downloads.stop.fg = bg
          c.colors.downloads.error.bg = err
          c.colors.downloads.error.fg = bg
          c.colors.keyhint.bg = bg
          c.colors.keyhint.fg = fg
          c.colors.keyhint.suffix.fg = accent
          c.colors.contextmenu.menu.bg = bg
          c.colors.contextmenu.menu.fg = fg
          c.colors.contextmenu.selected.bg = accent
          c.colors.contextmenu.selected.fg = bg
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
