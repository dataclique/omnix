# Packages a nushell script as an executable derivation. Runs the co-located
# `<name>.test.nu` (if present) in checkPhase so `nix flake check` gates it, and
# wraps the script with nushell + `runtimeInputs` on PATH.
#
# An opt-in dev/CI building block (see adrs/0001): a consumer calls it and wires
# the result into its own packages/apps/dev shell — never forced module config.
{
  pkgs,
  name,
  # Directory holding `<name>.nu` (and optionally `<name>.test.nu`). The whole
  # directory is the source so a script's relative `use ./other.nu` resolves.
  scriptsDir,
  runtimeInputs ? [ ],
  nushell ? pkgs.nushell,
}:

let
  inherit (pkgs) lib;
in
pkgs.stdenvNoCC.mkDerivation {
  pname = name;
  version = "0";
  src = scriptsDir;

  nativeBuildInputs = [ pkgs.makeWrapper ];
  dontConfigure = true;
  dontBuild = true;
  doCheck = true;

  checkPhase = ''
    runHook preCheck
    if [ -f ./${name}.test.nu ]; then
      ${lib.getExe nushell} ./${name}.test.nu
    fi
    runHook postCheck
  '';

  installPhase = ''
    runHook preInstall
    install -Dm755 ./${name}.nu $out/libexec/${name}.nu
    makeWrapper ${lib.getExe nushell} $out/bin/${name} \
      --add-flags $out/libexec/${name}.nu \
      --prefix PATH : ${lib.makeBinPath runtimeInputs}
    runHook postInstall
  '';

  meta.mainProgram = name;
}
