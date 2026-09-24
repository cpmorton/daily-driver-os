# 0008. Daily users are systemd-homed LUKS homes on a separate partition

- **Status:** Superseded by [0017](0017-dual-boot-internal-disk.md). homed LUKS homes stay; the separate partition and the OS-on-USB layout are gone.
- **Date:** 2026-09-23

## Context

The OS runs from a USB stick; the laptop's internal disk also holds Windows.
Home data should live on the internal disk, encrypted, and survive reinstalls.

## Decision

- Daily users are created with `ujust homed-user` (`homectl create
  --storage=luks`), each with an explicit size.
- `/var/home` is a separate internal partition, added by `ujust
  home-partition`, which copies the existing contents and never formats.
- Rootless podman needs subordinate IDs, which `useradd` normally allocates;
  `ujust homed-user` writes them to `/etc/subuid` and `/etc/subgid`.

## Alternatives

- **Plain `useradd` users with LUKS on the whole partition:** one key for
  everyone; homes don't lock on suspend.
- **Home on the stick:** small, slow, and lost with the stick.

## Consequences

- homed's signing keys (`/var/lib/systemd/home/local.*`) live on the stick and
  must be backed up elsewhere, or homes won't activate after a reinstall.
- homed users can't be managed with `usermod`/`gpasswd`; group changes go
  through `homectl update`.
- `/var/home` is mounted `nofail`: without the partition, only localadmin can
  log in.

## Revisit when

systemd-homed or SELinux policy changes break login; test every Fedora major
upgrade in a VM first.
