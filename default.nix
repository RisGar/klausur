# The server, compiled into a single self-contained executable by
# `bun build --compile`. Nothing comes from npm here: the source has no
# runtime dependencies, bun is only needed at build time.
#
# The flake outputs live in flake.nix, the NixOS module in module.nix.
{
  lib,
  src,
  stdenvNoCC,
  bun,
}:
stdenvNoCC.mkDerivation {
  pname = "klausur";
  version = "0.1.0";

  inherit src;

  nativeBuildInputs = [ bun ];

  buildPhase = ''
    runHook preBuild
    export HOME=$(mktemp -d) # bun wants somewhere to write its cache
    bun build ./index.ts --compile --minify --bytecode --outfile klausur
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    install -Dm755 klausur $out/bin/klausur
    runHook postInstall
  '';

  # a bun-compiled binary stops working if fixup strips or patches it
  dontFixup = true;

  meta = {
    description = "Hand every visitor of klausur.rishab.org one exam paper";
    license = lib.licenses.eupl12;
    mainProgram = "klausur";
  };
}
