{
  config,
  pkgs,
  lib,
  ...
}: let
  walCacheDir = "${config.home.homeDirectory}/.cache/wal";

  # Recolors the Papirus folder icons to match the wallpaper accent.
  # The logic is in recolor-icons.sh next to this file; shellcheck runs on it
  # at build time, so a mistake there fails the rebuild instead of the desktop.
  recolorIcons = pkgs.writeShellApplication {
    name = "recolor-icons";
    runtimeInputs = with pkgs; [coreutils findutils gawk gnugrep gnused gtk3 papirus-folders];
    text = ''
      export PAPIRUS_SRC="${pkgs.papirus-icon-theme}/share/icons"
      ${builtins.readFile ./recolor-icons.sh}
    '';
  };
in {
  # `recolor-icons` is the command to run by hand after `wal -i`.
  home.packages = [recolorIcons pkgs.papirus-folders];

  # Dark base theme (structure/chrome), colors get overridden by pywal below
  gtk = {
    enable = true;

    theme = {
      name = "Adwaita-dark";
      package = pkgs.gnome-themes-extra;
    };

    iconTheme = {
      name = "Papirus-Dark";
      package = pkgs.papirus-icon-theme;
    };

    cursorTheme = {
      name = "Bibata-Modern-Classic";
      package = pkgs.bibata-cursors;
      size = 24;
    };

    font = {
      name = "Rubik";
      package = pkgs.rubik;
      size = 11;
    };

    gtk3 = {
      extraConfig = {
        gtk-application-prefer-dark-theme = 1;
      };
      # Pulls in whatever `wal -i` last generated
      extraCss = ''
        @import url("file://${walCacheDir}/colors-gtk3.css");
      '';
    };

    gtk4 = {
      extraConfig = {
        gtk-application-prefer-dark-theme = 1;
      };
      extraCss = ''
        @import url("file://${walCacheDir}/colors-gtk4.css");
      '';
    };
  };

  qt = {
    enable = true;
    platformTheme.name = "gtk";
    style.name = "adwaita-dark";
  };

  # Values come from the gtk block above so a name or size is only written once.
  dconf.settings = {
    "org/gnome/desktop/interface" = {
      color-scheme = "prefer-dark";
      gtk-theme = config.gtk.theme.name;
      icon-theme = config.gtk.iconTheme.name;
      cursor-theme = config.gtk.cursorTheme.name;
      cursor-size = config.gtk.cursorTheme.size;
      font-name = "${config.gtk.font.name} ${toString config.gtk.font.size}";
    };
  };

  # Make sure the imported files exist before the first `wal -i` run,
  # otherwise GTK apps will refuse to load gtk.css at all.
  home.activation.ensureWalGtkCss = lib.hm.dag.entryAfter ["writeBoundary"] ''
    mkdir -p "${walCacheDir}"
    [ -f "${walCacheDir}/colors-gtk3.css" ] || touch "${walCacheDir}/colors-gtk3.css"
    [ -f "${walCacheDir}/colors-gtk4.css" ] || touch "${walCacheDir}/colors-gtk4.css"
  '';

  # Keep the Papirus folder colour in sync with the wallpaper on every switch.
  # Silent, and does nothing unless the accent colour or the Papirus package
  # changed. After picking a new wallpaper, run `recolor-icons` by hand.
  home.activation.recolorFolders = lib.hm.dag.entryAfter ["writeBoundary"] ''
    HOME="${config.home.homeDirectory}" ${recolorIcons}/bin/recolor-icons --quiet || true
  '';
}
