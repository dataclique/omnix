use std/assert
use bootstrap.nu *

let script_dir = (path self | path dirname)

def "test update-keys-nix single-line" [] {
  let fixture = (mktemp)
  '{ host = "ssh-ed25519 AAAA_old_key"; }' | save -f $fixture
  update-keys-nix $fixture "my-node" "ssh-ed25519 AAAA_new_key"
  let content = (open $fixture --raw)
  assert ($content | str contains "ssh-ed25519 AAAA_new_key")
  assert not ($content | str contains "AAAA_old_key")
  rm -f $fixture
}

def "test update-keys-nix multi-line indented" [] {
  let fixture = (mktemp)
  "{\n  host =\n      \"ssh-ed25519 AAAA_old_key\";\n}" | save -f $fixture
  update-keys-nix $fixture "my-node" "ssh-ed25519 AAAA_new_key"
  let content = (open $fixture --raw)
  assert ($content | str contains "ssh-ed25519 AAAA_new_key")
  assert not ($content | str contains "AAAA_old_key")
  rm -f $fixture
}

def "test update-keys-nix scoped to node" [] {
  let fixture = (mktemp)
  "{\n  node-a = {\n    host = \"ssh-ed25519 AAAA_key_a\";\n  };\n  node-b = {\n    host = \"ssh-ed25519 AAAA_key_b\";\n  };\n}" | save -f $fixture
  update-keys-nix $fixture "node-b" "ssh-ed25519 AAAA_new_b"
  let content = (open $fixture --raw)
  assert ($content | str contains "ssh-ed25519 AAAA_new_b")
  assert ($content | str contains "ssh-ed25519 AAAA_key_a") # node-a unchanged
  assert not ($content | str contains "AAAA_key_b")
  rm -f $fixture
}

def main [] {
  let tests = (scope commands
    | where ($it.type == "custom") and ($it.name | str starts-with "test ")
    | get name)

  let bootstrap_path = ($script_dir | path join "bootstrap.nu")
  let test_path = ($script_dir | path join "bootstrap.test.nu")

  for test_name in $tests {
    print $"  running: ($test_name)"
    nu -c $"use std/assert; use ($bootstrap_path) *; source ($test_path); ($test_name)"
  }

  print $"(ansi green)all ($tests | length) tests passed(ansi reset)"
}
