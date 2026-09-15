{
  config,
  lib,
  pkgs,
  ...
}: {
  imports = [
    ./hardware-configuration.nix
  ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.systemd-boot.configurationLimit = 3;
  boot.loader.systemd-boot.consoleMode = "max";
  boot.loader.systemd-boot.editor = false;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.initrd.systemd.enable = true;

  system.nixos.label = "licht";

  boot.plymouth = {
    enable = true;
    theme = "circle_hud";
    themePackages = with pkgs; [
      (adi1090x-plymouth-themes.override {
        selected_themes = ["circle_hud"];
      })
    ];
  };

  boot.consoleLogLevel = 3;
  boot.initrd.verbose = false;
  boot.kernelParams = [
    "quiet"
    "splash"
    "boot.shell_on_fail"
    "udev.log_priority=3"
    "rd.systemd.show_status=auto"
  ];

  boot.loader.timeout = 0;

  boot.tmp.cleanOnBoot = true;

  networking.hostName = "licht";
  networking.networkmanager.enable = true;
  networking.firewall.enable = true;

  time.timeZone = "Asia/Karachi";
  i18n.defaultLocale = "en_US.UTF-8";

  console = {
    keyMap = "us";
  };

  nix.settings = {
    experimental-features = [
      "nix-command"
      "flakes"
    ];
    auto-optimise-store = true;
    trusted-users = ["licht"];
    substituters = ["https://hyprland.cachix.org"];
    trusted-public-keys = ["hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIBMioiJM7ypFP8PwtkuGc="];
  };

  nix.gc = {
    automatic = true;
    dates = "daily";
  };

  nixpkgs.config.allowUnfree = true;

  documentation.man.generateCaches = false;
  documentation.nixos.enable = false;
  documentation.doc.enable = false;

  programs.nix-ld.enable = true;
  programs.nix-ld.libraries = with pkgs; [
    stdenv.cc.cc.lib
  ];

  programs.nix-index.enable = true;
  programs.direnv.enable = true;

  services.xserver.xkb.layout = "us";

  age.identityPaths = ["/var/lib/agenix/key.txt"];

  age.secrets = {
    aria2-rpc-secret = {
      file = ../../secrets/aria2-rpc-secret.age;
      owner = "licht";
      group = "users";
      mode = "0400";
    };
    qbittorrent-webui-password = {
      file = ../../secrets/qbittorrent-webui-password.age;
      owner = "licht";
      group = "users";
      mode = "0400";
    };
  };

  zramSwap = {
    enable = true;
    memoryPercent = 100;
  };

  swapDevices = [
    {
      device = "/var/lib/swapfile";
      size = 4096;
    }
  ];

  services.fstrim.enable = true;

  programs.hyprland.enable = true;
  programs.zsh.enable = true;

  programs.dconf.enable = true;
  security.pam.services.hyprlock = {};

  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    pulse.enable = true;
  };

  xdg.portal = {
    enable = true;
    extraPortals = [
      pkgs.xdg-desktop-portal-hyprland
      pkgs.xdg-desktop-portal-gtk
    ];
  };

  security.polkit.enable = true;
  services.udisks2.enable = true;
  services.gvfs.enable = true;
  services.upower.enable = true;

  hardware.cpu.intel.updateMicrocode = true;
  hardware.enableRedistributableFirmware = true;

  hardware.graphics = {
    enable = true;

    extraPackages = with pkgs; [
      intel-media-driver
    ];
  };

  services.power-profiles-daemon.enable = true;
  services.thermald.enable = true;
  services.fwupd.enable = true;

  environment.sessionVariables = {
    LIBVA_DRIVER_NAME = "iHD";
    NIXOS_OZONE_WL = "1";
  };

  environment.variables = {
    EDITOR = "nvim";
    VISUAL = "nvim";
    NH_FLAKE = "/etc/nixos";
  };

  users.users.licht = {
    isNormalUser = true;
    shell = pkgs.zsh;
    extraGroups = [
      "networkmanager"
      "wheel"
    ];
  };

  fonts.packages = with pkgs; [
    nerd-fonts.jetbrains-mono
    noto-fonts
    noto-fonts-color-emoji
    rubik
  ];
  system.stateVersion = "26.05";
}
