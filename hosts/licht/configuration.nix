{
  config,
  lib,
  pkgs,
  ...
}: {
  imports = [
    ./hardware-configuration.nix
    ./system/boot.nix
    ./system/nix.nix
    ./system/networking.nix
    ./system/hardware.nix
    ./system/desktop.nix
    ./system/greeter
    ./system/updater.nix
    ./system/wireguard.nix
  ];

  programs.zsh.enable = true;

  age.identityPaths = ["/var/lib/agenix/key.txt"];

  # One entry per name in secrets/names.nix, each readable only by licht.
  age.secrets = lib.genAttrs (import ../../secrets/names.nix) (name: {
    file = ../../secrets/${name}.age;
    owner = "licht";
    group = "users";
    mode = "0400";
  });

  environment.variables = {
    EDITOR = "nvim";
    VISUAL = "nvim";
  };

  users.users.licht = {
    isNormalUser = true;
    shell = pkgs.zsh;
    extraGroups = [
      "networkmanager"
      "wheel"
    ];
  };

  system.stateVersion = "26.05";
}
