{
  pkgs,
  keysFile,
  ragenixPkg ? null,
  secretsRules ? null,
  ...
}:

let
  scriptsDir = ../scripts;
  shell = import ./shell.nix { inherit pkgs scriptsDir; };
  inherit (shell) mkNuScript;

  runtimeInputs = [
    pkgs.terraform
    pkgs.rage
    pkgs.jq
  ]
  ++ (if ragenixPkg != null then [ ragenixPkg ] else [ ]);

  mkTfTask =
    { name, subcommand }:
    mkNuScript {
      inherit name subcommand runtimeInputs;
      script = "terraform.nu";
      extraArgs = [ (toString keysFile) ];
    };

in
{
  inherit runtimeInputs;

  tfInit = mkTfTask { name = "tf-init"; subcommand = "init"; };
  tfPlan = mkTfTask { name = "tf-plan"; subcommand = "plan"; };
  tfApply = mkTfTask { name = "tf-apply"; subcommand = "apply"; };
  tfDestroy = mkTfTask { name = "tf-destroy"; subcommand = "destroy"; };
  tfImport = mkTfTask { name = "tf-import"; subcommand = "import"; };
  tfEditVars = mkTfTask { name = "tf-edit-vars"; subcommand = "edit-vars"; };

  # tfRekey is always available (optionally passes --secrets-rules).
  # rekey only exists when ragenixPkg and secretsRules are both provided,
  # because it invokes ragenix which requires both.
  tfRekey = mkNuScript {
    name = "tf-rekey";
    script = "terraform.nu";
    subcommand = "rekey";
    inherit runtimeInputs;
    extraArgs = [
      (toString keysFile)
    ]
    ++ (
      if secretsRules != null && ragenixPkg != null then
        [
          "--secrets-rules"
          (toString secretsRules)
        ]
      else
        [ ]
    );
  };

  rekey =
    if ragenixPkg != null && secretsRules != null then
      mkNuScript {
        name = "rekey";
        script = "terraform.nu";
        subcommand = "rekey";
        inherit runtimeInputs;
        extraArgs = [
          (toString keysFile)
          "--secrets-rules"
          (toString secretsRules)
        ];
      }
    else
      null;

  remote = mkNuScript {
    name = "remote";
    script = "terraform.nu";
    subcommand = "remote";
    runtimeInputs = [
      pkgs.rage
      pkgs.jq
      pkgs.openssh
    ];
    extraArgs = [ (toString keysFile) ];
  };

  resolveIp = mkNuScript {
    name = "resolve-ip";
    script = "terraform.nu";
    subcommand = "resolve-ip";
    runtimeInputs = [
      pkgs.rage
      pkgs.jq
    ];
    extraArgs = [ (toString keysFile) ];
  };
}
