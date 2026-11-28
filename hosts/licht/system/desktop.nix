{
  inputs,
  pkgs,
  ...
}: {
  programs.hyprland.enable = true;
  security.pam.services.qs-lock = {};

  programs.dconf.enable = true;
  security.pam.services.login.enableGnomeKeyring = true;

  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    pulse.enable = true;
  };

  xdg.portal = {
    enable = true;
    extraPortals = [
      pkgs.xdg-desktop-portal-hyprland
      pkgs.xdg-desktop-portal-gtk
      # Luciole as the Open/Save dialog. Registering it is not enough; the
      # FileChooser preference below selects it.
      inputs.luciole.packages.${pkgs.stdenv.hostPlatform.system}.default
    ];
    # Hyprland sessions read hyprland-portals.conf, which takes precedence over
    # the generic portals.conf (config.common), so the preference goes here.
    # default and Secret restate what the Hyprland and keyring packages already
    # chose, because a configuration file is used as a whole.
    config.hyprland = {
      default = ["hyprland" "gtk"];
      "org.freedesktop.impl.portal.FileChooser" = ["luciole" "gtk"];
      "org.freedesktop.impl.portal.Secret" = ["gnome-keyring"];
    };
  };

  services.gnome.gnome-keyring.enable = true;
  security.polkit.enable = true;
  services.udisks2.enable = true;
  services.gvfs.enable = true;
  services.upower.enable = true;

  environment.sessionVariables = {
    LIBVA_DRIVER_NAME = "iHD";
    NIXOS_OZONE_WL = "1";
  };

  fonts.packages = with pkgs; [
    nerd-fonts.jetbrains-mono
    noto-fonts
    noto-fonts-color-emoji
    rubik
  ];
}
