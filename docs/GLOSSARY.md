# Glossary

Every name this repository uses, what it is, and how it relates to this image.
Entries are grouped from the bottom of the stack up. Facts were checked against
upstream source on 2026-09-23; the ecosystem moves fast, so the
[decision records](decisions/README.md) say what to re-check and when.

## The operating system

**Fedora Atomic Desktops**
: Fedora's family of image-based desktops: the same RPMs as Fedora Workstation,
  composed by Fedora into complete filesystem trees and shipped whole.

**Silverblue**
: The GNOME member of the Atomic Desktops (Kinoite is KDE). Formerly "Fedora
  Atomic Workstation", renamed in 2018. This image's base is
  `quay.io/fedora-ostree-desktops/silverblue:44`, pinned by digest in the
  `Containerfile` and bumped by Renovate.

**OSTree**
: "Git for operating system binaries": content-addressed storage of filesystem
  trees, plus *deployments*. Still the storage layer under bootc.

**rpm-ostree**
: The older update client that turns RPMs into OSTree commits and supports
  *package layering* (`rpm-ostree install` on a running machine). This image
  never layers packages, and its updates are driven by bootc through uupd.

**bootc**
: The container-native update client. The OS is a bootable OCI image; `bootc
  upgrade`, `bootc switch` and `bootc rollback` move a machine between image
  digests. This whole repository exists to produce such an image.

**Deployment**
: One bootable version of the OS on disk. bootc keeps the booted one plus a
  staged or rollback one; each has its own bootloader entry.

**composefs**
: The read-only mount that serves the deployment's `/`. Anything baked into the
  image (including `/opt`, `/usr/local` and `/root` here) is read-only at runtime.

**`/etc` three-way merge**
: On every update, bootc carries local edits in `/etc` forward. A file edited on
  the machine stops receiving the image's changes. See *drift*.

**`/var`**
: The one persistent, writable tree, shared by all deployments and never
  touched by updates. Image content in `/var` is copied only at install.

**Drift**
: The difference between a machine's `/etc` and the image's default `/etc`.
  `ujust etc-drift` lists it.

## The ecosystem

**Universal Blue (`ublue-os`)**
: The community organization that pioneered customized Fedora Atomic images.
  It still hosts shared pieces this image uses: the `ghcr.io/ublue-os/brew`
  layer and the `ublue-os/packages` COPR that provides uupd.

**Bluefin**
: An opinionated GNOME developer workstation built on Silverblue. Moved from
  `ublue-os` to its own `projectbluefin` organization in July 2026 and publishes
  `ghcr.io/projectbluefin/bluefin` and `bluefin-nvidia`. This image is *not*
  Bluefin; it shares Bluefin's plumbing (see finpilot).

**`projectbluefin/common`**
: A container image carrying files, not an OS. Three parts:
  - `shared/`: plumbing (ujust, first-boot hooks, the Flatpak and Homebrew
    services, the container trust policy). **This image uses it.**
  - `bluefin/`: Bluefin's product opinions, including branding and the
    `devmode` recipe. **This image does not use it.**
  - `nvidia/`: NVIDIA support. Not used.

**`ublue-os/brew`**
: A container image carrying a Homebrew tarball, its systemd units
  (`brew-setup`, `brew-update`, `brew-upgrade`) and shell integration.

**finpilot**
: The template this repository was generated from: assemble your own image from
  a Fedora base plus common's `shared/` layer plus brew, the same inputs Bluefin
  uses, but without Bluefin's product layer.
  [decision 0001](decisions/0001-assemble-with-finpilot.md)

**Dakota**
: Bluefin rebuilt on GNOME OS and freedesktop-sdk, with no RPMs. In alpha and
  published as a separate edition. Worth watching; not a base for this image.

**DX, `bluefin-dx`**
: Bluefin's former developer edition: a separate, heavier image. Retired in
  2026 when developer tooling moved into user space.

**devmode**
: Before 2026, `ujust devmode` rebased between `bluefin` and `bluefin-dx`. Now
  it's an interactive picker in common's `bluefin/` layer that installs tools per
  user, mostly through Homebrew. Not available in this image.
  [decision 0007](decisions/0007-developer-experience-baked-in.md)

**GDX, aimode**
: The AI/ML equivalents of DX and devmode. Not relevant here.

## Running the machine

**ujust**
: Universal Blue's `just` wrapper for user-facing recipes. This image's are in
  `custom/ujust/daily-driver.just`; upstream's are in the other `.just` files.

**uupd**
: The auto-updater (from the `ublue-os/packages` COPR). It stages new images,
  and on a laptop waits for AC power.

