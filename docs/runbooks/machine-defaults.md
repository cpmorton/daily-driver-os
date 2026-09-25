# Set a machine's defaults (Windows, optional)

The defaults pre-fill first boot's questions for one machine: hostname,
localadmin's password (as a hash), how the encrypted disk unlocks, the daily
users, and extra Flatpaks. First boot shows each one; **Enter accepts it**, or
type something else. No user's password is ever stored: each is typed at
first boot. [Decision 0020](../decisions/0020-machine-defaults-on-the-esp.md).

The defaults live in one small file on the machine's EFI partition, which
Windows and Linux share. Reinstalling Linux keeps it, so a reinstall offers the
same answers again. Without it, first boot simply asks.

## Run it

On the machine itself, in Windows: open PowerShell with **Run as
administrator** (only administrators can reach the EFI partition), then, from
the folder holding `tools/windows/Set-DailyDriverDefaults.ps1` (on GitHub: open
the file, then **Download raw file**):

```powershell
Set-ExecutionPolicy -Scope Process Bypass     # this window only

# Machine values. Asks for localadmin's password twice; stores only its hash.
.\Set-DailyDriverDefaults.ps1 -Hostname lap-01 -SetLocalAdminPassword -DiskUnlock tpm2-pin

# One run per daily user; run again to change one.
.\Set-DailyDriverDefaults.ps1 -User chris -RealName 'Chris' -Uid 60101 -Shell /bin/bash -HomeSizeGB 200
.\Set-DailyDriverDefaults.ps1 -User violet -RealName 'Violet' -MustChangePassword

.\Set-DailyDriverDefaults.ps1 -AddFlatpak org.gnome.Boxes    # extra apps, from Flathub
.\Set-DailyDriverDefaults.ps1                                # show what's set
```

| Option | Does |
| --- | --- |
| `-Hostname NAME` | The machine's name |
| `-SetLocalAdminPassword` | Asks for localadmin's password (12+ characters) and stores its SHA-512 crypt hash |
| `-LocalAdminHash '$6$...'` | Stores a hash you already have, e.g. from another machine's `/etc/shadow` (`$y$` works too) |
| `-ClearLocalAdminPassword` | Removes the hash: first boot asks for the password |
| `-DiskUnlock tpm2-pin` | Default unlock method: `tpm2-pin` (the default without this option, when there's a TPM), `tpm2`, `fido2` (security key) or `passphrase`. [first-boot.md](first-boot.md#disk-unlock) |
| `-User NAME` | Adds or updates a daily user. With `-RealName`, `-Uid` (60001-60513), `-Shell` (e.g. `/bin/zsh`; must exist in the image), `-HomeSizeGB` (default 100), `-MustChangePassword` (you'll type their first password; they change it at first login) |
| `-RemoveUser NAME` | Removes a user from the defaults |
| `-AddFlatpak ID`, `-RemoveFlatpak ID` | Extra Flatpaks for this machine, beyond the image's |
| `-PrintHash` | Just prints a hash for a password you type, e.g. for your password manager |
| `-Delete` | Removes the defaults file |

Same users and administrator password on several machines: run the same
commands on each one's Windows. `-LocalAdminHash` with a hash kept in your
password manager avoids retyping the password.

## Keep in mind

- localadmin's hash is readable by anyone who can read this disk; the EFI
  partition can't be encrypted. The 12-character minimum and 500,000 hashing
  rounds make guessing slow, not impossible. Once a machine is set up, you can
  remove the hash (`-ClearLocalAdminPassword`) and type it on a reinstall.
- A mistake in the file (it's checked at first boot) means first boot ignores
  it all and asks for everything; the console says why.

## What's in it

`\EFI\daily-driver\defaults.json`:

```json
{
  "version": 1,
  "hostname": "lap-01",
  "localadmin": { "hashedPassword": "$6$rounds=500000$..." },
  "diskUnlock": "tpm2",
  "users": [
    { "userName": "chris", "realName": "Chris", "uid": 60101,
      "shell": "/bin/bash", "diskSize": 214748364800, "passwordChangeNow": false }
  ],
  "flatpaks": ["org.gnome.Boxes"]
}
```

First boot reads only these fields. Anything else is logged and ignored, so the
file can't give anyone a password or administrator rights.
