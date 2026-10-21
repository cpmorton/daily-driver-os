#!/usr/bin/env bats
# Unit tests for the pull-request half of .github/workflows/build-image.yml.
#
# A PR builds the image so a breaking change (a Renovate digest bump included)
# is caught before main, but code under review must never publish, sign or
# seed the layer cache. Those properties live in YAML nothing else checks, and
# the PR job must keep building on the same runner and setup as the publishing
# job, or "it built on the PR" stops meaning anything.
#
# Run with: bats tests/template/build-image-pr_test.bats

SCRIPT_DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")" && pwd)"
WORKFLOW="${SCRIPT_DIR}/../../.github/workflows/build-image.yml"

# The text of one top-level job: from its key to the next job's key.
job() {
	awk -v key="  $1:" '
		$0 == key { on = 1; print; next }
		on && /^  [a-z][a-z0-9-]*:$/ { exit }
		on { print }
	' "${WORKFLOW}"
}

@test "build-image: pull requests trigger the workflow" {
	grep -qE '^  pull_request:' "${WORKFLOW}"
}

@test "build-image: the publishing job never runs for a pull request" {
	job build | grep -qF "github.event_name != 'pull_request'"
}

@test "build-image: the PR job runs only for pull requests, read-only" {
	pr="$(job image-build)"
	[ -n "${pr}" ]
	grep -qF "if: github.event_name == 'pull_request'" <<<"${pr}"
	grep -qE '^      contents: read$' <<<"${pr}"
	run grep -E 'packages: write|id-token: write|attestations: write' <<<"${pr}"
	[ "$status" -ne 0 ]
	# The workflow-level default must not hand them out either.
	run awk '/^permissions:/{on=1;next} on && /^[a-z]/{exit} on' "${WORKFLOW}"
	[[ "$output" != *"write"* ]]
}

@test "build-image: the PR job never publishes, signs or writes the cache" {
	pr="$(job image-build)"
	run grep -E 'push-image|sign-and-publish|tag-images|action: save|allow-write' <<<"${pr}"
	[ "$status" -ne 0 ]
	grep -qF 'REGISTRY_CACHE_WRITE: "0"' <<<"${pr}"
}

@test "build-image: the PR job builds on the same runner and setup as main" {
	for field in 'runs-on:' 'bootc-build/setup-runner@' 'storage-backend:' 'native-overlay:'; do
		main_line="$(job build | grep -F "${field}" | head -n1 | sed 's/^ *//')"
		pr_line="$(job image-build | grep -F "${field}" | head -n1 | sed 's/^ *//')"
		[ -n "${main_line}" ]
		[ "${main_line}" = "${pr_line}" ]
	done
}
