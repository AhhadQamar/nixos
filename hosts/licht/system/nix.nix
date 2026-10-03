{pkgs, ...}: {
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
}
