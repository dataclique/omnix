# Derives ragenix/agenix secret rules from service definitions: every service
# that declares an `encryptedSecret` gets a rule pinning the recipients allowed
# to decrypt it.
#
# Pure builtins only (no nixpkgs `lib`): ragenix evaluates the rules file in a
# NIX_PATH-free context where `import <nixpkgs/lib>` is fragile.
#
# `recipients` is polymorphic: pass a list of public keys (same recipients for
# every secret) or a function `serviceDef -> [ publicKey ]` (per-service). This
# covers both the flat `roles.service` shape and the nested
# `roles.prod.service ++ roles.staging.service` shape — the caller resolves the
# list it wants.
{
  # Service definitions (the `services` attrset; each value may have an
  # `encryptedSecret` = "<file>.age").
  services,
  recipients,
  # Extra rules merged on top, e.g. tailscale auth keys not tied to a service.
  extraRules ? { },
}:

let
  resolve = def: if builtins.isFunction recipients then recipients def else recipients;

  secretNames = builtins.filter (name: (services.${name}.encryptedSecret or null) != null) (
    builtins.attrNames services
  );

  rules = builtins.listToAttrs (
    map (name: {
      name = services.${name}.encryptedSecret;
      value = {
        publicKeys = resolve services.${name};
      };
    }) secretNames
  );
in
rules // extraRules
