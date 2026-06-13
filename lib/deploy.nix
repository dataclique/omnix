{ deploy-rs, lib }:

{
  self,
  nodeName,
  services,
  package,
  # Opt-in per-service activation hooks, keyed by service name. Each may set:
  #   secret        path to an age-encrypted file, decrypted on-host with the
  #                 host key to /run/<nodeName>/<name>.secret (mode 0400)
  #   validateBin   binary in the service profile run before restart; a non-zero
  #                 exit fails activation so deploy-rs rolls back
  #   validateArgs  arguments to validateBin
  #   chownPaths    paths to chown after decrypt (chownOwner required)
  #   chownOwner    "user:group" for chownPaths
  #   recordGitRev  write the deployed git rev to /run/<nodeName>/<name>.git-rev
  serviceHooks ? { },
  hostKey ? "/etc/ssh/ssh_host_ed25519_key",
  rageBin ? "/run/current-system/sw/bin/rage",
  # Deploy transport: how the deploy scripts reach the host.
  #   { kind = "ip"; }                              resolve the public IPv4 from
  #                                                 terraform state (default)
  #   { kind = "tailnet"; magicDnsName = "..."; }   deploy over the tailnet
  #                                                 MagicDNS name when connected,
  #                                                 else fall back to the IP
  transport ? {
    kind = "ip";
  },
  staticSites ? { },
  nixosConfig ? null,
  targetSystem ? "x86_64-linux",
}:

let
  system = targetSystem;
  inherit (deploy-rs.lib.${system}) activate;
  profileBase = "/nix/var/nix/profiles/per-service";
  siteBase = "/var/lib/sites";

  srv = import ./services.nix { inherit lib; } {
    inherit services;
    project = nodeName;
  };

  # Deterministic activation order (see lib/services.nix). Static sites have no
  # systemd unit and follow the services.
  enabledServices = srv.orderedNames;
  enabledSites = builtins.filter (name: staticSites.${name}.enabled or true) (
    builtins.attrNames staticSites
  );

  gitRev = self.rev or self.dirtyRev or "unknown";

  # Marker file gates the unit's ConditionPathExists. Touch it BEFORE restart so
  # systemd actually starts the unit (an absent marker makes systemd silently
  # skip the unit and return success), and remove it if the restart fails so a
  # broken unit can't satisfy the condition on the next system activation.
  #
  # Optional per-service hooks (serviceHooks.<name>) splice the secret pipeline
  # in between: decrypt -> validate -> chown -> record git rev, all before the
  # marker so a failure rolls back without leaving the unit startable.
  mkServiceProfile =
    name:
    let
      svc = srv.enabled.${name};
      markerFile = svc.markerFile;
      hooks = serviceHooks.${name} or { };
      secretPath = "/run/${nodeName}/${name}.secret";

      decryptCmds = lib.optional (
        hooks ? secret
      ) "${rageBin} -d -i ${hostKey} ${hooks.secret} | install -D -m 0400 /dev/stdin ${secretPath}";

      validateCmds =
        lib.optional (hooks ? validateBin)
          "${svc.profilePath}/bin/${hooks.validateBin} ${
            builtins.concatStringsSep " " (hooks.validateArgs or [ ])
          }";

      # Parenthesised so the `|| true` is scoped to chown only — without it the
      # `||` would rescue a failure from an earlier command in the `&&` chain
      # (e.g. a failed validate), defeating the rollback.
      chownCmds =
        lib.optional ((hooks.chownPaths or [ ]) != [ ] && (hooks.chownOwner or null) != null)
          "(chown ${hooks.chownOwner} ${builtins.concatStringsSep " " hooks.chownPaths} 2>/dev/null || true)";

      gitRevCmds = lib.optional (hooks.recordGitRev or false
      ) "echo '${gitRev}' > /run/${nodeName}/${name}.git-rev";
    in
    activate.custom package (
      builtins.concatStringsSep " && " (
        [
          "systemctl stop ${name} || true"
          "mkdir -p /run/${nodeName}"
        ]
        ++ decryptCmds
        ++ validateCmds
        ++ chownCmds
        ++ gitRevCmds
        ++ [
          "touch ${markerFile}"
          "systemctl restart ${name} || { rm -f ${markerFile}; exit 1; }"
        ]
      )
    );

  mkProfile = name: {
    path = mkServiceProfile name;
    profilePath = "${profileBase}/${name}";
  };

  mkSiteProfile =
    name: sitePackage:
    activate.custom sitePackage (
      builtins.concatStringsSep " && " [
        "mkdir -p ${siteBase}"
        "ln -sfn ${sitePackage} ${siteBase}/${name}"
        "systemctl reload nginx || systemctl restart nginx"
      ]
    );

