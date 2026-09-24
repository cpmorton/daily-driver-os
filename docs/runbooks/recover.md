# Recover

## A bad update

See `upgrade.md`: pick the previous GRUB entry, or `sudo bootc rollback`.

## A root shell (root is locked)

At the GRUB menu, press `e` and append to the `linux` line:

    systemd.setenv=SYSTEMD_SULOGIN_FORCE=1 systemd.unit=emergency.target

Anyone with physical access can do this, and the OS stick is not encrypted:
the stick is exactly as sensitive as the machine. Daily users' homes are LUKS
and stay locked.

## Forgotten localadmin password

Get a root shell as above, then `passwd localadmin`.

## Lost homed keys

Homes signed by a key this machine no longer has won't activate. Restore
`local.public` / `local.private` from the backup (see `reinstall.md`). Without
a backup, recent systemd can take over an existing home with `homectl adopt`.
[VERIFY that `homectl adopt` exists in the image's systemd and how it handles
LUKS homes, before relying on it.]

## Home partition missing at boot

`/var/home` is mounted `nofail`, so the system still boots; homed users can't
log in, but localadmin can on the console. Check `lsblk -f` and `/etc/fstab`.
