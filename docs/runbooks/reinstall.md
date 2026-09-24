# Install or reinstall (dual boot, from Windows)

Linux goes into free space on the laptop's internal disk, beside Windows. No
Linux needed anywhere; everything is prepared on Windows.
[Decision 0017](../decisions/0017-dual-boot-internal-disk.md).

| You need | For |
| --- | --- |
| **Installer stick**, 8 GB+ | The generic installer ISO. Erased when written; reusable for every machine. |
| **Seed stick** (optional), any size | This machine's hostname, user names and files for their homes; no passwords. [seed-stick.md](seed-stick.md). |
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
   instead.
3. **Create no user.** The image creates localadmin (UID 1000) itself, and a
   user made here would take that UID. Root is already locked.
4. Begin installation. When it finishes, remove the installer stick.

## 5. First boot

1. If you made a seed stick, plug it in now.
2. Boot. The menu lists this OS first and **Windows Boot Manager** second
   (the Windows entry appears from the second boot on).
3. Before the login screen, the console imports the seed (if any), then asks
   for localadmin's password, then each daily user's. Stay at the keyboard.
   Details: [first-boot.md](first-boot.md).
4. Remove the seed stick; first boot deleted the seed from it.

## Reinstall

Reinstalling wipes the Linux side, encrypted homes included. Before: copy each
`/var/home/<user>.home` file somewhere safe (it's one file per user, still
encrypted). After: copy it back to `/var/home/` and run `sudo homectl list`;
if the home is listed as unsigned by this machine, see
[recover.md](recover.md#an-encrypted-home-from-another-install).

## Alternative: switch an existing Fedora Atomic install

```bash
sudo bootc switch ghcr.io/OWNER/daily-driver-os:stable
sudo systemctl reboot
```

Any user the old installer created stays in `wheel`, and on UID 1000 it keeps
localadmin from getting that UID. Prefer a fresh install.
