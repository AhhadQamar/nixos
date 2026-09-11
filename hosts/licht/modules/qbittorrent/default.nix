# modules/qbittorrent/default.nix
{
  config,
  pkgs,
  lib,
  osConfig,
  ...
}:
{
  home.packages = [ pkgs.qbittorrent-nox ];

  # qBittorrent.conf's password is already a PBKDF2 hash — fine as-is
  xdg.configFile."qBittorrent/qBittorrent.conf".source = ./config/qBittorrent.conf;

  home.activation.qbittorrentuiConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    mkdir -p "$HOME/.config/qbittorrentui"
    ${pkgs.gnused}/bin/sed \
      "s|@QBT_PASSWORD@|$(cat ${osConfig.age.secrets.qbittorrent-webui-password.path})|" \
      ${./config/default.ini.tmpl} \
      > "$HOME/.config/qbittorrentui/default.ini"
    chmod 600 "$HOME/.config/qbittorrentui/default.ini"
  '';

  systemd.user.services.qbittorrent-nox = {
    Unit = {
      Description = "qBittorrent-nox daemon";
      After = [ "network.target" ];
    };
    Service = {
      ExecStart = "${pkgs.qbittorrent-nox}/bin/qbittorrent-nox";
      Restart = "on-failure";
    };
    Install.WantedBy = [ "default.target" ];
  };
}
