@AGENTS.md

# daily-driver-os

A public bootc image for one person's workstation, built on the finpilot
template. Read `docs/ARCHITECTURE.md` before changing anything: it says which
layer owns what, and most wrong changes put something in the wrong layer.

## Invariants

`tests/contract/daily-driver_test.bats` enforces most of these.

- **Public repository.** Never add secrets, tokens, keys, password hashes or
  personal data. User-specific config belongs in the separate `dotfiles`
  repository, and secret values in neither.
- **Where things go.** System files: `custom/files/` (prefer paths under `/usr`).
  Packages and switches: `build/70-daily-driver.sh`. Flatpaks:
  `custom/flatpaks/daily.preinstall`. Recipes: `custom/ujust/daily-driver.just`.
  Leave upstream's files alone unless there is no other way; override from this
  image's own phases instead.
- **Disable any repository you enable**, before the phase ends.
- **`/opt`, `/usr/local` and `/root` are real directories.** Never reintroduce
  upstream's `/opt -> /var/opt` symlink. Nothing may write into `/root` during
  the build.
- **Access model.** Root stays locked. localadmin stays local-only (pam_access +
  sshd). Rootful podman stays masked. Changing any of these needs the user's
  explicit say-so.

## Before committing

    just lint && just check && just test-unit

`just validate-flatpaks` needs flatpak and network. Nothing here builds without
podman; never say a build passed unless CI or a local `just build` ran it.
