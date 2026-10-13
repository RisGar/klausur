# `tsc --noEmit`, with typescript from nixpkgs and the Bun types from types.nix
{
  src,
  nodeModules,
  stdenvNoCC,
  typescript,
}:
stdenvNoCC.mkDerivation {
  pname = "klausur-typecheck";
  version = "0.1.0";

  inherit src;

  nativeBuildInputs = [ typescript ];

  buildPhase = ''
    runHook preBuild
    ln -s ${nodeModules}/node_modules node_modules
    tsc --noEmit
    runHook postBuild
  '';

  installPhase = "mkdir -p $out";
}
