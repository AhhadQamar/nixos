{
  config,
  pkgs,
  lib,
  ...
}: let
  walCacheDir = "${config.home.homeDirectory}/.cache/wal";

  # Closest-match a wal hex color to one of papirus-folders' fixed preset
  # names (it only accepts names, not arbitrary hex). Distances are plain
  # RGB Euclidean — good enough for "which preset looks closest", not exact.
  nearestPapirusColor = pkgs.writeShellScript "nearest-papirus-color" ''
    #!/usr/bin/env bash
    hex="''${1#\#}"
    r=$((16#''${hex:0:2}))
    g=$((16#''${hex:2:2}))
    b=$((16#''${hex:4:2}))

    declare -A presets=(
      [black]="30 30 30"
      [blue]="26 128 196"
      [bluegrey]="96 125 139"
      [brown]="93 64 55"
      [cyan]="0 172 193"
      [green]="76 175 80"
      [grey]="158 158 158"
      [magenta]="216 27 96"
      [orange]="245 124 0"
      [red]="211 47 47"
      [teal]="0 121 107"
      [violet]="123 31 162"
      [yellow]="251 192 45"
    )

    best="grey"
    bestDist=999999
    for name in "''${!presets[@]}"; do
      read -r pr pg pb <<< "''${presets[$name]}"
      dr=$((r - pr)); dg=$((g - pg)); db=$((b - pb))
      dist=$((dr*dr + dg*dg + db*db))
      if [ "$dist" -lt "$bestDist" ]; then
        bestDist=$dist
        best=$name
      fi
    done
    echo "$best"
  '';
in {
  home.packages = with pkgs; [
    papirus-folders
  ];

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

  dconf.settings = {
    "org/gnome/desktop/interface" = {
      color-scheme = "prefer-dark";
      gtk-theme = "Adwaita-dark";
      icon-theme = "Papirus-Dark";
      cursor-theme = "Bibata-Modern-Classic";
      font-name = "Rubik 11";
    };
  };

  # Make sure the imported files exist before the first `wal -i` run,
  # otherwise GTK apps will refuse to load gtk.css at all.
  home.activation.ensureWalGtkCss = lib.hm.dag.entryAfter ["writeBoundary"] ''
    mkdir -p "${walCacheDir}"
    [ -f "${walCacheDir}/colors-gtk3.css" ] || touch "${walCacheDir}/colors-gtk3.css"
    [ -f "${walCacheDir}/colors-gtk4.css" ] || touch "${walCacheDir}/colors-gtk4.css"
  '';

  # Recolor Papirus folder icons to whichever preset is closest to wal's
  # accent color (color4), so icons roughly follow your wallpaper too.
  home.activation.recolorFolders = lib.hm.dag.entryAfter ["writeBoundary"] ''
    iconsDir="${config.home.homeDirectory}/.local/share/icons"
    mkdir -p "$iconsDir"
    for variant in Papirus Papirus-Dark; do
      if [ ! -e "$iconsDir/$variant" ] || [ ! -w "$iconsDir/$variant" ]; then
        rm -rf "$iconsDir/$variant"
        cp -r --no-preserve=mode ${pkgs.papirus-icon-theme}/share/icons/$variant "$iconsDir/$variant"
      fi
    done
    if [ -s "${walCacheDir}/colors" ]; then
      accent=$(${pkgs.gawk}/bin/awk 'NR==5' "${walCacheDir}/colors")
      nearest=$(${nearestPapirusColor} "$accent")
      PATH="${pkgs.gawk}/bin:${pkgs.coreutils}/bin:$PATH" HOME="${config.home.homeDirectory}" ${pkgs.papirus-folders}/bin/papirus-folders -C "$nearest" --theme Papirus || true
      ${pkgs.gtk3}/bin/gtk-update-icon-cache -f "$iconsDir/Papirus" 2>/dev/null || true
      ${pkgs.gtk3}/bin/gtk-update-icon-cache -f "$iconsDir/Papirus-Dark" 2>/dev/null || true
    fi
  '';
}
