# Architecture

The image owns the machine. Everything else has a different owner, and a
different lifecycle.

| Layer | Lives in | Survives an image swap? | Owner |
| --- | --- | --- | --- |
| OS, packages, policy | `/usr`, plus `/etc` files never edited locally | Replaced atomically | This repository |
| Machine state | Locally edited `/etc`, all of `/var` | Persists, and drifts | Keep it small; `ujust etc-drift` |
| User state | systemd-homed LUKS homes on the internal partition | Untouched | The `dotfiles` repository (chezmoi) |
| Secrets | GNOME Keyring; password manager to be decided | Untouched | Never in any repository |
| Integrations | claude.ai connectors, GitHub and Google accounts | Account-side | Nothing to image |

## Rules

- **Prefer `/usr`.** Ship config where the software reads it from `/usr`
  (sysusers.d, tmpfiles.d, systemd units and drop-ins, journald.conf.d). An
  `/etc` file stops following the image the moment it is edited locally; bootc
  keeps the local copy through every update.
- **`/var` is copied once.** Image content in `/var` is unpacked at install and
  never updated. Create `/var` paths with tmpfiles.d or `StateDirectory=`.
  90-cleanup.sh prunes `/var` from the image anyway.
- **No per-user config in the image.** `/etc/skel` only seeds homes created
  after the build. Per-user defaults belong in the dotfiles repository.
- **Public repository.** No secrets, tokens, keys or password hashes, ever.
  `tests/contract/daily-driver_test.bats` scans for crypt(3) hashes.
- **Disable what you enable.** Every third-party repository a build phase turns
  on is off again before cleanup.

## Build phases

| Phase | Owner | Does |
| --- | --- | --- |
| `00-image-info.sh` | upstream | os-release and image-info.json |
| `10-overlay.sh` | upstream | common + brew overlays, `custom/files`, seams, units |
| `20-packages-and-services.sh` | upstream | just, gum, fzf, jq, uupd |
| `70-daily-driver.sh` | this image | real `/opt`, Chrome, VS Code, gh, chezmoi, homed, accounts, PAM, rootless podman |
| `75-claude.sh` | this image | Claude Code CLI, fingerprint-checked |
| `90-cleanup.sh` | upstream | repositories off, `/var` pruned, lint prep |

Upstream files are left as they are wherever possible; this image overrides
them from its own phases (for example, masking the `podman.socket` that
`10-overlay.sh` enables). That keeps upstream's test suite meaningful and
makes pulling template changes a merge rather than a rewrite.

## Access model

| Account | Login | Admin |
| --- | --- | --- |
| root | none: password locked; emergency shell only via the GRUB command line | n/a |
| localadmin | console, GDM, su, sudo, polkit; never remote | `wheel` |
| homed users | anywhere PAM allows | no; polkit asks for localadmin |

`/etc/security/access.d/50-localadmin.conf` refuses localadmin wherever
`PAM_RHOST` is set. sudo leaves `PAM_RHOST` unset on Linux (its `pam_rhost`
flag defaults on only for Solaris); `70-daily-driver.sh` fails the build if
sudoers ever turns it on.

## Claude

- **Claude Code CLI**: baked in from the stable channel, so it updates with the
  image. The nightly rebuild keeps it current.
- **Guardrails**: `/etc/claude-code/managed-settings.json` denies reads of SSH,
  GPG, keyring and gh credentials on every account. Deny rules only ever add up
  across settings files, so users can't loosen them. Treat it as a speed bump,
  not a sandbox: a Bash command can still read those files.
- **Desktop app**: Debian/Ubuntu-only today. Chat, connectors (Gmail, Calendar,
  Drive, ...) and cloud sessions run on claude.ai, and connectors belong to the
  Anthropic account, not the machine.
- **This repository**: `CLAUDE.md` plus `.claude/skills` (upstream's agent
  skills) give Claude Code working here the same procedures and rules.
