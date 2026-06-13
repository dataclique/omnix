{
  nixpkgs,
  deploy-rs,
  nixos-anywhere,
  ...
}:

let
  inherit (nixpkgs) lib;
in
{
  mkServices = import ./services.nix { inherit lib; };
  mkServiceSecretRules = import ./secret-rules.nix;
  mkNuScript = import ./nu.nix;
  mkCI = import ./ci.nix;
  mkTerraform = import ./terraform.nix;
  mkDeploy = import ./deploy.nix { inherit deploy-rs lib; };
  mkBootstrap = import ./bootstrap.nix { inherit nixos-anywhere; };
  mkGitHooks = import ./hooks.nix;
}
