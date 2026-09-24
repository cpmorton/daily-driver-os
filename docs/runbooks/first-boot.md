# First boot

What happens before the login screen, in order. Someone has to be at the
keyboard. Where the machine has defaults ([machine-defaults.md](machine-defaults.md)),
each question shows one in brackets: **Enter accepts it**, or type another
answer. If first boot is interrupted, it picks up after the last finished step.

1. **Disk passphrase** (if you ticked *Encrypt my data*): the one you chose in
   the installer. Only this once, if you pick TPM2 below.
2. **Hostname.**
3. **localadmin's password.** From the defaults (*Use localadmin's password
   from the machine defaults? [Y/n]*), or typed twice by the administrator,
   never the machine's user. Weak passwords are refused.
4. **Disk unlock**, below.
5. **Daily users.** For each user in the defaults: **[C]reate** now, or
   **[s]kip** to restore their backed-up home afterwards
   ([home-backup.md](home-backup.md)). Then any more users (username, full
   name, home size). For each new user:
   - *Is \<user\> at the keyboard to choose their own password?* Yes: they type
     it. No: you type a first password, and they must change it at their first
     login.
   - The password, twice. It encrypts that user's home; localadmin can't open
     or recover it.

The login screen appears when it's done.

## Disk unlock

How the encrypted disk opens at every boot
([decision 0021](../decisions/0021-encrypted-root.md)):

| Method | At boot | Needs |
| --- | --- | --- |
| `tpm2` | Nothing to type. But whoever holds the laptop can get a root shell from the GRUB menu (not users' homes) | A TPM2 chip (most laptops since 2016) |
| `tpm2-pin` | A short PIN | A TPM2 chip |
| `fido2` | Plug in and touch the security key (and its PIN, if set) | A FIDO2 key such as a YubiKey. Enroll a spare when asked |
| `passphrase` | The installer's passphrase | Nothing |

Enrolling asks for the installer passphrase once. That passphrase keeps
working as a fallback whatever you pick. Changing methods later
(`ujust disk-unlock`) removes the previous TPM or security-key enrollment.
Then comes the **recovery key**: answer yes, and save the key it shows (text,
plus a QR code for your phone) in your password manager. It is shown once.

If the root isn't encrypted, first boot says so in `!!!` lines. Reinstall with
*Encrypt my data* ticked to fix that.

## After first boot (localadmin)

```bash
ujust homed-user <name> 100G           # more users later; each gets its own encrypted home
ujust restore-home <name> <folder>     # bring back a backed-up home (see home-backup.md)
ujust disk-unlock                      # change the unlock method, or re-enroll the TPM
ujust brew-owner <name>                # optional: let a daily user run brew install
```

## After first boot (each user)

```bash
ujust dotfiles <github-user>      # git identity and GitHub sign-in (the dotfiles repository)
claude                            # Claude Code: sign in with your claude.ai account
```

Flatpaks (Signal, Discord, LibreOffice, Obsidian, GIMP, Podman Desktop, plus
the defaults' extras) install in the background:
`systemctl status flatpak-preinstall.service`.

## If Windows is missing from the boot menu

`ujust windows-entry` (as localadmin) re-detects it. The one-time boot menu
(F12) always works too.
