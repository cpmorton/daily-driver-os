# Install or reinstall (dual boot, from Windows)

Linux goes into free space on the laptop's internal disk, beside Windows. No
Linux needed anywhere; everything is prepared on Windows.
[Decision 0017](../decisions/0017-dual-boot-internal-disk.md).

| You need | For |
| --- | --- |
| **Installer stick**, 8 GB+ | The generic installer ISO. Erased when written; reusable for every machine. |
| Machine defaults (optional) | Pre-filled answers for first boot, set from Windows. [machine-defaults.md](machine-defaults.md). |
| A backup drive (reinstall only) | Each user's home, saved with `ujust backup-home` first. [home-backup.md](home-backup.md). |
| 100 GB+ of free disk space | Linux plus the encrypted homes. |

## 1. Prepare Windows (admin PowerShell, once per machine)

```powershell
manage-bde -status C:          # if "Protection On": save the recovery key first (aka.ms/myrecoverykey)
powercfg /h off                # Fast Startup and hibernation off: Linux can safely share the disk
# Windows keeps the hardware clock in local time, Linux in UTC; make Windows use UTC:
reg add "HKLM\System\CurrentControlSet\Control\TimeZoneInformation" /v RealTimeIsUniversal /t REG_DWORD /d 1 /f
diskmgmt.msc                   # right-click C: > Shrink Volume; leave the space Unallocated
```

Shrink by at least 100 GB. Don't create a partition in the freed space: the
installer uses unallocated space.

Optionally, in the same window, set this machine's defaults:
[machine-defaults.md](machine-defaults.md).

## 2. Get and check the installer

Download the ISO artifact from the latest **Build installer ISO** run
(Actions tab of the repository; re-run the workflow if it has expired), unzip
it, and check it:

```powershell
(Get-FileHash .\daily-driver-os-stable.iso -Algorithm SHA256).Hash.ToLower()
Get-Content .\daily-driver-os-stable.iso.sha256     # must match
```

## 3. Write the installer stick

Fedora Media Writer (*Select .iso file*), or Rufus (portable, no install) in
**DD image mode**. One installer stick serves every machine until the next
image release.

## 4. Install

1. Plug in the installer stick only. Restart, and open the **one-time boot
   menu** (usually F12; HP F9; ASUS F8 or Esc). Pick the stick. Secure Boot
   stays on.
2. **Installation Destination:** select the internal disk. Keep
   **Automatic** storage configuration. The installer uses the free space; if
   it offers to *reclaim* or *delete* space, cancel and shrink Windows more
   instead. Tick **Encrypt my data** and choose a strong disk passphrase; keep
   it in your password manager. It stays the fallback however the disk ends up
   unlocking ([decision 0021](../decisions/0021-encrypted-root.md)).
3. **Create no user.** The image creates localadmin (UID 1000) itself, and a
   user made here would take that UID. Root is already locked.
4. Begin installation. When it finishes, remove the installer stick.

## 5. First boot

1. Boot. The menu lists this OS first and **Windows Boot Manager** second
   (the Windows entry appears from the second boot on).
2. Type the disk passphrase.
3. Before the login screen, the console asks for the hostname, localadmin's
   password, how the disk should unlock, and the daily users, offering the
   machine defaults where set. Stay at the keyboard.
   Details: [first-boot.md](first-boot.md).

## Reinstall

Reinstalling wipes the Linux side, encrypted homes included; the machine
defaults on the EFI partition survive. Before: `ujust backup-home` each user.
After: skip those users at first boot, then `ujust restore-home` them.
[home-backup.md](home-backup.md).

## Alternative: switch an existing Fedora Atomic install

```bash
sudo bootc switch ghcr.io/OWNER/daily-driver-os:stable
sudo systemctl reboot
```

Any user the old installer created stays in `wheel`, and on UID 1000 it keeps
localadmin from getting that UID. Prefer a fresh install.
