# 0022. Back up and restore a user's whole encrypted home as one file

- **Status:** Accepted
- **Date:** 2026-09-23

## Context

A reinstall wipes the Linux partition, homes included. Each daily user's home
is one LUKS image, `/var/home/<user>.home`, openable only with that user's
password, so it can travel as it is without exposing anything.

## Decision

- **`ujust backup-home <user> <folder>`**, as localadmin while the user is
  logged out, copies the image with zstd. homed trims freed space on logout,
  so the unused parts are holes, and the copy is about the size of the data.
  It also saves this install's homed public key, which signed the user's
  record, plus checksums. It refuses while the home is active and throws the
  copy away if the user logs in during it.
- **`ujust restore-home <user> <folder>`** on the new install checks the
  checksums, decompresses the image sparse to `/var/home/<user>.home`,
  installs the old key as `/etc/systemd/home/restored-*.public` (a directory
  homed trusts for signatures), and registers the home: `homectl adopt`, or a
  homed restart where `adopt` is missing (homed scans `/home` on start). The
  user logs in with their old password.
- **Restore happens as localadmin, never as the user**, and only while the
  user doesn't exist on the new install: first boot lets a default user be
  skipped for this. localadmin's own home is a plain directory, so its session
  never touches an encrypted home.

## Alternatives

- **Restore during the install (kickstart `%post`):** the installer has no
  homed, and the backup would have to live on the installer stick.
- **File-level backup (rsync, restic) from inside the session:** works, but
  needs the user logged in and decrypts the data onto the backup unless the
  backup is encrypted separately; the image is already encrypted.

## Consequences

- The backup drive needs room for the data (exFAT or NTFS; FAT32's 4 GiB file
  limit is too small). Treat the copy like the laptop: encrypted, but still the
  user's data.
- A home moved to a different machine works the same way.
- If the old UID is taken on the new machine, homed assigns another and
  re-owns the files at login.

## Verification

`tests/contract/daily-driver-helpers_test.bats`: backup then restore gives back
the image byte for byte and still sparse; backups are refused while active,
restores refused over an existing user or a damaged backup; the old key is
trusted only when it differs; the homed-restart fallback. Source read:
systemd's `homed-manager.c` (trusted keys in `/etc/systemd/home/`),
`man/homectl.xml` (`adopt`), `docs/USER_RECORD.md` (`status` and `binding`).
[VERIFY on hardware: homed accepts a restored home signed by the old key, and
how `homectl adopt` treats it.]

## Revisit when

homed gains a native export/import.
