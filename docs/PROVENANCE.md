# Provenance

Where everything on a machine running this image came from, and why it's there.
The "why" links go to the [decision records](decisions/README.md).

On a running machine, ask about any single path:

    ujust provenance /etc/gitconfig

It combines `rpm -qf` (which package owns it), the build's overlay manifest at
`/usr/share/daily-driver-os/provenance.tsv` (which overlay placed it), and, for
`/etc`, a comparison against the image's default copy (has it drifted?).

`tests/contract/daily-driver_test.bats` fails when a file, package, service
change, Flatpak or recipe this repository adds is missing from this page.

## How the image is assembled

In build order. A later layer wins where two write the same path.

| # | Layer | Source | Pinned by | Adds |
| --- | --- | --- | --- | --- |
| 1 | Base OS | `quay.io/fedora-ostree-desktops/silverblue:44` | digest in `Containerfile`, bumped by Renovate | Fedora Silverblue: kernel, GNOME, systemd, podman, ~all RPMs |
| 2 | `00-image-info.sh` | finpilot (upstream) | this repository | `os-release` identity, `/usr/share/ublue-os/image-info.json` |
| 3 | `10-overlay.sh`: common | `ghcr.io/projectbluefin/common`, `system_files/shared/` only | digest in `Containerfile` | ~114 files: ujust, first-boot setup, uupd config, container trust policy, `%wheel` passwordless `bootc upgrade`, polkit rules |
| 4 | `10-overlay.sh`: brew | `ghcr.io/ublue-os/brew` | digest in `Containerfile` | Homebrew tarball, `brew-setup`/`brew-update`/`brew-upgrade` units, shell integration |
| 5 | `10-overlay.sh`: seams | this repository, `custom/` | this repository | `custom/files/`, Brewfiles, ujust recipes, Flatpak preinstalls, `/etc/skel/.config` seeds, Flathub remote descriptor |
| 6 | `20-packages-and-services.sh` | finpilot (upstream) | this repository | `just`, `gum`, `fzf`, `jq`; `uupd` from the `ublue-os/packages` COPR |
| 7 | `70-daily-driver.sh` | this repository | this repository | Everything under "Packages" and "Changes made by build steps" below |
| 8 | `75-claude.sh` | this repository | this repository | `claude-code` |
| 9 | `90-cleanup.sh` | finpilot (upstream) | this repository | Disables third-party repos, masks the Fedora Flatpak remote, disables `rpm-ostreed-automatic.timer`, prunes `/var` |
| 10 | Containerfile tail | finpilot (upstream) | this repository | OCI labels, `bootc container lint` |

Not overlaid: common's `system_files/bluefin/` (Bluefin's product layer, which
includes `devmode`) and `system_files/nvidia/`.
[0001](decisions/0001-assemble-with-finpilot.md),
[0007](decisions/0007-developer-experience-baked-in.md)

## Packages this repository installs

| Package | From | Phase | Why |
| --- | --- | --- | --- |
| `fedora-workstation-repositories` | Fedora | 70 | Ships the Google Chrome repository definition and key |
| `google-chrome-stable` | Google's repository (via the above) | 70 | Browser requested for the daily driver |
| `code` | Microsoft's repository (`packages.microsoft.com/yumrepos/vscode`) | 70 | VS Code, the devcontainer IDE. [0007](decisions/0007-developer-experience-baked-in.md) |
| `podman-docker` | Fedora | 70 | `/usr/bin/docker` runs podman. [0006](decisions/0006-rootless-podman-only.md) |
| `podman-compose` | Fedora | 70 | Compose for podman; `docker-compose` points here. [0006](decisions/0006-rootless-podman-only.md) |
| `gh` | Fedora | 70 | GitHub CLI and git credential helper. [0004](decisions/0004-where-software-goes.md) |
| `chezmoi` | Fedora | 70 | Applies the dotfiles. [0003](decisions/0003-two-repositories.md) |
| `/usr/bin/homectl` (systemd-homed) | Fedora | 70 | Encrypted daily-user homes. [0008](decisions/0008-homed-users-on-a-separate-partition.md) |
| `tpm2-tools` | Fedora | 70 | dracut adds TPM2 unlock to the initramfs only when it's installed. [0021](decisions/0021-encrypted-root.md) |
| `libfido2` | Fedora | 70 | Security-key (YubiKey) unlock in the initramfs. [0021](decisions/0021-encrypted-root.md) |
| `zstd` | Fedora | 70 | Compresses home images for `ujust backup-home`. [0022](decisions/0022-home-backup-and-restore.md) |
| `claude-code` | Anthropic's repository (`downloads.claude.ai/claude-code/rpm/stable`) | 75 | Claude Code CLI. [0012](decisions/0012-claude.md) |