**`:stable`, `:stable-testing`**
: Image tags. `main` builds `:stable-testing`; the release gate promotes that
  exact digest to `:stable`. [decision 0014](decisions/0014-nightly-builds-and-release-channels.md)

**Flatpak, Flathub, preinstall**
: Sandboxed GUI apps from the Flathub remote. `*.preinstall` files declare
  apps that `flatpak-preinstall.service` installs on first boot. The
  declaration is in the image; installed apps live in `/var`.

**Homebrew**
: A package manager for command-line tools that installs into
  `/home/linuxbrew`, outside the image. [decision 0011](decisions/0011-homebrew-single-owner.md)

## Development

**Devcontainer**
: A project's development environment, declared in the repository
  (`.devcontainer/devcontainer.json`) and run as a container. Holds a project's
  toolchains and its VS Code extensions.
  [decision 0004](decisions/0004-where-software-goes.md)

**Dev Containers extension**
: VS Code's devcontainer integration (`ms-vscode-remote.remote-containers`),
  installed per user on first login by `vscode-devcontainers-ext.service`.

**podman, rootless, rootful**
: The container engine. *Rootless* runs as the user, with no daemon; *rootful*
  runs as root. This image allows rootless only.
  [decision 0006](decisions/0006-rootless-podman-only.md)

**podman-docker**
: Fedora package whose `/usr/bin/docker` runs podman. Tools that call `docker`
  get rootless podman instead.

## Accounts and security

**localadmin**
: The administrator's account on every machine: UID 1000, in `wheel`, allowed on the
  console, GDM, su, sudo and polkit only. [decision 0005](decisions/0005-accounts-and-access.md)

**systemd-homed, `homectl`**
: Manages self-contained, LUKS-encrypted user homes. Daily users are homed
  users. [decision 0008](decisions/0008-homed-users-on-a-separate-partition.md)

**Machine defaults, `defaults.json`**
: Pre-filled first-boot answers for one machine (hostname, localadmin's
  password hash, disk unlock, users, extra Flatpaks), stored on its EFI
  partition from Windows by `Set-DailyDriverDefaults.ps1`. Never a user's
  password. [decision 0020](decisions/0020-machine-defaults-on-the-esp.md)

**EFI system partition (ESP)**
: The small FAT32 partition the firmware boots from. Windows and Linux share
  it in a dual boot; reinstalling Linux doesn't erase it.

**LUKS2, TPM2, PCR 7, FIDO2**
: LUKS2 is Linux disk encryption. A TPM2 chip can hold its key and release it
  only while PCR 7 (its record of the Secure Boot state) matches enrollment
  time. FIDO2 security keys (YubiKey) can unlock it with a touch.
  `systemd-cryptenroll` enrolls both, plus recovery keys.
  [decision 0021](decisions/0021-encrypted-root.md)

**zram**
: Swap in compressed RAM; Fedora's default. Nothing reaches the disk.

**bootupd, static GRUB config**
: bootc's bootloader updater. Its GRUB menu is a fixed file that never scans
  for other systems, hence `windows-boot-entry`.
  [decision 0017](decisions/0017-dual-boot-internal-disk.md)

**sysusers.d, tmpfiles.d, environment.d**
: systemd's declarative ways to create accounts, create or link paths, and set
  user-session environment variables at boot or login, from files in `/usr`
  that stay under the image's control.

**authselect**
: Fedora's owner of `/etc/pam.d`. Features such as `with-systemd-homed` and
  `with-pamaccess` switch PAM modules on; hand edits get overwritten.

**pam_access, `PAM_RHOST`**
: pam_access allows or denies logins by user and origin.
  `-:localadmin:ALL EXCEPT LOCAL` means "refuse localadmin wherever PAM_RHOST
  (the remote host) is set". sshd sets PAM_RHOST; local logins and sudo on
  Linux don't.

**Cosign, keyless signing, Fulcio, `policy.json`**
: CI signs each image with a short-lived certificate tied to the GitHub
  workflow (keyless). `/etc/containers/policy.json` decides what a machine
  accepts. [decision 0013](decisions/0013-image-signing.md)

**Renovate**
: A bot that opens pull requests to bump pinned digests and action versions.

## The home directory

**chezmoi**
: Dotfiles manager. The separate `dotfiles` repository holds git identity and
  the GitHub sign-in hook. [decision 0003](decisions/0003-two-repositories.md)

**Claude Code**
: Anthropic's CLI coding agent, baked into the image.
  `/etc/claude-code/managed-settings.json` is machine-wide policy.
  [decision 0012](decisions/0012-claude.md)
