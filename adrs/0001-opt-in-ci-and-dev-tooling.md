# ADR 0001: Opt-in CI and dev tooling as omnix building blocks

- Status: Accepted
- Date: 2026-06-13

## Context

omnix's founding rule is **"No application opinions"** (see `SPEC.md` Design
Constraints and `AGENTS.md`): omnix handles infrastructure, while Rust/frontend
builds, dev shells, and CI pipelines stay in each consumer repo.

The consolidation program (see `ROADMAP.md`) lifts capabilities that have
re-diverged across the consumer repos (`st0x.liquidity`, `st0x.rest.api`,
`moneymentum`) back into omnix so every consumer shares one implementation. Two
of those capabilities — the optimized **CI** and the generic **nushell
version-control tooling** (`gitbutler-stack`, `pr-stack-footer`, `pr-template`)
— appear to collide head-on with "no CI pipeline definitions" and "no dev shell
configuration."

If we read the rule literally we either (a) keep CI and dev tooling per-repo and
accept perpetual re-divergence — the exact problem the consolidation exists to
fix — or (b) smuggle CI/dev-shell config into NixOS modules and break the rule's
intent. Neither is acceptable. The rule needs a sharper line.

## Decision

The forbidden thing is **forced application config**, not the mere mention of CI
or tooling. We distinguish:

- **Forced application config (forbidden).** Anything every consumer is made to
  carry, or that encodes one application's build:
  - CI or dev-shell configuration inside `nixosModules` — nothing under
    `omnix.*` module options configures CI or a dev shell.
  - Rust/frontend build logic as first-class omnix primitives (nextest
    matrices, bun builds, `prep.sh`, solidity caching).
  - A blessed/dictated dev-shell base or env-var wiring (`DATABASE_URL`,
    `SQLX_OFFLINE`, devenv-vs-mkShell choice).
  - Application-specific systemd timers or services.

- **Opt-in building blocks (allowed).** Things a consumer must explicitly call
  or wire, where a non-user pays nothing:
  - Pure lib functions that **emit artifacts**: `mkCI` / `mkDeployWorkflow`
    produce workflow YAML plus a drift-check derivation; `mkNuScript`,
    `mkSmoke`, `mkUptimeRobotMonitors`.
  - Flake `apps` / `packages` — e.g. generic version-control nushell scripts a
    consumer runs with `nix run omnix#pr-stack-footer` or inherits into its own
    shell.
  - Inert **reusable** GitHub workflows under `.github/workflows/` (callable via
    `uses: data-cartel/omnix/.github/workflows/<x>.yml@<ref>`), which do nothing
    until a consumer writes a caller.

These building blocks live in `lib/`, `scripts/`, and `.github/workflows/` —
**never** in `modules/`. "Pure Nix: no wrapper CLIs" is preserved: a generator
that emits text is a Nix function, not a runtime CLI, and a flake app is opt-in.

### The test

> Does a consumer opt in by calling or wiring it, and does a non-user pay
> nothing?

If yes, it is a building block and belongs in omnix. If it forces config on
every consumer or encodes one app's build, it is an application opinion and
stays in the consumer repo.

## Consequences

- omnix gains `lib/ci.nix`, `lib/ci-deploy.nix`, `lib/nu.nix`, `lib/smoke.nix`,
  `scripts/*.nu`, and reusable `.github/workflows/*.yml`. None land in
  `modules/`; nothing under `omnix.*` module options configures CI or dev shells.
- `SPEC.md` and `AGENTS.md` "No application opinions" are refined (not removed)
  to encode the forced-config-vs-building-block test.
- Drift is self-policed: `mkCI`/`mkDeployWorkflow` each expose a `check`
  derivation added to flake `checks`, so generated workflow YAML that drifts
  from its generator fails `nix flake check`.
- Carry cost: omnix now owns these generators. Mitigated by the opt-in nature
  (consumers pay only if they wire them) and the drift checks.

## Alternatives considered

- **Keep CI and nushell tooling per-repo.** Rejected: re-divergence is the
  problem the consolidation exists to solve.
- **Model CI as NixOS module options under `omnix.*`.** Rejected: couples host
  configuration to CI and violates the rule's core intent.
- **Ship app build logic (nextest matrices, bun) as omnix primitives.**
  Rejected: that is an application opinion. Consumers needing it pass raw job
  entries, keeping the opinion in their repo.
