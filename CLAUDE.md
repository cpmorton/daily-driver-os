@AGENTS.md

# daily-driver-os

A public bootc image for a small fleet of dual-boot workstations with one
administrator, built on the finpilot template. Read `docs/README.md` first,
then `docs/ARCHITECTURE.md`: most wrong changes put something in the wrong
layer. `docs/decisions/` says why things are
the way they are; check there before "fixing" something deliberate.

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
- **No stored user passwords.** Daily users' passwords are typed at first
  boot; only localadmin's *hash* may come from the machine defaults on the EFI
  partition (decisions 0019, 0020). Never commit a `defaults.json` or a
  password hash, even a test one that looks real (published test vectors in
  `tests/` excepted).
- **Encrypted root.** Nothing may weaken disk unlock: the initramfs
  assertions in `70-daily-driver.sh` stay, and the passphrase stays a fallback
  (decision 0021).
- **Access model.** Root stays locked. localadmin stays local-only (pam_access +
  sshd), with no SSH key. Rootful podman stays masked. Changing any of these
  needs the user's explicit say-so.

## Documentation is part of the change

- Every file, package, service change, Flatpak or recipe you add gets a row in
  `docs/PROVENANCE.md`; the contract test fails otherwise.
- Every choice with real alternatives gets a record in `docs/decisions/`, and
  a line in its index. Supersede, don't rewrite.
- Mark anything not proven on a real machine **[VERIFY]**.

## Before committing

    just lint && just check && just test-unit

`just validate-flatpaks` needs flatpak and network. Nothing here builds without
podman; never say a build passed unless CI or a local `just build` ran it.
