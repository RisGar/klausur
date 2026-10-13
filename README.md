# klausur

Serves each visitor exactly one exam paper

## Server

- `index.ts`, a bun server on the unix socket in `$KLAUSUR_SOCKET`
  (default `./klausur.sock`)
- `GET /` returns a PDF from `$EXAM_DIR`, any other path is a 404
- `$EXAM_DIR` is required and holds the papers as `*.pdf`
- no papers there means a 503
- papers are read once at startup, so restart after adding or removing one

## Cookies

- no `klausur` cookie means a random paper
- the cookie pins that paper, so a reload serves the same one
- the value is `Bun.hash` of the paper's file name
- it is not signed, so another paper's hash in the cookie picks that paper
- a hash of a paper that is gone is replaced by a fresh pick

## Nix

    nix build        # result/bin/klausur, the server compiled by bun
    nix develop      # bun and tsc, node_modules linked from the store
    nix flake check  # builds the package and typechecks

- `flake.nix`: package, check and `nixosModules.default` with
  `services.klausur.enable` and `services.klausur.socketPath`
- `default.nix`: the package
- `module.nix`: the NixOS module, serving `assets/*.pdf` from a store path
- `types.nix`: `@types/bun` and its dependencies pinned with the hashes from
  `bun.lock`
- the server has no runtime dependencies, only the typecheck needs packages
- `bun run check` in a dev shell is the same typecheck
