# `node_modules` holding only the type packages, taken straight from the
# registry but pinned by the integrity hashes recorded in bun.lock.
#
# bun2nix would do this automatically, but it only understands Bun <= 1.3
# lockfiles (`lockfileVersion: 1`); Bun 1.4 writes version 2. When bumping a
# type package: `bun install`, then update the version, URL and hash below.
{
  stdenvNoCC,
  fetchurl,
}:
let
  typesBun = fetchurl {
    url = "https://registry.npmjs.org/@types/bun/-/bun-1.4.3.tgz";
    hash = "sha512-N67Pqy8JXbAY/j0tNraS3V5mubGvc6rrrNDmDCtZLlFzccbUJPDb0tvgUBC5q4m8ybkP93Jcn1QB+RYQ6PvBhw==";
  };
  bunTypes = fetchurl {
    url = "https://registry.npmjs.org/bun-types/-/bun-types-1.4.3.tgz";
    hash = "sha512-tinRJNGOmUN+tEAsn2y2e942n9JHRHR42iUYzDH75NmhJqVBokGSQkkfSFdNWwsANIdrK6ACH9t01M452YyTwg==";
  };
  typesNode = fetchurl {
    url = "https://registry.npmjs.org/@types/node/-/node-26.6.5.tgz";
    hash = "sha512-uMzsv9stDdofIZBx4UGh4Z9ZgXnGC9seRDscilBcTHAeOFk67MZg/k9bWVfO+bk4qZmG+l52hRnLwUiH2LnJTg==";
  };
  undiciTypes = fetchurl {
    url = "https://registry.npmjs.org/undici-types/-/undici-types-8.11.2.tgz";
    hash = "sha512-iMVNmWZ0leK/goS6eXMizSzmm9CDWtyphwbaCms3DNLqRxDL+mMoNVcZMTyyVgXP0N+Z8neAMzDoUOUJL8veKg==";
  };
in
stdenvNoCC.mkDerivation {
  pname = "klausur-node-modules";
  version = "1";

  dontUnpack = true;

  installPhase = ''
    runHook preInstall

    for pkg in @types/bun @types/node bun-types undici-types; do
      mkdir -p "$out/node_modules/$pkg"
    done

    tar -xzf ${typesBun} --strip-components=1 -C "$out/node_modules/@types/bun"
    tar -xzf ${typesNode} --strip-components=1 -C "$out/node_modules/@types/node"
    tar -xzf ${bunTypes} --strip-components=1 -C "$out/node_modules/bun-types"
    tar -xzf ${undiciTypes} --strip-components=1 -C "$out/node_modules/undici-types"

    runHook postInstall
  '';
}
