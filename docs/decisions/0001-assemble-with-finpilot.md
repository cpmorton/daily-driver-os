# 0001. Assemble the image with finpilot, not by deriving from Bluefin

- **Status:** Accepted
- **Date:** 2026-09-23

## Context

Two ways exist to make a custom Bluefin-like image: `FROM ghcr.io/.../bluefin`
and modify it, or assemble one from the same inputs Bluefin uses. Bluefin moved
to the second pattern itself in 2026, and projectbluefin's finpilot template
packages it for forks.

## Decision

Generate this repository from `projectbluefin/finpilot` (at upstream commit
`341cbac`). The image is Fedora Silverblue 44 plus `projectbluefin/common`'s
`shared/` layer plus `ublue-os/brew`, plus this repository's phases.

## Alternatives

- **`FROM bluefin`:** inherits every Bluefin opinion, then undoes the unwanted
  ones. Brittle: each Bluefin change can collide with an override.
- **Plain Silverblue, no ublue pieces:** loses ujust, uupd, the Flatpak and
  Homebrew first-boot plumbing, and finpilot's CI (signing, release gate,
  Renovate, tests).
- **Dakota (GNOME OS base):** alpha, and no RPMs, so no Chrome/VS Code RPMs.

## Consequences

- The image is Bluefin's plumbing without Bluefin's product: no branding and
  no `devmode` ([0007](0007-developer-experience-baked-in.md)).
- Template updates don't arrive automatically: a "Use this template" repo has no
  upstream link. Pull template improvements by hand, which
  [0015](0015-leave-upstream-files-alone.md) makes cheap.

## Verification

finpilot's `Containerfile` and Bluefin's own `Containerfile` read on
2026-09-23: same base, same `common` and `brew` inputs; Bluefin additionally
overlays `common/system_files/bluefin`.

## Revisit when

Dakota leaves alpha, or finpilot's upstream pattern changes (check its
`README.md` and `build/README.md`).
