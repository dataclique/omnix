{ deploy-rs, lib }:

{
  self,
  nodeName,
  services,
  package,
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

  # Marker file gates the unit's ConditionPathExists. Touch it BEFORE restart so
  # systemd actually starts the unit (an absent marker makes systemd silently
  # skip the unit and return success), and remove it if the restart fails so a
  # broken unit can't satisfy the condition on the next system activation.
  mkServiceProfile =
    name:
    let
      markerFile = srv.enabled.${name}.markerFile;
    in
    activate.custom package (
      builtins.concatStringsSep " && " [
        "systemctl stop ${name} || true"
        "mkdir -p /run/${nodeName}"
        "touch ${markerFile}"
        "systemctl restart ${name} || { rm -f ${markerFile}; exit 1; }"
      ]
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
      ];

      deployPreamble = ''
        ${infraPkgs.resolveIp}

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
