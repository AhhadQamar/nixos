{
  config,
  pkgs,
  lib,
  ...
}: {
  home.packages = with pkgs; [
    quickshell
    imagemagick
  ];

  xdg.configFile."quickshell" = {
    source = ./config;
    recursive = true;
  };

  home.activation.linkWalColorsQml = lib.hm.dag.entryAfter ["writeBoundary"] ''
    mkdir -p "$HOME/.cache/wal" "$HOME/.config/quickshell"
    # Seed with real QML, not an empty file -- Quickshell fails to load an
    # empty WalColors.qml on a fresh machine before the first `wal -i`.
    if [ ! -s "$HOME/.cache/wal/colors.qml" ]; then
      ${pkgs.coreutils}/bin/install -m 644 \
        ${./WalColors.fallback.qml} "$HOME/.cache/wal/colors.qml"
    fi
    ln -sfn "$HOME/.cache/wal/colors.qml" "$HOME/.config/quickshell/WalColors.qml"
  '';
}
