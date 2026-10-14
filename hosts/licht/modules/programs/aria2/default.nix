{
  config,
  pkgs,
  lib,
  osConfig,
  ...
}: {
  home.packages = [
    pkgs.aria2
  ];

  xdg.configFile."aria2/aria2.conf".source = ./config/aria2.conf;

  systemd.user.services.aria2 = {
    Unit.Description = "aria2 Daemon";
    Service = {
      RuntimeDirectory = "aria2";
      RuntimeDirectoryMode = "0700";
      ExecStart = pkgs.writeShellScript "aria2-start" ''
        set -euo pipefail
        conf="$RUNTIME_DIRECTORY/aria2.conf"
        umask 077
        cat ${./config/aria2.conf} > "$conf"
        printf 'rpc-secret=%s\n' \
          "$(cat ${osConfig.age.secrets.aria2-rpc-secret.path})" >> "$conf"
        exec ${pkgs.aria2}/bin/aria2c --conf-path="$conf"
      '';
      Restart = "on-failure";
    };
    Install.WantedBy = ["default.target"];
  };
}
