# Validate that omnix examples are internally consistent.
# Checks that proxy ports in staticSites have corresponding service configs.

use std/assert

def extract-proxy-ports [os_file: string]: nothing -> list<int> {
  let content = (open $os_file --raw)
  $content
    | parse --regex 'proxyPass\s*=\s*"http://127\.0\.0\.1:(\d+)'
    | get capture0
    | each {|p| $p | into int }
}

def extract-service-ports [config_dir: string]: nothing -> list<int> {
  if not ($config_dir | path exists) { return [] }
  glob $"($config_dir)/*.toml"
    | each {|f|
      let content = (open $f)
      if ($content | get -o server.port) != null {
        $content | get server.port
      }
    }
    | flatten
}

def validate-example [example_dir: string] {
  let os_file = $"($example_dir)/os.nix"
  let config_dir = $"($example_dir)/config"

  if not ($os_file | path exists) {
    error make { msg: $"($os_file) does not exist" }
  }

  let proxy_ports = (extract-proxy-ports $os_file)
  if ($proxy_ports | is-empty) { return }

  let service_ports = (extract-service-ports $config_dir)

  let missing = ($proxy_ports | where {|p| not ($p in $service_ports) })
  if ($missing | is-not-empty) {
    error make {
      msg: $"($example_dir): proxy ports ($missing) have no matching service config in ($config_dir). Service configs define ports: ($service_ports)"
    }
  }

  print $"  ✓ ($example_dir): all proxy ports match service configs"
}

export def main [examples_dir: string = "examples"] {
  let examples = (
    (glob $"($examples_dir)/*/os.nix") ++ (glob $"($examples_dir)/os.nix")
    | each {|f| $f | path dirname }
    | uniq
  )

  if ($examples | is-empty) {
    error make { msg: $"no examples found in ($examples_dir)" }
  }

  for example in $examples {
    validate-example $example
  }

  print $"all ($examples | length) examples validated"
}
