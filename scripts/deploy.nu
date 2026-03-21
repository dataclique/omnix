# Deploy wrappers for deploy-rs.
# Resolves host IP from terraform state and invokes deploy with the right flags.

use common.nu *

def deploy-preamble [
  keys_file: string
  local_system: string
  ...args: string
]: nothing -> record<identity: string, host_ip: string, ssh_flag: string, deploy_flags: list<string>, rest: list<string>> {
  let resolved = (resolve-ip $keys_file ...$args)

  let default_identity = ($env.HOME | path join ".ssh" "id_ed25519")
  let ssh_flag = if $resolved.identity != $default_identity {
    $"--ssh-opts=-i ($resolved.identity)"
  } else {
    ""
  }

  let deploy_flags = if $local_system == "x86_64-linux" {
    ["--skip-checks"]
  } else {
    ["--remote-build" "--skip-checks"]
  }

  {
    identity: $resolved.identity
    host_ip: $resolved.host_ip
    ssh_flag: $ssh_flag
    deploy_flags: $deploy_flags
    rest: $resolved.rest
  }
}

def build-deploy-args [
  ctx: record
  target: string
]: nothing -> list<string> {
  mut args = ($ctx.deploy_flags ++ [--hostname $ctx.host_ip])
  if ($ctx.ssh_flag | is-not-empty) { $args = ($args | append $ctx.ssh_flag) }
  $args | append $ctx.rest | append $target
}

# Deploy only the NixOS system profile.
export def "main nixos" [
  keys_file: string
  node_name: string
  local_system: string
  ...args: string
] {
  let ctx = (deploy-preamble $keys_file $local_system ...$args)
  if ($ctx.ssh_flag | is-not-empty) { $env.NIX_SSHOPTS = $"-i ($ctx.identity)" }
  ^deploy ...(build-deploy-args $ctx $".#($node_name).system")
}

# Deploy a single service profile.
export def "main service" [
  keys_file: string
  node_name: string
  local_system: string
  profile: string
  ...args: string
] {
  let ctx = (deploy-preamble $keys_file $local_system ...$args)
  if ($ctx.ssh_flag | is-not-empty) { $env.NIX_SSHOPTS = $"-i ($ctx.identity)" }
  ^deploy ...(build-deploy-args $ctx $".#($node_name).($profile)")
}

# Deploy system + all service profiles.
export def "main all" [
  keys_file: string
  node_name: string
  local_system: string
  --service-cleanup: string  # semicolon-separated reset-failed commands
  ...args: string
] {
  let ctx = (deploy-preamble $keys_file $local_system ...$args)
  if ($ctx.ssh_flag | is-not-empty) { $env.NIX_SSHOPTS = $"-i ($ctx.identity)" }

  if ($service_cleanup != null) and ($service_cleanup | is-not-empty) {
    ^ssh -i $ctx.identity $"root@($ctx.host_ip)" $service_cleanup
  }

  ^deploy ...(build-deploy-args $ctx $".#($node_name)")
}

export def main [] {
  print "usage: deploy <nixos|service|all>"
}
