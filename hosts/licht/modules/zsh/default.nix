{ config, pkgs, ... }:

{
  home.packages = with pkgs; [
    git # needed for zinit's self-bootstrap clone
    eza
    bat
    fzf
    ripgrep
    zoxide
    btop
    yazi
    trash-cli
    mpv
    python3Packages.edge-tts
    unzip
  ];

  programs.zsh = {
    enable = true;
    initContent = builtins.readFile ./config/.zshrc;
  };

  programs.starship = {
    enable = true;
    enableZshIntegration = false;
    settings = builtins.fromTOML (builtins.readFile ./config/starship.toml);
  };
}
