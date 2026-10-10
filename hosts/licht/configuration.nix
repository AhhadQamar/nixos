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
    ./system/updater.nix
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
    ahhadqamar1-gmail = {
      file = ../../secrets/ahhadqamar1-gmail.age;
      owner = "licht";
      group = "users";
      mode = "0400";
    };
    ahadqam1-gmail = {
      file = ../../secrets/ahadqam1-gmail.age;
      owner = "licht";
      group = "users";
      mode = "0400";
    };
    ahhad067-gmail = {
      file = ../../secrets/ahhad067-gmail.age;
      owner = "licht";
      group = "users";
      mode = "0400";
    };
    ahhadqamar3154-gmail = {
      file = ../../secrets/ahhadqamar3154-gmail.age;
      owner = "licht";
      group = "users";
      mode = "0400";
    };
    ahhad3309-gmail = {
      file = ../../secrets/ahhad3309-gmail.age;
      owner = "licht";
      group = "users";
      mode = "0400";
    };
    gamerking3154-gmail = {
      file = ../../secrets/gamerking3154-gmail.age;
      owner = "licht";
      group = "users";
      mode = "0400";
    };
    msahhad78-gmail = {
      file = ../../secrets/msahhad78-gmail.age;
      owner = "licht";
      group = "users";
      mode = "0400";
    };
    ahhadqamara-gmail = {
      file = ../../secrets/ahhadqamara-gmail.age;
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