in
{
  config = {
    nodes.${nodeName} = {
      hostname = "MUST_OVERRIDE_HOSTNAME";
      sshUser = "root";
      user = "root";

      profilesOrder = [ "system" ] ++ enabledServices ++ enabledSites;

      profiles = {
        system.path =
          if nixosConfig != null then
            activate.nixos nixosConfig
          else
            activate.nixos self.nixosConfigurations.${nodeName};
      }
      // builtins.listToAttrs (
        map (name: {
          inherit name;
          value = mkProfile name;
        }) enabledServices
      )
      // builtins.listToAttrs (
        map (name: {
          inherit name;
          value = {
            path = mkSiteProfile name staticSites.${name}.package;
            profilePath = "${profileBase}/${name}";
          };
        }) enabledSites
      );
    };
  };

  wrappers =
    {
      pkgs,
      infraPkgs,
      localSystem,
    }:
    let
      deployInputs = [
        pkgs.rage
        pkgs.jq
        deploy-rs.packages.${localSystem}.deploy-rs
      ]
      ++ lib.optional (transport.kind == "tailnet") pkgs.tailscale;

      # Resolve $host_ip according to the transport. The tailnet path parses the
      # identity once, then prefers the MagicDNS name when connected and falls
      # back to the terraform IP (ipFromState — no second parseIdentity).
      hostResolve =
        if transport.kind == "tailnet" then
          ''
            ${infraPkgs.parseIdentity}
            if tailscale status >/dev/null 2>&1; then
              host_ip="${transport.magicDnsName}"
            else
              echo "Tailscale not connected; resolving host via terraform IP" >&2
              ${infraPkgs.ipFromState}
            fi
          ''
        else
          infraPkgs.resolveIp;

      deployPreamble = ''
        ${hostResolve}

        if [ -z "$host_ip" ]; then
          echo "ERROR: host_ip not resolved" >&2
          exit 1
        fi

        ssh_flag=""
        if [ "$identity" != "$HOME/.ssh/id_ed25519" ]; then
          export NIX_SSHOPTS="-i $identity"
          ssh_flag="--ssh-opts=-i $identity"
        fi
      '';

      deployFlags =
        if localSystem == "x86_64-linux" then "--skip-checks" else "--remote-build --skip-checks";

    in
    {
      deployNixos = pkgs.writeShellApplication {
        name = "deploy-nixos";
        runtimeInputs = deployInputs;
        text = ''
          ${deployPreamble}
          deploy ${deployFlags} --hostname "$host_ip" ''${ssh_flag:+"$ssh_flag"} "$@" .#${nodeName}.system
        '';
      };

      # Like deployNixos but with --boot: stage the new system as the boot
      # default without switching, for changes that need a reboot to apply.
      deployNixosBoot = pkgs.writeShellApplication {
        name = "deploy-nixos-boot";
        runtimeInputs = deployInputs;
        text = ''
          ${deployPreamble}
          deploy ${deployFlags} --boot --hostname "$host_ip" ''${ssh_flag:+"$ssh_flag"} "$@" .#${nodeName}.system
        '';
      };

      deployService = pkgs.writeShellApplication {
        name = "deploy-service";
        runtimeInputs = deployInputs;
        text = ''
          ${deployPreamble}
          profile="''${1:?usage: deploy-service <profile>}"
          shift
          deploy ${deployFlags} --hostname "$host_ip" ''${ssh_flag:+"$ssh_flag"} "$@" ".#${nodeName}.$profile"
        '';
      };

      # reset-failed recovery is handled in-activation by the omnix.services
      # module (system profile activates first), so deployAll no longer needs a
      # separate pre-deploy SSH cleanup pass.
      deployAll = pkgs.writeShellApplication {
        name = "deploy-all";
        runtimeInputs = deployInputs;
        text = ''
          ${deployPreamble}
          deploy ${deployFlags} --hostname "$host_ip" ''${ssh_flag:+"$ssh_flag"} "$@" .#${nodeName}
        '';
      };
    };
}
