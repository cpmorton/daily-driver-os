# First boot

From a fresh install (see `reinstall.md`) to a working daily user.

## 1. Set localadmin's password (tty1, before GDM)

The console asks for it before the login screen appears. A mistyped
confirmation or a password pwquality rejects just asks again.

## 2. Log in as localadmin and give /var/home its own partition

Daily users' encrypted home images belong on the internal disk, not on the OS
stick. The recipe copies the current `/var/home` across and adds an fstab entry;
it never formats anything.

```bash
lsblk -f                                   # find the empty partition; the internal disk also holds Windows
sudo mkfs.btrfs -L home /dev/nvme0n1pN     # only if it has no filesystem yet; triple-check N
ujust home-partition /dev/nvme0n1pN
sudo systemctl reboot
findmnt /var/home                          # after the reboot: must show the partition
```

## 3. Create the daily user

```bash
ujust homed-user <name> 200G               # asks for the new user's password
ujust brew-owner <name>                    # Homebrew has one owner; make it this user
```

## 4. Back up systemd-homed's signing keys, off this stick

Every homed home is signed by this machine's key pair. Lose it, for example to
a reinstall, and existing homes come back as unsigned by this host.

```bash
sudo tar -C /var/lib/systemd/home -czf /tmp/homed-keys.tgz local.public local.private
# Move it somewhere safe that isn't the OS stick (password manager attachment,
# encrypted USB). It is a private key: never into a repository.
```

## 5. Sign in as the daily user

```bash
ujust dotfiles <github-user>               # chezmoi; runs gh auth login on first apply
claude                                     # Claude Code: browser sign-in with your claude.ai account
```

Sign in to claude.ai in Chrome for chat, connectors and cloud sessions.
Flatpaks install in the background after the first login; check with
`systemctl status flatpak-preinstall.service`.
