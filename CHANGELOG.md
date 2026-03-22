# Changelog

## Unreleased

### Added

- **flake-parts**: Migrated from flake-utils to flake-parts for structured flake
  composition
- **omnix.acme**: ACME/Let's Encrypt certificate management module
- **omnix.staticSites**: Nginx virtual hosts via symlink swap for zero-rebuild
  frontend deploys
- **omnix.firewall**: `enableHTTP` and `enableHTTPS` convenience flags
- **omnix.services**: `logDir` option with automatic logrotate configuration
- **lib.mkGitHooks**: Pre-commit hooks (nixfmt, deadnix, taplo, optional
  rustfmt) via git-hooks.nix
- **lib.mkDeploy**: `targetSystem` parameter (default x86_64-linux),
  `staticSites` support
- **Integration test**: GitHub Actions workflow for full lifecycle testing
  (terraform → bootstrap → deploy → verify → teardown)
- **Template**: Integration test workflow and `resolveIp` package added to
  do-service template
- **Nushell guidelines**: AGENTS.md now includes nushell code style and testing
  conventions
- `formatter` flake output (nixfmt)
- `devShells.default` with git-hooks shellHook

### Changed

- Switched from nixfmt-classic to nixfmt
- `nixosModules.default` now includes upstream disko and ragenix modules
- Shell helpers hardened: `chmod 600` on decrypted terraform files, `jq -e` for
  fail-fast on missing IP
- Rewrote `lib/shell.nix` to expose `mkNuScript` for nushell script wrapping;
  removed prior bash/age helper exports (`parseIdentity`, `resolveIp`,
  `decryptState`, etc.)
- `pkgs.openssh` added to bootstrap runtimeInputs

### Removed

- `lib.mkRemote` (redundant with `mkTerraform`'s `remote` output)
- `lib/remote.nix`
- `flake-utils` dependency (replaced by flake-parts)

### Breaking changes / Migration

- **`lib.mkRemote` removed**: Consumers calling `lib.mkRemote` must switch to
  the `remote` output of `mkTerraform`. Replace `omnix.lib.mkRemote { ... }`
  with the `remote` attribute returned by `omnix.lib.mkTerraform { ... }`.

- **Bash/age helper exports removed** (`parseIdentity`, `resolveIp`,
  `decryptState`): `lib/shell.nix` no longer exports these bash functions.
  Impact: any scripts or packages that referenced
  `omnix.lib.parseIdentity`, `omnix.lib.resolveIp`, or
  `omnix.lib.decryptState` will fail to evaluate. Replacement: use
  `mkNuScript` from the rewritten `lib/shell.nix` to wrap nushell scripts
  that call the equivalent nushell helpers in `scripts/common.nu`, or port
  existing bash helpers to nushell.

- **`flake-utils` replaced by `flake-parts`**: Consumers that override or
  extend the omnix flake via `flake-utils.lib.eachDefaultSystem` must migrate
  to `flake-parts.lib.mkFlake` and `perSystem`. Update your `flake.nix`
  inputs to replace `flake-utils` with `flake-parts` and restructure outputs
  using `perSystem` modules.
