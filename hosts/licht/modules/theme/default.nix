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

  # Mirrors Colors.qml's _pickAccent(): among color1..color6, pick
  # whichever is most saturated AND closest to mid-brightness (value
  # ~0.65) — so icon accent matches the workspace-dot accent exactly,
  # instead of a fixed color line that may not be the "accent" one.
  pywalAccentPick = pkgs.writeShellScript "pywal-accent-pick" ''
    #!/usr/bin/env bash
    colors_file="$1"
    best=""
    bestScore="-1"
    for i in 1 2 3 4 5 6; do
      hex=$(${pkgs.gawk}/bin/awk -v n=$((i+1)) 'NR==n' "$colors_file")
      hex="''${hex#\#}"
      r=$((16#''${hex:0:2})); g=$((16#''${hex:2:2})); b=$((16#''${hex:4:2}))

      max=$r; [ $g -gt $max ] && max=$g; [ $b -gt $max ] && max=$b
      min=$r; [ $g -lt $min ] && min=$g; [ $b -lt $min ] && min=$b
      value=$max
      if [ $max -eq 0 ]; then sat=0; else sat=$(( (max - min) * 1000 / max )); fi

      distFrom65=$(( value > 166 ? value - 166 : 166 - value ))
      distFrom65Scaled=$(( distFrom65 * 1000 / 255 ))
      score=$(( sat * (1000 - distFrom65Scaled) / 1000 ))

      if [ "$score" -gt "$bestScore" ]; then
        bestScore=$score
        best="#$hex"
      fi
    done
    echo "$best"
  '';
in {
  home.packages = with pkgs; [
    papirus-folders
    (writeShellScriptBin "recolor-icons" ''
      colors_file="$HOME/.cache/wal/colors"
      [ -s "$colors_file" ] || { echo "No wal colors found — run 'wal -i <wallpaper>' first."; exit 1; }

      accent=$(${pywalAccentPick} "$colors_file")
      nearest=$(${nearestPapirusColor} "$accent")
      echo "Accent: $accent -> nearest preset: $nearest"

      iconsDir="$HOME/.local/share/icons"
      ${papirus-folders}/bin/papirus-folders -C "$nearest" --theme Papirus
      ${gtk3}/bin/gtk-update-icon-cache -f "$iconsDir/Papirus" 2>/dev/null || true
      ${gtk3}/bin/gtk-update-icon-cache -f "$iconsDir/Papirus-Dark" 2>/dev/null || true
      pkill nautilus 2>/dev/null || true
      echo "Done."
    '')
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

  # Recolor Papirus folder icons to match the same accent Colors.qml
  # computes for the workspace dot, so icons stay visually consistent
  # with the rest of the rice, not just "some wal color".
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
      accent=$(${pywalAccentPick} "${walCacheDir}/colors")
      nearest=$(${nearestPapirusColor} "$accent")
      PATH="${pkgs.gawk}/bin:${pkgs.coreutils}/bin:$PATH" HOME="${config.home.homeDirectory}" ${pkgs.papirus-folders}/bin/papirus-folders -C "$nearest" --theme Papirus || true
      ${pkgs.gtk3}/bin/gtk-update-icon-cache -f "$iconsDir/Papirus" 2>/dev/null || true
      ${pkgs.gtk3}/bin/gtk-update-icon-cache -f "$iconsDir/Papirus-Dark" 2>/dev/null || true
    fi
  '';
}
