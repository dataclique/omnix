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

        # Evaluate a single omnix module in isolation and produce a
        # derivation that succeeds when the module evaluates cleanly
        evalModule = name: module:
          let
            eval = nixpkgs.lib.nixosSystem {
              inherit system;
              modules = [
                module
                {
                  boot.loader.grub.device = "nodev";
                  fileSystems."/" = { device = "none"; fsType = "tmpfs"; };
                  nixpkgs.hostPlatform = system;
                }
              ];
            };
          in pkgs.runCommand "eval-${name}" { } ''
            # Force evaluation of the module option definitions
            cat ${eval.config.system.build.toplevel.drvPath} > /dev/null
            touch $out
          '';

      in {
        # Expose disko and ragenix modules for consumer nixosSystem calls
        packages.disko = disko.packages.${system}.default or null;
        packages.ragenix = ragenix.packages.${system}.default;

        checks = {
          # Verify each module evaluates without errors in isolation
          eval-base = evalModule "base" self.nixosModules.base;
          eval-firewall = evalModule "firewall" self.nixosModules.firewall;
          eval-storage = evalModule "storage" self.nixosModules.storage;
          eval-digitalocean = evalModule "digitalocean" self.nixosModules.digitalocean;
          eval-services = evalModule "services" self.nixosModules.services;
          eval-disko = evalModule "disko" self.nixosModules.disko;
        };
      });
}
