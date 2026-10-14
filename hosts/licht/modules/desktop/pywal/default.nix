{
  config,
  pkgs,
  lib,
  ...
}: {
  home.packages = with pkgs; [
    pywal
  ];

  xdg.configFile."wal/templates" = {
    source = ./templates;
    recursive = true;
  };
}
