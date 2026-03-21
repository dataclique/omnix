# Shared helpers for omnix infrastructure scripts.
# All functions operate on the conventional infra/ directory structure.

const TF_STATE = "infra/terraform.tfstate"
const TF_VARS = "infra/terraform.tfvars"
const TF_PLAN = "infra/tfplan"

# Parse the optional -i <identity> flag, defaulting to ~/.ssh/id_ed25519.
export def parse-identity [
  ...args: string
]: nothing -> record<identity: string, rest: list<string>> {
  if ($args | length) >= 2 and ($args.0 == "-i") {
    { identity: $args.1, rest: ($args | skip 2) }
  } else {
    { identity: ($env.HOME | path join ".ssh" "id_ed25519"), rest: $args }
  }
}

# Decrypt terraform state from age-encrypted file.
export def decrypt-state [identity: string] {
  let encrypted = $"($TF_STATE).age"
  if ($encrypted | path exists) {
    ^rage -d -i $identity $encrypted | save -f $TF_STATE
    ^chmod 600 $TF_STATE
  }
}

# Encrypt terraform state to age-encrypted file using keys.nix roles.
export def encrypt-state [keys_file: string] {
  if ($TF_STATE | path exists) {
    let recipients = (^nix eval --raw --file $keys_file roles.infra
      --apply 'builtins.concatStringsSep "\n"')
    if ($recipients | is-empty) {
      error make { msg: "no recipients found in keys.nix roles.infra — cannot encrypt state" }
    }
    $recipients | ^rage -e -R /dev/stdin -o $"($TF_STATE).age" $TF_STATE
  }
}

# Decrypt terraform variables from age-encrypted file.
export def decrypt-vars [identity: string] {
  let encrypted = $"($TF_VARS).age"
  if ($encrypted | path exists) {
    ^rage -d -i $identity $encrypted | save -f $TF_VARS
    ^chmod 600 $TF_VARS
  }
}

# Encrypt terraform variables to age-encrypted file using keys.nix roles.
export def encrypt-vars [keys_file: string] {
  let recipients = (^nix eval --raw --file $keys_file roles.infra
    --apply 'builtins.concatStringsSep "\n"')
  $recipients | ^rage -e -R /dev/stdin -o $"($TF_VARS).age" $TF_VARS
}

# Resolve the droplet IP from encrypted terraform state.
# Returns a record with identity and host_ip.
export def resolve-ip [
  keys_file: string
  --output-key: string = "outputs.droplet_ipv4.value"  # terraform output path for host IP
  ...args: string
]: nothing -> record<identity: string, host_ip: string, rest: list<string>> {
  let parsed = (parse-identity ...$args)
  decrypt-state $parsed.identity

  let host_ip = (open $TF_STATE | get $output_key)
  rm -f $TF_STATE

  if ($host_ip | is-empty) {
    error make { msg: "failed to resolve droplet IP from terraform state" }
  }

  { identity: $parsed.identity, host_ip: $host_ip, rest: $parsed.rest }
}

# Remove decrypted terraform files.
export def cleanup [] {
  rm -f $TF_STATE $"($TF_STATE).backup" $TF_VARS
}

# Remove decrypted terraform files including plan.
export def cleanup-with-plan [] {
  cleanup
  rm -f $TF_PLAN
}
