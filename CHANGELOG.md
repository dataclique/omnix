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
