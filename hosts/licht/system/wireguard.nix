{
  config,
  pkgs,
  ...
}: {
  environment.systemPackages = [pkgs.wireguard-tools];
  age.secrets.wg-licht.file = ../../../secrets/wg-licht.age;

  # Lets the Quickshell network popup start and stop the tunnel without a
  # password prompt (plain `systemctl start/stop`, no sudo). Only this one unit,
  # only for wheel.
  security.polkit.extraConfig = ''
    polkit.addRule(function(action, subject) {
      if (action.id == "org.freedesktop.systemd1.manage-units" &&
          action.lookup("unit") == "wg-quick-wg0.service" &&
          subject.isInGroup("wheel")) {
        return polkit.Result.YES;
      }
    });
  '';

  networking.wg-quick.interfaces.wg0 = {
    autostart = false;
    address = ["10.8.0.2/24"];
    dns = ["10.8.0.1"];
    privateKeyFile = config.age.secrets.wg-licht.path;
    peers = [
      {
        publicKey = "1F4nVlWDxZxPPTd2EkR7ryJW0LzjNDz1EneFQcY1Fio="; # gitleaks:allow
        endpoint = "20.215.69.236:51820";
        allowedIPs = ["0.0.0.0/0" "::/0"];
        persistentKeepalive = 25;
      }
    ];
  };
}
