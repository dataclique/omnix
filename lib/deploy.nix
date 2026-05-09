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
        "ln -sfnT ${sitePackage} ${siteBase}/${name}"
        "systemctl reload nginx || systemctl restart nginx"
      ]
    );

  scriptsDir = ../scripts;

in
{
  config = {
    nodes.${nodeName} = {
      hostname = "MUST_OVERRIDE_HOSTNAME";
      sshUser = "root";
      user = "root";

      profilesOrder = [
        "system"
      ]
      ++ map (name: "service:${name}") enabledServices
      ++ map (name: "site:${name}") enabledSites;

      profiles = {
        system.path =
          if nixosConfig != null then
            activate.nixos nixosConfig
          else
            activate.nixos self.nixosConfigurations.${nodeName};
      }
      // builtins.listToAttrs (
        map (name: {
          name = "service:${name}";
          value = mkProfile name;
        }) enabledServices
      )
      // builtins.listToAttrs (
        map (name: {
          name = "site:${name}";
          value = {
            path = mkSiteProfile name staticSites.${name}.package;
            profilePath = "${profileBase}/site-${name}";
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
      shell = import ./shell.nix { inherit pkgs scriptsDir; };
      inherit (shell) mkNuScript;

      deployInputs = [
        pkgs.rage
        pkgs.jq
        pkgs.openssh
        deploy-rs.packages.${localSystem}.deploy-rs
      ];

      serviceCleanup = builtins.concatStringsSep "; " (
        map (name: "systemctl reset-failed ${name} || true") enabledServices
      );

    in
    {
      deployNixos = mkNuScript {
        name = "deploy-nixos";
        script = "deploy.nu";
        subcommand = "nixos";
        runtimeInputs = deployInputs;
        extraArgs = [
          (toString infraPkgs.keysFile or "keys.nix")
          nodeName
          localSystem
        ];
      };

      deployService = mkNuScript {
        name = "deploy-service";
        script = "deploy.nu";
        subcommand = "service";
        runtimeInputs = deployInputs;
        extraArgs = [
          (toString infraPkgs.keysFile or "keys.nix")
          nodeName
          localSystem
        ];
      };

      deployAll = mkNuScript {
        name = "deploy-all";
        script = "deploy.nu";
        subcommand = "all";
        runtimeInputs = deployInputs;
        extraArgs = [
          (toString infraPkgs.keysFile or "keys.nix")
          nodeName
          localSystem
          "--service-cleanup"
          serviceCleanup
        ];
      };
    };
}