All three third-party repositories are disabled again before the phase ends.
Everything else comes from the base image or upstream's phases: `rpm -qa` on
a machine lists it, and `ujust provenance <path>` names the owning package.

## Files this repository adds

Everything under `custom/files/` lands at the same path in the image.

| Path in the image | What it does | Why |
| --- | --- | --- |
| `/etc/claude-code/managed-settings.json` | Claude Code policy for every account: deny reads of credential files | [0012](decisions/0012-claude.md) |
| `/etc/containers/nodocker` | Silences podman-docker's "emulating Docker" notice | [0006](decisions/0006-rootless-podman-only.md) |
| `/etc/gitconfig` | Git defaults for every account; GitHub credentials through gh | [0004](decisions/0004-where-software-goes.md) |
| `/etc/security/access.d/50-localadmin.conf` | pam_access: localadmin only where `PAM_RHOST` is unset | [0005](decisions/0005-accounts-and-access.md) |
| `/etc/ssh/sshd_config.d/10-hardening.conf` | `PermitRootLogin no`, `DenyUsers localadmin` | [0005](decisions/0005-accounts-and-access.md) |
| `/etc/tmpfiles.d/podman-docker.conf` | Symlink to `/dev/null`: masks the system `/run/docker.sock` → rootful socket link | [0006](decisions/0006-rootless-podman-only.md) |
| `/usr/lib/environment.d/60-docker-host.conf` | `DOCKER_HOST` = the user's rootless podman socket, for every app | [0006](decisions/0006-rootless-podman-only.md) |
| `/usr/lib/systemd/journald.conf.d/60-volatile.conf` | Journal in RAM only, 256M cap | [0010](decisions/0010-var-journal-tmp.md) |
| `/usr/lib/systemd/system/brew-setup.service.d/10-var-home.conf` | Unpack Homebrew only after `/var/home` is mounted (a no-op unless it's a separate mount) | [0011](decisions/0011-homebrew-single-owner.md) |
| `/usr/lib/systemd/system/localadmin-home.service` | Creates localadmin's home from `/etc/skel` | [0005](decisions/0005-accounts-and-access.md) |
| `/usr/lib/systemd/user/vscode-devcontainers-ext.service` | Installs the Dev Containers extension once per user | [0007](decisions/0007-developer-experience-baked-in.md) |
| `/usr/lib/sysusers.d/50-localadmin.conf` | Creates localadmin (UID 1000) in `wheel` | [0005](decisions/0005-accounts-and-access.md), [0018](decisions/0018-provisioning-seed-stick.md) |
| `/usr/lib/dracut/dracut.conf.d/50-daily-driver-unlock.conf` | Adds dracut's `tpm2-tss` and `fido2` modules to the initramfs the build regenerates | [0021](decisions/0021-encrypted-root.md) |
| `/usr/lib/systemd/system/daily-driver-defaults.service` | First boot: reads the machine defaults from the EFI partition | [0020](decisions/0020-machine-defaults-on-the-esp.md) |
| `/usr/lib/systemd/system/daily-driver-firstboot.service` | First boot on tty1, before GDM: hostname, localadmin, disk unlock, users | [0020](decisions/0020-machine-defaults-on-the-esp.md), [0021](decisions/0021-encrypted-root.md) |
| `/usr/lib/systemd/system/windows-boot-entry.service` | Adds Windows to the boot menu once | [0017](decisions/0017-dual-boot-internal-disk.md) |
| `/usr/libexec/daily-driver/defaults-import` | Finds `EFI/daily-driver/defaults.json`, validates it, keeps allowlisted fields in RAM, writes extra Flatpaks' preinstall file | [0020](decisions/0020-machine-defaults-on-the-esp.md) |
| `/usr/libexec/daily-driver/firstboot` | The tty1 first-boot steps, each offering the defaults; resumable | [0020](decisions/0020-machine-defaults-on-the-esp.md) |
| `/usr/libexec/daily-driver/disk-unlock` | Enrolls TPM2, TPM2 + PIN or FIDO2 keys and a recovery key with `systemd-cryptenroll` | [0021](decisions/0021-encrypted-root.md) |
| `/usr/libexec/daily-driver/first-users` | Creates (or skips, for a restore) each default user, or users typed in; every password typed | [0020](decisions/0020-machine-defaults-on-the-esp.md), [0019](decisions/0019-no-seeded-passwords.md) |
| `/usr/libexec/daily-driver/home-backup` | Copies a logged-out user's encrypted home image, compressed, plus homed's public key | [0022](decisions/0022-home-backup-and-restore.md) |
| `/usr/libexec/daily-driver/home-restore` | Puts a backed-up home back, trusts the old key, registers it with homed | [0022](decisions/0022-home-backup-and-restore.md) |
| `/usr/libexec/daily-driver/localadmin-needs-password` | Lets first boot set localadmin's password only while it's locked | [0019](decisions/0019-no-seeded-passwords.md) |
| `/usr/libexec/daily-driver/ensure-subids` | Subordinate UID/GID ranges for homed users (rootless podman) | [0006](decisions/0006-rootless-podman-only.md), [0018](decisions/0018-provisioning-seed-stick.md) |
| `/usr/libexec/daily-driver/windows-boot-entry` | Finds the Windows boot manager and writes `/boot/grub2/custom.cfg` | [0017](decisions/0017-dual-boot-internal-disk.md) |

## Changes made by build steps

Not files in `custom/`, so easy to miss.

| Change | Where | Why |
| --- | --- | --- |
| `/opt`, `/usr/local`, `/root` replaced with real directories | 70 | [0009](decisions/0009-real-opt-usrlocal-root.md) |
| `/usr/local/bin/docker-compose` → `/usr/bin/podman-compose` | 70 | [0006](decisions/0006-rootless-podman-only.md) |
| root's password locked (`passwd -l root`) | 70 | [0005](decisions/0005-accounts-and-access.md) |
| authselect features `with-systemd-homed`, `with-pamaccess` added to the current profile | 70 | [0005](decisions/0005-accounts-and-access.md), [0008](decisions/0008-homed-users-on-a-separate-partition.md) |
| Initramfs regenerated (`dracut --no-hostonly --add ostree`), checked for TPM2 and FIDO2 token plugins and ostree | 70 | [0021](decisions/0021-encrypted-root.md) |
| `/usr/share/daily-driver-os/provenance.tsv` generated | 70 | This page |
| Third-party repositories disabled (`google-chrome`, `code`, `claude-code`) | 70, 75 | [0015](decisions/0015-leave-upstream-files-alone.md) |
| `/root` emptied of build leftovers | 75 | [0009](decisions/0009-real-opt-usrlocal-root.md) |
| finpilot's final `rm -rf /opt && ln -s /var/opt /opt` removed | `Containerfile` | [0009](decisions/0009-real-opt-usrlocal-root.md) |

## Service changes

| Unit | Change | By | Why |
| --- | --- | --- | --- |
| `podman.socket` (system) | enabled by upstream `10-overlay.sh`, then disabled and masked here | 70 | [0006](decisions/0006-rootless-podman-only.md) |
| `podman.service`, `podman-restart.service`, `podman-auto-update.service`, `podman-auto-update.timer` | masked | 70 | [0006](decisions/0006-rootless-podman-only.md) |
| `podman.socket` (user, every account) | enabled globally | 70 | [0006](decisions/0006-rootless-podman-only.md) |
| `vscode-devcontainers-ext.service` (user) | enabled globally | 70 | [0007](decisions/0007-developer-experience-baked-in.md) |
| `daily-driver-defaults.service` | enabled | 70 | [0020](decisions/0020-machine-defaults-on-the-esp.md) |
| `daily-driver-firstboot.service` | enabled | 70 | [0020](decisions/0020-machine-defaults-on-the-esp.md) |
| `systemd-homed-firstboot.service` | masked: replaced by `daily-driver-firstboot.service` | 70 | [0018](decisions/0018-provisioning-seed-stick.md) |
| `windows-boot-entry.service` | enabled | 70 | [0017](decisions/0017-dual-boot-internal-disk.md) |
| `localadmin-home.service` | enabled | 70 | [0005](decisions/0005-accounts-and-access.md) |
| `systemd-homed.service` | enabled | 70 | [0008](decisions/0008-homed-users-on-a-separate-partition.md) |
| `debug-shell.service` | masked | 70 | [0005](decisions/0005-accounts-and-access.md) |
| `gnome-remote-desktop.service` | masked | 70 | [0005](decisions/0005-accounts-and-access.md) |

Upstream's service changes, kept as they are: `brew-setup.service`,
`brew-update.timer`, `brew-upgrade.timer`, `flatpak-preinstall.service`,
`flatpak-appstream-refresh.service`, `ublue-system-setup.service`, `uupd.timer`
and `uupd-resume.timer` enabled; user units `brew-preinstall.service` and
`ublue-user-setup.service` enabled; `flatpak-add-fedora-repos.service` masked;
`rpm-ostreed-automatic.timer` disabled.

## Flatpaks installed on first boot

`custom/flatpaks/daily.preinstall` (this repository):

| App ID | App | Why |
| --- | --- | --- |
| `org.signal.Signal` | Signal | Requested |
| `com.discordapp.Discord` | Discord | Requested |
| `org.libreoffice.LibreOffice` | LibreOffice | Requested |
| `md.obsidian.Obsidian` | Obsidian | Requested |
| `org.gimp.GIMP` | GIMP | Requested |
| `io.podman_desktop.PodmanDesktop` | Podman Desktop | devmode's default pick. [0007](decisions/0007-developer-experience-baked-in.md) |

`custom/flatpaks/default.preinstall` (upstream finpilot, kept):
`org.mozilla.Thunderbird`, `com.github.tchx84.Flatseal`,
`com.mattjakeman.ExtensionManager`. Delete the file to drop them.

## ujust recipes

`custom/ujust/daily-driver.just` (this repository):

| Recipe | Does | Why |
| --- | --- | --- |
| `homed-user` | Creates a LUKS homed user with subordinate IDs | [0017](decisions/0017-dual-boot-internal-disk.md) |
| `brew-owner` | Hands the Homebrew prefix and timers to one user (default owner: localadmin) | [0011](decisions/0011-homebrew-single-owner.md) |
| `windows-entry` | Re-detects Windows and rewrites its boot menu entry | [0017](decisions/0017-dual-boot-internal-disk.md) |
| `dotfiles` | Applies the dotfiles repository with chezmoi | [0003](decisions/0003-two-repositories.md) |
| `etc-drift` | Lists `/etc` files that no longer follow the image | [0003](decisions/0003-two-repositories.md) |
| `provenance` | Explains where one path came from | This page |
| `backup-home` | Backs up a logged-out user's encrypted home to a folder | [0022](decisions/0022-home-backup-and-restore.md) |
| `restore-home` | Restores a home saved by `backup-home` onto a new install | [0022](decisions/0022-home-backup-and-restore.md) |
| `disk-unlock` | Changes how the encrypted root unlocks (TPM2, PIN, security key, passphrase) | [0021](decisions/0021-encrypted-root.md) |

Upstream's recipes (`custom-apps.just`, `custom-system.just`) and common's are
also present. Upstream's `configure-dev-groups` adds users to `docker` and
`libvirt` with `usermod`: it doesn't fit this image (no Docker, and homed users
need `homectl`).

