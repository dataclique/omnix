#!/usr/bin/env nu
# Tests for pr-stack-footer.nu. Run directly: `nu pr-stack-footer.test.nu`
# (also runs in the package's checkPhase). Exits nonzero on the first
# failed assertion. Only the pure footer functions are exercised; the
# `but`/`gh` I/O in `main` is not invoked.

use std assert
use ./pr-stack-footer.nu *

# build-footer numbers the stack base-first (position 1 = bottom), lists
# it top-first, and points at the current PR -- byte-for-byte the shape
# GitButler emits.
const EXPECTED = "<!-- GitButler Footer Boundary Top -->
---
This is **part 2 of 3 in a stack** made with GitButler:
- <kbd>&nbsp;3&nbsp;</kbd> #268
- <kbd>&nbsp;2&nbsp;</kbd> #266 👈
- <kbd>&nbsp;1&nbsp;</kbd> #264
<!-- GitButler Footer Boundary Bottom -->"

assert equal (build-footer [264 266 268] 266) $EXPECTED

# The bottom PR is part 1; the top PR is part N.
assert ((build-footer [264 266 268] 264) | str contains "part 1 of 3")
assert ((build-footer [264 266 268] 268) | str contains "part 3 of 3")

# Exactly one pointer, on the current PR.
assert equal ((build-footer [264 266 268] 266) | split row "👈" | length) 2
assert ((build-footer [264 266 268] 268) | str contains "#268 👈")

# A single-PR lane renders as a 1-of-1 footer so every forest PR carries one.
assert ((build-footer [286] 286) | str contains "part 1 of 1")
assert ((build-footer [286] 286) | str contains "#286 👈")
assert equal ((build-footer [286] 286) | lines | where ($it | str starts-with "- ") | length) 1

# splice-footer replaces an existing footer region and keeps the prose.
let body_with_footer = "## Motivation

Some prose.

<!-- GitButler Footer Boundary Top -->
---
This is **part 5 of 17 in a stack** made with GitButler:
- <kbd>&nbsp;1&nbsp;</kbd> #256
<!-- GitButler Footer Boundary Bottom -->"
let fresh = (build-footer [264 266 268] 264)
let spliced = (splice-footer $body_with_footer $fresh)

assert ($spliced | str contains "## Motivation")
assert ($spliced | str contains "Some prose.")
assert ($spliced | str contains "part 1 of 3")
assert (not ($spliced | str contains "part 5 of 17"))
assert (not ($spliced | str contains "#256"))
# The boundary markers appear exactly once after a splice.
assert equal ($spliced | split row "<!-- GitButler Footer Boundary Top -->" | length) 2

# splice-footer appends when the body has no footer yet, keeping the body.
let bare_body = "## Motivation

No footer here."
let appended = (splice-footer $bare_body $fresh)

assert ($appended | str starts-with "## Motivation")
assert ($appended | str contains "part 1 of 3")
assert ($appended | str contains "<!-- GitButler Footer Boundary Bottom -->")

print "pr-stack-footer: all tests passed"
