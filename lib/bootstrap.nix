{ nixos-anywhere }:

{
  pkgs,
  keysFile,
  configName,
  system,
  ragenixPkg ? null,
  secretsRules ? null,
}:

let
  scriptsDir = ../scripts;
  shell = import ./shell.nix { inherit pkgs scriptsDir; };
in
shell.mkNuScript {
  name = "bootstrap-nixos";
  script = "bootstrap.nu";
  runtimeInputs = [
    pkgs.rage
    pkgs.jq
    pkgs.gnused
    pkgs.openssh
    nixos-anywhere.packages.${system}.default
  ]
  ++ (if ragenixPkg != null then [ ragenixPkg ] else [ ]);
  extraArgs = [
    (toString keysFile)
    configName
  ]
  ++ (
    if secretsRules != null then
      [
        "--secrets-rules"
        (toString secretsRules)
      ]
    else
      [ ]
  );
}
