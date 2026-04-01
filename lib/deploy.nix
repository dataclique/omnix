{ deploy-rs }:

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

  enabledServices = builtins.filter (name: services.${name}.enabled) (builtins.attrNames services);
  enabledSites = builtins.filter (name: staticSites.${name}.enabled) (builtins.attrNames staticSites);

  mkServiceProfile =
    name:
    let
      markerFile = "/run/${nodeName}/${name}.ready";
    in
    activate.custom package (
      builtins.concatStringsSep " && " [
        "systemctl stop ${name} || true"
        "rm -f ${markerFile}"
        "mkdir -p /run/${nodeName}"
        "touch ${markerFile}"
        "systemctl restart ${name}"
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

      serviceCleanup = builtins.concatStringsSep "; " (
        map (name: "systemctl reset-failed ${name} || true") enabledServices
      );

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

      deployAll = pkgs.writeShellApplication {
        name = "deploy-all";
        runtimeInputs = deployInputs ++ [ pkgs.openssh ];
        text = ''
          ${deployPreamble}

          ssh -i "$identity" "root@$host_ip" '${serviceCleanup}'

          deploy ${deployFlags} --hostname "$host_ip" ''${ssh_flag:+"$ssh_flag"} "$@" .#${nodeName}
        '';
      };
    };
}
