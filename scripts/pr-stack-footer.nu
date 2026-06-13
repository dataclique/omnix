#!/usr/bin/env nu
# Rebuild the GitButler stack-navigation footer on every PR in each
# multi-branch stack and splice it into the PR bodies. GitButler writes
# the footer when it opens or pushes a PR, but a no-op push never rewrites
# it, so after a rebase or a branch add/remove the footers go stale (list
# merged PRs, wrong position/total) or are missing entirely. This
# recomputes each stack's footer from the live `but status` and updates
# the PRs via gh.
#
# Usage:
#   pr-stack-footer            # dry run: print the planned footer per PR
#   pr-stack-footer --apply    # write the footers to the PRs via gh

const TOP_MARKER = "<!-- GitButler Footer Boundary Top -->"
const BOTTOM_MARKER = "<!-- GitButler Footer Boundary Bottom -->"

# Build the footer block for one PR, given its stack's PR numbers ordered
# base -> tip (position 1 is the bottom of the stack). The list runs
# top-first, the current PR carries the pointer, matching GitButler's
# own output.
export def build-footer [prs: list, current: int]: nothing -> string {
  let total = ($prs | length)
  let current_position = (($prs | enumerate | where item == $current | get index | first) + 1)

  let rows = (
    $prs
    | enumerate
    | reverse
    | each {|entry|
        let position = ($entry.index + 1)
        let pointer = if ($entry.item == $current) { " 👈" } else { "" }
        $"- <kbd>&nbsp;($position)&nbsp;</kbd> #($entry.item)($pointer)"
      }
  )

  [
    $TOP_MARKER
    "---"
    $"This is **part ($current_position) of ($total) in a stack** made with GitButler:"
  ]
  | append $rows
  | append $BOTTOM_MARKER
  | str join "\n"
}

# Replace the footer region of a PR body with a fresh footer, or append
# the footer when the body has none. Content outside the boundary markers
# is preserved verbatim.
export def splice-footer [body: string, footer: string]: nothing -> string {
  if (($body | str contains $TOP_MARKER) and ($body | str contains $BOTTOM_MARKER)) {
    let before = ($body | split row $TOP_MARKER | first)
    let after = ($body | split row $BOTTOM_MARKER | last)
    $"($before)($footer)($after)"
  } else {
    $"($body | str trim --right)\n\n($footer)\n"
  }
}

# PR numbers per stack, ordered base -> tip. Every stack carrying at least
# one PR gets a footer -- including single-PR lanes, which render as a
# "part 1 of 1" footer so every PR in the forest carries the section.
def stacks-with-prs []: record -> list {
  $in.stacks
  | each {|stack|
      $stack.branches
      | reverse
      | each {|branch| $branch.reviewId? | parse-pr-number }
      | compact
    }
  | where {|prs| ($prs | length) >= 1}
}

# Extract the integer PR number from a GitButler reviewId like "(#352)".
def parse-pr-number []: any -> any {
  let review_id = $in

  if ($review_id | is-empty) {
    return null
  }

  let matched = ($review_id | parse --regex '#(?<num>\d+)')

  if ($matched | is-empty) { null } else { $matched.0.num | into int }
}

def main [--apply]: nothing -> any {
  let stacks = (^but status -j | from json | stacks-with-prs)

  for prs in $stacks {
    for pr in $prs {
      let footer = (build-footer $prs $pr)

      if $apply {
        let body = (^gh pr view $pr --json body | from json | get body)
        let updated = (splice-footer $body $footer)
        ^gh pr edit $pr --body $updated
        print $"updated #($pr)"
      } else {
        let position = (($prs | enumerate | where item == $pr | get index | first) + 1)
        print $"would update #($pr): part ($position) of ($prs | length)"
      }
    }
  }
}
