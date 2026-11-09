{
  description = "NixOS and Home Manager configuration for licht";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
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
  };
  outputs = {
    self,
    nixpkgs,
    home-manager,
    agenix,
    nix-index-database,
    ...
  } @ inputs: let
    system = "x86_64-linux";
  in {
    formatter.${system} = nixpkgs.legacyPackages.${system}.alejandra;

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
