{
  config,
  pkgs,
  lib,
  osConfig,
  ...
}: let
  secretFile = osConfig.age.secrets.aria2-rpc-secret.path;

  # `dl <link | magnet | file.torrent | curl command>...`: add downloads from a
  # terminal, a launcher or a browser's "open with". Goes to the downloads panel
  # when the shell is running, and straight to the aria2 daemon when it is not.
  dl = pkgs.writeShellScriptBin "dl" ''
    if [ $# -eq 0 ]; then
      echo "usage: dl <link | magnet | file.torrent | curl command>..." >&2
      exit 1
    fi
    rc=0
    for a in "$@"; do
      case "$a" in
        http:*|https:*|ftp:*|sftp:*|magnet:*|file:*|/*|"~"*|curl\ *) ;;
        *) [ -e "$a" ] && a="$PWD/$a" ;;
      esac
      if ${pkgs.quickshell}/bin/qs ipc call downloads add "$a" >/dev/null 2>&1; then
        continue
      fi
      secret=$(cat ${secretFile}) || { echo "dl: can't read the aria2 secret" >&2; rc=1; continue; }
      case "$a" in
        *.torrent|*.metalink|*.meta4)
          method=aria2.addTorrent
          [ "''${a##*.}" = torrent ] || method=aria2.addMetalink
          body=$(${pkgs.coreutils}/bin/base64 -w0 "''${a#file://}" | ${pkgs.jq}/bin/jq -Rn --arg s "$secret" --arg m "$method" \
            '{jsonrpc:"2.0",id:"dl",method:$m,params:["token:"+$s,input]}') ;;
        http:*|https:*|ftp:*|sftp:*|magnet:*)
          body=$(${pkgs.jq}/bin/jq -n --arg s "$secret" --arg u "$a" \
            '{jsonrpc:"2.0",id:"dl",method:"aria2.addUri",params:["token:"+$s,[$u]]}') ;;
        *)
          echo "dl: the panel isn't running, and I can only add links and torrents without it: $a" >&2
          rc=1
          continue ;;
      esac
      printf '%s' "$body" | ${pkgs.curl}/bin/curl -sf -H 'Content-Type: application/json' -d @- http://localhost:6800/jsonrpc >/dev/null \
        || { echo "dl: aria2 isn't answering" >&2; rc=1; }
    done
    exit $rc
  '';
in {
  home.packages = [
    pkgs.aria2
    dl
  ];

  xdg.configFile."aria2/aria2.conf".source = ./config/aria2.conf;

  # Magnet links and .torrent files can be opened with the panel. Make it the
  # default once with:
  #   xdg-mime default dl.desktop x-scheme-handler/magnet application/x-bittorrent application/metalink+xml
  xdg.desktopEntries.dl = {
    name = "Add to downloads";
    exec = "${dl}/bin/dl %U";
    mimeType = [
      "x-scheme-handler/magnet"
      "application/x-bittorrent"
      "application/metalink+xml"
      "application/metalink4+xml"
    ];
    noDisplay = true;
    terminal = false;
  };

  systemd.user.services.aria2 = {
    Unit.Description = "aria2 Daemon";
    Service = {
      RuntimeDirectory = "aria2";
      RuntimeDirectoryMode = "0700";
      # ~/.local/state/aria2: the list of downloads, so a restart or a reboot
      # picks them up again where they were
      StateDirectory = "aria2";
      StateDirectoryMode = "0700";
      ExecStart = pkgs.writeShellScript "aria2-start" ''
        set -euo pipefail
        conf="$RUNTIME_DIRECTORY/aria2.conf"
        session="$STATE_DIRECTORY/session"
        umask 077
        touch "$session"
        cat ${./config/aria2.conf} > "$conf"
        printf 'rpc-secret=%s\n' \
          "$(cat ${secretFile})" >> "$conf"
        printf 'input-file=%s\nsave-session=%s\nsave-session-interval=30\n' \
          "$session" "$session" >> "$conf"
        exec ${pkgs.aria2}/bin/aria2c --conf-path="$conf"
      '';
      Restart = "on-failure";
    };
    Install.WantedBy = ["default.target"];
  };
}
