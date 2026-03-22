{
  description = "My service on DigitalOcean";

  inputs = {
    omnix.url = "github:data-cartel/omnix";
    nixpkgs.follows = "omnix/nixpkgs";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    {
      self,
      omnix,
      nixpkgs,
      flake-utils,
      ...
    }:
    let
      projectName = "my-service";
      services = import ./services.nix;
    in
    {
      nixosConfigurations.${projectName} = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = { };

        modules = [
          omnix.nixosModules.default
          ./os.nix
        ];
      };

      # Hardcoded to x86_64-linux: deploy-rs targets the remote NixOS host,
      # which is always x86_64-linux regardless of the local dev machine.
      deploy =
        let
          deployConfig = omnix.lib.mkDeploy {
            inherit self services;
            nodeName = projectName;
            package = self.packages.x86_64-linux.default;
          };
        in
        deployConfig.config;
    }
    // flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs {
          inherit system;
          config.allowUnfreePredicate = pkg: builtins.elem (pkgs.lib.getName pkg) [ "terraform" ];
        };

        infraPkgs = omnix.lib.mkTerraform {
          inherit pkgs system;
          keysFile = ./keys.nix;
          ragenixPkg = omnix.inputs.ragenix.packages.${system}.default;
          secretsRules = ./config/secrets.nix;
        };

        deployConfig = omnix.lib.mkDeploy {
          inherit self services;
          nodeName = projectName;
          package = pkgs.hello; # replace with your actual package
        };

        deployPkgs = deployConfig.wrappers {
          inherit pkgs infraPkgs;
          localSystem = system;
        };

      in
      {
        packages = {
          default = pkgs.hello; # replace with your actual package

          inherit (infraPkgs)
            tfInit
            tfPlan
            tfApply
            tfDestroy
            tfEditVars
            tfRekey
            remote
            ;
        }
        // (if infraPkgs.rekey != null then { inherit (infraPkgs) rekey; } else { })
        // {

          bootstrap = omnix.lib.mkBootstrap {
            inherit pkgs system;
            keysFile = ./keys.nix;
            configName = projectName;
            ragenixPkg = omnix.inputs.ragenix.packages.${system}.default;
            secretsRules = ./config/secrets.nix;
          };

          resolveIp = pkgs.writeShellApplication {
            name = "resolve-ip";
            runtimeInputs = [
              pkgs.rage
              pkgs.jq
            ];
            text = ''
              ${infraPkgs.resolveIp}
              echo "$host_ip"
            '';
          };

          inherit (deployPkgs) deployNixos deployService deployAll;
        };

        devShells.default = pkgs.mkShell {
          packages = with pkgs; [
            infraPkgs.remote
            deployPkgs.deployNixos
            deployPkgs.deployService
            deployPkgs.deployAll
          ];
        };
      }
    );
}
