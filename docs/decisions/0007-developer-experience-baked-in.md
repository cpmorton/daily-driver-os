# 0007. Developer experience baked into the image; no devmode

- **Status:** Accepted
- **Date:** 2026-09-23

## Context

The request was "devmode on by default". As of 2026, Bluefin's `devmode` is a
per-user interactive installer in `projectbluefin/common`'s `bluefin/` layer,
which finpilot doesn't overlay, so this image has no `ujust devmode`.
Its `-dx` image predecessor was retired.

What current devmode installs (read from common, 2026-09-23): the devcontainer
CLI (always), Docker + compose + lazydocker + dive and Podman Desktop
(pre-selected), and optionally virt-manager, Lima, incus, VS Code, VSCodium,
Zed, JetBrains Toolbox, Neovim, Helix, vim and micro. Almost all through
Homebrew. It then adds the user to `dialout` (and `docker`, `libvirt`,
`incus-admin` as chosen) with `usermod`.

## Decision

Bake the equivalent into the image: VS Code (RPM), the Dev Containers
extension (per user, on first login), rootless podman behind a Docker CLI
([0006](0006-rootless-podman-only.md)), and Podman Desktop (Flatpak).

## Alternatives

- **Overlay common's `bluefin/` layer to get `devmode`:** brings all of
  Bluefin's product layer with it, and its group step uses `usermod`, which does
  nothing for systemd-homed users.
- **Brew casks for VS Code (devmode's way):** VS Code would update and roll
  back independently of the OS.

## Consequences

Missing compared with devmode: the devcontainer CLI, Docker (by choice),
virt-manager, Lima, incus, other IDEs and editors, and `dialout` membership.
Each is one command away (`brew install devcontainer`; a Flatpak for
virt-manager; `homectl update <user> --member-of=dialout`).

## Revisit when

Bluefin moves devmode into common's `shared/` layer, or a missing tool becomes
routine: add it to the image then.
