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
- Test functions prefixed with `test` for auto-discovery
- Run tests via `nu <name>.test.nu`

**Nix integration:**

- Scripts are nushell files in `scripts/` directory
- Wrapped via nix derivations with nushell + runtimeInputs on PATH
- External commands use caret prefix (`^rage`, `^jq`, `^terraform`)
- Build argument vectors as lists and splat them to avoid string-concatenation
  bugs:

  ```nu
  let argv = ["arg1" "--flag" $value]
  ^cmd ...$argv
  ```

  Never join flags into a single string -- each flag must be a separate list
  element so splatting passes them as distinct arguments.

### Agent implementations & responsibilities

**bootstrap** (`scripts/bootstrap.nu`)
- Responsibilities: provision a DigitalOcean droplet via nixos-anywhere, update host keys (scoped to the target node), optionally rekey secrets
- Public interface: `main` entrypoint — `nu bootstrap.nu <keys_file> <config_name> [--secrets-rules <path>] [...args]`; `update-keys-nix` accepts `keys_file`, `config_name`, and `new_key` to scope replacement to the correct node stanza
- Inputs: `keys_file` (path to `keys.nix`), `config_name` (NixOS flake config), optional `--secrets-rules`, passthrough args (`-i <identity>`)
- Outputs: updated `keys.nix` with new host key for the specified node; rekeyed secrets if `--secrets-rules` provided
- Failure modes: SSH timeout (60 retries × 5 s), empty/malformed host key, key replacement failure (scoped to node stanza) — all surface explicit `error make` messages
- Testing: direct unit tests via `nu scripts/bootstrap.test.nu` (tests `update-keys-nix` with single-line and multi-line fixtures); integration test via the GitHub Actions lifecycle workflow
- Dependencies: `nixos-anywhere`, `ssh`, `ragenix` (optional); calls `common.nu` helpers

**terraform** (`scripts/terraform.nu`)
- Responsibilities: wrap terraform commands with age-encrypted state/vars management
- Public interface: subcommands — `init`, `plan`, `apply`, `destroy`, `import`, `edit-vars`, `rekey`, `remote`, `resolve-ip`
- Inputs: `keys_file` (path to `keys.nix`), optional `-i <identity>`, optional `--secrets-rules` (rekey only), passthrough terraform args
- Outputs: encrypted state/vars files, terraform plan artifacts, SSH sessions (remote)
- Failure modes: missing recipients in `keys.nix`, terraform errors — state re-encrypted before surfacing errors; edit-vars preserves a `.recover` file on encryption failure
- Testing: integration test workflow (terraform → bootstrap → deploy → verify → teardown)
- Dependencies: `terraform`, `rage`, `jq`, `openssh`, `ragenix` (optional); calls `common.nu` helpers

**common** (`scripts/common.nu`)
- Responsibilities: shared helpers — identity parsing, state/vars encryption/decryption, IP resolution, cleanup
- Public interface: exported functions — `parse-identity`, `decrypt-state`, `encrypt-state`, `decrypt-vars`, `encrypt-vars`, `resolve-ip`, `cleanup`, `cleanup-with-plan`
- Inputs: identity file path, keys file, terraform state/vars files in `infra/`
- Outputs: decrypted/encrypted files, `record<identity, host_ip, rest>` from `resolve-ip`
- Failure modes: missing recipients, empty IP — explicit `error make` messages
- Testing: direct unit tests via `nu scripts/common.test.nu` (tests `parse-identity` with various flag combinations); also evaluated indirectly through terraform and bootstrap integration tests
- Dependencies: `rage`, `jq`, `nix` (for `nix eval`)

**deploy** (`scripts/deploy.nu`, wrapped by `lib/deploy.nix`)
- Responsibilities: orchestrate deploy-rs deployments for NixOS system, individual services, and static sites
- Public interface: subcommands — `nixos`, `service`, `all`
- Inputs: `keys_file`, `nodeName`, `localSystem`, optional `--service-cleanup`
- Outputs: deploy-rs activation on remote host
- Failure modes: deploy-rs activation failures, SSH errors
- Testing: integration test workflow deploy step
- Dependencies: `deploy-rs`, `rage`, `jq`, `openssh`; calls `common.nu` helpers

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