## Upstream files this repository changed

| File | Change | Why |
| --- | --- | --- |
| `Containerfile` | Name; description and keywords; phases 70 and 75; the `/opt` step removed | [0009](decisions/0009-real-opt-usrlocal-root.md), [0015](decisions/0015-leave-upstream-files-alone.md) |
| `Justfile` | Image name default; `ISO_IMAGE_TAG` override in `_build-bib` | Identity rename (`tests/contract/identity_test.bats`); [0016](decisions/0016-installer-built-in-ci.md) |
| `.github/workflows/build-image.yml` | Nightly schedule | [0014](decisions/0014-nightly-builds-and-release-channels.md) |
| `iso/iso.toml` | `rootpw --lock` in the kickstart | [0005](decisions/0005-accounts-and-access.md) |
| `README.md` | Rewritten top half; upstream reference sections kept | |
| `artifacthub-repo.yml` | Deleted: not publishing to Artifact Hub | |

New repository files outside the image:

| File | Does | Why |
| --- | --- | --- |
| `.github/workflows/build-iso.yml` | Builds the installer ISO on demand and uploads it as an artifact | [0016](decisions/0016-installer-built-in-ci.md) |
| `.gitattributes` | LF line endings on every checkout, Windows included | [0016](decisions/0016-installer-built-in-ci.md) |
| `.gitignore` (additions) | Refuses defaults files and hash files | [0020](decisions/0020-machine-defaults-on-the-esp.md) |
| `tools/windows/Set-DailyDriverDefaults.ps1` | Writes this machine's defaults to its EFI partition from Windows (PowerShell 5.1) | [0020](decisions/0020-machine-defaults-on-the-esp.md) |
| `CLAUDE.md`, `.claude/` | Claude Code rules and upstream's agent skills | [0012](decisions/0012-claude.md) |
| `docs/`, `tests/contract/daily-driver_test.bats`, `tests/contract/daily-driver-helpers_test.bats`, `tests/contract/provenance_test.bats` | This documentation, and the tests that keep it and the first-boot helpers true | This page |

