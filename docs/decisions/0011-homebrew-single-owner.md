# 0011. Keep Homebrew, owned by one user

- **Status:** Accepted
- **Date:** 2026-09-23

## Context

finpilot bakes in `ublue-os/brew`: a Homebrew tarball unpacked to
`/home/linuxbrew` on first boot. Its `brew-setup.service` runs
`chown -R 1000:1000`, and its update timers run as `User=1000`. In this image
UID 1000 never exists: localadmin is 1999, and homed users are 60001 or higher.

## Decision

Keep Homebrew for ad-hoc CLI tools ([0004](0004-where-software-goes.md)).
`ujust brew-owner <user>` hands the prefix and both timers to one user, with a
`StateDirectory` as the timers' HOME, so they run while that user's LUKS home is
locked. `brew-setup` waits for the `/var/home` mount.

## Alternatives

- **Remove Homebrew:** stricter "image or devcontainer" discipline, at the cost
  of rebuilding the image for every CLI tool you try. A three-line change if
  preferred.
- **Group-writable shared prefix:** Homebrew doesn't support multi-user prefixes.

## Consequences

Only the owner can `brew install`. `gh` and `chezmoi` are RPMs so every account
has them.

## Verification

`ublue-os/brew`'s `brew-setup.service`, `brew-update.service` and
`brew-upgrade.service`, read 2026-09-23. Their comments say to override the user.
