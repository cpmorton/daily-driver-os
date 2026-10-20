---
name: ci
description: >-
  GitHub Actions, Renovate, trunk-based releases, signing, and promotion of a
  tested digest to :stable. Use when changing workflows, dependency policy, or
  releasing.
---

# CI

## Workflows

| Workflow | Trigger | Does |
|---|---|---|
| `build-image.yml` | push to `main`, daily 14:00 UTC, dispatch | Builds, signs, and pushes `:stable-testing`. |
| `release.yml` | dispatch | Promotes the signed `:stable-testing` digest to `:stable` and `:<version>`; records the GitHub Release. Never rebuilds. |
| `pr-validation.yml` | pull request | The `validate` check (shellcheck, hadolint), plus Brewfiles, Flatpaks, Justfiles and Renovate config, each gated on the paths it checks. |
| `unit-tests.yml` | push, pull request | The bats suite. |
| `build-iso.yml` | dispatch | The installer ISO for a published tag. |
| `renovate.yml` | weekly, config change | Runs Renovate. |
| `clean.yml` | weekly | Deletes images older than 90 days, keeping the newest seven tagged. |

Most steps call reusable actions or workflows in `projectbluefin/actions`.
`release.yml` is the exception: its verify-then-copy core is plain `skopeo` and
`cosign`, owned here ([0025](../../../docs/decisions/0025-trunk-based-releases.md)).

## The release model

One long-lived branch, `main`. Every push builds `:stable-testing`. A release
resolves that tag to a digest once, verifies its cosign signature, copies the
digest with `skopeo copy --preserve-digests` to `:<version>` and then
`:stable`, and creates git tag `v<version>` on the commit the image's revision
label names. The version is the image's own `org.opencontainers.image.version`
label, which the Justfile makes unique per build (`<fedora>.<date>[.N]`).

`--preserve-digests` is load-bearing: cosign signatures are stored against the
digest, so a re-encoded copy would leave `:stable` unsigned. The version tag is
written before `:stable` so the mutable tag never points at something with no
immutable name.

Roll `:stable` back by dispatching `release.yml` with an earlier `version`. A
hotfix that must skip work already on `main` is a branch cut from the last
`v*` tag; that's rare enough to do by hand.

The README owns the release table and the release's current limits.

## Signing

Keyless OIDC via Cosign. There are no keys to generate or store; the build
needs `id-token: write` and `packages: write`. Signing in the build is
`continue-on-error`, so an unsigned image can reach `:stable-testing`, but
`release.yml` refuses it. The README has the command to verify an image.

The identity regexp is scoped with `github.repository`, not
`github.repository_owner`. Matching the owner and then any repository accepts a
signature minted by any repository in the org, and `github.repository` keeps
the scope correct in a fork without hardcoding it.
`tests/template/release_test.bats` guards this.

## Renovate

Self-hosted through `projectbluefin/actions`, running weekly (Monday 14:00
UTC). It pins GitHub Actions to SHAs and updates image digests. The policy lives
in `.github/renovate.json`: updates below a major automerge once checks pass;
majors wait for a pull request.

Renovate needs the `RENOVATE_TOKEN` secret and auto-merge enabled. Both are
onboarding steps.

Automerge deliberately covers GitHub Actions SHA bumps, which reverses a guard
upstream kept. Those SHAs run in jobs holding `packages: write`,
`id-token: write`, and `secrets: inherit`, and PR builds are disabled, so a bump
merges with only shellcheck, hadolint, and the test suite having run. Putting the
guard back is one rule — `matchManagers: ["github-actions"]` with
`automerge: false`.

## Making a change

1. Branch from `main` and open a pull request against it.
2. Wait for `validate` and the tests.
3. Merge. `main` publishes `:stable-testing`.
4. Boot `:stable-testing` if the change is risky.
5. Run **Actions → Release** to publish `:stable`.
