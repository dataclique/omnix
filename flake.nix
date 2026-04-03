{
  description = "Composable Nix infrastructure for DigitalOcean deployments";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    flake-utils.url = "github:numtide/flake-utils";

    ragenix.url = "github:yaxitech/ragenix";
    ragenix.inputs.nixpkgs.follows = "nixpkgs";

    deploy-rs.url = "github:serokell/deploy-rs";
    deploy-rs.inputs.nixpkgs.follows = "nixpkgs";

    disko.url = "github:nix-community/disko";
    disko.inputs.nixpkgs.follows = "nixpkgs";

    nixos-anywhere.url = "github:nix-community/nixos-anywhere";
    nixos-anywhere.inputs.nixpkgs.follows = "nixpkgs";

    git-hooks.url = "github:cachix/git-hooks.nix";
    git-hooks.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
      ragenix,
      deploy-rs,
      disko,
      nixos-anywhere,
      git-hooks,
      ...
    }:
    {
      nixosConfigurations = {
        example-minimal = import ./examples/minimal.nix {
          inherit
            self
            nixpkgs
            disko
            ragenix
            ;
        };
        example-single-service = import ./examples/single-service.nix {
          inherit
            self
            nixpkgs
            disko
            ragenix
            ;
        };
        example-full = import ./examples/full.nix {
          inherit
            self
            nixpkgs
            disko
            ragenix
            ;
        };
      };

      nixosModules = {
        disko = import ./modules/disko.nix;
        digitalocean = import ./modules/digitalocean.nix;
        base = import ./modules/base.nix;
        storage = import ./modules/storage.nix;
        services = import ./modules/services.nix;
        firewall = import ./modules/firewall.nix;
        acme = import ./modules/acme.nix;

        # Convenience: all modules at once (includes upstream disko + ragenix)
        default = {
          imports = [
            disko.nixosModules.disko
            ragenix.nixosModules.default
            self.nixosModules.disko
            self.nixosModules.digitalocean
            self.nixosModules.base
            self.nixosModules.storage
            self.nixosModules.services
            self.nixosModules.firewall
            self.nixosModules.acme
          ];
        };
      };

      lib = import ./lib {
        inherit
          nixpkgs
          deploy-rs
          nixos-anywhere
          git-hooks
          ;
      };

      templates = {
        do-service = {
          path = ./templates/do-service;
          description = "DigitalOcean service with deploy-rs, terraform, and age secrets";
        };
        default = self.templates.do-service;
      };
    }
    // flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs { inherit system; };
        hooks = self.lib.mkGitHooks { };
      in
      {
        packages.disko =
          disko.packages.${system}.default or (throw "disko package not available for ${system}");
        packages.ragenix = ragenix.packages.${system}.default;

        checks.git-hooks = git-hooks.lib.${system}.run {
          inherit hooks;
          src = self;
        };

        formatter = pkgs.nixfmt;

        devShells.default = pkgs.mkShell {
          inherit (self.checks.${system}.git-hooks) shellHook;
          packages = [
            pkgs.nixfmt
            pkgs.deadnix
            pkgs.taplo
          ];
        };
      }
    );
}
