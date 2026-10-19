# Getting started

The whole journey, start to finish, in one place. Each step links to the
runbook with the exact commands; this page is the map, not a replacement for
them.

This image is always installed **beside Windows** on the laptop's internal
disk — it never erases Windows ([decision 0017](decisions/0017-dual-boot-internal-disk.md)).
Every step is prepared from Windows; you do not need a Linux machine anywhere.

---

## 1. Image the machine the first time

All of this happens on Windows. The two routes differ only in how you carry
the installer; both end at the same Anaconda installer.

### Prepare Windows (once per machine)

Shrink `C:` by 100 GB+, turn Fast Startup off, set the hardware clock to UTC,
and save your BitLocker recovery key somewhere off the laptop. The exact
PowerShell is in **[runbooks/reinstall.md](runbooks/reinstall.md) § 1**.

### Get the installer

The installer ISO is built in CI, not by hand ([decision 0016](decisions/0016-installer-built-in-ci.md)):
**Actions → Build installer ISO → Run workflow → tag `stable`** (~15 min),
then download and `sha256`-check the artifact.

Then pick one route:

- **With a USB stick** (simplest): write the ISO with Rufus (DD mode) or Fedora
  Media Writer. Full steps: **[runbooks/reinstall.md](runbooks/reinstall.md) §§ 2–4**.
- **Without a USB stick** (first-class, keeps a reinstall partition on the
  machine forever): carve an 8 GiB FAT32 `DDINSTALL` partition out of the free
  space, copy the ISO contents onto it, relabel, and boot it once. Full steps:
  **[runbooks/reinstall-no-usb.md](runbooks/reinstall-no-usb.md)**. Parts of
  this route are **[VERIFY]** — not yet proven on hardware.

### Install

Boot the installer (one-time boot menu, usually **F12**). Pick the internal
disk, keep **Automatic** storage, tick **Encrypt my data** and choose a strong
disk passphrase, and **create no user** — the image makes `localadmin` itself.
Details and the traps to watch: **[runbooks/reinstall.md](runbooks/reinstall.md) § 4**.

## 2. First boot

Someone has to be at the keyboard. Before the login screen the console asks, in
order, for: the disk passphrase, the hostname, `localadmin`'s password, how the
disk should unlock (`tpm2-pin` by default; `fido2`, `passphrase` or bare `tpm2`
too), and the daily users. Each question offers the machine defaults where you
set them. Full walkthrough: **[runbooks/first-boot.md](runbooks/first-boot.md)**.

Then, per account — your dotfiles apply themselves at first login if localadmin
named a repo for you, and update daily after
([decision 0024](decisions/0024-dotfiles-apply-themselves.md)):

```bash
ujust dotfiles [github-user]   # only when asked, or to set up dotfiles nobody named for you
gh auth login --web            # GitHub sign-in
claude                         # Claude Code: sign in with your claude.ai account
```

Flatpaks (Signal, Discord, LibreOffice, Obsidian, GIMP, Podman Desktop) install
in the background once you're online.

## 3. Daily driving

The image owns everything under `/usr`; you move between image digests to
update, roll back or reinstall. You never patch the running system in place.

### Update and roll back

`uupd` updates automatically on a schedule and once the laptop is on AC power;
the new image stages and takes effect at the next boot. To drive it by hand:

```bash
sudo bootc status             # booted / staged / rollback deployments
sudo bootc upgrade --check    # is there a newer digest?
sudo bootc upgrade            # stage it now
sudo systemctl reboot
```

Roll back by picking the previous entry in the GRUB menu, or:

```bash
sudo bootc rollback && sudo systemctl reboot
```

Two channels ([decision 0014](decisions/0014-nightly-builds-and-release-channels.md)):
`:stable` is what the laptop follows; `:stable-testing` is every push to `main`
plus the daily build, for trying a change first.

```bash
sudo bootc switch ghcr.io/cpmorton/daily-driver-os:stable-testing   # and back to :stable
```

More: **[runbooks/upgrade.md](runbooks/upgrade.md)**, **[runbooks/recover.md](runbooks/recover.md)**.

### Installing new software

There are two ways, and the right one depends on *who* the software is for
([decision 0004](decisions/0004-where-software-goes.md)):

- **Just for this machine, right now, no rebuild** — the daily-driver way:
  - GUI app → `flatpak install …` (Flathub)
  - CLI tool → `brew install …` (Homebrew; `ujust brew-owner <name>` first to
    let a daily user run it)
  - A one-off system package can be layered with `rpm-ostree install …`, but
    that's the escape hatch: it's re-applied on every update and is easy to
    forget. Prefer the image route below.
- **Baked into the image, for every machine and every rebuild** — edit this
  repo, push, let the daily build publish it, then `bootc upgrade` on the
  laptop. Where each kind goes:
  | Kind | Lives in |
  | --- | --- |
  | System package (dnf) | `build/20-packages-and-services.sh` or `build/70-daily-driver.sh` |
  | CLI tool | `custom/brew/` |
  | GUI app (Flatpak) | `custom/flatpaks/` |
  | `ujust` command | `custom/ujust/` |

  The [`customize`](../.agents/skills/customize/SKILL.md) skill decides which
  one a given package belongs in.

---

New to the vocabulary (Silverblue, bootc, homed, finpilot, …)? Start with
**[GLOSSARY.md](GLOSSARY.md)**, then **[ARCHITECTURE.md](ARCHITECTURE.md)**.
