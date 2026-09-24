# Install or reinstall (from Windows)

No Linux needed. You need a Windows PC, two USB devices, and about an hour.

| Device | Role | Size |
| --- | --- | --- |
| **Installer stick** | Temporary: boots the installer. Erased. | 8 GB or more |
| **OS drive** | Where the OS lives from now on. Erased. | 64 GB or more; an external SSD is much faster than a stick |

**The laptop's internal disk holds Windows. Nothing in these steps touches
it, as long as you pick the right disk in step 6.**

## 0. Before you start

- **BitLocker recovery key.** Booting from USB can make Windows ask for it
  next time. Get it now from <https://aka.ms/myrecoverykey> (or
  `manage-bde -protectors -get C:` in an admin terminal) and keep it off
  the laptop.
- **Reinstalling?** Make sure the homed key backup from `first-boot.md`
  step 4 exists. Without it, existing homes won't unlock.

## 1. Get the ISO

Someone with access to the repository runs **Actions → Build installer ISO →
Run workflow** (tag: `stable`), or `gh workflow run build-iso.yml -f tag=stable`.
It takes 20–40 minutes. Then download the artifact from the run page, or:

```powershell
gh run download --repo OWNER/daily-driver-os --name daily-driver-os-stable-iso
```

Artifacts expire after 14 days; re-run the workflow for a fresh one.

## 2. Check it

```powershell
(Get-FileHash .\daily-driver-os-stable.iso -Algorithm SHA256).Hash.ToLower()
Get-Content .\daily-driver-os-stable.iso.sha256
```

The two hashes must match.

## 3. Write the installer stick

Use **Fedora Media Writer** (`winget install Fedora.FedoraMediaWriter`):
choose *Select .iso file*, pick the ISO, pick the installer stick, write.

Rufus also works: when it asks, choose **DD image mode** (not ISO mode).

## 4. Boot the installer

1. Plug in **both** USB devices. Shut Windows down fully: hold **Shift**
   while clicking *Shut down*, so Fast Startup doesn't leave the disk half
   hibernated.
2. Power on and open the **one-time boot menu** (usually F12; Dell and Lenovo
   F12, HP F9, ASUS F8 or Esc). Pick the installer stick, in UEFI mode.
   Don't change the permanent boot order: that's what tends to trigger
   BitLocker recovery.
3. Secure Boot can stay on: the image uses Fedora's signed kernel and boot
   chain.

## 5. Install

1. Language and keyboard as usual.
2. **Installation destination: select only the OS drive.** Check the size and
   model. Leave the laptop's internal disk and the installer stick unselected.
   Choose automatic partitioning and let it erase the OS drive.
3. **Create no user.** The image creates `localadmin` itself; an
   installer-made user would be an unrestricted administrator. Root is
   already locked.
4. Install, then reboot and remove the installer stick.

## 6. First boot

Use the boot menu again and pick the OS drive, then follow
[first-boot.md](first-boot.md): the console asks for localadmin's password
before the login screen appears.

After installing, the firmware may list the new OS first. If the laptop should
still start Windows by default, move Windows back to the top in the firmware
boot order, or in Windows run `bcdedit /enum firmware` to check.

## Reinstall: after step 5

The home partition already holds the homes, so mount it as it is instead of
running `ujust home-partition`:

1. Set localadmin's password on tty1 (`first-boot.md` step 1), then:
   ```bash
   lsblk -f                         # note the home partition's UUID and FSTYPE
   echo "UUID=<uuid> /var/home <fstype> defaults,nofail,x-systemd.device-timeout=10s 0 0" | sudo tee -a /etc/fstab
   sudo systemctl reboot
   ```
2. Restore the homed keys, then restart homed:
   ```bash
   sudo install -m 0644 local.public  /var/lib/systemd/home/local.public
   sudo install -m 0600 local.private /var/lib/systemd/home/local.private
   sudo systemctl restart systemd-homed
   homectl list                     # existing homes should be listed
   ```
3. Re-run `ujust homed-user <name>` (it skips creating an existing home and
   restores the subordinate IDs rootless podman needs) and
   `ujust brew-owner <name>`; both wrote to the old `/etc`.

## Alternative: switch an existing Fedora Atomic install

A machine already running Silverblue or Bluefin can switch without an ISO:

```bash
sudo bootc switch ghcr.io/OWNER/daily-driver-os:stable
sudo systemctl reboot
```

Any user the old installer created stays in `wheel`: once localadmin works,
remove it (`sudo userdel -r <old-user>`).
