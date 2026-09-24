# 0002. Public repository and public image; nothing secret

- **Status:** Accepted
- **Date:** 2026-09-23

## Amendments

- 2026-09-23, [0018](0018-provisioning-seed-stick.md): per-machine secrets travel on a seed stick that first boot imports and wipes; still never in the repository or the ISO.

## Context

The repository and the GHCR package are public. Anything in either, including
every layer of every past image, is readable by anyone, forever.

## Decision

No secrets, tokens, private keys, password hashes or personal data in the
repository or the image. Secret values come from the machine (typed at first
boot) or a password manager (decided later: `secrets` in the dotfiles).

## Alternatives

- **Bake localadmin's password hash via a CI secret:** the hash would be in a
  public image layer, crackable offline, and shared by every install.
- **Private GHCR package:** every machine then needs a registry pull secret,
  itself a secret to distribute.

## Consequences

- localadmin's password is typed on tty1 at first boot
  ([0005](0005-accounts-and-access.md)).
- `tests/contract/daily-driver_test.bats` fails on any crypt(3) hash in the
  image inputs.

## Revisit when

Never for secrets. A private image would change the model only if a machine
ever needs a baked-in credential.
