{ lib, config, ... }:

let
  cfg = config.omnix.firewall;

  httpPorts = lib.optional cfg.enableHTTP 80;
  httpsPorts = lib.optional cfg.enableHTTPS 443;
in
{
  options.omnix.firewall = {
    enable = lib.mkEnableOption "omnix firewall (SSH always allowed)";

    enableHTTP = lib.mkEnableOption "port 80 (HTTP, needed for ACME challenges)";
    enableHTTPS = lib.mkEnableOption "port 443 (HTTPS)";

    allowedTCPPorts = lib.mkOption {
      type = lib.types.listOf lib.types.port;
      default = [ ];
      description = "Additional TCP ports to allow (SSH 22 is always included)";
    };
  };

  config = lib.mkIf cfg.enable {
    networking.firewall = {
      enable = true;
      allowedTCPPorts = [ 22 ] ++ httpPorts ++ httpsPorts ++ cfg.allowedTCPPorts;
    };
  };
}
