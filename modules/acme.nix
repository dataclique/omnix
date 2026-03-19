{ lib, config, ... }:

let
  cfg = config.omnix.acme;
in
{
  options.omnix.acme = {
    enable = lib.mkEnableOption "ACME/Let's Encrypt certificate management";

    email = lib.mkOption {
      type = lib.types.str;
      description = "Email address for ACME renewal notifications";
    };
  };

  config = lib.mkIf cfg.enable {
    security.acme = {
      acceptTerms = true;
      defaults.email = cfg.email;
    };
  };
}
