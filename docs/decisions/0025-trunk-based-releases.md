# 0025. Trunk-based releases: promote a signed digest, record it as a tag

- **Status:** Accepted
- **Date:** 2026-10-20
- **Supersedes:** [0014](0014-nightly-builds-and-release-channels.md),
  [0023](0023-release-without-inline-sbom.md)

## Context

[0014](0014-nightly-builds-and-release-channels.md) kept finpilot's two-branch
model: `main` builds `:stable-testing`, a squash PR promotes `main` into a
`stable` branch, and merging it copies the tested digest to `:stable`. The
property worth keeping is the last part: `:stable` is never rebuilt, so what
ships is the exact image that was tested.

Everything else existed to keep two branches in agreement on a personal
repository the factory reusables were not designed for: a job that rebuilds the
promotion branch when its tree drifts from `main`, a job that approves the check
runs GitHub holds on a bot's PR, a rule that the PR must be merged by a person
so the push-triggered release fires, a tree check in `validate`, a back-sync
workflow, a stable-branch ruleset and two release labels. About 400 lines of
workflow for one administrator.

## Decision

- One long-lived branch, `main`. Feature branches merge into it by PR, and
  every push builds and signs `:stable-testing`, as before.
- `release.yml`, dispatched by hand, resolves `:stable-testing` to a digest
  once, verifies its keyless cosign signature against this repository's
  workflow identity, and copies that digest (`skopeo copy --preserve-digests`)
  to an immutable tag named after the image's version label (for example
  `:46.20261019`) and then to `:stable`.
- The release is recorded as git tag `v<version>` on the commit the image's
  revision label names, with a GitHub Release carrying the digest, the
  `bootc switch` commands and the `cosign verify` command.
- Rolling `:stable` back is the same workflow given an earlier version.
- The daily 14:00 UTC build ([0014](0014-nightly-builds-and-release-channels.md),
  moved in the Wave 1 simplification) stays; it refreshes `:stable-testing`,
  not `:stable`.
- The four PR linters fold into `pr-validation.yml`, each job gated on the paths
  it checks.

## Alternatives

- **Keep the two branches** ([0014](0014-nightly-builds-and-release-channels.md)).
  It has the same guarantee, but most of the machinery exists to keep `stable`
  in sync with `main`.
- **Build on a pushed git tag.** It's simpler, but `:stable` would then be a
  fresh build nobody ran, which throws away the guarantee above.
- **Release automatically on a schedule.** Browser and editor fixes would reach
  `:stable` without anyone acting, but nobody would gate the release. Adding a
  `schedule:` to `release.yml` is the whole change if that's wanted later.
- **Keep calling `reusable-execute-release.yml`.** It resolves the mutable tag
  once per variant, so writing both a version tag and `:stable` would resolve
  twice. Its sticky-comment and issue steps assume a promotion PR. The
  verify-then-copy core is about 20 lines of bash, which is easy to own.

## Consequences

- `:stable` moves only when someone releases. Chrome, VS Code and Claude Code
  are baked-in RPMs, so their fixes reach a machine on `:stable` at the next
  release, not the next build. Flatpaks and Homebrew update independently.
- A hotfix to `:stable` that skips work already on `main` needs a branch cut
  from the last release tag, and that branch's own build. Accepted as rare.
- Releases no longer carry an SBOM, placeholder or otherwise, so
  [0023](0023-release-without-inline-sbom.md)'s problem goes away along with
  the reusable that caused it. A real SBOM is a separate decision.
- `clean.yml` prunes tagged images older than 90 days beyond the newest seven,
  version tags included. The GitHub Release keeps the digest on record. Keeping
  release images longer needs a cleanup action that can exclude tags.
- The `stable` branch, its protection, its ruleset and the `release/*` labels
  can be deleted. Installed machines follow the `:stable` image tag, not the
  branch, so they are unaffected.

## Verification

Verified 2026-10-20 by the first dispatch
([run 39422287739](https://github.com/cpmorton/daily-driver-os/actions/runs/39422287739)):
it resolved the short revision label to the full commit `34aeeea…` through
`gh api repos/{repo}/commits/<short>`, verified the cosign signature, promoted
digest `sha256:368c9451…` to `:46.20261020` and `:stable`, and created
[v46.20261020](https://github.com/cpmorton/daily-driver-os/releases/tag/v46.20261020)
on that commit. A rollback dispatch (an earlier `version`) is still unexercised.

## Revisit when

There is more than one machine or more than one administrator: a scheduled
release, a soak period on `:stable-testing`, or an end-to-end boot test before
promotion all become worth their cost.
