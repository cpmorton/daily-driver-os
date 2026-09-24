# Install or reinstall

Installing wipes the OS stick's `/etc` and `/var`. The home partition survives.
**The internal disk also holds Windows: in every step, check which device you
point at.**

## Before a reinstall

1. Make sure the homed key backup from `first-boot.md` step 4 exists.
2. Note the home partition: `lsblk -f`.

## Path A: installer ISO built from this image (clean)

On any Linux machine with podman:

```bash
just build-iso ghcr.io/OWNER/daily-driver-os stable
```

[VERIFY that the recipe takes a registry reference; if not, run `just build`
first and use the local default.]

Boot the ISO and choose **the USB stick** as the target. Create **no user**:
the image creates localadmin itself, and an installer-made user would be an
unrestricted `wheel` admin. Root is already locked by the kickstart.

## Path B: switch an existing Silverblue or Bluefin install

```bash
sudo bootc switch ghcr.io/OWNER/daily-driver-os:stable
sudo systemctl reboot
```

localadmin gets created and prompts on tty1 at the first boot into this image.
Any user the old installer created is still there, still in `wheel`: once
localadmin works, remove it (`sudo userdel -r <old-user>`).

## After the install

1. Set localadmin's password on tty1 (`first-boot.md` step 1). Skip
   `ujust home-partition`: the partition already holds the homes, so mount it
   as it is:
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
3. Re-run `ujust brew-owner <name>`, since its drop-ins lived in the old `/etc`.
