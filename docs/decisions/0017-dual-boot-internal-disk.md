# 0017. Dual boot on the internal disk, beside Windows

- **Status:** Accepted
- **Date:** 2026-09-23
- **Supersedes:** [0008](0008-homed-users-on-a-separate-partition.md) (OS on a
  USB drive, homes on a separate internal partition)

## Context

Machines already run Windows on their only internal disk. Installing to
external media needs a second device per machine, and the people using these
machines have no Linux to prepare anything with.

## Decision

- Install into unallocated space on the internal disk, made by shrinking
  Windows' volume from Windows (Disk Management). The installer's *automatic*
  partitioning uses only free space, and shares the existing EFI System
  Partition. `iso/iso.toml`'s kickstart has no `clearpart`, so nothing is
  erased unless someone chooses to in the installer.
- Homes live inside the Linux installation: each daily user is a systemd-homed
  LUKS home, one file in `/var/home`, openable only with that user's password.
  localadmin can't read it.
- A reinstall wipes the Linux side, homes included, unless each home file is
  copied off first. Accepted: the OS is disposable, and data belongs in sync
  services or backups.
- bootc's boot menu (bootupd's static GRUB config) never looks for other
  systems and shows for one second. `windows-boot-entry.service` adds a
  Windows entry and a 5-second menu through `/boot/grub2/custom.cfg`, which the
  static config sources. It never overwrites that file; `ujust windows-entry`
  regenerates it.

## Alternatives

- **OS on external media (0008):** a second device per machine, slower, easy
  to lose.
- **A separate home partition:** homes survive a reinstall, but needs custom
  partitioning in the installer, which is where dual-boot installs go wrong.
- **Rely on the firmware boot menu for Windows:** works, but asks every user to
  learn a key per laptop model.

## Consequences

- Windows' clock: Windows keeps the hardware clock in local time, Linux in UTC,
  so one of them shows the wrong time after switching. The runbook sets
  Windows to UTC (`RealTimeIsUniversal`).
- Windows Fast Startup leaves NTFS half-hibernated; the runbook turns it off.
- Windows updates occasionally reset the firmware boot order to Windows. Fix
  in the firmware settings, or with the one-time boot menu.

## Verification

bootupd's source (2026-09-23): `grub-static-pre.cfg` sets `timeout=1`;
`configs.d/41_custom.cfg` sources `$prefix/custom.cfg`; nothing runs
os-prober. [VERIFY on hardware: the chainload entry boots Windows with Secure
Boot on; the installer accepts a small (100 MB) Windows EFI partition; `/boot`
remount in a private namespace works on bootc.]

## Revisit when

bootupd gains other-OS detection, or machines move to Linux-only.
