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

    but.url = "github:data-cartel/but.nix";
    but.inputs.nixpkgs.follows = "nixpkgs";
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
      but,
      ...
    }:
    {
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

        # Repo-specific "## This Repository" section spliced into the gitbutler
        # agent skill provided by the but.nix flake.
        butRepoNotes = ''
          ## This Repository

          - **Dev shell provides `but`.** It is on `PATH` via the `but.nix` flake
            input; run `direnv allow` (or enter `nix develop`) if `but --version`
            is missing.
          - **Pre-commit hooks** (`nixfmt`, `deadnix`, `taplo`, via
            `git-hooks.nix`) run on `but commit`. `but amend` / `but rub` skip
            them, so prefer new commits and clean up history with squash/reword.
          - **CI gate:** `nix flake check` must pass (formatting, isolated module
            evaluation, and full NixOS toplevel builds). Run it before pushing.
          - **Commit messages:** short, lowercase, imperative; conventional
            prefixes (`feat:`, `fix:`, `chore:`) where they fit.
          - **`master` is the default branch.** Never `but push` to it or
            `but pr new` without an explicit instruction.

        '';

        # Build a minimal NixOS system with a single omnix module to
        # verify it evaluates and builds without errors in isolation
        evalModule =
          module: extraModules:
          (nixpkgs.lib.nixosSystem {
            inherit system;
            modules = [
              module
              {
                boot.loader.grub.device = "nodev";
                fileSystems."/" = {
                  device = "none";
                  fsType = "tmpfs";
                };
                nixpkgs.hostPlatform = system;
              }
            ]
            ++ extraModules;
          }).config.system.build.toplevel;
      in
      {
        packages.disko =
          disko.packages.${system}.default or (throw "disko package not available for ${system}");
        packages.ragenix = ragenix.packages.${system}.default;

        checks = {
          git-hooks = git-hooks.lib.${system}.run {
            inherit hooks;
            src = self;
          };
        }
        // (nixpkgs.lib.optionalAttrs pkgs.stdenv.isLinux {
          eval-base = evalModule self.nixosModules.base [ ];
          eval-firewall = evalModule self.nixosModules.firewall [ ];
          eval-storage = evalModule self.nixosModules.storage [ ];
          eval-digitalocean = evalModule self.nixosModules.digitalocean [ ];
          eval-services = evalModule self.nixosModules.services [ ];
          eval-disko = evalModule self.nixosModules.disko [
            disko.nixosModules.disko
          ];
        });

        formatter = pkgs.nixfmt;

        devShells.default = pkgs.mkShell {
          packages = [
            pkgs.nixfmt
            pkgs.deadnix
            pkgs.taplo
            but.lib.${system}.gitbutler-cli
          ];
          shellHook = ''
            ${self.checks.${system}.git-hooks.shellHook}
            ${but.lib.${system}.installSkillScript { repoNotes = butRepoNotes; }}
          '';
        };
      }
    );
}
