# Terraform wrapper scripts with age-encrypted state and variables.
# All subcommands accept -i <identity> to override the SSH key.

use common.nu *

# Run a terraform command with decrypted vars only (no state encryption).
def with-tf-vars [keys_file: string, args: list<string>, action: closure] {
  let parsed = (parse-identity ...$args)
  try {
    decrypt-vars $parsed.identity
    do $action $parsed.rest
  } catch { |e|
    cleanup
    error make { msg: $e.msg }
  }
  cleanup
}

# Run a terraform command that reads and writes state (encrypts after).
def with-tf-state [keys_file: string, args: list<string>, action: closure] {
  let parsed = (parse-identity ...$args)
  try {
    decrypt-vars $parsed.identity
    decrypt-state $parsed.identity
    do $action $parsed.rest
    encrypt-state $keys_file
  } catch { |e|
    encrypt-state $keys_file
    cleanup-with-plan
    error make { msg: $e.msg }
  }
  cleanup-with-plan
}

# Initialize terraform.
export def "main init" [keys_file: string, ...args: string] {
  with-tf-vars $keys_file $args {|rest| ^terraform -chdir=infra init ...$rest }
}

# Plan terraform changes.
export def "main plan" [keys_file: string, ...args: string] {
  let parsed = (parse-identity ...$args)
  try {
    decrypt-vars $parsed.identity
    decrypt-state $parsed.identity
    ^terraform -chdir=infra plan -out=tfplan ...$parsed.rest
  } catch { |e|
    cleanup-with-plan
    error make { msg: $e.msg }
  }
  cleanup-with-plan
}

# Apply terraform changes (re-encrypts state after).
export def "main apply" [keys_file: string, ...args: string] {
  with-tf-state $keys_file $args {|rest| ^terraform -chdir=infra apply ...$rest tfplan }
}

# Destroy terraform infrastructure (re-encrypts state after).
export def "main destroy" [keys_file: string, ...args: string] {
  with-tf-state $keys_file $args {|rest| ^terraform -chdir=infra destroy ...$rest }
}

# Import a terraform resource (re-encrypts state after).
export def "main import" [keys_file: string, ...args: string] {
  with-tf-state $keys_file $args {|rest| ^terraform -chdir=infra import ...$rest }
}

# Edit terraform variables (decrypt, open in $EDITOR, re-encrypt).
export def "main edit-vars" [keys_file: string, ...args: string] {
  let parsed = (parse-identity ...$args)
  let vars_file = "infra/terraform.tfvars"
  let vars_age = $"($vars_file).age"
  let vars_example = $"($vars_file).example"

  try {
    if ($vars_age | path exists) {
      decrypt-vars $parsed.identity
    } else {
      cp $vars_example $vars_file
    }

    let editor = ($env | get -i EDITOR | default "vi")
    ^$editor $vars_file
    encrypt-vars $keys_file
  } catch { |e|
    rm -f $vars_file
    error make { msg: $e.msg }
  }
  rm -f $vars_file
}

# Rekey all terraform secrets (and optionally ragenix secrets).
export def "main rekey" [
  keys_file: string
  --secrets-rules: string  # path to ragenix secrets.nix rules
  ...args: string
] {
  let parsed = (parse-identity ...$args)
  try {
    decrypt-state $parsed.identity
    encrypt-state $keys_file
    decrypt-vars $parsed.identity
    encrypt-vars $keys_file
    if ($secrets_rules != null) {
      ^ragenix --rules $secrets_rules -i $parsed.identity -r
    }
  } catch { |e|
    encrypt-state $keys_file
    cleanup
    error make { msg: $e.msg }
  }
  cleanup
}

# SSH into the remote host.
export def "main remote" [keys_file: string, ...args: string] {
  let resolved = (resolve-ip $keys_file ...$args)
  ^ssh -i $resolved.identity $"root@($resolved.host_ip)" ...$resolved.rest
}

# Print the resolved host IP.
export def "main resolve-ip" [keys_file: string, ...args: string] {
  let resolved = (resolve-ip $keys_file ...$args)
  print $resolved.host_ip
}

export def main [] {
  print "usage: terraform <init|plan|apply|destroy|import|edit-vars|rekey|remote|resolve-ip>"
}
