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
| `/usr/lib/systemd/system/brew-setup.service.d/10-var-home.conf` | Unpack Homebrew only after `/var/home` is mounted | [0011](decisions/0011-homebrew-single-owner.md) |
| `/usr/lib/systemd/system/localadmin-firstboot.service` | Asks for localadmin's password on tty1 before GDM, once | [0005](decisions/0005-accounts-and-access.md) |
| `/usr/lib/systemd/system/localadmin-home.service` | Creates localadmin's home from `/etc/skel` | [0005](decisions/0005-accounts-and-access.md) |
| `/usr/lib/systemd/user/vscode-devcontainers-ext.service` | Installs the Dev Containers extension once per user | [0007](decisions/0007-developer-experience-baked-in.md) |
| `/usr/lib/sysusers.d/50-localadmin.conf` | Creates localadmin (UID 1999) in `wheel` | [0005](decisions/0005-accounts-and-access.md) |

## Changes made by build steps

Not files in `custom/`, so easy to miss.

| Change | Where | Why |
| --- | --- | --- |
| `/opt`, `/usr/local`, `/root` replaced with real directories | 70 | [0009](decisions/0009-real-opt-usrlocal-root.md) |
| `/usr/local/bin/docker-compose` → `/usr/bin/podman-compose` | 70 | [0006](decisions/0006-rootless-podman-only.md) |
| root's password locked (`passwd -l root`) | 70 | [0005](decisions/0005-accounts-and-access.md) |
| authselect features `with-systemd-homed`, `with-pamaccess` added to the current profile | 70 | [0005](decisions/0005-accounts-and-access.md), [0008](decisions/0008-homed-users-on-a-separate-partition.md) |
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
| `localadmin-firstboot.service` | enabled | 70 | [0005](decisions/0005-accounts-and-access.md) |
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
| `home-partition` | Moves `/var/home` onto an already-formatted partition | [0008](decisions/0008-homed-users-on-a-separate-partition.md) |
| `homed-user` | Creates a LUKS homed user with subordinate IDs | [0008](decisions/0008-homed-users-on-a-separate-partition.md) |
| `brew-owner` | Hands the Homebrew prefix and timers to one user | [0011](decisions/0011-homebrew-single-owner.md) |
| `dotfiles` | Applies the dotfiles repository with chezmoi | [0003](decisions/0003-two-repositories.md) |
| `etc-drift` | Lists `/etc` files that no longer follow the image | [0003](decisions/0003-two-repositories.md) |
| `provenance` | Explains where one path came from | This page |

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
| `CLAUDE.md`, `.claude/` | Claude Code rules and upstream's agent skills | [0012](decisions/0012-claude.md) |
| `docs/`, `tests/contract/daily-driver_test.bats`, `tests/contract/provenance_test.bats` | This documentation, and the tests that keep it true | This page |

## Created on each machine, not in the image

This is state a reinstall wipes (on the stick) or keeps (on the home partition).

| State | Created by | Where | Survives reinstall? |
| --- | --- | --- | --- |
| localadmin's password | `localadmin-firstboot.service` | `/etc/shadow` | No |
| `/var/home` fstab entry | `ujust home-partition` | `/etc/fstab` | No: re-add ([runbook](runbooks/reinstall.md)) |
| Daily users and their homes | `ujust homed-user` | `/var/home/<user>.home` | Yes (home partition) |
| homed signing keys | systemd-homed, first start | `/var/lib/systemd/home/local.*` | **No: back them up** |
| Subordinate IDs | `ujust homed-user` | `/etc/subuid`, `/etc/subgid` | No: re-run `ujust homed-user <user>` |
| Homebrew owner | `ujust brew-owner` | `/etc/systemd/system/brew-*.service.d/` | No: re-run |
| Homebrew and its packages | `brew-setup.service`, users | `/var/home/linuxbrew` | Yes (home partition) |
| Flatpaks | `flatpak-preinstall.service` | `/var/lib/flatpak` | No: reinstalled on first boot |
| Dev Containers extension | `vscode-devcontainers-ext.service` | `~/.vscode/extensions` | Yes (in the home) |
| Git identity | the dotfiles | `~/.gitconfig` | Yes (in the home) |
| GitHub token | the dotfiles' `gh auth login` | desktop keyring, in the home | Yes (in the home) |
| Claude Code sign-in | `claude` on first run | `~/.claude*` | Yes (in the home) |
