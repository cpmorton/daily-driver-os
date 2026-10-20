#!/usr/bin/env bats
# Unit tests for .github/workflows/release.yml (decision 0025).
#
# The release has one job: put the exact signed digest :stable-testing already
# serves under :stable, without rebuilding. Each property below is a way that
# quietly stops being true — a re-encoded copy orphans the signature, a missing
# verify ships an unsigned image, an org-wide identity accepts another repo's
# signature — and none of them would fail a run. The checks read the workflow
# itself, so they cannot drift from it.
#
# Run with: bats tests/template/release_test.bats

SCRIPT_DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")" && pwd)"
REPO_ROOT="${SCRIPT_DIR}/../.."
WORKFLOW="${REPO_ROOT}/.github/workflows/release.yml"

line_of() {
	grep -nF -- "$1" "${WORKFLOW}" | head -n1 | cut -d: -f1
}

@test "release: runs only on dispatch, from the default branch" {
	run grep -E '^  (push|schedule|pull_request|workflow_run):' "${WORKFLOW}"
	[ "$status" -ne 0 ]
	grep -qF 'workflow_dispatch:' "${WORKFLOW}"
	grep -qF 'if: github.ref_name == github.event.repository.default_branch' "${WORKFLOW}"
}

@test "release: promotes a digest and never builds" {
	run grep -qE 'just build|podman build|buildah|docker build' "${WORKFLOW}"
	[ "$status" -ne 0 ]
	grep -qF 'skopeo copy --preserve-digests --all "docker://${IMAGE}@${DIGEST}"' "${WORKFLOW}"
}

@test "release: verifies the signature before anything is copied" {
	verify="$(line_of 'cosign verify \')"
	copy="$(line_of 'skopeo copy')"
	[ -n "${verify}" ] && [ -n "${copy}" ]
	[ "${verify}" -lt "${copy}" ]
	# A failed verify must stop the job, not warn and carry on.
	run grep -qF 'continue-on-error' "${WORKFLOW}"
	[ "$status" -ne 0 ]
}

@test "release: writes the immutable version tag before moving :stable" {
	grep -qF 'for tag in "${VERSION}" "${TARGET_TAG}"; do' "${WORKFLOW}"
	grep -qF 'TARGET_TAG: stable' "${WORKFLOW}"
}

@test "release: resolves the mutable source tag exactly once" {
	[ "$(grep -cF 'docker://${IMAGE}:${SOURCE_TAG}' "${WORKFLOW}")" -eq 1 ]
}

@test "release: the signature identity is scoped to this repository" {
	# A signature's identity is the signing workflow's URL. Matching the owner and
	# then any repository (`[^/]+`) accepts a signature minted by any repo in the
	# org, so the identity must name this repository. github.repository keeps that
	# true in a fork without hardcoding the owner.
	grep -qF 'IDENTITY_REGEXP: ^https://github\.com/${{ github.repository }}/\.github/workflows/' "${WORKFLOW}"

	# The org-wide form is the regression this guards, in any workflow.
	run grep -rqF 'github.repository_owner }}/[^/]+/\.github' "${REPO_ROOT}/.github/workflows/"
	[ "$status" -ne 0 ]
}

@test "release: no workflow still targets a stable branch" {
	# Decision 0025 removed the branch; a trigger on it would never fire.
	run grep -rqE 'branches: *\[[^]]*\bstable\b' "${REPO_ROOT}/.github/workflows/"
	[ "$status" -ne 0 ]
	# The block form: a `- stable` item within a few lines of `branches:`.
	run bash -c "grep -rA3 -E '^ +branches:' '${REPO_ROOT}/.github/workflows/' | grep -qE -- '- +- stable\$'"
	[ "$status" -ne 0 ]
}
