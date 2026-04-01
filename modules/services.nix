{ lib, config, ... }:

let
  cfg = config.omnix.services;

  enabledServices = lib.filterAttrs (_: v: v.enabled) cfg.definitions;

  mkService =
    name: svcCfg:
    let
      path = "/nix/var/nix/profiles/per-service/${name}/bin/${svcCfg.bin}";
      markerFile = "/run/${cfg.project}/${name}.ready";
      configFile = cfg.configDir + "/${name}.toml";
      execStart =
        if svcCfg.extraArgs == [ ] then
          "${path} --config ${configFile}"
        else
          builtins.concatStringsSep " " (
            [
              path
              "--config"
              "${configFile}"
            ]
            ++ svcCfg.extraArgs
          );
    in
    {
      description = "${cfg.project} ${svcCfg.bin} (${name})";

      wantedBy = [ ];

      restartIfChanged = false;
      stopIfChanged = false;

      unitConfig = {
        "X-OnlyManualStart" = true;
        ConditionPathExists = markerFile;
      };

      serviceConfig = {
        DynamicUser = cfg.dynamicUser;
        Restart = "always";
        RestartSec = 5;
        ExecStart = execStart;
      }
      // lib.optionalAttrs (cfg.user != null) { User = cfg.user; }
      // lib.optionalAttrs (cfg.group != null) { Group = cfg.group; }
      // lib.optionalAttrs (cfg.dynamicUser && cfg.group != null) {
        SupplementaryGroups = [ cfg.group ];
      }
      // (
        let
          rwPaths = lib.filter (p: p != null) [
            svcCfg.dataDir
            svcCfg.logDir
          ];
        in
        lib.optionalAttrs (rwPaths != [ ]) { ReadWritePaths = rwPaths; }
      );
    };

in
{
  options.omnix.services = {
    project = lib.mkOption {
      type = lib.types.str;
      description = "Project name (used for marker dir /run/<project>/ and service descriptions)";
    };

    user = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "System user to run services as (null uses DynamicUser naming)";
    };

    group = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "System group for services";
    };

    dynamicUser = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Use systemd DynamicUser for service isolation";
    };

    configDir = lib.mkOption {
      type = lib.types.path;
      description = "Path to directory containing <service-name>.toml configs";
    };

    definitions = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            enabled = lib.mkOption {
              type = lib.types.bool;
              default = true;
              description = "Whether this service is deployed and managed";
            };
            bin = lib.mkOption {
              type = lib.types.str;
              description = "Binary name inside the deploy-rs profile (looked up at /nix/var/nix/profiles/per-service/<name>/bin/<bin>)";
            };
            dataDir = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = "Persistent data directory (created via tmpfiles, added to ReadWritePaths)";
            };
            extraArgs = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ ];
              description = "Additional CLI arguments appended after --config <file>";
            };
            logDir = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = "Log directory (created via tmpfiles, logrotate rules auto-generated for *.log)";
            };
          };
        }
      );
      default = { };
      description = "Service definitions";
    };
  };

  config = lib.mkIf (cfg.definitions != { }) {
    system.activationScripts."${cfg.project}-init".text = "mkdir -p /run/${cfg.project}";

    systemd.services = lib.mapAttrs mkService enabledServices;

    systemd.tmpfiles.rules =
      let
        dataDirs = lib.mapAttrsToList (_: svcCfg: svcCfg.dataDir) (
          lib.filterAttrs (_: svcCfg: svcCfg.dataDir != null) enabledServices
        );
        logDirs = lib.mapAttrsToList (_: svcCfg: svcCfg.logDir) (
          lib.filterAttrs (_: svcCfg: svcCfg.logDir != null) enabledServices
        );
        owner = if cfg.user != null then cfg.user else "root";
        group = if cfg.group != null then cfg.group else "root";
      in
      map (dir: "d ${dir} 0770 ${owner} ${group} -") (dataDirs ++ logDirs);

    services.logrotate.settings = lib.mkMerge (
      lib.mapAttrsToList (
        _: svcCfg:
        lib.optionalAttrs (svcCfg.logDir != null) {
          "${svcCfg.logDir}/*.log" = {
            su = "${if cfg.user != null then cfg.user else "root"} ${
              if cfg.group != null then cfg.group else "root"
            }";
            rotate = 14;
            weekly = true;
            compress = true;
            missingok = true;
            notifempty = true;
          };
        }
      ) enabledServices
    );

    users.users = lib.mkIf (cfg.user != null && !cfg.dynamicUser) {
      ${cfg.user} = {
        isSystemUser = true;
        group = if cfg.group != null then cfg.group else cfg.user;
      };
    };

    users.groups = lib.mkIf (cfg.user != null && !cfg.dynamicUser || cfg.group != null) (
      lib.optionalAttrs (cfg.group != null) { ${cfg.group} = { }; }
      // lib.optionalAttrs (cfg.group == null && cfg.user != null && !cfg.dynamicUser) {
        ${cfg.user} = { };
      }
    );
  };
}
