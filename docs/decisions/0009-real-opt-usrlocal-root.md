# 0009. `/opt`, `/usr/local` and `/root` are real, image-owned directories

- **Status:** Accepted
- **Date:** 2026-09-23

## Context

Silverblue ships all three as symlinks into `/var`. finpilot additionally ends
its build with `rm -rf /opt && ln -s /var/opt /opt`. Chrome installs into
`/opt/google`, and `90-cleanup.sh` prunes `/var`.

## Decision

At the top of `70-daily-driver.sh`, before any package installs, replace the
symlinks with real directories. Remove finpilot's final `/opt` step.

## Alternatives

- **finpilot's suggested `RUN rm /opt && mkdir /opt` at the end:** too late:
  Chrome would already have unpacked into `/var/opt`, which cleanup deletes.
- **Keep the symlinks:** machine-local, mutable, unversioned content in paths
  that should be part of the OS.

## Consequences

- All three are read-only at runtime. Software that wants to write under
  `/opt/<name>` at runtime needs a symlink into `/var` for that one path.
- Anything written to `/root` during the build ships in the image, so
  `75-claude.sh` empties it and gpg runs with a throwaway keyring.
- `custom/files/` can't place files in these directories: it's applied before
  they become real. A contract test enforces this.

## Verification

bootc's filesystem documentation: `/usr/local` may be a symlink for "final"
images; real directories are the default for images meant to be derived from.
