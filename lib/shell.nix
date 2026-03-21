# Nushell script wrapper infrastructure.
# Provides mkNuScript to create derivations that invoke nushell scripts.
{ pkgs, scriptsDir }:

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
      cmd = if subcommand != null then "nu ${nuPath} ${subcommand}" else "nu ${nuPath}";
      argsStr = builtins.concatStringsSep " " (map (a: ''"${a}"'') extraArgs);
    in
    pkgs.writeShellApplication {
      inherit name;
      runtimeInputs = [ pkgs.nushell ] ++ runtimeInputs;
      text = ''
        ${cmd} ${argsStr} "$@"
      '';
    };
}
