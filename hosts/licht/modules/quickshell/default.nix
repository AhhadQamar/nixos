{
  config,
  pkgs,
  ...
}: {
  home.packages = with pkgs; [
    quickshell
  ];

  xdg.configFile."quickshell" = {
    source = ./config;
    recursive = true;
  };
}
