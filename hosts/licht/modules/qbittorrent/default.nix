# modules/qbittorrent/default.nix
{
  config,
  pkgs,
  lib,
  osConfig,
  ...
}: {
  home.packages = [pkgs.qbittorrent-nox];

  home.activation.seedQbittorrentConf = lib.hm.dag.entryAfter ["writeBoundary"] ''
    confDir="$HOME/.config/qBittorrent"
    mkdir -p "$confDir"
    if [ ! -e "$confDir/qBittorrent.conf" ]; then
      cp ${./config/qBittorrent.conf} "$confDir/qBittorrent.conf"
      chmod 600 "$confDir/qBittorrent.conf"
    fi
  '';

  home.activation.qbittorrentuiConfig = lib.hm.dag.entryAfter ["writeBoundary"] ''
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
      After = ["network.target"];
    };
    Service = {
      ExecStart = "${pkgs.qbittorrent-nox}/bin/qbittorrent-nox";
      Restart = "on-failure";
    };
    Install.WantedBy = ["default.target"];
  };
}
