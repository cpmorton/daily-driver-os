# 0016. The installer ISO is built in CI; nobody needs Linux to install

- **Status:** Accepted
- **Date:** 2026-09-23

## Amendments

- 2026-09-23, [0017](0017-dual-boot-internal-disk.md): installs go to free space on the internal disk; the installer stick is the only boot media.

## Context

The people installing this image have Windows machines and no Linux.
finpilot builds ISOs locally (`just build-iso`), which needs Linux,
privileged podman and bootc-image-builder.

finpilot's ISO recipe takes the tag that installed machines follow from the
image's own `image-info.json`. `:stable` is a promoted `:stable-testing`
build (the stable branch never rebuilds), so its `image-info.json` says
`stable-testing`: an ISO built from `:stable` would install machines that
follow the testing channel and skip the release gate.

## Decision

- `.github/workflows/build-iso.yml`, run by hand, builds the ISO from the
  published image with the same `just build-iso` recipe, and uploads it plus a
  SHA-256 file as a workflow artifact (kept 14 days).
- The Justfile honors `ISO_IMAGE_TAG`; the workflow sets it to the tag chosen,
  `stable` by default.
- Everything after the artifact happens on Windows: download it, check the
  hash, and write it to a USB stick with Fedora Media Writer
  (`docs/runbooks/reinstall.md`).

## Alternatives

- **Local ISO builds:** need a Linux machine, which the users don't have.
- **WSL2:** bootc-image-builder needs privileged containers and loop devices;
  unproven there.
- **Stock Silverblue ISO, then `bootc switch`:** works, but the installer then
  creates an unrestricted admin user that must be removed afterwards.
- **GitHub Release asset:** release files are capped at 2 GiB, and an ISO with
  this image embedded is expected to exceed that. Check the size from the
  first build's summary before ruling it in or out.

## Consequences

- Downloading the artifact needs a GitHub login and expires after 14 days;
  re-run the workflow to make a fresh one. It's also a good habit: a fresh ISO
  installs a current image.
- A small, documented edit to an upstream file (the Justfile).

## Verification

Read finpilot's `_build-bib` and `_rootful_load_image`: a registry image
reference is pulled into root podman, and the ISO's install target comes from
`image-info.json`. [VERIFY on the first run: runner disk space is enough, and
the artifact downloads.]

## Revisit when

finpilot fixes the tag at the source, or the ISO fits a release asset.
