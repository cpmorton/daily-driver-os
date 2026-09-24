# 0004. Where software and configuration go

- **Status:** Accepted
- **Date:** 2026-09-23

## Context

Five places can hold software or configuration. Putting something in the wrong
one either bloats the image, loses it on reinstall, or couples a project to a
machine.

## Decision

| It is… | It goes in | Lives at runtime in |
| --- | --- | --- |
| The OS, apps you always want, system policy, defaults for every account | The image (`build/70-daily-driver.sh`, `custom/files/`) | `/usr`, `/etc` |
| A GUI app from Flathub | `custom/flatpaks/daily.preinstall` | `/var/lib/flatpak` |
| A CLI tool you're trying out, or don't want to rebuild for | Homebrew (`brew install`) | `/home/linuxbrew` |
| A project's toolchain, runtimes, linters, language servers, **and its VS Code extensions** | That repository's `.devcontainer/` | Container images |
| Identity, secrets, and preferences that change faster than an image build | The dotfiles repository | The user's home |

Rules of thumb:
- **Would a collaborator cloning the repository need it?** Devcontainer.
- **Do you want it on every reinstall, and it isn't personal?** Image.
- **Is it who you are, or secret?** Home, via the dotfiles and a password
  manager.
- **A Homebrew tool you keep using?** Promote it to a package in the image.

**Moving things from the home into the image is the default.** Reasons a thing
stays in the home anyway, other than size:

1. **It's personal or secret.** The image is public ([0002](0002-public-and-secret-free.md)).
2. **Iteration speed.** An image change is a pull request, a CI build and a
   reboot. Settings you tweak daily belong in the home.
3. **Defaults don't beat overrides.** Image config is a default; anything the
   user sets in their home wins. A clean slate needs a fresh home too.
4. **Only per-user config exists.** Some apps read nothing system-wide.
   VS Code has no machine-level `settings.json`, which is why this image
   changes what `docker` *is* (podman-docker) rather than setting
   `dev.containers.dockerPath` per user.
5. **`/etc` drift.** A config file in `/etc` stops following the image once
   edited locally. Prefer paths under `/usr`.
6. **Redistribution.** Shipping Marketplace VS Code extensions or font
   binaries in a public image raises licensing questions this repository
   hasn't cleared. The Dev Containers extension is installed per user by an
   image-declared unit instead.
7. **Update coupling.** Baked-in software updates only when the image rebuilds
   ([0014](0014-nightly-builds-and-release-channels.md)), and rolls back with
   the OS. Usually a feature, sometimes not.
8. **Every account gets it.** Image config applies to localadmin too.

## Moved into the image under this decision

- VS Code devcontainers on podman: `podman-docker`, a `docker-compose` link to
  podman-compose, and `DOCKER_HOST` via `/usr/lib/environment.d`. Replaced a
  per-user `settings.json` from the dotfiles.
- Git defaults (`init.defaultBranch`, `pull.rebase`, gh credential helper):
  `/etc/gitconfig`. Replaced most of the dotfiles' `~/.gitconfig`.

## Revisit when

A per-user tool gains system-wide config, or an app in the home becomes
permanent.
