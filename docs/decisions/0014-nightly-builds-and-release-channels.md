# 0014. Nightly builds and finpilot's two-channel release

- **Status:** Accepted
- **Date:** 2026-09-23

## Context

Chrome, VS Code and Claude Code are baked-in RPMs, and finpilot builds only on
pushes to `main`.

## Decision

- `build-image.yml` also runs at 02:17 UTC, before finpilot's promotion
  workflow at 04:00 UTC, so the promotion picks up a fresh build.
- finpilot's channels are kept as they are: `main` → `:stable-testing`, and the
  release gate promotes that exact digest to `:stable`. Machines track
  `:stable`, and uupd applies updates.

## Consequences

Up to a day's delay on browser security fixes. Trigger `workflow_dispatch`
for an urgent one.

## Revisit when

[VERIFY] the first scheduled run tags images as expected (finpilot's tagging
action receives `event-name: schedule`).
