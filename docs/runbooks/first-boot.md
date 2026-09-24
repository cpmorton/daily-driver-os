# First boot

What happens before the login screen, in order, and what to do at each step.

## With a seed stick

Nothing to do. The machine imports the seed, sets the hostname and
localadmin's password, creates each seeded user's encrypted home, deletes the
seed from the stick, and shows the login screen. Each seeded user signs in
with the initial password and must choose a new one (unless the seed said
otherwise).

## Without a seed (or a partial one)

The console asks, on screen, before the login screen:

1. **localadmin's password** (only if the seed didn't provide one). The
   administrator types it, not the machine's user. Save it in the password
   manager, then save its hash too: `ujust localadmin-hash` after first boot.
2. **The first user** (only if the seed had no users): username, full name,
   home size, then the password twice. That password encrypts the home;
   localadmin can't open it. Answer `y` to add another user.

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
