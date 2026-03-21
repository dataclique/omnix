{
  lib,
  config,
  pkgs,
  ...
}:

let
  cfg = config.omnix.staticSites;

  enabledSites = lib.filterAttrs (_: v: v.enabled) cfg.definitions;

  siteBase = "/var/lib/sites";
in
{
  options.omnix.staticSites = {
    definitions = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            enabled = lib.mkOption {
              type = lib.types.bool;
              default = true;
              description = "Whether this static site is deployed and managed";
            };
            port = lib.mkOption {
              type = lib.types.port;
              description = "Port nginx listens on for this site";
            };
            isDefault = lib.mkOption {
              type = lib.types.bool;
              default = false;
              description = "Whether this is the default nginx vhost";
            };
            extraLocations = lib.mkOption {
              type = lib.types.attrsOf lib.types.anything;
              default = { };
              description = "Additional nginx location blocks (e.g. /api/ proxy)";
            };
          };
        }
      );
      default = { };
      description = "Static site definitions deployed via symlink swap";
    };
  };

  config = lib.mkIf (enabledSites != { }) {
    services.nginx.enable = true;

    services.nginx.virtualHosts = lib.mapAttrs (name: siteCfg: {
      default = siteCfg.isDefault;
      listen = [
        {
          addr = "0.0.0.0";
          port = siteCfg.port;
        }
      ];
      root = "${siteBase}/${name}";
      locations = {
        "/".tryFiles = "$uri $uri/ /index.html";
      }
      // siteCfg.extraLocations;
    }) enabledSites;

    systemd.tmpfiles.rules = map (name: "d ${siteBase}/${name} 0755 root root -") (
      builtins.attrNames enabledSites
    );
  };
}
