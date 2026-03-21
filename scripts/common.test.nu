use std/assert
use common.nu *

def "test parse-identity with flag" [] {
  let result = (parse-identity "-i" "/tmp/my-key" "extra" "args")
  assert equal $result.identity "/tmp/my-key"
  assert equal $result.rest ["extra" "args"]
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

  for test_name in $tests {
    print $"  running: ($test_name)"
    nu -c $"use std/assert; use common.nu *; source common.test.nu; ($test_name)"
  }

  print $"(ansi green)all ($tests | length) tests passed(ansi reset)"
}
