# 0024. Dotfiles apply themselves at login and stay current

- **Status:** Accepted
- **Date:** 2026-10-19

## Context

[0003](0003-two-repositories.md) left applying the dotfiles to each user:
`ujust dotfiles <github-user>` once per fresh home, then `chezmoi update` by
hand. The request is that it be automatic: if a user has a dotfiles
repository, use it, without anyone remembering a command.

Constraints:

- **Homes are locked until login.** Each daily home is a LUKS image opened
  with its user's password ([0008](0008-homed-users-on-a-separate-partition.md)),
  so nothing can be written into it at first boot. The first chance is the
  user's own session.
- **Applying a chezmoi repository runs its scripts as that user.** Whoever
  names the repository decides what code runs in the home, so a guessed name
  (say, `<local username>/dotfiles` on GitHub) would let a stranger's public
  repository run code here. The repository must be named explicitly.
- **No one is at the keyboard.** chezmoi's questions need defaults, and a file
  changed locally must never be overwritten silently.

## Decision

- **Named once, by localadmin, per user:** the machine defaults' `dotfiles`
  field ([machine-defaults.md](../runbooks/machine-defaults.md)), the
  first-boot question for typed-in users, or `ujust homed-user <user> <size>
  <repo>`. Each writes `/var/lib/daily-driver/dotfiles/<user>`: one line, a
  GitHub user (meaning `<user>/dotfiles`), `user/repo`, or an `https://` URL.
  Not secret, so world-readable; root-owned, so a user can't redirect another's.
- **Applied by the user's own systemd:** `daily-driver-dotfiles.service` at
  every login and `daily-driver-dotfiles.timer` daily, both enabled globally,
  run `/usr/libexec/daily-driver/dotfiles-sync`:
  - first time: `chezmoi init --apply --no-tty --promptDefaults <repo>`, then
    a marker in `~/.local/state/daily-driver/`;
  - afterwards: `chezmoi update --no-tty --error-on-conflict`, which stops
    rather than overwrite a file changed since chezmoi last wrote it.
  - Anything needing a person (a conflict, a question without a default, no
    network) ends in one desktop notification: run `ujust dotfiles`.
- **`ujust dotfiles` is the interactive path**, run as the user: it answers
  the repository's questions, settles conflicts (`chezmoi update --init`), and
  sets the marker so the automatic path takes over. It refuses to run as
  localadmin, which has no personal dotfiles ([0005](0005-accounts-and-access.md)).
- **A repository's contract:** every chezmoi prompt has a default
  (`promptStringOnce . "key" "question" "default"`), and scripts that need a
  terminal check for one and skip quietly without it. The `dotfiles`
  repository meets this.

## Alternatives

- **BlueBuild's chezmoi module** ([docs](https://blue-build.org/reference/modules/chezmoi)):
  the same init-at-login service and update timer, but one repository baked
  into the image for every user. Fine for a single-user image; here users
  differ, and the image is public.
- **Guess `<username>/dotfiles` on GitHub:** zero setup, but it runs whatever
  a stranger publishes under a matching name. Refused.
- **Seed from `/etc/skel`:** can't reach an encrypted home, and runs once
  ([0003](0003-two-repositories.md)).
- **Store the repository in the homed user record:** travels with a restored
  home, but custom record fields need `homectl update --identity=` JSON
  surgery. A restored home already carries chezmoi's own state, which is all
  later updates need.
- **`--force` on updates:** never stuck, but silently discards local edits.
- **`--keep-going` on updates (BlueBuild's "skip"):** applies what it can, but
  in chezmoi 2.73 it still stops at the first conflict prompt with no TTY, and
  exits non-zero anyway. `--error-on-conflict` (chezmoi 2.71+) says so up front.

## Consequences

- A new user with a named repository gets it at first login, and every user's
  dotfiles follow the repository within a day, with no command.
- Pushing to a dotfiles repository reaches every machine where it's applied.
  That's the point, and also why only localadmin may name a repository.
- A dotfiles repository whose prompts lack defaults fails its first automatic
  apply; the notification sends the user to `ujust dotfiles`. The failed clone
  is removed, because `chezmoi init` never pulls into an existing one.
- Updates pull from the network daily.

## Verification

Tested in the cloud session with the chezmoi 2.73.2 release binary (Fedora 44
ships 2.73.0): `init --apply --no-tty --promptDefaults` applies a repository
whose prompts have defaults, and fails with `EOF` on one without; re-running
`init` after a failure does not pull; `update --no-tty --error-on-conflict`
exits 1 and leaves a locally edited target alone. `gdbus call ... Notify`
argument parsing checked against a session bus with no notification server.

**[VERIFY]** on a real machine: the units start at a homed user's login; the
notification shows in GNOME; `nm-online` is at `/usr/bin` and waits as
expected from a user unit.

## Revisit when

chezmoi gains a supported unattended mode, or a user needs a repository behind
authentication (that needs a credential at first login, which this avoids).
