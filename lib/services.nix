# Shared service-definition helpers for the omnix.services module and
# lib/deploy.nix. Applies the per-service computed paths, filters enabled
# services, and computes a deterministic activation order from each service's
# `order` field.
#
# `order` controls the deploy-rs activation sequence. When no service sets it,
# activation falls back to alphabetical attribute order (backwards compatible).
# When services set it, every enabled service must set a unique value, so adding
# a new service forces choosing its slot rather than silently inheriting a
# non-deterministic order.
{ lib }:

{
  # Raw service definitions: the same attrset passed to
  # `omnix.services.definitions` and to `mkDeploy`'s `services` argument.
  services,
  # Project name, used for the per-service marker directory (/run/<project>).
  project ? "omnix",
}:

let
  profileBase = "/nix/var/nix/profiles/per-service";

  withComputed =
    name: def:
    def
    // {
      profilePath = "${profileBase}/${name}";
      markerFile = "/run/${project}/${name}.ready";
    };

  normalized = lib.mapAttrs withComputed services;
  enabled = lib.filterAttrs (_: v: v.enabled or true) normalized;
  enabledNames = builtins.attrNames enabled;

  orders = map (name: enabled.${name}.order or null) enabledNames;
  setOrders = builtins.filter (o: o != null) orders;
  uniqueOrders = builtins.foldl' (
    acc: o: if builtins.elem o acc then acc else acc ++ [ o ]
  ) [ ] setOrders;

  orderedNames =
    if setOrders == [ ] then
      enabledNames
    else if builtins.length setOrders != builtins.length enabledNames then
      throw "omnix.services: either all or none of the enabled services must set `order` (got a partial set: ${builtins.toJSON orders})"
    else if builtins.length setOrders != builtins.length uniqueOrders then
      throw "omnix.services: duplicate `order` values among enabled services: ${builtins.toJSON setOrders}"
    else
      builtins.sort (a: b: enabled.${a}.order < enabled.${b}.order) enabledNames;

in
{
  inherit
    normalized
    enabled
    enabledNames
    orderedNames
    ;
}
