{
  config,
  pkgs,
  lib,
  ...
}: {
  home.packages = with pkgs; [
    hypridle
    hyprsunset
    hyprshot
    cliphist
    wl-clipboard
    wl-clip-persist
    brightnessctl
    pywalfox-native
    awww
    dbus # for dbus-update-activation-environment in autostart.lua
  ];

  xdg.configFile."hypr" = {
    source = ./config;
    recursive = true;
  };

  # See autostart.lua for why this exists -- short version: your polkit
  # prompt already working suggests something (most likely Hyprland's own
  # native systemd integration on this nixpkgs build) is already getting
  # graphical-session.target active without this. This is added as a
  # cheap, idempotent safety net, not because anything is confirmed broken.
  systemd.user.targets.hyprland-session = {
    Unit = {
      Description = "Hyprland compositor session";
      BindsTo = ["graphical-session.target"];
      Wants = ["graphical-session-pre.target"];
      After = ["graphical-session-pre.target"];
    };
  };

  home.activation.ensureCurrentWallpaper = lib.hm.dag.entryAfter ["writeBoundary"] ''
    WALLPAPER_LINK="$HOME/Pictures/Wallpapers/.current_wallpaper"
    if [ ! -e "$WALLPAPER_LINK" ]; then
      DEFAULT_WALLPAPER="$HOME/Pictures/Wallpapers/moon.jpg"
      if [ -f "$DEFAULT_WALLPAPER" ]; then
        ln -sf "$DEFAULT_WALLPAPER" "$WALLPAPER_LINK"
      fi
    fi
  '';
  home.activation.ensureWalHyprFiles = lib.hm.dag.entryAfter ["writeBoundary"] ''
    mkdir -p "$HOME/.cache/wal"
    [ -f "$HOME/.cache/wal/colors-hyprland.lua" ] || touch "$HOME/.cache/wal/colors-hyprland.lua"
    [ -f "$HOME/.cache/wal/colors-hyprlock.conf" ] || touch "$HOME/.cache/wal/colors-hyprlock.conf"
  '';

  systemd.user.services.polkit-gnome-authentication-agent-1 = {
    Unit = {
      Description = "polkit-gnome-authentication-agent-1";
      Wants = ["graphical-session.target"];
      After = ["graphical-session.target"];
    };
    Install = {
      WantedBy = ["graphical-session.target"];
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
