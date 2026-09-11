{ config, pkgs, ... }:
{
  programs.kitty.enable = true;

  xdg.configFile."kitty" = {
    source = ./config;
    recursive = true;
  };
}
