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
| `build-image.yml` | push to `main`, daily 14:00 UTC, dispatch; pull request | Builds, signs, and pushes `:stable-testing`. On a pull request, the read-only `image-build` job builds without publishing. |
| `release.yml` | dispatch | Promotes the signed `:stable-testing` digest to `:stable` and `:<version>`; records the GitHub Release. Never rebuilds. |
| `pr-validation.yml` | pull request | The `validate` check (shellcheck, hadolint), plus Brewfiles, Flatpaks, Justfiles, Renovate config and workflow security (zizmor), each gated on the paths it checks. |
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
`id-token: write`, and `secrets: inherit`, so a bump merges once `image-build`
has proven the image still builds — provided `main` requires that check, since
GitHub's auto-merge waits only for required checks.
Putting the guard back is one rule — `matchManagers: ["github-actions"]` with
`automerge: false`.

`image-build` builds only when a PR touches an image input (`Containerfile`,
`Justfile`, `build/`, `custom/`, or `build-image.yml`); otherwise it skips the
build and passes. It always reports, so it can be required without stranding
CI- or docs-only PRs. Add a path there if the Containerfile ever copies
something new. It holds
only `contents: read` and builds with `REGISTRY_CACHE_WRITE=0`, so unmerged code
never publishes, signs, or seeds the layer cache.
`tests/template/build-image-pr_test.bats` guards those properties and keeps its
runner and setup identical to the publishing job's.

## Supply chain

Pins make every upstream change a reviewable diff. These guards decide what the
diff has to clear, and `tests/template/supply-chain_test.bats` keeps each one in
place.

- **Cooldown.** Renovate holds GitHub Actions, reusable workflows, and tools
  pinned in workflow env vars (`github-tags`, `github-releases`, `pypi`) until a
  release is 7 days old. Most hijacked releases are caught and pulled within
  days. Container images can't be aged this way: GHCR and Quay publish no
  release timestamps, and Renovate's default (`timestamp-required`) would hold
  every image update forever, so never add `docker` to that rule. A force-pushed
  tag still ages against its original release date, which is why the next guard
  exists.
- **zizmor** audits every workflow on a PR that touches one, online with the
  job's read-only token, so it also catches a pinned SHA that doesn't belong to
  the repository it claims. Pinned by exact version from PyPI. Locally:
  `uvx zizmor@<version> .github/workflows/` (add `--offline` without a token).
  Every `actions/checkout` sets `persist-credentials: false`, and workflow
  expressions reach shell through `env:`, never inline in `run:`.
- **Upstream signatures.** `build-image.yml` runs `cosign verify` on the
  digests the Containerfile pins before it builds. `ghcr.io/projectbluefin/common`
  signs keyless from its own repository's workflows. `ghcr.io/ublue-os/brew`
  signs with ublue-os's key, kept at `.github/cosign/ublue-os.pub` (from
  `ublue-os/brew`'s `cosign.pub`); if ublue-os rotates it, the build fails until
  the file is updated. The Fedora base is pinned by digest only. [VERIFY]
  whether it carries a signature worth checking.
- **Soak warning.** `release.yml` warns, never blocks, when the candidate's
  commit or the Containerfile's last pin change is under `SOAK_DAYS` (2) old.
  The digest itself is always fresh because `main` rebuilds daily, so the
  change behind it is what gets aged.

## Making a change

1. Branch from `main` and open a pull request against it.
2. Wait for `validate`, `image-build`, and the tests.
3. Merge. `main` publishes `:stable-testing`.
4. Boot `:stable-testing` if the change is risky.
5. Run **Actions → Release** to publish `:stable`.
