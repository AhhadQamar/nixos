{
  config,
  pkgs,
  ...
}: {
  home.username = "licht";
  home.homeDirectory = "/home/licht";
  home.stateVersion = "26.05";

  home.packages = with pkgs; [
    firefox
    brave
    nautilus
    python3
    nh
    vesktop
    playerctl
    obsidian
    bombsquad
    libnotify
    github-copilot-cli
  ];

  services.udiskie = {
    enable = true;
    automount = true;
    notify = true;
  };

  programs.yazi = {
    enable = true;
    enableZshIntegration = false;
  };

  xdg.userDirs = {
    enable = true;
    createDirectories = true;
    desktop = "${config.home.homeDirectory}/Desktop";
    documents = "${config.home.homeDirectory}/Documents";
    download = "${config.home.homeDirectory}/Downloads";
    music = "${config.home.homeDirectory}/Music";
    pictures = "${config.home.homeDirectory}/Pictures";
    videos = "${config.home.homeDirectory}/Videos";
    publicShare = "${config.home.homeDirectory}/Public";
    templates = "${config.home.homeDirectory}/Templates";
  };

  programs.home-manager.enable = true;

  imports = [
    ./modules/git
    ./modules/zsh
    ./modules/hypr
    ./modules/pyprland
    ./modules/kitty
    ./modules/nvim
    ./modules/vscodium
    ./modules/quickshell
    ./modules/pywal
    ./modules/theme
    ./modules/cava
    ./modules/aria2
    ./modules/yt-dlp
    ./modules/fetch
  ];
}
