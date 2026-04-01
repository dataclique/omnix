{ lib, config, ... }:

let
  cfg = config.omnix.acme;
in
{
  options.omnix.acme = {
    enable = lib.mkEnableOption "ACME/Let's Encrypt certificate management";

    email = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Email address for ACME renewal notifications";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.email != null;
        message = "omnix.acme.email must be set when omnix.acme.enable is true";
      }
    ];

    security.acme = {
      acceptTerms = true;
      defaults.email = cfg.email;
    };
  };
}
