{
  pkgs,
  inputs,
  ...
}: let
  pixie =
    inputs.pixie-sddm.packages.${pkgs.stdenv.hostPlatform.system}.pixie-sddm.override
    {
      fontFamily = "Rubik";
      autoColor = true;
      background = /var/lib/wallpaper/current;
    };
in {
  services.displayManager.sddm = {
    enable = true;
    package = pkgs.kdePackages.sddm;

    theme = "pixie";
    wayland.enable = true;

    extraPackages = with pkgs.kdePackages; [
      qtsvg
      qtdeclarative
      qt5compat
    ];

    settings = {
      Theme = {
        CursorTheme = "Bibata-Modern-Classic";
        CursorSize = 24;
      };
    };
  };

  services.displayManager.defaultSession = "hyprland-uwsm";

  environment.systemPackages = [
    pixie
    pkgs.bibata-cursors
  ];

  security.pam.services.sddm.enableGnomeKeyring = true;
}
