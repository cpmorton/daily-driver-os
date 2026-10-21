#!/usr/bin/env bash
# Verify the cosign signatures on the upstream images the Containerfile pins,
# before anything is built on them. CI runs this in both build-image jobs.
#
# Renovate cannot age GHCR or Quay digests (they publish no release
# timestamps), so this is the check that a bumped digest is genuine:
# - ghcr.io/projectbluefin/common signs keyless from its own repository's
#   workflows.
# - ghcr.io/ublue-os/brew signs with ublue-os's key, copied from
#   ublue-os/brew's cosign.pub into .github/cosign/ublue-os.pub.
# The Fedora base is pinned by digest only. [VERIFY] whether it is signed.
#
# Usage: build/verify-upstream-signatures.sh   (needs cosign on PATH)
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONTAINERFILE="${REPO_ROOT}/Containerfile"
UBLUE_KEY="${REPO_ROOT}/.github/cosign/ublue-os.pub"

# Print "<image>@<digest>" for the FROM line that pins $1, or nothing.
pinned() {
	sed -nE "s|^FROM (${1//./\\.}):[^@ ]+@(sha256:[0-9a-f]{64}).*|\\1@\\2|p" "${CONTAINERFILE}"
}

common=$(pinned ghcr.io/projectbluefin/common)
brew=$(pinned ghcr.io/ublue-os/brew)
if [[ -z "${common}" || -z "${brew}" ]]; then
	echo "::error::Containerfile no longer pins common and brew by digest"
	exit 1
fi

cosign verify \
	--certificate-identity-regexp '^https://github\.com/projectbluefin/common/\.github/workflows/' \
	--certificate-oidc-issuer 'https://token.actions.githubusercontent.com' \
	"${common}" >/dev/null
cosign verify --key "${UBLUE_KEY}" "${brew}" >/dev/null
echo "Signatures verified: ${common} ${brew}"
