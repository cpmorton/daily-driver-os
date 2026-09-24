# First boot

What happens before the login screen, in order, and what to do at each step.
Someone has to be at the keyboard: every password is typed here
([decision 0019](../decisions/0019-no-seeded-passwords.md)).

1. **Seed stick** (if one is plugged in). Imported silently: hostname,
   user names, skel files. Then the seed is deleted from the stick.
2. **localadmin's password.** The administrator types it, twice, not the
   machine's user. Save it in the password manager. Weak passwords are
   refused; it asks again.
3. **Daily users.** For each user on the seed stick, or, with no stick, for
   each user you enter (username, full name, home size in GB, default 100):
   - *Is \<user\> at the keyboard to choose their own password?* Answer `Y`
     (default) and let them type it. Answer `n` if you're typing an initial
     password for them; they must choose a new one at their first login.
   - The password, twice. It encrypts that user's home; localadmin can't open
     or recover it.
   - Then *Create another user?*

The login screen appears once all users exist.

## After first boot (localadmin)

```bash
ujust homed-user <name> 100G      # more users later; each gets its own encrypted home
ujust brew-owner <name>           # optional: let a daily user run brew install
```

## After first boot (each user)

```bash
ujust dotfiles <github-user>      # git identity and GitHub sign-in (the dotfiles repository)
claude                            # Claude Code: sign in with your claude.ai account
```

Flatpaks (Signal, Discord, LibreOffice, Obsidian, GIMP, Podman Desktop)
install in the background after the first login:
`systemctl status flatpak-preinstall.service`.

## If Windows is missing from the boot menu

`ujust windows-entry` (as localadmin) re-detects it. The one-time boot menu
(F12) always works too.
