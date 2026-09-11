{
  config,
  pkgs,
  lib,
  osConfig,
  ...
}: {
  home.packages = [pkgs.aria2];

  xdg.configFile."aria2/aria2.conf".source = ./config/aria2.conf;
  xdg.configFile."aria2p/config.toml".source = ./config/config.toml;

  systemd.user.services.aria2 = {
    Unit.Description = "aria2 Daemon";
    Service = {
      ExecStart = pkgs.writeShellScript "aria2-start" ''
        exec ${pkgs.aria2}/bin/aria2c \
          --conf-path="$HOME/.config/aria2/aria2.conf" \
          --rpc-secret="$(cat ${osConfig.age.secrets.aria2-rpc-secret.path})"
      '';
      Restart = "on-failure";
    };
    Install.WantedBy = ["default.target"];
  };
}
