# Recover

## A bad update

See `upgrade.md`: pick the previous GRUB entry, or `sudo bootc rollback`.

## A root shell (root is locked)

At the GRUB menu, press `e` and append to the `linux` line:

    systemd.setenv=SYSTEMD_SULOGIN_FORCE=1 systemd.unit=emergency.target

The disk still has to unlock first. With `passphrase`, `tpm2-pin` or `fido2`
that takes the secret; with plain `tpm2` it doesn't, so anyone at the keyboard
can do this ([decision 0021](../decisions/0021-encrypted-root.md)). Daily
users' homes are LUKS and stay locked either way.

## Forgotten localadmin password

Get a root shell as above, then `passwd localadmin`.

## Windows missing from the boot menu

`ujust windows-entry` re-detects Windows and writes `/boot/grub2/custom.cfg`.
If a Windows update made Windows the default, change the order back in the
firmware settings (the menu's **UEFI Firmware Settings** entry gets you there).

## The disk asks for its passphrase after an update

A firmware or Secure Boot database update changed what the TPM measured
(PCR 7), so the TPM no longer releases the key. Type the passphrase (or the
recovery key), then re-enroll as localadmin: `ujust disk-unlock tpm2`.

## A lost or broken security key

Unlock with the passphrase, the recovery key or the spare key, then
`ujust disk-unlock fido2` enrolls a new one. Remove the lost key's slot with
`sudo systemd-cryptenroll --wipe-slot=fido2 <device>` and re-enroll the keys
you still have (`sudo systemd-cryptenroll <device>` lists the slots; the
device is the `crypto_LUKS` one in `lsblk -f`).

## An encrypted home from another install

Use `ujust restore-home`: [home-backup.md](home-backup.md). It trusts the old
install's signing key and registers the home.
