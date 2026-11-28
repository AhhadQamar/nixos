{
  config,
  inputs,
  lib,
  pkgs,
  ...
}: let
  # Turns ~/.cache/wal/colors-luciole.toml into ~/.config/luciole/colors.toml by
  # filling in the accent. The accent rule is the same as Colors.qml's
  # _pickAccent() and recolor-icons: of color1..color6, the one with the highest
  # saturation * (1 - |value - 0.65|). Text on it is whichever of the palette's
  # background and foreground contrasts more (Colors.qml's onAccent).
  lucioleColors = pkgs.writers.writePython3Bin "luciole-palette" {flakeIgnore = ["E501"];} ''
    import colorsys
    import os
    import re
    import sys
    from pathlib import Path

    home = Path.home()
    cache = Path(os.environ.get("XDG_CACHE_HOME", home / ".cache")) / "wal"
    out = Path(os.environ.get("XDG_CONFIG_HOME", home / ".config")) / "luciole" / "colors.toml"


    def rgb(h):
        return [int(h[i:i + 2], 16) / 255 for i in (1, 3, 5)]


    def score(h):
        _, s, v = colorsys.rgb_to_hsv(*rgb(h))
        return s * (1 - abs(v - 0.65))


    def lum(h):
        c = [x / 12.92 if x <= 0.03928 else ((x + 0.055) / 1.055) ** 2.4 for x in rgb(h)]
        return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]


    def contrast(a, b):
        x, y = lum(a) + 0.05, lum(b) + 0.05
        return max(x, y) / min(x, y)


    try:
        template = (cache / "colors-luciole.toml").read_text()
        lines = (cache / "colors").read_text().split()
    except OSError:
        sys.exit("luciole-palette: no wal colours yet, run wal -i first")

    hexes = [x for x in lines[1:7] if re.fullmatch(r"#[0-9a-fA-F]{6}", x)]
    if not hexes:
        sys.exit("luciole-palette: no usable accent in the wal colours")
    accent = max(hexes, key=score)
    bg = re.search(r'^surface = "(#[0-9a-fA-F]{6})"', template, re.M).group(1)
    fg = re.search(r'^on_surface = "(#[0-9a-fA-F]{6})"', template, re.M).group(1)
    on_accent = bg if contrast(accent, bg) >= contrast(accent, fg) else fg

    out.parent.mkdir(parents=True, exist_ok=True)
    tmp = out.with_name(out.name + ".tmp")
    tmp.write_text(template.replace("@ACCENT@", accent).replace("@ON_ACCENT@", on_accent))
    os.replace(tmp, out)
  '';
in {
  imports = [inputs.luciole.homeModules.default];

  home.packages = [lucioleColors];

  # The module installs the package. config.toml is the declarative base;
  # changes made in Luciole's Settings go to settings.toml and win over it.
  programs.luciole = {
    enable = true;
    settings.browser.terminal_command = "kitty";
  };

  # Installing Luciole does not make it the default, so folders open in it.
  xdg.mimeApps.defaultApplications."inode/directory" = "dev.noctalia.luciole.desktop";

  # The wallpaper switcher runs luciole-palette after `wal -i`. It writes a
  # real file because Luciole watches ~/.config/luciole, and a symlink into
  # ~/.cache/wal would not trigger its live reload. Also run on every switch so
  # a fresh machine gets a palette.
  home.activation.lucioleColors = lib.hm.dag.entryAfter ["writeBoundary"] ''
    HOME="${config.home.homeDirectory}" ${lucioleColors}/bin/luciole-palette || true
  '';
}
