# Generates a GitHub Actions CI workflow as YAML from a Nix description, so CI
# stays in sync with the build system instead of drifting per-repo. Returns the
# generated workflow file as a derivation; pair it with a drift check (build the
# file and diff it against the committed copy) in flake `checks`.
#
# An opt-in building block (see adrs/0001): omnix never configures CI in a NixOS
# module. The `nix` field parameterises the install/cache stack that has
# re-diverged across consumers — the default (Determinate + magic-nix-cache)
# needs no Cachix org; consumers select nix-quick-install + cachix as needed.
{
  pkgs,
  name ? "CI",
  on ? {
    push.branches = [
      "master"
      "main"
    ];
    pull_request = null;
  },
  permissions ? {
    contents = "read";
  },
  runner ? "ubuntu-latest",
  timeoutMinutes ? 20,
  nix ? { },
  # Jobs: attrset of jobId -> { name?; run = [ "<shell>" ... ]; }. Each job gets
  # the nix install/cache setup steps prepended. `run` entries are named nix
  # invocations, not app build logic (that stays in the consumer repo).
  jobs ? {
    flake-check = {
      name = "Flake check";
      run = [ "nix flake check" ];
    };
  },
}:

let
  inherit (pkgs) lib;
  yaml = pkgs.formats.yaml { };

  nixCfg = {
    installer = "determinate";
    cache = "magic";
    cachixName = null;
  }
  // nix;

  installerStep =
    if nixCfg.installer == "nix-quick-install" then
      { uses = "nixbuild/nix-quick-install-action@v30"; }
    else if nixCfg.installer == "determinate" then
      { uses = "DeterminateSystems/nix-installer-action@v22"; }
    else
      throw "mkCI: unknown nix.installer '${nixCfg.installer}' (expected determinate | nix-quick-install)";

  cacheSteps =
    if nixCfg.cache == "magic" then
      [ { uses = "DeterminateSystems/magic-nix-cache-action@v13"; } ]
    else if nixCfg.cache == "cachix" then
      [
        {
          uses = "cachix/cachix-action@v15";
          "with" = {
            name =
              if nixCfg.cachixName != null then
                nixCfg.cachixName
              else
                throw "mkCI: nix.cache = \"cachix\" requires nix.cachixName";
            authToken = "\${{ secrets.CACHIX_AUTH_TOKEN }}";
          };
        }
      ]
    else if nixCfg.cache == "none" then
      [ ]
    else
      throw "mkCI: unknown nix.cache '${nixCfg.cache}' (expected magic | cachix | none)";

  setupSteps = [
    { uses = "actions/checkout@v4"; }
    installerStep
  ]
  ++ cacheSteps;

  mkJob = jobId: job: {
    name = job.name or jobId;
    runs-on = runner;
    timeout-minutes = timeoutMinutes;
    steps = setupSteps ++ map (cmd: { run = cmd; }) job.run;
  };

  workflow = {
    inherit name on permissions;
    jobs = lib.mapAttrs mkJob jobs;
  };
in
{
  workflow = yaml.generate "${name}.yml" workflow;
}
