# 0018. Provisioning: a generic installer plus a per-machine seed stick

- **Status:** Accepted
- **Date:** 2026-09-23
- **Amends:** [0005](0005-accounts-and-access.md) (localadmin's password and
  UID), [0002](0002-public-and-secret-free.md) (where secrets live)

## Context

One administrator builds the installers and controls localadmin on every
machine; users must not choose localadmin's password. Daily users may be
created at first boot, or pre-configured so the machine comes up ready.
Everything is prepared on Windows. The installer ISO is public
([0016](0016-installer-built-in-ci.md)), so it can't carry anything secret.

## Decision

- **Two pieces of media.** The *installer* is the generic public ISO,
  unchanged, using the stock installer with its defaults. The *seed* is a
  FAT32/exFAT volume labelled `DDSEED` (a second small stick, or a partition),
  written on Windows by `tools/windows/New-DailyDriverSeed.ps1`.
- **At first boot, before the login screen:**
  1. `daily-driver-seed.service` imports the seed if one is plugged in:
     hostname; localadmin's password *hash* (from the administrator's secret
     store); files for localadmin's home; one systemd-homed user record per
     daily user, staged as `home.create.<name>` credentials in `/run/credstore`
     (RAM only). Then it **deletes the seed from the stick**.
  2. `localadmin-firstboot.service` asks for localadmin's password on tty1
     only if the seed didn't set one (the administrator types it).
  3. `daily-driver-users.service` creates the seeded users through
     `homectl firstboot`, the documented path for those credentials, or with no
     seed asks for users on tty1. Every homed user gets subordinate IDs for
     rootless podman.
- **localadmin is UID 1000** (was 1999), so upstream pieces that assume the
  first user (Homebrew's prefix and update timers) belong to it. Daily users
  are homed users, UID 60001 and up.
- **Daily users' initial passwords are plaintext on the seed.** homed derives
  the LUKS key from the password when it creates the home, so a hash can't do.
  `passwordChangeNow` defaults to true: the user replaces it at first login,
  which re-keys the home. The stick is the secret until first boot, which
  wipes it.
- upstream's `systemd-homed-firstboot.service` is masked: it skips its prompt
  whenever any regular user exists, and localadmin always does.

## Alternatives

- **Secrets in the installer ISO (kickstart):** the ISO is public, and its CI
  artifact downloadable.
- **Seed files on the installer stick itself:** a stick written as a disk image
  is read-only from Windows. A second partition added in Windows may work; the
  importer only looks for the `DDSEED` label, so it accepts either. Ventoy
  keeps one writable stick, but needs a Secure Boot key enrolled on every
  machine.
- **Unattended kickstart install:** a later step. It needs partitioning rules
  that are safe next to Windows on unknown disks, and no secrets in the ISO.
  The seed design already separates the two.
- **iPXE:** later; the seed format carries over (served instead of plugged in).

## Consequences

- Private SSH keys or other secrets placed in a user's skel folder travel in
  plain text on the stick until first boot. Prefer generating keys on the
  machine or using a password manager's SSH agent.
- A seed with a mistake (bad hash, missing password) stops the import before
  anything changes and leaves the stick intact; fix it and reboot.

## Open

- **localadmin and SSH.** The seed format reserves
  `localadmin.sshAuthorizedKeys`, and the importer ignores it:
  [0005](0005-accounts-and-access.md) keeps localadmin console-only. Remote
  administration needs its own decision (key-only sshd for localadmin, likely
  over Tailscale; see `build/30-tailscale.sh.example`).

## Verification

`tests/contract/daily-driver-helpers_test.bats` runs the importer and the
first-users script in a sandbox, including a seed written by the PowerShell
maker (under pwsh) and imported by the Linux importer. Source read: homed's
`USER_RECORD.md` (`secret.password`, `passwordChangeNow`,
`skeletonDirectory`), `homectl firstboot` (credentials first, then the
`SYSTEMD_HOME_FIRSTBOOT_OVERRIDE` check). [VERIFY on hardware: the console
prompts before GDM; a forced password change at first GDM login re-keys the
LUKS home; exFAT seeds mount at first boot.]
