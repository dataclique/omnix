{
  pkgs,
  keysFile,
  ragenixPkg ? null,
  secretsRules ? null,
  ...
}:

let
  shell = import ./shell.nix { inherit keysFile; };
  inherit (shell)
    tfState
    tfVars
    parseIdentity
    decryptState
    encryptState
    decryptVars
    encryptVars
    resolveIp
    ;

  buildInputs = [
    pkgs.terraform
    pkgs.rage
    pkgs.jq
  ]
  ++ (if ragenixPkg != null then [ ragenixPkg ] else [ ]);

  tfPlanFile = "infra/tfplan";

  cleanup = "rm -f ${tfState} ${tfState}.backup ${tfVars}";
  cleanupWithPlan = "${cleanup} ${tfPlanFile}";

  preamble = ''
    ${parseIdentity}
    on_exit() { ${cleanup}; }
    trap on_exit EXIT
    ${decryptVars}
  '';

  preambleWithEncrypt = ''
    ${parseIdentity}
    on_exit() {
      ${encryptState}
      ${cleanupWithPlan}
    }
    trap on_exit EXIT
    ${decryptVars}
  '';

  rekeyPreamble = ''
    ${parseIdentity}
    on_exit() {
      ${encryptState}
      ${cleanup}
    }
    trap on_exit EXIT
    ${decryptState}
    ${encryptState}
    ${decryptVars}
    ${encryptVars}
  '';

  mkTask =
    name: body:
    pkgs.writeShellApplication {
      inherit name;
      runtimeInputs = buildInputs;
      text = body;
    };

in
{
  inherit buildInputs parseIdentity resolveIp;

  tfInit = mkTask "tf-init" ''
    ${preamble}
    terraform -chdir=infra init "$@"
  '';

  tfPlan = mkTask "tf-plan" ''
    ${preamble}
    ${decryptState}
    terraform -chdir=infra plan -out=tfplan "$@"
  '';

  tfApply = mkTask "tf-apply" ''
    ${preambleWithEncrypt}
    ${decryptState}
    terraform -chdir=infra apply "$@" tfplan
  '';

  tfDestroy = mkTask "tf-destroy" ''
    ${preambleWithEncrypt}
    ${decryptState}
    terraform -chdir=infra destroy "$@"
  '';

  tfImport = mkTask "tf-import" ''
    ${preambleWithEncrypt}
    ${decryptState}
    terraform -chdir=infra import "$@"
  '';

  tfEditVars = mkTask "tf-edit-vars" ''
    ${parseIdentity}
    on_exit() { rm -f ${tfVars}; }
    trap on_exit EXIT

    if [ -f ${tfVars}.age ]; then
      ${decryptVars}
    else
      cp ${tfVars}.example ${tfVars}
    fi
    ''${EDITOR:-vi} ${tfVars}
    ${encryptVars}
  '';

  tfRekey = mkTask "tf-rekey" ''
    ${rekeyPreamble}
  '';

  rekey =
    if ragenixPkg != null && secretsRules != null then
      mkTask "rekey" ''
        ${rekeyPreamble}
        ragenix --rules ${secretsRules} -i "$identity" -r
      ''
    else
      null;

  remote = pkgs.writeShellApplication {
    name = "remote";
    runtimeInputs = [
      pkgs.rage
      pkgs.jq
      pkgs.openssh
    ];
    text = ''
      ${resolveIp}
      exec ssh -i "$identity" "root@$host_ip" "$@"
    '';
  };
}
