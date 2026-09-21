{
  config,
  pkgs,
  ...
}: {
  programs.mpv = {
    enable = true;
    scripts = with pkgs.mpvScripts; [uosc];
  };

  xdg.configFile."mpv".source =
    config.lib.file.mkOutOfStoreSymlink
    "${config.home.homeDirectory}/nixos/hosts/licht/modules/mpv/config";
}
