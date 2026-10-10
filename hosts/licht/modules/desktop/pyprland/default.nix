{
  config,
  pkgs,
  lib,
  ...
}: {
  home.packages = with pkgs; [
    pyprland
  ];

  xdg.configFile."pypr" = {
    source = ./config;
    recursive = true;
  };
}