## Created on each machine, not in the image

A reinstall wipes all of this except the first row: the rest lives in the
Linux partition.

| State | Created by | Where |
| --- | --- | --- |
| Machine defaults | `Set-DailyDriverDefaults.ps1`, on Windows | `EFI/daily-driver/defaults.json` on the EFI partition (survives reinstalls) |
| Validated defaults, extra Flatpaks | `defaults-import` | `/run/daily-driver/defaults.json` (RAM); `/etc/flatpak/preinstall.d/60-machine-defaults.preinstall` |
| Hostname | first boot (defaults or typed) | `/etc/hostname` |
| localadmin's password | first boot: the defaults' hash, or typed | `/etc/shadow` |
| Disk encryption and its unlock methods | the installer ("Encrypt my data"), then `disk-unlock` | LUKS2 header of the root partition |
| localadmin's home | `localadmin-home.service` | `/var/home/localadmin` |
| Daily users and their encrypted homes | first boot, `ujust homed-user` or `ujust restore-home` | `/var/home/<user>.home` (one LUKS file each) |
| Trusted signing keys of restored homes | `home-restore` | `/etc/systemd/home/restored-*.public` |
| homed's signing keys | systemd-homed, first start | `/var/lib/systemd/home/local.*` |
| Subordinate IDs | `ensure-subids` | `/etc/subuid`, `/etc/subgid` |
| Windows boot entry | `windows-boot-entry.service` | `/boot/grub2/custom.cfg` |
| First-boot markers | `firstboot` | `/var/lib/daily-driver/` |
| Homebrew and its packages | `brew-setup.service`, then its owner | `/var/home/linuxbrew` (owner: localadmin unless `ujust brew-owner`) |
| Flatpaks | `flatpak-preinstall.service` | `/var/lib/flatpak` |
| Dev Containers extension, git identity, GitHub token, Claude Code sign-in | first login, the dotfiles, `claude` | inside each encrypted home |
