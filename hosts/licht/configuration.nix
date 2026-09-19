{
  config,
  lib,
  pkgs,
  ...
}: {
  imports = [
    ./hardware-configuration.nix
    ./sddm.nix
  ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.systemd-boot.configurationLimit = 5;
  boot.loader.systemd-boot.consoleMode = "max";
  boot.loader.systemd-boot.editor = false;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.initrd.systemd.enable = true;

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

  services.tailscale.enable = true;

  networking.firewall.trustedInterfaces = ["tailscale0"];
  networking.firewall.allowedUDPPorts = [config.services.tailscale.port];

  services.vaultwarden = {
    enable = true;
    backupDir = "/var/backup/vaultwarden";
    environmentFile = config.age.secrets.vaultwarden-admin-token.path;
    config = {
      DOMAIN = "https://licht.possum-fir.ts.net";
      ROCKET_ADDRESS = "127.0.0.1";
      ROCKET_PORT = 8000;
      SIGNUPS_ALLOWED = false;
    };
  };

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
    auto-optimise-store = false;
    warn-dirty = false;
  };

  nix.optimise = {
    automatic = true;
    dates = ["weekly"];
  };

  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 14d";
    randomizedDelaySec = "45min";
  };

  nixpkgs.config.allowUnfree = true;

  documentation.man.cache.enable = false;
  documentation.nixos.enable = false;
  documentation.doc.enable = false;

  programs.nix-ld.enable = true;
  programs.nix-ld.libraries = with pkgs; [
    stdenv.cc.cc.lib
  ];

  programs.nix-index-database.comma.enable = true;

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
    vaultwarden-admin-token = {
      file = ../../secrets/vaultwarden-admin-token.age;
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

  programs.hyprland = {
    enable = true;
    withUWSM = true;
  };
  programs.hyprlock.enable = true;
  programs.zsh.enable = true;

  programs.dconf.enable = true;
  security.pam.services.login.enableGnomeKeyring = true;

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

  services.gnome.gnome-keyring.enable = true;
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
    NH_FLAKE = "/home/licht/nixos";
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
