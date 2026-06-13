# AGENTS.md

Rules and guidelines for AI agents working in this repository.

---

## Project Direction

omnix is a composable Nix infrastructure library. See [SPEC.md](./SPEC.md) for
the vision and [ROADMAP.md](./ROADMAP.md) for the path.

---

## Development Commands

Enter the dev shell first (`direnv allow`, or `nix develop`) — it provides
`nixfmt`, `deadnix`, `taplo`, and the GitButler CLI `but` (verify with
`but --version`).

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
- Use `pkgs.writeShellApplication` for shell scripts (not raw `writeScript`)
- Include `runtimeInputs` -- never assume tools are on PATH
- All shell scripts must use `set -eo pipefail`

### Testing

- Each module should evaluate without errors in isolation
- Library functions should produce derivations that build
- Template projects should pass `nix flake check`
- Consumer repos using devenv dev shells require `nix flake check --impure`
  (devenv needs impure evaluation to resolve the working directory)

---

## Workflow & Policies

### Version control

This repo uses the **GitButler CLI (`but`)** for all version-control writes. The
dev shell wires in the [`but.nix`](https://github.com/data-cartel/but.nix) flake
input, which puts `but` on `PATH` and symlinks the `gitbutler` agent skill into
`.claude/skills/gitbutler`. Use `but` instead of `git add` / `commit` / `push` /
`branch` / `rebase`; read-only `git` inspection (`status`, `log`, `diff`) is
fine. See the gitbutler skill for the full git-to-but command map. Never
`but push` or open a PR without an explicit instruction.

### Quality checks

Never suppress Nix evaluation errors or warnings.

### No application opinions

omnix handles infrastructure. The line is **forced application config vs.
opt-in building blocks**, not the mere mention of CI or tooling. See
[adrs/0001-opt-in-ci-and-dev-tooling.md](./adrs/0001-opt-in-ci-and-dev-tooling.md).

**Forbidden** (forced application config):

- Rust or frontend build logic as first-class omnix primitives (nextest
  matrices, bun builds, `prep.sh`, solidity caching)
- CI or dev-shell configuration inside `nixosModules` — nothing under `omnix.*`
  module options configures CI or a dev shell
- A blessed/dictated dev-shell base or env-var wiring
- Application-specific systemd timers or services

**Allowed** (opt-in building blocks a consumer explicitly wires, where a
non-user pays nothing) — these live in `lib/`, `scripts/`, `.github/workflows/`,
never in `modules/`:

- Pure lib functions that emit artifacts (`mkCI` / `mkDeployWorkflow` emitting
  workflow YAML + a drift-check derivation; `mkNuScript`, `mkSmoke`)
- Flake `apps` / `packages` (e.g. generic version-control nushell scripts)
- Inert reusable GitHub workflows callable via `uses:`, doing nothing until a
  consumer writes a caller

The test: does a consumer opt in by calling/wiring it, and does a non-user pay
nothing? If yes, it is a building block. If it forces config on every consumer
or encodes one app's build, it is an application opinion — keep it in the
consumer repo.

### Composability

Every module and lib function must work independently. A consumer should be able
to use `omnix.nixosModules.disko` without importing any other omnix module. Test
this by evaluating modules in isolation.

### Backwards compatibility

When changing module option interfaces, preserve the old option with
`lib.mkRenamedOptionModule` or `lib.mkRemovedOptionModule` with a clear
migration message.
