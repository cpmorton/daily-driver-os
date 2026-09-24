# 0012. Claude: the CLI in the image, the rest on claude.ai

- **Status:** Accepted
- **Date:** 2026-09-23

## Context

The goal was an image "integrated with Claude workflows". The Claude desktop
app (with Cowork) supports only Debian and Ubuntu on Linux; Anthropic's
documentation says to use the CLI on Fedora.

## Decision

- Claude Code CLI from Anthropic's signed dnf repository (stable channel), in
  `75-claude.sh`. The build checks the signing key's fingerprint
  (`31DDDE24DDFAB679F42D7BD2BAA929FF1A7ECACE`) because CI can't answer dnf's
  prompt.
- `/etc/claude-code/managed-settings.json` denies reads of SSH, GPG, keyring,
  gh and chezmoi credentials for every account. It's a guardrail, not a sandbox:
  a shell command can still read those files.
- Chat, connectors and cloud sessions are account-side on claude.ai: nothing
  to put in an image.
- This repository has `CLAUDE.md` and `.claude/skills`, so Claude Code working
  here follows finpilot's procedures and these decisions.

## Alternatives

- **Desktop app in a Debian distrobox, or an unofficial RPM repackage:**
  unsupported; Cowork also needs KVM and vhost-vsock access.

## Consequences

The CLI updates with the image (nightly), never by itself.

## Revisit when

Anthropic ships the desktop app for Fedora.
