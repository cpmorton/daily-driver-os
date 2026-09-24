# 0019. Passwords are typed at first boot, never seeded

- **Status:** Accepted
- **Date:** 2026-09-23
- **Amends:** [0018](0018-provisioning-seed-stick.md) (what the seed carries),
  [0005](0005-accounts-and-access.md) (where localadmin's password comes from),
  [0002](0002-public-and-secret-free.md) (where secrets live)

## Context

[0018](0018-provisioning-seed-stick.md) let the seed stick carry localadmin's
password hash and each daily user's initial password, in plain text, so a
machine could come up with no typing. An unattended install isn't needed yet,
and those passwords made the stick a secret until first boot, turned the
administrator's password manager into a hash store, and required a forced
password change that re-keys a LUKS home on its first login, which hasn't been
proven on hardware.

## Decision

- **Every password is typed on the console at first boot**, before the login
  screen: localadmin's first (`localadmin-firstboot.service`, `passwd`), then
  each daily user's (`daily-driver-users.service`, `homectl create`, which asks
  twice and refuses weak ones).
- **First boot, not install time.** The stock installer can't create a
  systemd-homed LUKS home, and a user made on its user screen takes UID 1000,
  which is localadmin's. One place asks for everything.
- **The seed stick stays, without passwords:** hostname, daily users' names,
  full names and home sizes, and optional skel folders. The console asks
  for each seeded user's password in turn, then offers to add more.
- **Allowlist, not blocklist.** The importer rebuilds each user record from
  `userName`, `realName` and `diskSize` only (plus `storage: luks` and the
  staged `skeletonDirectory`). A `secret`, `passwordChangeNow`, `memberOf` or
  any other field on a stick is logged and dropped, so an older or hand-edited
  stick can't set a password or grant `wheel`. `seed.json` keys other than
  `version` and `hostname` (an old `localadmin.hashedPassword`) are ignored the
  same way.
- **Who is typing decides the forced change.** For each user the console asks
  whether that person is at the keyboard. If not (the administrator types an
  initial password for them), the user must choose a new one at first login
  (`--password-change-now=yes`). The default is no forced change.
- **localadmin has no SSH key.** It stays console-only
  ([0005](0005-accounts-and-access.md)); nothing on a seed can change that.
- `ujust localadmin-hash` and the maker's `-LocalAdminHash` and
  `-NoPasswordChange` options are gone. The maker removes passwords and hashes
  that an older version left on a stick.

## Alternatives

- **Keep seeded passwords (0018):** the no-typing install isn't needed yet, and
  plaintext passwords on removable media aren't worth it.
- **Ask in the installer:** see the second point above.
- **Drop the seed stick altogether:** hostname and user names are a few
  keystrokes. Kept for now because skel folders still save real work; revisit
  if they go unused.

## Consequences

- Someone must be at each machine's console at first boot. Each daily user can
  type their own password there, so the administrator never knows it.
- The seed stick is no longer a secret, unless skel folders carry private
  files. First boot still deletes the seed.
- Unattended install ([0018](0018-provisioning-seed-stick.md)'s "later") will
  need its own decision on how passwords arrive.

## Verification

`tests/contract/daily-driver-helpers_test.bats`: a stick carrying an old hash,
plaintext passwords and `memberOf` imports with none of them applied or left
on disk; the console flow creates seeded and typed-in users through
`homectl create` with no password argument, and retries a failed create; the
Windows maker takes no password parameter and scrubs old sticks. Source read:
systemd v257 and v258 `src/home/homectl.c`: `create --identity=` merges
command-line options such as `--password-change-now` into the record, and
`create_home_common` asks for a new password when the record carries none.
[VERIFY on hardware: the tty1 prompts before GDM.]

## Revisit when

An unattended or iPXE install is wanted, or skel folders go unused.
