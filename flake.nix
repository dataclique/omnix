{
  description = "Composable Nix infrastructure for DigitalOcean deployments";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    flake-parts.url = "github:hercules-ci/flake-parts";

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
    inputs@{
      self,
      nixpkgs,
      flake-parts,
      ragenix,
      deploy-rs,
      disko,
      nixos-anywhere,
      git-hooks,
      ...
    }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];

      flake = {
        nixosModules = {
          disko = import ./modules/disko.nix;
          digitalocean = import ./modules/digitalocean.nix;
          base = import ./modules/base.nix;
          storage = import ./modules/storage.nix;
          services = import ./modules/services.nix;
          firewall = import ./modules/firewall.nix;
          staticSites = import ./modules/static-sites.nix;
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
              self.nixosModules.staticSites
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

        nixosConfigurations =
          let
            mkExample =
              configFile:
              nixpkgs.lib.nixosSystem {
                system = "x86_64-linux";
                modules = [
                  self.nixosModules.default
                  configFile
                ];
              };
          in
          {
            example-minimal = mkExample ./examples/minimal/os.nix;
            example-single-service = mkExample ./examples/single-service/os.nix;
            example-full = mkExample ./examples/full/os.nix;
          };

        templates = {
          do-service = {
            path = ./templates/do-service;
            description = "DigitalOcean service with deploy-rs, terraform, and age secrets";
          };
          default = self.templates.do-service;
        };
      };

      perSystem =
        { pkgs, system, ... }:
        let
          hooks = self.lib.mkGitHooks { };
        in
        {
          packages = {
            disko = disko.packages.${system}.default or (throw "disko package not available for ${system}");
            ragenix = ragenix.packages.${system}.default;
          };

          checks.git-hooks = git-hooks.lib.${system}.run {
            inherit hooks;
            src = self;
          };

          checks.examples = pkgs.runCommand "validate-examples" { nativeBuildInputs = [ pkgs.nushell ]; } ''
            cd ${self}
            nu scripts/validate-examples.nu examples
            touch $out
          '';

          formatter = pkgs.nixfmt;

          devShells.default = pkgs.mkShell {
            inherit (self.checks.${system}.git-hooks) shellHook enabledPackages;
            packages = self.checks.${system}.git-hooks.enabledPackages;
          };
        };
    };
}
