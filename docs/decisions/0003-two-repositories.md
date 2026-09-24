# 0003. Two repositories: the image and the dotfiles

- **Status:** Accepted
- **Date:** 2026-09-23

## Context

The machine and the user's home change at different rates and have different
owners. The goal is being able to wipe the OS to a clean slate at any time.

## Decision

- `daily-driver-os` (this repository) owns everything that isn't personal.
- `dotfiles` (chezmoi) owns only what must live in a home and is personal:
  git identity and the one-time GitHub sign-in. Its `secrets` switch is the
  slot for a future password manager.
- Anything that *can* move from the home into the image does
  ([0004](0004-where-software-goes.md)).

## Alternatives

- **Monorepo:** fights finpilot's layout and CI triggers, and couples a git
  identity change to an image build.
- **Seeding homes from `/etc/skel`:** only reaches homes created after the
  build; existing homes never update.

## Consequences

- Clean slate is two commands: reinstall or switch the image; re-run
  `ujust dotfiles` in a fresh home.
- The dotfiles repository is tiny, and should stay that way.

## Revisit when

The dotfiles grow configuration that isn't personal: move it into the image.
