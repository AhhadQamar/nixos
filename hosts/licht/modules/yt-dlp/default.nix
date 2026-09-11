{ pkgs, ... }:

{
  home.packages = with pkgs; [
    yt-dlp
    ffmpeg
  ];

  xdg.configFile."yt-dlp/config".source = ./config;

}
