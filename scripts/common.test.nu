use std/assert
use common.nu *

let script_dir = (path self | path dirname)

def "test parse-identity with flag" [] {
  let result = (parse-identity "-i" "/tmp/my-key" "extra" "args")
  assert equal $result.identity "/tmp/my-key"
  assert equal $result.rest ["extra" "args"]
}

def "test parse-identity with long flag" [] {
  let result = (parse-identity "--identity" "/tmp/my-key" "extra")
  assert equal $result.identity "/tmp/my-key"
  assert equal $result.rest ["extra"]
}

def "test parse-identity without flag" [] {
  let result = (parse-identity "extra" "args")
  assert ($result.identity | str ends-with ".ssh/id_ed25519")
  assert equal $result.rest ["extra" "args"]
}

def "test parse-identity empty args" [] {
  let result = (parse-identity)
  assert ($result.identity | str ends-with ".ssh/id_ed25519")
  assert equal $result.rest []
}

def main [] {
  let tests = (scope commands
    | where ($it.type == "custom") and ($it.name | str starts-with "test ")
    | get name)

  let common_path = ($script_dir | path join "common.nu")
  let test_path = ($script_dir | path join "common.test.nu")

  for test_name in $tests {
    print $"  running: ($test_name)"
    nu -c $"use std/assert; use ($common_path) *; source ($test_path); ($test_name)"
  }

  print $"(ansi green)all ($tests | length) tests passed(ansi reset)"
}
