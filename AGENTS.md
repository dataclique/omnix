# AGENTS.md

Rules and guidelines for AI agents working in this repository.

---

## Project Direction

omnix is a composable Nix infrastructure library. See [SPEC.md](./SPEC.md) for
the vision and [ROADMAP.md](./ROADMAP.md) for the path.

---

## Development Commands

```bash
# Check flake validity
nix flake check

# Evaluate modules
nix eval .#nixosModules

# Evaluate lib
nix eval .#lib

# Format Nix files
nixfmt **/*.nix
```

---

## Code Style

### Nix

- Use `lib.mkOption` with proper types for all module options
- Every module must be independently usable (no implicit dependencies on other
  omnix modules)
- Options live under the `omnix.*` namespace
- Use `lib.mkIf cfg.enable` for conditional configuration
- Use `lib.mkDefault` for overridable defaults
- Keep modules focused on a single concern

### Module Interface Design

- Every configurable value must be a module option with a type and description
- Avoid hardcoded project-specific values -- parameterize them
- Prefer `lib.types.str` over `lib.types.path` for values that may come from
  terraform or other dynamic sources
- Group related options under a single `omnix.<module>` prefix

### Library Function Design

- Functions take an attrset of required parameters
- Return an attrset of derivations or values
- Scripts are written in nushell, not bash (see Nushell section below)
- Include `runtimeInputs` -- never assume tools are on PATH

### Nushell

All omnix scripts are written in nushell. No bash.

**Naming:**

- Commands: kebab-case (`resolve-ip`, `decrypt-state`)
- Sub-commands: space-separated kebab-case (`tf apply`, `tf plan`)
- Variables and parameters: snake_case (`host_ip`, `key_file`)
- Flags: kebab-case definition (`--identity (-i)`), snake_case access
  (`$identity`)
- Environment variables: SCREAMING_SNAKE_CASE

**Types and safety:**

- Always type parameters explicitly (`param: string`, not bare `param`)
- Use immutable `let` bindings by default, `mut` only when necessary
- Return values implicitly (last expression) -- no `echo` or explicit `return`
- Use structured data (records, tables) over string parsing
- Use `error make { msg: "..." }` for explicit errors
- Use `try { } catch { |e| }` for error handling

**Script structure:**

- Use the `main` command pattern for script entry points
- Export public API with `export def`, keep helpers as plain `def`
- Keep ≤ 2 positional parameters; use named flags for the rest
- Provide both long and short flag forms (`--identity (-i)`)

**Testing:**

- Test files named `<name>.test.nu` alongside the source
- Use `use std/assert` for assertions (`assert equal`, `assert`, `assert not`)
- Test string properties via piped assertions: `assert ($val | str contains "sub")`
- Test functions prefixed with `test ` for auto-discovery
- Run tests via `nu <name>.test.nu`

**Nix integration:**

- Scripts are nushell files in `scripts/` directory
- Wrapped via nix derivations with nushell + runtimeInputs on PATH
- External commands use caret prefix (`^rage`, `^jq`, `^terraform`)

### Testing

- Each module should evaluate without errors in isolation
- Library functions should produce derivations that build
- Template projects should pass `nix flake check`
- Consumer repos using devenv dev shells require `nix flake check --impure`
  (devenv needs impure evaluation to resolve the working directory)

---

## Workflow & Policies

### Quality checks

Never suppress Nix evaluation errors or warnings.

A comment explaining a poor design choice is never an answer to the design
choice itself. If the code is wrong, fix it. If a reviewer points out a problem,
change the code — don't add a comment defending why it's the way it is.

**Every change must improve something**: A change that doesn't make things
better is worse than no change — it's overhead for reviewers. Acceptable
improvements: correctness, reliability, security, maintainability, documentation
accuracy, and test coverage. Prerequisite or mechanical changes (linting,
formatting, refactors) are acceptable when clearly tied to a follow-up objective
described in the PR description. Trivial extractions (e.g., moving a single
logging line) do not count unless they reduce measurable complexity or support
the stated follow-up objective.

### No application opinions

omnix handles infrastructure. It must never contain:

- Rust build logic
- Frontend build logic
- Dev shell configuration
- CI pipeline definitions
- Application-specific systemd timers or services

These belong in consumer repos. omnix provides the building blocks.

### Composability

Every module and lib function must work independently. A consumer should be able
to use `omnix.nixosModules.disko` without importing any other omnix module. Test
this by evaluating modules in isolation.

### Backwards compatibility

When changing module option interfaces, preserve the old option with
`lib.mkRenamedOptionModule` or `lib.mkRemovedOptionModule` with a clear
migration message.
