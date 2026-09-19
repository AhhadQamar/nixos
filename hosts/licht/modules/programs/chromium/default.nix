{
  config,
  pkgs,
  lib,
  ...
}: {
  programs.chromium = {
    enable = true;
    extensions = [
      # Unhook - Remove YouTube Recommended & Shorts
      {id = "khncfooichmfjbepaaaebmommgaepoid";}
    ];
  };
}
