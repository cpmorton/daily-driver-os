# Back up and restore a user's home

Each daily user's home is one encrypted file, `/var/home/<user>.home`. Backing
it up copies that file as it is: still encrypted, openable only with the
user's password. Restoring it on a new install brings everything back, and the
user logs in with their old password.
[Decision 0022](../decisions/0022-home-backup-and-restore.md).

You need a USB drive formatted **exFAT or NTFS** (FAT32 can't hold files over
4 GiB) with room for the user's data.

## Back up (before a reinstall, or regularly)

1. The user logs out.
2. Log in as localadmin, plug in the drive, and run:

   ```bash
   ujust backup-home chris /run/media/localadmin/BACKUP
   ```

   It refuses while chris's home is in use. If chris is logged out but it
   still says so, run `sudo loginctl terminate-user chris` and try again.
   Don't log in as chris until it finishes.

The folder then holds `chris.home.zst` (the home), `chris.public` (the key that
signed chris's account on this install), `chris.json` and `chris.sha256`.

## Restore (after a reinstall, or on another machine)

1. At first boot, answer **[s]kip** for chris. If you created an empty chris
   by mistake, remove it first as localadmin: `sudo homectl remove chris`.
2. Log in as localadmin, plug in the drive, and run:

   ```bash
   ujust restore-home chris /run/media/localadmin/BACKUP
   ```

3. chris logs in with the password they had before.

If chris's old UID is taken on this machine, homed gives them a new one and
fixes file ownership at login. Rootless containers' subordinate IDs are set up
again by the restore.
