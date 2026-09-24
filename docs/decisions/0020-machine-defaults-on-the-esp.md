# 0020. Machine defaults live on the EFI partition, written from Windows

- **Status:** Accepted
- **Date:** 2026-09-23
- **Supersedes:** [0018](0018-provisioning-seed-stick.md) (the seed stick)
- **Amends:** [0019](0019-no-seeded-passwords.md) (localadmin's password
  may come from a stored hash again; daily users' passwords are still always
  typed), [0005](0005-accounts-and-access.md)

## Context

The administrator wants no second USB stick, and wants each machine to
reinstall quickly, or several machines to share one administrator password and
the same users, with every default overridable at install time. The installer
stick can't carry them: Fedora's supported way to write it is a raw disk image,
which Windows can't write to afterwards, and rebuilding it as a FAT32 copy
(Rufus's "ISO mode") means patching boot labels and working around FAT32's
4 GiB file and 32 GB format limits, none of which Fedora supports. Nothing
secret or per-machine may go in the public repository or ISO
([0002](0002-public-and-secret-free.md)).

## Decision

- **The defaults live on the machine's own EFI system partition**, as
  `\EFI\daily-driver\defaults.json`. Windows and Linux share that partition in
  a dual boot, and reinstalling Linux never touches it, so a reinstall picks
  the same defaults up again. `tools/windows/Set-DailyDriverDefaults.ps1` writes
  it from an elevated PowerShell on that machine (`mountvol X: /S`), in the
  same session that prepares Windows for the install.
- **Fields:** hostname; localadmin's password as a crypt(3) hash (the script
  computes SHA-512 crypt, `$6$`, 500,000 rounds, from a typed password, or
  takes a hash copied from a shadow file); how the disk unlocks
  ([0021](0021-encrypted-root.md)); daily users (name, full name, UID in
  60001-60513, shell, home size, must-change-password); extra Flatpaks.
  Never a user's password.
- **First boot offers every value, and Enter accepts it.**
  `daily-driver-defaults.service` finds and validates the file, and keeps an
  allowlisted copy in RAM (`/run`). `daily-driver-firstboot.service` then
  walks tty1 through hostname, localadmin, disk unlock and users, each showing
  its default. Any other answer overrides it, and a default user can be
  skipped to restore a backed-up home instead
  ([0022](0022-home-backup-and-restore.md)).
- **Allowlist, as before:** fields outside the list are logged and dropped, so
  the file can't set a user's password, group membership or any other record
  field. Invalid values reject the whole file, and first boot asks for
  everything.
- **Extra Flatpaks** go to `/etc/flatpak/preinstall.d/`, which Flatpak reads
  alongside the image's `/usr/share/flatpak/preinstall.d/`.
- One tty1 service replaces the seed importer and the two separate console
  services, so only one unit owns the console, and an interrupted first boot
  resumes after its last finished step.

## Alternatives

- **Customize the installer stick** (FAT32 copy plus kickstart): see Context.
  It also couldn't pre-fill anything the installer can't do itself: homed
  users only exist after first boot.
- **The seed stick ([0018](0018-provisioning-seed-stick.md)):** a second
  stick to carry and keep in sync; unwanted.
- **Defaults on the Windows `C:` drive:** Linux would need to read NTFS at
  first boot, and BitLocker would lock it away.
- **Per-machine Homebrew packages:** not offered. upstream's automatic
  Brewfile install reads only a folder inside the read-only image, and
  localadmin owns the Homebrew prefix ([0011](0011-homebrew-single-owner.md));
  fleet-wide tools belong in `custom/brew/`.

## Consequences

- localadmin's hash sits on the EFI partition, readable by anyone who can read
  the disk (the partition can't be encrypted). The script insists on 12+
  characters, and 500,000 rounds make each guess slow; still, it's a hash to
  guard like one. Remove it with `-ClearLocalAdminPassword` once a machine is
  set up if you'd rather type it on the next reinstall.
- Setting up several machines alike means running the script on each one's
  Windows. It takes seconds, and the Windows preparation happens there anyway.
- The EFI partition's free space: the file is well under 1 KB.
  [VERIFY on hardware: a Windows-made 100 MB EFI partition also fits bootc's
  boot files ([0017](0017-dual-boot-internal-disk.md)).]

## Verification

`tests/contract/daily-driver-helpers_test.bats`: the PowerShell script's
SHA-512 crypt matches the specification's published test vector and glibc's
crypt(3) output; a file written by the script (under pwsh) imports on the Linux
side; off-list fields are dropped and bad values rejected; the tty1 flow
accepts defaults on Enter, takes overrides, and resumes after an interruption.
Source read: flatpak's `common/flatpak-dir.c` (preinstall read from both
`$datadir` and `$sysconfdir`). [VERIFY on hardware: `mountvol /S` from an
elevated PowerShell; the tty1 prompts before GDM.]

## Revisit when

An unattended or iPXE install is wanted: the same file could be served instead.
