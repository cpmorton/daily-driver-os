---
name: customize
description: >-
  Decide where a package, app, or command belongs — dnf5 at build time,
  Homebrew, Flatpak, or ujust — and how each is validated. Use when adding
  or removing something from the image.
---

# Customize

## Where does it go?

| The thing is… | Put it in | Installed |
|---|---|---|
| A system package the image needs to boot or run | `build/20-packages-and-services.sh` | at build time |
| A CLI tool a user chooses to have | `custom/brew/*.Brewfile` | on demand, by the user |
| A GUI application | `custom/flatpaks/*.preinstall` | on first boot |
| A command that configures the system | `custom/ujust/*.just` | available from first login |
| A system file: unit, preset, tmpfiles.d | `custom/files/` | at build time |
| Per-user config for new accounts | `custom/config/` | at build time, into `/etc/skel` |
| Personal per-user config (identity, preferences) | the user's `dotfiles` repository (chezmoi) | at every login and daily, by `dotfiles-sync` |

The dividing line is who decides and when: build time for what the image must
have, runtime for what the user chooses.

## By destination

### Build-time packages

`build/20-packages-and-services.sh`. Use `dnf5`, always with `-y`, and disable
any repository you enable. [build/README.md](../../../build/README.md) has the
phase map.

Prefer a package the base already ships. When a COPR is unavoidable,
`copr_install_isolated` enables and disables it for you.

### Homebrew

Brewfiles in `custom/brew/`, plus a `ujust` recipe so users install it by name.
[custom/brew/README.md](../../../custom/brew/README.md) has the format.

### Flatpak

Preinstall declarations in `custom/flatpaks/`. The app must exist on Flathub;
`just validate-flatpaks` checks.
[custom/flatpaks/README.md](../../../custom/flatpaks/README.md) has the format and
the first-boot behaviour.

### ujust

Recipes in `custom/ujust/`. No `dnf5` or `rpm` — the image is immutable.
[custom/ujust/README.md](../../../custom/ujust/README.md) has the recipe shape.

### System files and user config

`custom/files/` mirrors `/`; `custom/config/` seeds `/etc/skel/.config/`. Each
directory's README has the semantics.

### Personal, per user

Daily homes are homed LUKS images, locked until their user logs in, so
`/etc/skel` never reaches them after first boot. Anything personal goes in the
user's chezmoi repository, which `daily-driver-dotfiles.service` and `.timer`
apply with no terminal ([decision 0024](../../../docs/decisions/0024-dotfiles-apply-themselves.md)).
What surprised the last change:

- Every chezmoi prompt needs a default (`promptStringOnce . "k" "q" "default"`):
  the first apply runs `--promptDefaults` with stdin at `/dev/null`, and a
  prompt without one fails with `EOF`.
- `chezmoi init <repo>` never pulls into an existing clone, so a failed first
  apply must remove its clone or the next login re-applies the stale copy.
- `chezmoi update --keep-going` still stops at a conflict prompt with no TTY;
  `--error-on-conflict` (2.71+) fails cleanly and touches nothing.
- `gdbus call ... Notify` takes a negative timeout as an option: pass `0`.

## Removing something

The reverse of adding: delete the line or the file, then check nothing still
references it. A package removed from the package phase may still arrive as a
dependency or from an overlay; `bootc container lint` and the image build catch
the obvious cases.

## Validate

```bash
just validate-brewfiles
just validate-flatpaks
just check
just build
```

CI runs `validate-brewfiles`, `validate-flatpaks`, and `validate-justfiles` on
every pull request.
