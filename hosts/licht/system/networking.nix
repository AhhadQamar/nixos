{...}: {
  networking.hostName = "licht";
  networking.networkmanager.enable = true;
  networking.firewall.enable = true;

  time.timeZone = "Asia/Karachi";
  i18n.defaultLocale = "en_US.UTF-8";

  console = {
    keyMap = "us";
  };

  services.xserver.xkb.layout = "us";
}
