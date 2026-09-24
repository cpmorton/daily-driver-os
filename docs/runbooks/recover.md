# Recover

## A bad update

See `upgrade.md`: pick the previous GRUB entry, or `sudo bootc rollback`.

## A root shell (root is locked)

At the GRUB menu, press `e` and append to the `linux` line:

    systemd.setenv=SYSTEMD_SULOGIN_FORCE=1 systemd.unit=emergency.target

Anyone with physical access can do this: the Linux system partition isn't
encrypted. Daily users' homes are LUKS and stay locked.

## Forgotten localadmin password

Get a root shell as above, then `passwd localadmin`.

## Windows missing from the boot menu

`ujust windows-entry` re-detects Windows and writes `/boot/grub2/custom.cfg`.
If a Windows update made Windows the default, change the order back in the
firmware settings (the menu's **UEFI Firmware Settings** entry gets you there).

## An encrypted home from another install

A home copied back after a reinstall is signed by the old installation's key.
Recent systemd can take it over with `homectl adopt`.
[VERIFY that `homectl adopt` exists in the image's systemd and how it treats
LUKS homes, before relying on it.]
