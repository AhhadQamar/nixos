{
  config,
  lib,
  pkgs,
  ...
}: let
  vault = "Documents/Vault"; # relative to $HOME, which is what home.file wants
  repo = "${config.home.homeDirectory}/nixos/hosts/licht/modules/programs/obsidian";
in {
  home.packages = [pkgs.obsidian];

  # 1. My own theme: a link to the file in the repo, so edits show up
  #    in Obsidian with no rebuild (same idea as the mpv module).
  home.file."${vault}/.obsidian/snippets/vault.css".source =
    config.lib.file.mkOutOfStoreSymlink "${repo}/config/vault.css";

  # 2. The wallpaper colours: wal writes ~/.cache/wal/obsidian-pywal.css,
  #    this links it into the vault.
  home.activation.linkObsidianPywal = lib.hm.dag.entryAfter ["linkGeneration"] ''
    mkdir -p "$HOME/.cache/wal"
    [ -e "$HOME/.cache/wal/obsidian-pywal.css" ] || touch "$HOME/.cache/wal/obsidian-pywal.css"
    ln -sfn "$HOME/.cache/wal/obsidian-pywal.css" \
      "$HOME/${vault}/.obsidian/snippets/obsidian-pywal.css"
  '';
}
