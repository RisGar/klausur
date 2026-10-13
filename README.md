# Exam papers for klausur.rishab.org

Every `*.pdf` in this directory is a paper that can be handed out. Put the
papers here and rebuild the homelab:

    nixos-rebuild switch --flake .#Rishabs-Homelab

Nothing else has to change when papers are added or removed: the list of
candidates is read from the store path when the service starts and the ordering
is just the sorted file names.

Each visitor is served exactly one paper:

- a visitor without a cookie gets the next paper in round-robin order, so all
  papers are handed out equally often,
- the choice is then pinned in a `klausur` cookie so reloading always yields
  the same paper,
- the cookie holds an HMAC of the file name, so it cannot be edited to pick
  another paper.

The assignment counter and the signing secret live in `/var/lib/klausur`
(`assignments` and `secret`). Deleting them restarts the round-robin and
invalidates all existing cookies.
