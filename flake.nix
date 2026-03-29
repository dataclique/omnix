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
  };

  outputs = { self, nixpkgs, flake-utils, ragenix, deploy-rs, disko
    , nixos-anywhere, ... }:
    {
      nixosModules = {
        disko = import ./modules/disko.nix;
        digitalocean = import ./modules/digitalocean.nix;
        base = import ./modules/base.nix;
        storage = import ./modules/storage.nix;
        services = import ./modules/services.nix;
        firewall = import ./modules/firewall.nix;

        # Convenience: all modules at once
        default = {
          imports = [
            self.nixosModules.disko
            self.nixosModules.digitalocean
            self.nixosModules.base
            self.nixosModules.storage
            self.nixosModules.services
            self.nixosModules.firewall
          ];
        };
      };

      lib = import ./lib { inherit nixpkgs deploy-rs nixos-anywhere; };

      templates = {
        do-service = {
          path = ./templates/do-service;
          description =
            "DigitalOcean service with deploy-rs, terraform, and age secrets";
        };
        default = self.templates.do-service;
      };
    } // flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };

        # Build a minimal NixOS system with a single omnix module to
        # verify it evaluates and builds without errors in isolation
        evalModule = name: module: extraModules:
          (nixpkgs.lib.nixosSystem {
            inherit system;
            modules = [
              module
              {
                boot.loader.grub.device = "nodev";
                fileSystems."/" = { device = "none"; fsType = "tmpfs"; };
                nixpkgs.hostPlatform = system;
              }
            ] ++ extraModules;
          }).config.system.build.toplevel;

      in {
        # Expose disko and ragenix modules for consumer nixosSystem calls
        packages.disko = disko.packages.${system}.default or null;
        packages.ragenix = ragenix.packages.${system}.default;

        checks = {
          # Verify each module evaluates and builds without errors in isolation
          eval-base = evalModule "base" self.nixosModules.base [ ];
          eval-firewall = evalModule "firewall" self.nixosModules.firewall [ ];
          eval-storage = evalModule "storage" self.nixosModules.storage [ ];
          eval-digitalocean = evalModule "digitalocean" self.nixosModules.digitalocean [ ];
          eval-services = evalModule "services" self.nixosModules.services [ ];
          eval-disko = evalModule "disko" self.nixosModules.disko [
            disko.nixosModules.disko
          ];
        };
      });
}
