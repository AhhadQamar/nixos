{
  config,
  pkgs,
  lib,
  ...
}: {
  home.packages = with pkgs; [
    quickshell
  ];

  xdg.configFile."quickshell" = {
    source = ./config;
    recursive = true;
  };

  home.activation.linkWalColorsQml = lib.hm.dag.entryAfter ["linkGeneration"] ''
    mkdir -p "$HOME/.cache/wal"
    [ -f "$HOME/.cache/wal/colors.qml" ] || touch "$HOME/.cache/wal/colors.qml"
    ln -sf "$HOME/.cache/wal/colors.qml" "$HOME/.config/quickshell/WalColors.qml"
  '';
}
