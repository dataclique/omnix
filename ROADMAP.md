# Roadmap

## Migrate scripts to nushell

All omnix shell scripts (terraform wrappers, bootstrap, deploy, remote) are
currently bash embedded in Nix via `writeShellApplication`. Migrate to nushell
for type safety, structured data, testability, and composability.

### Independent migrations (parallelizable)

- [x] scripts/common.nu -- shared helpers (parse-identity, resolve-ip,
      decrypt/encrypt state/vars)
- [x] scripts/terraform.nu -- all terraform tasks (init, plan, apply, destroy,
      import, edit-vars, rekey, remote, resolve-ip)
- [x] scripts/bootstrap.nu -- nixos-anywhere bootstrap
- [x] scripts/deploy.nu -- deploy-rs wrappers (nixos, service, all)

### Dependent on above

- [x] lib/shell.nix -- rewritten to mkNuScript (nushell wrapper infra)
- [x] lib/terraform.nix, lib/bootstrap.nix, lib/deploy.nix -- updated to use
      mkNuScript

### Testing (alongside each migration)

- [x] scripts/common.test.nu -- parse-identity tests
- [ ] scripts/terraform.test.nu -- unit tests for pure helpers
- [ ] scripts/deploy.test.nu -- unit tests for build-deploy-args
- [ ] scripts/bootstrap.test.nu -- unit tests for update-keys-nix

## Refactor to idiomatic Nix

The initial extraction from moneymentum was mechanical copy-paste. This pass
makes it proper library-quality Nix before more consumers adopt.

- [x] Consolidate duplicate `resolveIp` / `parseIdentity` shell fragments --
      extracted to lib/shell.nix, removed redundant lib/remote.nix
- [ ] Organize lib/ more logically -- group related helpers, review module
      boundaries
- [ ] Use NixOS module options consistently -- current lib functions use raw
      attrset args, some could be module options instead for better composition
      and type checking
- [ ] Add `_module.args` passthrough for omnix-specific config so consumers
      don't need to wire specialArgs manually

## Age-based secret management

Build a Rust CLI using the `age` crate that handles the secret lifecycle omnix
consumers need: encrypt secrets to role-based recipients defined in `keys.nix`,
decrypt on-host using the SSH host key, and integrate with deploy-rs activation.
This replaces the ragenix dependency with an omnix-owned tool.

The current pattern in existing deployments: `.toml.age` files committed to git,
deploy-rs activation calls `rage` to decrypt to `/run/agenix/` using the host's
`/etc/ssh/ssh_host_ed25519_key`, services read plaintext from tmpfs. The new
tool must support this exact workflow.

```mermaid
graph LR
  A[Scaffold Rust crate] --> B[age encrypt/decrypt core]
  B --> C[keys.nix role parsing]
  B --> D[Host key decryption]
  B --> F[NixOS module]
  B --> G[deploy-rs activation]
  C --> E[CLI: encrypt/decrypt/rekey]
  D --> E
  E --> H[Integrate into omnix flake]
  F --> H
  G --> H
```

- [ ] Scaffold `crates/omnix-age/` Rust crate with `age` dependency
- [ ] Implement encrypt/decrypt using age -- encrypt to multiple recipients,
      decrypt with SSH identity file
- [ ] Support `keys.nix` role-based recipient resolution -- parse the Nix
      attrset to extract public keys per role
- [ ] Support on-host decryption using SSH host key --
      `/etc/ssh/ssh_host_ed25519_key` as identity, same as ragenix today
- [ ] CLI: `omnix-age encrypt`, `omnix-age decrypt`, `omnix-age rekey`
- [ ] Integrate into omnix flake as a package
- [ ] Add NixOS module to omnix -- declares secrets with encryption rules,
      replaces ragenix module import
- [ ] Add deploy-rs activation that uses omnix-age instead of raw rage commands
- [ ] Optional: implement secretspec `Provider` trait to emit `secretspec.toml`
      -- if the secretspec SDK is available, wire the `Provider` trait so the
      CLI can produce structured secret declarations alongside age encryption

## CI generation

A lib function that generates GitHub Actions workflow YAML from Nix config,
keeping CI in sync with the build system -- when packages change, CI updates
automatically.

- [ ] Design CI generation API -- take a list of checks/builds and produce
      `.github/workflows/ci.yml` content
- [ ] Support common patterns: parallel jobs, nix cache, deploy-on-push,
      submodule caching, SSH key setup
- [ ] Generate deploy job that uses omnix deploy wrappers
- [ ] Support matrix strategies for multi-target builds

## Integration test flow

Validate the full omnix lifecycle end-to-end: provision infrastructure via
terraform, bootstrap with nixos-anywhere, deploy sample services, verify access
via remote, then tear everything down.

- [x] GitHub Actions workflow for full lifecycle (manual trigger)
- [x] Scaffold test project from template, provision, bootstrap, deploy, verify
- [x] Teardown via terraform destroy (always runs, even on failure)
- [ ] Add service-level verification -- deploy a sample service, hit its HTTP
      endpoint, verify response
- [ ] Redeploy test -- deploy a different service profile, verify switchover
- [ ] `mkIntegrationTest` lib function -- let consumers define their own
      lifecycle test flows

## Not epic

- [ ] Add Hetzner cloud modules -- alternative to DigitalOcean for when we need
      better price/performance or EU hosting
- [ ] services-flake integration -- portable service management without
      systemd/NixOS dependency (process-compose backend)

## Completed: Refactoring and new modules

- [x] Migrated from flake-utils to flake-parts
- [x] Added git-hooks.nix integration with mkGitHooks lib function
- [x] Switched from nixfmt-classic to nixfmt, added formatter output
- [x] Added omnix.acme module (Let's Encrypt)
- [x] Added omnix.firewall enableHTTP/enableHTTPS convenience flags
- [x] Added omnix.services logrotate integration via logDir option
- [x] Added omnix.staticSites module (nginx vhosts via symlink swap)
- [x] Hardened shell helpers (chmod 600 on decrypted files, jq -e)
- [x] Parameterized targetSystem in deploy.nix
- [x] Added integration test workflow to template
- [x] Added resolveIp package to template

## Completed: Extract and publish omnix

Extracted from moneymentum, published as standalone library at
`data-cartel/omnix`. Moneymentum migrated as first consumer.

- [x] Extract omnix from moneymentum into standalone flake
- [x] Move omnix to its own repo (`data-cartel/omnix`)
- [x] Wire moneymentum as first consumer
- [x] All 8 NixOS modules implemented with typed option interfaces
- [x] All 4 lib functions (mkTerraform, mkDeploy, mkBootstrap, mkGitHooks)
- [x] Flake template (`do-service`) scaffolds complete projects
