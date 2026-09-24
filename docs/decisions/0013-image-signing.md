# 0013. Image signing: keyless in CI, not yet enforced on the machine

- **Status:** Accepted, known gap
- **Date:** 2026-09-23

## Status note

Accepted with a known gap.

## Context

finpilot signs every image with keyless Cosign (Fulcio certificate bound to
the GitHub workflow), and its release gate refuses unsigned images. The machine
decides what it accepts from `/etc/containers/policy.json`, shipped by
`projectbluefin/common`.

## Findings

- common's policy trusts `ghcr.io/ublue-os` by key and accepts any other
  `docker` registry unconditionally, this repository's included.
- `containers-policy.json(5)`: Fulcio matching requires `subjectEmail`. GitHub
  Actions certificates carry a workflow URI instead, so a keyless Actions
  identity can't be expressed.
- Bluefin's own notes: podman/bootc find signatures only at the legacy
  `sha256-<digest>.sig` tag; cosign 3's default bundle format is invisible to
  them.

## Decision

Keep keyless signing for the release gate. Treat the machine's trust as TLS to
GHCR plus GitHub account security, until key-based signing is added.

## Next step

Key-based Cosign signing (key in a repository secret), plus a
`sigstoreSigned` `policy.json` entry and `registries.d` file for
`ghcr.io/OWNER/daily-driver-os`, verified with the `.sig` tag check from
Bluefin's `docs/skills/security/references/signing.md`.
