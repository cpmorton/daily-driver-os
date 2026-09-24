# 0010. Persistent `/var`, volatile journal, tmpfs `/tmp`

- **Status:** Accepted
- **Date:** 2026-09-23

## Context

The original request was to keep "some parts of `/var` around" (Flatpaks,
Homebrew, NetworkManager), a volatile journal, and a tmpfs `/tmp`.

## Decision

- `/var` stays persistent (bootc's default), so Flatpaks, Homebrew,
  NetworkManager state and homed's keys survive without an allowlist.
- Journal: `Storage=volatile`, capped at 256M
  (`/usr/lib/systemd/journald.conf.d/60-volatile.conf`).
- `/tmp`: tmpfs, via Fedora's own `tmp.mount`; the build asserts it.

## Alternatives

- **Ephemeral `/var` with a persist allowlist:** more state control, but every
  missed path is silent data loss, and homed's keys must be on the list.

## Consequences

The logs of a boot you rolled back from are gone: reproduce failures in a VM.

## Revisit when

You want forensic logs, or persistent `/var` drift becomes a problem.
