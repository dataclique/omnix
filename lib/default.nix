{ deploy-rs, nixos-anywhere, ... }:

{
  mkTerraform = import ./terraform.nix;
  mkDeploy = import ./deploy.nix { inherit deploy-rs; };
  mkBootstrap = import ./bootstrap.nix { inherit nixos-anywhere; };
  mkGitHooks = import ./hooks.nix;
}
