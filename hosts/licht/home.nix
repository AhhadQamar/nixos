{
  config,
  pkgs,
  ...
}: {
  home.username = "licht";
  home.homeDirectory = "/home/licht";
  home.stateVersion = "26.05";

  home.packages = with pkgs; [
    nautilus
    python3
    nh
    vesktop
    playerctl
    bombsquad
    github-copilot-cli
    bluetui
  ];

  services.udiskie = {
    enable = true;
    automount = true;
    notify = true;
    tray = "auto";
    settings = {
      device_config = [
        {
          is_systeminternal = true;
          ignore = true;
        }
      ];
    };
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
    ./modules/desktop
    ./modules/shell
    ./modules/programs
  ];
}
