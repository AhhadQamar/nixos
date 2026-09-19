{
  config,
  pkgs,
  lib,
  osConfig,
  ...
}: {
  home.packages = [
    pkgs.aria2
    # aria2p ships with TUI support (asciimatics + pyperclip) on by
    # default in nixpkgs -- no need for an explicit [tui] override.
    pkgs.python3Packages.aria2p
  ];

  xdg.configFile."aria2/aria2.conf".source = ./config/aria2.conf;
  xdg.configFile."aria2p/config.toml".source = ./config/config.toml;

  systemd.user.services.aria2 = {
    Unit.Description = "aria2 Daemon";
    Service = {
      # RPC secret used to be passed as --rpc-secret="$(cat ...)", which
      # puts it in /proc/<pid>/cmdline -- world-readable for as long as the
      # daemon runs. Writing it into a 0600 file inside a 0700 runtime
      # directory (created and cleaned up by systemd) keeps it off argv.
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
