# Make a seed stick (Windows)

A seed stick carries one machine's specifics: hostname, localadmin's password
hash, and its daily users. The installed system imports it once at first boot,
before the login screen, and then **deletes it from the stick**.
[Decision 0018](../decisions/0018-provisioning-seed-stick.md).

## What you need

- Any small USB stick. It gets erased.
- `tools/windows/New-DailyDriverSeed.ps1` from this repository (on GitHub,
  open the file, then **Download raw file**).
- **localadmin's password hash** from your password manager. To get one the
  first time: install one machine *without* a seed (you type localadmin's
  password at first boot), then on it run `ujust localadmin-hash`, and save the
  output. Reuse that hash for every machine. It's a hash, not the password;
  still, keep it private.

## Make it

In PowerShell, from the folder holding the script:

```powershell
# Once per stick: erase it, label it DDSEED, set machine-wide values.
powershell -ExecutionPolicy Bypass -File .\New-DailyDriverSeed.ps1 `
    -Drive E: -Format -Hostname chris-laptop -LocalAdminHash '<hash from the password manager>'

# Once per daily user. Asks for their initial password; they must change it
# at first login.
powershell -ExecutionPolicy Bypass -File .\New-DailyDriverSeed.ps1 `
    -Drive E: -User chris -RealName 'Chris' -HomeSizeGB 200
```

Options:

| Option | Does |
| --- | --- |
| `-SkelPath C:\seed\chris` | Copies that folder into the user's new encrypted home |
| `-LocalAdminSkelPath C:\seed\admin` | Copies that folder into localadmin's home |
| `-NoPasswordChange` | Don't force a new password at first login |
| `-Path D:\somewhere` | Write to a folder instead of a drive (or a second partition) |

Leave out `-LocalAdminHash` and the console asks for localadmin's password at
first boot; leave out `-User` and it asks for the first user.

## Handle it like a password

Until first boot, the stick holds each user's initial password in plain text
(systemd-homed needs the password itself to create the encrypted home). Keep
it with you, and don't put private keys in a skel folder unless you must:
generate SSH keys on the machine, or use a password manager's SSH agent.

## What's on it

```
DDSEED\
  daily-driver-seed\
    seed.json            {"version":1,"hostname":"...","localadmin":{"hashedPassword":"$y$..."}}
    users\chris.json     systemd-homed user record: userName, realName, storage,
                         diskSize, passwordChangeNow, secret.password
    skel\chris\...       optional
    skel\localadmin\...  optional
```

After first boot the stick holds only `IMPORTED.txt`, naming the machine and
time. If the import finds a mistake (a malformed hash, a user without a
password), it changes nothing and leaves the seed in place: fix it and reboot.
