{
  config,
  pkgs,
  ...
}: {
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

  # nh: the CLI behind `u`, `ut`, `ub`. `flake` sets NH_FLAKE for every shell, and
  # `clean` replaces nix.gc: weekly, it keeps the last 5 generations plus anything
  # from the last 14 days and deletes the rest. Do not enable nix.gc as well.
  programs.nh = {
    enable = true;
    flake = "${config.users.users.licht.home}/nixos";
    clean = {
      enable = true;
      dates = "weekly";
      extraArgs = "--keep 5 --keep-since 14d";
    };
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

  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };
}
