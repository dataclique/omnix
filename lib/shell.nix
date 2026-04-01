{ keysFile }:

let
  tfState = "infra/terraform.tfstate";
  tfVars = "infra/terraform.tfvars";

  parseIdentity = ''
    identity=~/.ssh/id_ed25519
    if [ "''${1:-}" = "-i" ]; then
      identity="$2"
      shift 2
    fi
  '';

  decryptState = ''
    if [ -f ${tfState}.age ]; then
      rage -d -i "$identity" ${tfState}.age > ${tfState}
      chmod 600 ${tfState}
    fi
  '';

  encryptState = ''
    if [ -f ${tfState} ]; then
      nix eval --raw --file ${keysFile} roles.infra --apply 'builtins.concatStringsSep "\n"' \
        | rage -e -R /dev/stdin -o ${tfState}.age ${tfState}
    fi
  '';

  decryptVars = ''
    rage -d -i "$identity" ${tfVars}.age > ${tfVars}
    chmod 600 ${tfVars}
  '';

  encryptVars = ''
    nix eval --raw --file ${keysFile} roles.infra --apply 'builtins.concatStringsSep "\n"' \
      | rage -e -R /dev/stdin -o ${tfVars}.age ${tfVars}
  '';

  resolveIp = ''
    ${parseIdentity}
    trap 'rm -f ${tfState}' EXIT
    ${decryptState}
    host_ip=$(jq -e -r '.outputs.droplet_ipv4.value' ${tfState})
    rm -f ${tfState}
  '';

in
{
  inherit
    tfState
    tfVars
    parseIdentity
    decryptState
    encryptState
    decryptVars
    encryptVars
    resolveIp
    ;
}
