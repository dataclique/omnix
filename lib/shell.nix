# Nushell script wrapper infrastructure.
# Provides mkNuScript to create derivations that invoke nushell scripts.
{ pkgs, scriptsDir }:

let
  inherit (pkgs.lib) escapeShellArg;
in
{
  mkNuScript =
    {
      name,
      script,
      subcommand ? null,
      runtimeInputs ? [ ],
      extraArgs ? [ ],
    }:
    let
      nuPath = scriptsDir + "/${script}";
      quotedPath = escapeShellArg nuPath;
      subcmdStr = if subcommand != null then " ${escapeShellArg subcommand}" else "";
      argsStr = builtins.concatStringsSep " " (map escapeShellArg extraArgs);
    in
    pkgs.writeShellApplication {
      inherit name;
      runtimeInputs = [ pkgs.nushell ] ++ runtimeInputs;
      text = ''
        nu ${quotedPath}${subcmdStr} ${argsStr} "$@"
      '';
    };
}
