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
      ${pkgs.coreutils}/bin/install -m 600 ${./config/qBittorrent.conf} "$confDir/qBittorrent.conf"
    fi
  '';

  # Every switch, make sure the WebUI password hash actually matches the
  # agenix secret - so there's no more "log in with the qBittorrent-generated
  # temp password, then manually change it to match" dance. If the existing
  # hash already verifies against the secret, the file is left untouched; if
  # it doesn't (fresh install, or the secret was rotated), a new PBKDF2 hash
  # is written in place and the running daemon is restarted so it takes
  # effect immediately.
  home.activation.syncQbittorrentWebuiPassword = lib.hm.dag.entryAfter ["seedQbittorrentConf"] ''
    result="$(${pkgs.python3}/bin/python3 ${./config/sync-webui-password.py} \
      ${osConfig.age.secrets.qbittorrent-webui-password.path} \
      "$HOME/.config/qBittorrent/qBittorrent.conf")"
    if [ "$result" = "changed" ]; then
      ${pkgs.systemd}/bin/systemctl --user try-restart qbittorrent-nox.service || true
    fi
  '';

  home.activation.qbittorrentuiConfig = lib.hm.dag.entryAfter ["writeBoundary"] ''
    mkdir -p "$HOME/.config/qbittorrentui"
    ${pkgs.coreutils}/bin/install -m 600 /dev/null "$HOME/.config/qbittorrentui/default.ini"
    ${pkgs.gnused}/bin/sed \
      "s|@QBT_PASSWORD@|$(cat ${osConfig.age.secrets.qbittorrent-webui-password.path})|" \
      ${./config/default.ini.tmpl} \
      > "$HOME/.config/qbittorrentui/default.ini"
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
