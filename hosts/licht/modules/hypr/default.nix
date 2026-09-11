{
  config,
  pkgs,
  lib,
  ...
}:
{
  home.packages = with pkgs; [
    hyprlock
    hypridle
    hyprsunset
    hyprshot
    cliphist
    wl-clipboard
    wl-clip-persist
    brightnessctl
    pywalfox-native
    awww
  ];

  xdg.configFile."hypr" = {
    source = ./config;
    recursive = true;
  };

  home.activation.ensureCurrentWallpaper = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    WALLPAPER_LINK="$HOME/Pictures/Wallpapers/.current_wallpaper"
    if [ ! -e "$WALLPAPER_LINK" ]; then
      DEFAULT_WALLPAPER="$HOME/Pictures/Wallpapers/moon.jpg"
      if [ -f "$DEFAULT_WALLPAPER" ]; then
        ln -sf "$DEFAULT_WALLPAPER" "$WALLPAPER_LINK"
      fi
    fi
  '';

  home.activation.ensureWalHyprFiles = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    mkdir -p "$HOME/.cache/wal"
    [ -f "$HOME/.cache/wal/colors-hyprland.lua" ] || touch "$HOME/.cache/wal/colors-hyprland.lua"
    [ -f "$HOME/.cache/wal/colors-hyprlock.conf" ] || touch "$HOME/.cache/wal/colors-hyprlock.conf"
  '';

  systemd.user.services.polkit-gnome-authentication-agent-1 = {
    Unit = {
      Description = "polkit-gnome-authentication-agent-1";
      Wants = [ "graphical-session.target" ];
      After = [ "graphical-session.target" ];
    };
    Install = {
      WantedBy = [ "graphical-session.target" ];
    };
    Service = {
      Type = "simple";
      ExecStart = "${pkgs.polkit_gnome}/libexec/polkit-gnome-authentication-agent-1";
      Restart = "on-failure";
      RestartSec = 1;
      TimeoutStopSec = 10;
    };
  };
}
