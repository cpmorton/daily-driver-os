# 0015. Leave upstream files alone; override from this image's phases

- **Status:** Accepted
- **Date:** 2026-09-23

## Context

Template improvements have to be merged in by hand
([0001](0001-assemble-with-finpilot.md)), and upstream's tests pin upstream's
behavior.

## Decision

This image's changes go in its own files: `build/70-daily-driver.sh`,
`build/75-claude.sh`, `custom/files/`, `custom/flatpaks/daily.preinstall`,
`custom/ujust/daily-driver.just`, `tests/contract/daily-driver_test.bats`,
`docs/`. Upstream behavior is overridden from there (for example, masking the
`podman.socket` that `10-overlay.sh` enables).

Upstream files that had to change are listed in
[PROVENANCE.md](../PROVENANCE.md#upstream-files-this-repository-changed).

## Consequences

Upstream's 184 tests still pass and still mean something, and pulling a
template change is usually a clean merge.
