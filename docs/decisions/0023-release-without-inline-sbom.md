# 0023. Stable releases carry a placeholder SBOM, not an inline Syft scan

- **Status:** Accepted
- **Date:** 2026-09-25

## Context

`execute-release.yml` promotes the candidate digest to `:stable`, then calls
`projectbluefin/actions`' `reusable-release.yml` to create a GitHub Release.
With `generate_sbom_inline: true` that job runs Syft against the promoted
image. On this image the hosted runner VM shut down during the scan both
times it ran (2026-09-25), at about 7 minutes 50 seconds. The step's own
8-minute timeout and `continue-on-error` never took effect, so the
placeholder-SBOM fallback after it was skipped and no release was created.
`:stable` itself was already published, so the image was unaffected.

## Decision

Call the reusable in artifact mode (`generate_sbom_inline: false`, with
`build_workflow: build-image.yml` and `build_branch: main`). The build uploads
no SBOM artifact, so the download fails and the reusable writes its minimal
SPDX placeholder, which it already does whenever inline generation fails. The
release is created every time, and its SBOM is empty.

## Alternatives

- **Keep inline mode:** fails on every promotion and leaves no release.
- **Generate an SBOM in `build-image.yml` and upload it as `sbom-bluefin`:**
  gives a real SBOM, but adds a memory-heavy scan to every nightly build.
  Worth doing if an SBOM is ever needed.
- **Drop the release job:** loses the release page and its verification
  notes.

## Consequences

- The release's SPDX file lists no packages. Don't treat it as an inventory:
  `docs/PROVENANCE.md` and `rpm -qa` on a machine are the real ones.
- Nothing changes for `:stable` or for installed machines.

## Verification

Runs 36092457768 attempts 1 and 2: "The runner has received a shutdown
signal" during "Generate SBOM inline from promoted image". Read
`reusable-release.yml` at `837850b`: artifact mode's fallback step runs when
the download fails.

## Revisit when

The build publishes an SBOM artifact, or the reusable's inline scan fits the
runner.
