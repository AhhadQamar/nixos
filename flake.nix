{
  description = "NixOS and Home Manager configuration for licht";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    agenix = {
      url = "github:ryantm/agenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-index-database = {
      url = "github:nix-community/nix-index-database";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    windscribe = {
      url = "github:ParkerrDev/nixpkgs-windscribe";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # Deliberately no `inputs.nixpkgs.follows`: Luciole needs nixos-unstable
    # (wayland-protocols >= 1.49, our 26.05 has 1.48). The `cachix` branch is
    # always a commit CI has built, so it comes from the Noctalia cache.
    luciole.url = "github:noctalia-dev/luciole/cachix";
  };
  outputs = {
    nixpkgs,
    nixpkgs-unstable,
    home-manager,
    agenix,
    nix-index-database,
    windscribe,
    ...
  } @ inputs: let
    system = "x86_64-linux";
  in {
    formatter.${system} = nixpkgs.legacyPackages.${system}.alejandra;

    # `nix flake check` fails if statix finds a lint or deadnix finds unused
    # code. hardware-configuration.nix is generated, so both skip it.
    checks.${system}.lint = let
      pkgs = nixpkgs.legacyPackages.${system};
    in
      pkgs.runCommand "lint" {
        nativeBuildInputs = [pkgs.statix pkgs.deadnix];
      } ''
        cd ${./.}
        statix check -i hosts/licht/hardware-configuration.nix .
        deadnix --fail --exclude hosts/licht/hardware-configuration.nix .
        touch $out
      '';

    # `nix develop`, or automatically in this folder through direnv (.envrc).
    #   agenix    edit secrets:  agenix -e secrets/<name>.age
    #   statix    lint:          statix check .   (statix fix . applies fixes)
    #   deadnix   unused code:   deadnix .
    #   gitleaks  secret scan:   gitleaks git --staged
    devShells.${system}.default = let
      pkgs = nixpkgs.legacyPackages.${system};
    in
      pkgs.mkShell {
        packages = [
          agenix.packages.${system}.default
          pkgs.statix
          pkgs.deadnix
          pkgs.gitleaks
          pkgs.alejandra
        ];
      };

    nixosConfigurations.licht = nixpkgs.lib.nixosSystem {
      specialArgs = {inherit inputs;};

      modules = [
        ./hosts/licht/configuration.nix
        agenix.nixosModules.default
        nix-index-database.nixosModules.nix-index
        home-manager.nixosModules.home-manager
        windscribe.nixosModules.windscribe
        {
          nixpkgs.overlays = [
            (_final: _prev: {
              unstable = import nixpkgs-unstable {
                inherit system;
                config.allowUnfree = true;
              };
            })
          ];
        }
        {
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.extraSpecialArgs = {inherit inputs;};
          home-manager.users.licht = import ./hosts/licht/home.nix;
        }
      ];
    };
  };
}
