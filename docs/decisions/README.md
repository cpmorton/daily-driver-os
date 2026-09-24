# Decision records

Why this image is the way it is. One file per decision: context,
decision, alternatives rejected, consequences, how it was verified, and when
to revisit it. Add a record for every new decision, and never rewrite history:
supersede a record with a new one and mark the old one's status.

| # | Decision | Status |
| --- | --- | --- |
| 0001 | [Assemble the image with finpilot, not by deriving from Bluefin](0001-assemble-with-finpilot.md) | Accepted |
| 0002 | [Public repository and public image; nothing secret](0002-public-and-secret-free.md) | Accepted, amended by 0018 |
| 0003 | [Two repositories: the image and the dotfiles](0003-two-repositories.md) | Accepted |
| 0004 | [Where software and configuration go](0004-where-software-goes.md) | Accepted |
| 0005 | [Accounts: root locked, localadmin local-only, no password in the image](0005-accounts-and-access.md) | Accepted, amended by 0018 |
| 0006 | [Rootless podman only; the Docker CLI runs podman](0006-rootless-podman-only.md) | Accepted |
| 0007 | [Developer experience baked into the image; no devmode](0007-developer-experience-baked-in.md) | Accepted |
| 0008 | [Daily users are systemd-homed LUKS homes on a separate partition](0008-homed-users-on-a-separate-partition.md) | Superseded by 0017 |
| 0009 | [`/opt`, `/usr/local` and `/root` are real, image-owned directories](0009-real-opt-usrlocal-root.md) | Accepted |
| 0010 | [Persistent `/var`, volatile journal, tmpfs `/tmp`](0010-var-journal-tmp.md) | Accepted |
| 0011 | [Keep Homebrew, owned by one user](0011-homebrew-single-owner.md) | Accepted, amended by 0018 |
| 0012 | [Claude: the CLI in the image, the rest on claude.ai](0012-claude.md) | Accepted |
| 0013 | [Image signing: keyless in CI, not yet enforced on the machine](0013-image-signing.md) | Accepted, known gap |
| 0014 | [Nightly builds and finpilot's two-channel release](0014-nightly-builds-and-release-channels.md) | Accepted |
| 0015 | [Leave upstream files alone; override from this image's phases](0015-leave-upstream-files-alone.md) | Accepted |
| 0016 | [The installer ISO is built in CI; nobody needs Linux to install](0016-installer-built-in-ci.md) | Accepted, amended by 0017 |
| 0017 | [Dual boot on the internal disk, beside Windows](0017-dual-boot-internal-disk.md) | Accepted |
| 0018 | [Provisioning: a generic installer plus a per-machine seed stick](0018-provisioning-seed-stick.md) | Accepted |

## Template

```markdown
# NNNN. Title

- **Status:** Proposed | Accepted | Superseded by NNNN
- **Date:** YYYY-MM-DD

## Context
## Decision
## Alternatives
## Consequences
## Verification
## Revisit when
```
