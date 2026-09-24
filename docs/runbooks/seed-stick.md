# Make a seed stick (Windows, optional)

A seed stick carries one machine's specifics: its hostname, its daily users'
names and home sizes, and optional files for their homes. **No passwords**:
the console asks for every password at first boot
([first-boot.md](first-boot.md)). The installed system imports the stick once,
before the login screen, and then **deletes the seed from it**.
Decisions [0018](../decisions/0018-provisioning-seed-stick.md) and
[0019](../decisions/0019-no-seeded-passwords.md).

Without a seed stick, the console asks for the users instead, and the hostname
comes from the installer. The stick saves typing and copies files; nothing
else.

## What you need

- Any small USB stick. It gets erased.
- `tools/windows/New-DailyDriverSeed.ps1` from this repository (on GitHub,
  open the file, then **Download raw file**).

## Make it

In PowerShell, from the folder holding the script:

```powershell
# Once per stick: erase it, label it DDSEED, set the hostname.
powershell -ExecutionPolicy Bypass -File .\New-DailyDriverSeed.ps1 `
    -Drive E: -Format -Hostname chris-laptop

# Once per daily user.
powershell -ExecutionPolicy Bypass -File .\New-DailyDriverSeed.ps1 `
    -Drive E: -User chris -RealName 'Chris' -HomeSizeGB 200
```

Options:

| Option | Does |
| --- | --- |
| `-SkelPath C:\seed\chris` | Copies that folder into the user's new encrypted home |
| `-LocalAdminSkelPath C:\seed\admin` | Copies that folder into localadmin's home |
| `-Path D:\somewhere` | Write to a folder instead of a drive (or a second partition) |

Running the script on a stick made by an older version removes any password
or password hash that version stored.

## Skel folders

The stick itself holds nothing secret, but whatever you put in a skel folder
travels on it, readable, until first boot. Keep private keys out: generate SSH
keys on the machine, or use a password manager's SSH agent.

## What's on it

```
DDSEED\
  daily-driver-seed\
    seed.json            {"version":1,"hostname":"..."}
    users\chris.json     {"userName":"chris","realName":"Chris","diskSize":<bytes>}
    skel\chris\...       optional
    skel\localadmin\...  optional
```

First boot reads only those fields. Anything else in a user file (a password,
group membership) is logged and ignored, so a stick can't make anyone an
administrator.

After first boot the stick holds only `IMPORTED.txt`, naming the machine and
time. If the import finds a mistake (a bad hostname, a user file named
differently from its `userName`, a home under 10 GB), it changes nothing and
leaves the seed in place. The console still asks for localadmin's password
and for users. The import tries again at every boot until it succeeds, so fix
the stick or unplug it.
