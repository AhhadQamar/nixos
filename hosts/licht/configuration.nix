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
    ./system/sddm.nix
    ./system/claude.nix
  ];

  programs.zsh.enable = true;

  age.identityPaths = ["/var/lib/agenix/key.txt"];

  age.secrets = {
    aria2-rpc-secret = {
      file = ../../secrets/aria2-rpc-secret.age;
      owner = "licht";
      group = "users";
      mode = "0400";
    };
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

  system.stateVersion = "26.05";
}
