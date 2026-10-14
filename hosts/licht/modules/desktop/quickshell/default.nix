{
  config,
  pkgs,
  lib,
  ...
}: let
  # Set to true to edit the QML in place: ~/.config/quickshell then links to the
  # config folder in this repo, and Quickshell reloads on every save with no
  # rebuild (the same idea as the mpv module). Needs one rebuild to switch on
  # or off. The WalColors.qml link lands inside the repo folder; it is in
  # .gitignore.
  liveReload = false;
  configDir = "${config.home.homeDirectory}/nixos/hosts/licht/modules/desktop/quickshell/config";
in {
  home.packages = with pkgs; [
    quickshell
    imagemagick
    sound-theme-freedesktop
    grim
  ];

  xdg.configFile."quickshell" =
    if liveReload
    then {source = config.lib.file.mkOutOfStoreSymlink configDir;}
    else {
      source = ./config;
      recursive = true;
    };

  # The normal setup makes ~/.config/quickshell a real folder of links; going
  # live needs it to be one link instead. Clear the old links first (only
  # links: anything else in there is left alone and home-manager will say so).
  home.activation.prepareQuickshellLiveReload = lib.mkIf liveReload (lib.hm.dag.entryBefore ["checkLinkTargets"] ''
    d="$HOME/.config/quickshell"
    if [ -d "$d" ] && [ ! -L "$d" ]; then
      find "$d" -maxdepth 1 -type l -delete
      rmdir "$d" 2>/dev/null || true
    fi
  '');

  # After linkGeneration, not just writeBoundary: before it, the mkdir below
  # would make ~/.config/quickshell a real folder and, with liveReload on,
  # home-manager could not replace it with its link.
  home.activation.linkWalColorsQml = lib.hm.dag.entryAfter ["linkGeneration"] ''
    mkdir -p "$HOME/.cache/wal"
    # Seed with real QML, not an empty file -- Quickshell fails to load an
    # empty WalColors.qml on a fresh machine before the first `wal -i`.
    if [ ! -s "$HOME/.cache/wal/colors.qml" ]; then
      ${pkgs.coreutils}/bin/install -m 644 \
        ${./WalColors.fallback.qml} "$HOME/.cache/wal/colors.qml"
    fi
    ln -sfn "$HOME/.cache/wal/colors.qml" "$HOME/.config/quickshell/WalColors.qml"
  '';
}
