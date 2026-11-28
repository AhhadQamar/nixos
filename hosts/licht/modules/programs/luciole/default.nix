{
  config,
  inputs,
  lib,
  ...
}: let
  walColors = "${config.home.homeDirectory}/.cache/wal/colors-luciole.toml";
  luciolePalette = "${config.xdg.configHome}/luciole/colors.toml";
in {
  imports = [inputs.luciole.homeModules.default];

  # The module installs the package. config.toml is the declarative base;
  # changes made in Luciole's Settings go to settings.toml and win over it.
  programs.luciole = {
    enable = true;
    settings.browser.terminal_command = "kitty";
  };

  # Installing Luciole does not make it the default, so folders open in it.
  xdg.mimeApps.defaultApplications."inode/directory" = "dev.noctalia.luciole.desktop";

  # `wal -i` writes the palette to ~/.cache/wal/colors-luciole.toml (template in
  # desktop/pywal/templates). Luciole watches ~/.config/luciole/colors.toml, and
  # a symlink into ~/.cache/wal would not trigger its live reload, so the
  # wallpaper switcher copies the file. This seeds it once for a fresh machine.
  home.activation.seedLucioleColors = lib.hm.dag.entryAfter ["writeBoundary"] ''
    if [ -f "${walColors}" ] && [ ! -e "${luciolePalette}" ]; then
      mkdir -p "$(dirname "${luciolePalette}")"
      cp "${walColors}" "${luciolePalette}"
    fi
  '';
}
