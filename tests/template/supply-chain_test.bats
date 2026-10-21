#!/usr/bin/env bats
# Unit tests for the CI supply-chain guards.
#
# Pins make every upstream change a reviewable diff; these guards decide what
# that diff must clear. Each one fails quietly when removed (a build still goes
# green), so the checks read the workflow and Renovate files themselves.
#
# Run with: bats tests/template/supply-chain_test.bats

SCRIPT_DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")" && pwd)"
REPO_ROOT="${SCRIPT_DIR}/../.."
WORKFLOWS="${REPO_ROOT}/.github/workflows"
BUILD="${WORKFLOWS}/build-image.yml"
RELEASE="${WORKFLOWS}/release.yml"
RENOVATE="${REPO_ROOT}/.github/renovate.json"

line_of() {
	grep -nF -- "$2" "$1" | head -n1 | cut -d: -f1
}

# The body of one named step, from its "- name:" line to the next step.
step_body() {
	awk -v name="- name: $2" '
		index($0, name) { found = 1; print; next }
		found && /^      - name:/ { exit }
		found { print }
	' "$1"
}

@test "supply chain: every checkout drops its token after cloning" {
	checkouts=$(cat "${WORKFLOWS}"/*.yml | grep -c 'uses: actions/checkout@')
	dropped=$(cat "${WORKFLOWS}"/*.yml | grep -c 'persist-credentials: false')
	[ "${checkouts}" -gt 0 ]
	[ "${checkouts}" -eq "${dropped}" ]
}

@test "supply chain: both build jobs verify upstream signatures before building" {
	# Each "Build image" step must be preceded, in its own job, by the verify.
	run awk '
		/^  [a-z-]+:$/ { verified = 0 }
		/run: build\/verify-upstream-signatures\.sh/ { verified = 1; seen++ }
		/- name: Build image/ { builds++; if (!verified) bad++ }
		END { exit !(builds == 2 && seen == 2 && bad == 0) }
	' "${BUILD}"
	[ "$status" -eq 0 ]
	run grep -qF 'continue-on-error' <<<"$(step_body "${BUILD}" 'Verify upstream image signatures')"
	[ "$status" -ne 0 ]
}

@test "supply chain: the verify script pins each signer" {
	script="${REPO_ROOT}/build/verify-upstream-signatures.sh"
	grep -qF -- "--certificate-identity-regexp '^https://github\.com/projectbluefin/common/" "${script}"
	grep -qF -- '--key "${UBLUE_KEY}"' "${script}"
	grep -qF -- 'UBLUE_KEY="${REPO_ROOT}/.github/cosign/ublue-os.pub"' "${script}"
}

@test "supply chain: the ublue-os key is a public key" {
	key="${REPO_ROOT}/.github/cosign/ublue-os.pub"
	grep -qF -- '-----BEGIN PUBLIC KEY-----' "${key}"
	run grep -qi 'PRIVATE' "${key}"
	[ "$status" -ne 0 ]
}

@test "supply chain: Renovate holds third-party code for a cooldown" {
	command -v jq >/dev/null || skip "jq not installed"
	rule=$(jq -c '.packageRules[] | select(.minimumReleaseAge != null)' "${RENOVATE}")
	[ -n "${rule}" ]
	jq -e '.matchDatasources | index("github-tags")' <<<"${rule}" >/dev/null
	# GHCR and Quay publish no release timestamps, so aging docker would hold
	# every image update forever.
	run jq -e '.matchDatasources | index("docker")' <<<"${rule}"
	[ "$status" -ne 0 ]
}

@test "supply chain: pull requests that touch workflows run zizmor" {
	pr="${WORKFLOWS}/pr-validation.yml"
	grep -qE "echo \"workflows=\\\$\(match '\^\\\\\.github/\(workflows/" "${pr}"
	grep -qF "if: needs.changes.outputs.workflows == 'true'" "${pr}"
	grep -qE 'ZIZMOR_VERSION: "[0-9]+\.[0-9]+\.[0-9]+"' "${pr}"
}

@test "supply chain: the release soak check warns and never blocks" {
	body="$(step_body "${RELEASE}" 'Warn on an unsoaked change')"
	[ -n "${body}" ]
	grep -qF '::warning::' <<<"${body}"
	run grep -qE 'exit 1|::error::' <<<"${body}"
	[ "$status" -ne 0 ]
}
