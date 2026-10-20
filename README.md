# daily-driver-os

My daily-driver workstation as a bootc image: Fedora Silverblue with Bluefin's
shared layer (`projectbluefin/common`), built from the
[finpilot](https://github.com/projectbluefin/finpilot) template and published to
GHCR. Updating, rolling back or reinstalling the machine means moving between
image digests; the image owns everything under `/usr`.

What the image does **not** own: user state (the
[`dotfiles`](https://github.com/cpmorton/dotfiles) repository, applied with
chezmoi), secrets (never in any repository), and account-side integrations
(claude.ai connectors, GitHub, Google).

**New here? Start with [docs/README.md](docs/README.md)**: glossary,
architecture, decision records, and a provenance inventory of everything on
the machine. On a running machine, `ujust provenance <path>` says where any
file came from.

## Getting started

Full on-ramp: **[docs/GETTING_STARTED.md](docs/GETTING_STARTED.md)**. In short:

1. **Image it from Windows** (the laptop dual-boots beside Windows; no Linux
   needed to install). Build the installer ISO in CI, then either write a USB
   stick or use the stickless [on-disk installer](docs/runbooks/reinstall-no-usb.md).
2. **First boot** asks for the disk passphrase, hostname, localadmin password,
   disk-unlock method and daily users — all at the console.
3. **Daily driving** is a bootc loop: `sudo bootc upgrade` / `rollback` (uupd
   also updates on its own), and roll back from the GRUB menu if a boot goes
   bad. Install GUI apps with Flatpak and CLI tools with Homebrew; bake
   anything system-wide into the image itself.

## What makes this raptor different

Based on `quay.io/fedora-ostree-desktops/silverblue:44` plus
`projectbluefin/common` and `ublue-os/brew`, as upstream finpilot is.

### Added packages (build time)

- **Google Chrome** (`google-chrome-stable`), from Fedora's third-party repository
- **Visual Studio Code**, from Microsoft's repository. The Dev Containers
  extension installs on each user's first login.
- **Claude Code CLI**, from Anthropic's signed dnf repository (stable channel),
  with machine-wide guardrails in `/etc/claude-code/managed-settings.json`
- **gh**, **chezmoi**, **systemd-homed**, from Fedora
- **podman-docker** and **podman-compose**: `docker` and `docker-compose` run
  rootless podman, so devcontainers work for every account with no settings

### Added applications (first boot, Flatpak)

Signal, Discord, LibreOffice, Obsidian, GIMP and Podman Desktop (`custom/flatpaks/daily.preinstall`),
alongside upstream's `default.preinstall`.

### Accounts and access

- **root**: password locked, in the image and in the installer kickstart.
- **localadmin** (UID 1000, `wheel`): the administrator's account on every
  machine, not the user's. Created by `sysusers.d`; its password is set at
  first boot, from a hash in the machine defaults or typed on tty1; never in
  this repository.
  Console, GDM, su, sudo and polkit only: `pam_access` refuses it anywhere
  `PAM_RHOST` is set, and sshd denies it. No SSH key.
- **Daily users**: systemd-homed, each home its own LUKS-encrypted file that
  localadmin can't open. Created at first boot: from the machine defaults or
  asked on screen, passwords always typed on screen. Not in `wheel`.

### Removed or disabled

- Rootful podman: the system `podman.socket` that upstream enables is masked,
  with the rest of the rootful units. Each user gets a rootless socket.
- `debug-shell.service` (root shell on tty9) and `gnome-remote-desktop.service`
  (system RDP authenticates through GDM) are masked.
- Upstream's `/opt -> /var/opt` symlink: `/opt`, `/usr/local` and `/root` are
  real, read-only, image-owned directories here.

### Configuration changes

- Journal is volatile (`Storage=volatile`): nothing persists across boots,
  including the logs of a boot you rolled back from.
- `/tmp` is tmpfs (asserted at build time).
- `DOCKER_HOST` points every app at the user's rootless podman socket.
- Git defaults and GitHub credentials through gh are system-wide
  (`/etc/gitconfig`); the dotfiles only add your name and email, and apply
  themselves at login.
- The image rebuilds daily, so baked-in RPMs pick up upstream releases on
  `:stable-testing`; a release carries them to `:stable`.

## Set up a machine

| Step | Where | Runbook |
| --- | --- | --- |
| Set a machine's defaults (optional) | Windows | [docs/runbooks/machine-defaults.md](docs/runbooks/machine-defaults.md) |
| Back up or restore a user's home | Linux | [docs/runbooks/home-backup.md](docs/runbooks/home-backup.md) |
| Install beside Windows | installer stick | [docs/runbooks/reinstall.md](docs/runbooks/reinstall.md) |
| First boot: localadmin, daily users | console | [docs/runbooks/first-boot.md](docs/runbooks/first-boot.md) |
| Update or roll back | any time | [docs/runbooks/upgrade.md](docs/runbooks/upgrade.md) |
| Something broke | | [docs/runbooks/recover.md](docs/runbooks/recover.md) |

## Set up this repository on GitHub

The published name is the repository name; three files carry it as a literal
and `just test-contract` fails if they disagree (`Containerfile` twice,
`Justfile`). [The `onboarding` skill](.agents/skills/onboarding/SKILL.md) covers
the rest: Actions, auto-merge, the Renovate token, branch protection and
labels. Claude Code in this repository reads it through
`.claude/skills` (see [CLAUDE.md](CLAUDE.md)).

## What's included

**Build system**

- A build on every push to `main` and once a day, publishing `:stable-testing`
- A dispatched release that promotes the tested digest to `:stable`
- Renovate through `projectbluefin/actions`, updating pinned actions and image
  digests weekly
- Images older than 90 days pruned automatically
- Pull requests validated for shellcheck, hadolint, Brewfiles, Flatpaks,
  Justfiles, and Renovate config
- Keyless OIDC signing on every published image

**Runtime**

- Homebrew, pre-staged at build time and unpacked on first boot
- Flatpaks declared in `custom/flatpaks/`, installed on first boot
- `ujust` shortcuts for the Brewfiles and for re-applying configuration
- `uupd` for scheduled system updates

## Customize

Pick your base image on the `Containerfile`'s `FROM` line; the template defaults
to Fedora Silverblue. That line is the only place the base is chosen: `just build`
reads the image name and the tag from it, and the Fedora major comes from the
base image itself during the build.

Then add to your image:

- **System packages** — `build/20-packages-and-services.sh` ([guide](build/README.md))
- **CLI tools** — `custom/brew/` ([guide](custom/brew/README.md))
- **GUI apps** — `custom/flatpaks/` ([guide](custom/flatpaks/README.md))
- **Commands** — `custom/ujust/` ([guide](custom/ujust/README.md))

[The `customize` skill](.agents/skills/customize/SKILL.md) decides which of
those a given package belongs in.

## Releases

One long-lived branch, `main`; work lands on it from feature branches by PR
([decision 0025](docs/decisions/0025-trunk-based-releases.md)).

| Image tag              | Moves when                          | Audience            |
| ---------------------- | ----------------------------------- | ------------------- |
| `:stable-testing`      | every push to `main`, and daily     | trying a change     |
| `:stable`              | a release                           | the laptop          |
| `:<version>`           | never: one per release              | pinning a machine   |

To release, run **Actions → Release → Run workflow**. It verifies the cosign
signature on the current `:stable-testing` digest, copies that same digest to
`:stable` and `:<version>` (it never rebuilds), and records git tag
`v<version>` with a GitHub Release holding the digest. Give it an earlier
version to roll `:stable` back.

> **Known gap:** the release checks the signature only. It runs no end-to-end
> tests, so a release means "signed and unmodified", not "functionally
> validated". Boot `:stable-testing` first.

## Image signing

CI signs every image with keyless OIDC via Cosign; there is no key to manage.

```bash
cosign verify \
  --certificate-identity-regexp="https://github.com/cpmorton/daily-driver-os/.github/workflows/" \
  --certificate-oidc-issuer="https://token.actions.githubusercontent.com" \
  ghcr.io/cpmorton/daily-driver-os:stable
```

The release refuses an unsigned image, so `:stable` stays where it was until
signing is restored.

> **The laptop does not enforce this signature.** `projectbluefin/common`'s
> `/etc/containers/policy.json` accepts any `docker` registry it doesn't name,
> and a keyless GitHub Actions identity can't be expressed there: the policy's
> Fulcio matcher requires `subjectEmail`, and Actions certificates carry a
> workflow URI instead. Enforced verification needs key-based signing plus a
> `sigstoreSigned` entry for this repository, which is how `ghcr.io/ublue-os`
> is configured. Until then, the trust anchors are TLS to GHCR and the GitHub
> account.

## Local testing

```bash
just build            # build the container image
just build-qcow2      # build a QCOW2 disk image
just run-vm-qcow2     # boot it in a browser-based VM
just build-iso        # build an installer ISO
just test-unit        # run the test suite
```

## Troubleshooting

[The `troubleshooting` skill](.agents/skills/troubleshooting/SKILL.md) covers
build, CI, and runtime failures symptom-first. The two most common first-boot
surprises:

- **No Flatpaks.** `flatpak-preinstall.service` needs a network connection and
  reports success even when it cannot reach Flathub, so a first boot before
  Wi-Fi is configured installs nothing. Reboot once you are online.
- **No `brew`.** `brew-setup.service` unpacks Homebrew on first boot; check its
  status before reaching for a reinstall.

## Community

- [Universal Blue Discord](https://discord.gg/WEu6BdFEtp)
- [bootc discussions](https://github.com/bootc-dev/bootc/discussions)

## Learn more

- [Universal Blue](https://universal-blue.org/)
- [bootc](https://containers.github.io/bootc/)
- [Project Bluefin contributing guide](https://docs.projectbluefin.io/contributing/)

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).
