# Bootstrap a DigitalOcean droplet with NixOS via nixos-anywhere.
# Resolves the host IP from terraform state, runs nixos-anywhere,
# waits for the host to come back, extracts the new host key,
# updates keys.nix, and optionally rekeys secrets.

use common.nu *

def wait-for-ssh [identity: string, host_ip: string] {
  let ssh_opts = [-o StrictHostKeyChecking=no -o ConnectTimeout=5 -i $identity]
  print "Waiting for host to come back up..."

  mut retries = 0
  loop {
    let result = (do { ^ssh ...$ssh_opts $"root@($host_ip)" true } | complete)
    if $result.exit_code == 0 { break }

    $retries += 1
    if $retries >= 60 {
      error make { msg: "host did not come back up after 5 minutes" }
    }
    sleep 5sec
  }
}

def extract-host-key [identity: string, host_ip: string]: nothing -> string {
  let ssh_opts = [-o StrictHostKeyChecking=no -o ConnectTimeout=5 -i $identity]
  let raw = (^ssh ...$ssh_opts $"root@($host_ip)" cat /etc/ssh/ssh_host_ed25519_key.pub | str trim)

  if ($raw | is-empty) {
    error make { msg: $"bootstrap: host key from ($host_ip) is empty" }
  }

  let parts = ($raw | split row " ")
  if ($parts | length) < 2 {
    error make { msg: $"bootstrap: host key from ($host_ip) is malformed: ($raw)" }
  }

  $"($parts.0) ($parts.1)"
}

export def update-keys-nix [keys_file: string, config_name: string, new_key: string] {
  let content = (open $keys_file --raw)
  let expected = $'host = "($new_key)"'

  # Scope replacement to the stanza matching config_name when present,
  # otherwise fall back to replacing the first host occurrence (flat keys.nix).
  let updated = if ($content | str contains $config_name) {
    let idx = ($content | str index-of $config_name)
    let before = ($content | str substring 0..$idx)
    let after = ($content | str substring $idx..
      | str replace --regex 'host\s*=\s*"ssh-ed25519 [^"]*"' $'host = "($new_key)"')
    $"($before)($after)"
  } else {
    $content | str replace --regex 'host\s*=\s*"ssh-ed25519 [^"]*"' $'host = "($new_key)"'
  }

  if not ($updated | str contains $expected) {
    error make { msg: $"host key replacement in keys.nix failed for ($config_name)" }
  }

  $updated | save -f $keys_file
  print $"Updated host key in ($keys_file) for ($config_name)"
}

export def main [
  keys_file: string
  config_name: string
  --secrets-rules: string  # path to ragenix secrets.nix rules
  ...args: string
] {
  let resolved = (resolve-ip $keys_file ...$args)

  ^nixos-anywhere --flake $".#($config_name)"
    --option pure-eval false
    --ssh-option $"IdentityFile=($resolved.identity)"
    --target-host $"root@($resolved.host_ip)"

  wait-for-ssh $resolved.identity $resolved.host_ip

  let new_key = (extract-host-key $resolved.identity $resolved.host_ip)
  update-keys-nix $keys_file $config_name $new_key

  if ($secrets_rules != null) {
    print "Rekeying secrets..."
    ^ragenix --rules $secrets_rules -i $resolved.identity -r
  }
}
