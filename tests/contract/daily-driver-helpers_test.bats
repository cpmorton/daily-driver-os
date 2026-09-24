#!/usr/bin/env bats
# Unit tests for the first-boot helpers in custom/files/usr/libexec/daily-driver.
# Each runs against a sandbox: SEED_ROOT / USERS_ROOT prefix every path the
# helpers touch, and stub commands (usermod, chown, homectl, ...) log calls.
#
# Run with: bats tests/contract/daily-driver-helpers_test.bats

REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
LIBEXEC="${REPO_ROOT}/custom/files/usr/libexec/daily-driver"

# `! cmd` in the middle of a test asserts nothing (set -e ignores negated
# commands); refute fails the test when cmd succeeds.
refute() {
	if "$@"; then
		echo "expected to fail: $*" >&2
		return 1
	fi
}

setup() {
	SANDBOX="${BATS_TEST_TMPDIR}/root"
	STUBS="${BATS_TEST_TMPDIR}/stubs"
	CALLS="${BATS_TEST_TMPDIR}/calls.log"
	mkdir -p "${SANDBOX}/etc" "${SANDBOX}/var/home" "${STUBS}"
	: >"${CALLS}"
	for tool in usermod chown restorecon homectl; do
		printf '#!/usr/bin/bash\necho "%s $*" >>"%s"\n' "${tool}" "${CALLS}" >"${STUBS}/${tool}"
		chmod +x "${STUBS}/${tool}"
	done
	export PATH="${STUBS}:${PATH}"
	SEED="${BATS_TEST_TMPDIR}/stick/daily-driver-seed"
	mkdir -p "${SEED}/users"
}

write_seed() {
	cat >"${SEED}/seed.json" <<'EOF'
{"version": 1, "hostname": "chris-laptop"}
EOF
	cat >"${SEED}/users/chris.json" <<'EOF'
{"userName": "chris", "realName": "Chris", "diskSize": 107374182400}
EOF
}

import() {
	SEED_ROOT="${SANDBOX}" SEED_DIR="${SEED}" run "${LIBEXEC}/seed-import"
}

staged() { echo "${SANDBOX}/run/daily-driver/users/$1.json"; }

@test "seed-import: applies the hostname and stages the user, skel included" {
	write_seed
	mkdir -p "${SEED}/skel/chris/.config" "${SEED}/skel/localadmin"
	echo hi >"${SEED}/skel/chris/.config/hello"
	echo admin >"${SEED}/skel/localadmin/.note"
	import
	[ "$status" -eq 0 ]
	[ "$(cat "${SANDBOX}/etc/hostname")" = chris-laptop ]
	[ -f "${SANDBOX}/var/home/localadmin/.note" ]
	rec="$(staged chris)"
	[ "$(stat -c %a "$(dirname "${rec}")")" = 700 ]
	[ "$(jq -c 'keys' "${rec}")" = '["diskSize","realName","skeletonDirectory","storage","userName"]' ]
	[ "$(jq -r .storage "${rec}")" = luks ]
	[ "$(jq -r .skeletonDirectory "${rec}")" = /run/daily-driver/skel/chris ]
	[ -f "${SANDBOX}/run/daily-driver/skel/chris/.config/hello" ]
	[ -f "${SANDBOX}/var/lib/daily-driver/seed-imported" ]
	refute grep -q '^usermod' "${CALLS}"
}

@test "seed-import: deletes the seed after importing" {
	write_seed
	import
	[ "$status" -eq 0 ]
	[ ! -e "${SEED}" ]
}

@test "seed-import: passwords and other fields on an older stick are never applied" {
	write_seed
	jq '.localadmin = {hashedPassword: "$6$saltsalt$abcdefghijklmnopqrstuv", sshAuthorizedKeys: ["ssh-ed25519 AAAA test"]}' \
		"${SEED}/seed.json" >"${SEED}/x" && mv "${SEED}/x" "${SEED}/seed.json"
	jq '.secret = {password: ["initial-Passw0rd"]} | .passwordChangeNow = false | .memberOf = ["wheel"]' \
		"${SEED}/users/chris.json" >"${SEED}/x" && mv "${SEED}/x" "${SEED}/users/chris.json"
	import
	[ "$status" -eq 0 ]
	[[ "$output" == *"seed.json: ignoring localadmin"* ]]
	[[ "$output" == *"users/chris.json: ignoring memberOf, passwordChangeNow, secret"* ]]
	refute grep -q '^usermod' "${CALLS}"
	[ ! -e "${SANDBOX}/var/home/localadmin/.ssh" ]
	[ "$(jq -c 'keys' "$(staged chris)")" = '["diskSize","realName","storage","userName"]' ]
	refute grep -rq 'initial-Passw0rd\|saltsalt' "${SANDBOX}"
	[ ! -e "${SEED}" ]
}

@test "seed-import: a bad hostname changes nothing and keeps the seed" {
	write_seed
	jq '.hostname = "not a hostname"' "${SEED}/seed.json" >"${SEED}/x" && mv "${SEED}/x" "${SEED}/seed.json"
	import
	[ "$status" -ne 0 ]
	[ ! -e "${SANDBOX}/etc/hostname" ]
	[ ! -e "${SANDBOX}/run/daily-driver" ]
	[ -d "${SEED}" ]
	[ ! -e "${SANDBOX}/var/lib/daily-driver/seed-imported" ]
}

@test "seed-import: a home smaller than 10 GiB is rejected" {
	write_seed
	jq '.diskSize = 1000' "${SEED}/users/chris.json" >"${SEED}/x" && mv "${SEED}/x" "${SEED}/users/chris.json"
	import
	[ "$status" -ne 0 ]
	[[ "$output" == *"diskSize"* ]]
	[ ! -e "${SANDBOX}/run/daily-driver" ]
}

@test "seed-import: userName must match the file name" {
	write_seed
	mv "${SEED}/users/chris.json" "${SEED}/users/violet.json"
	import
	[ "$status" -ne 0 ]
	[[ "$output" == *'userName must be "violet"'* ]]
}

@test "seed-import: localadmin can't be seeded as a homed user" {
	write_seed
	jq '.userName = "localadmin"' "${SEED}/users/chris.json" >"${SEED}/users/localadmin.json"
	import
	[ "$status" -ne 0 ]
}

@test "seed-import: no seed directory is a clean no-op" {
	rm -rf "${SEED}"
	import
	[ "$status" -eq 0 ]
	[ ! -s "${CALLS}" ]
	[ -f "${SANDBOX}/var/lib/daily-driver/seed-imported" ]
}

# first-users reads its answers from stdin, as it would from tty1.
first_users() {
	printf '#!/usr/bin/bash\necho "ensure-subids $*" >>"%s"\n' "${CALLS}" >"${STUBS}/ensure-subids"
	chmod +x "${STUBS}/ensure-subids"
	USERS_ROOT="${SANDBOX}" LIBEXEC="${STUBS}" run "${LIBEXEC}/first-users"
}

@test "first-users: a seeded user gets a password typed on the console" {
	mkdir -p "${SANDBOX}/run/daily-driver/users"
	echo '{"userName":"chris","realName":"Chris","diskSize":53687091200,"storage":"luks"}' >"$(staged chris)"
	# Chris isn't at the keyboard (n); no more users (n).
	first_users <<<$'n\nn'
	[ "$status" -eq 0 ]
	[[ "$output" == *"chris (Chris, 50 GB home, from the seed stick)"* ]]
	grep -qxF "homectl create --identity=$(staged chris) --password-change-now=yes" "${CALLS}"
	grep -qx 'ensure-subids ' "${CALLS}"
	[ ! -e "${SANDBOX}/run/daily-driver/users" ]
	[ -f "${SANDBOX}/var/lib/daily-driver/users-created" ]
}

@test "first-users: a failed create is retried, not skipped" {
	mkdir -p "${SANDBOX}/run/daily-driver/users"
	echo '{"userName":"chris","storage":"luks"}' >"$(staged chris)"
	# Fails once, then succeeds.
	cat >"${STUBS}/homectl" <<EOF
#!/usr/bin/bash
echo "homectl \$*" >>"${CALLS}"
[[ -e "${BATS_TEST_TMPDIR}/failed" ]] && exit 0
touch "${BATS_TEST_TMPDIR}/failed"; exit 1
EOF
	# At the keyboard (default); Enter to retry; no more users.
	first_users <<<$'\n\nn'
	[ "$status" -eq 0 ]
	[ "$(grep -c -- '--password-change-now=no' "${CALLS}")" -eq 2 ]
}

@test "first-users: with no seed, asks for each user's details on the console" {
	# Invalid name, then a too-small home, then a good user at the keyboard; stop.
	first_users <<<$'Bad Name\nchris\nChris M\n5\nchris\nChris M\n50\ny\nn'
	[ "$status" -eq 0 ]
	grep -qxF 'homectl create chris --real-name=Chris M --storage=luks --disk-size=50G --password-change-now=no' "${CALLS}"
	[ "$(grep -c '^homectl create' "${CALLS}")" -eq 1 ]
}

@test "first-users: never hands homectl a password" {
	refute grep -nE 'NEWPASSWORD|secret|--password=' "${LIBEXEC}/first-users"
}

@test "ensure-subids: allocates non-overlapping ranges, idempotently" {
	export SUBUID_FILE="${BATS_TEST_TMPDIR}/subuid" SUBGID_FILE="${BATS_TEST_TMPDIR}/subgid"
	echo "localadmin:524288:65536" >"${SUBUID_FILE}"
	: >"${SUBGID_FILE}"
	run "${LIBEXEC}/ensure-subids" chris violet
	[ "$status" -eq 0 ]
	grep -qx 'chris:589824:65536' "${SUBUID_FILE}"
	grep -qx 'violet:655360:65536' "${SUBUID_FILE}"
	grep -qx 'chris:100000:65536' "${SUBGID_FILE}"
	run "${LIBEXEC}/ensure-subids" chris violet
	[ "$(grep -c '^chris:' "${SUBUID_FILE}")" -eq 1 ]
}

@test "windows-boot-entry: renders a chainload entry for the ESP" {
	run "${LIBEXEC}/windows-boot-entry" --print ABCD-1234
	[ "$status" -eq 0 ]
	[[ "$output" == *"search --no-floppy --fs-uuid --set=root ABCD-1234"* ]]
	[[ "$output" == *"chainloader /EFI/Microsoft/Boot/bootmgfw.efi"* ]]
	[[ "$output" == *"set timeout=5"* ]]
	run "${LIBEXEC}/windows-boot-entry" --print 'x; rm -rf /'
	[ "$status" -eq 2 ]
}

@test "helpers: shellcheck clean (CI's lint only covers *.sh files)" {
	command -v shellcheck >/dev/null || skip "shellcheck not installed"
	shellcheck "${LIBEXEC}"/*
}

@test "seed maker -> seed-import: a seed written on Windows imports on Linux" {
	command -v pwsh >/dev/null || skip "pwsh not installed (GitHub's Ubuntu runners have it)"
	stick="${BATS_TEST_TMPDIR}/stick"
	pwsh -NoLogo -NoProfile -Command "
		& '${REPO_ROOT}/tools/windows/New-DailyDriverSeed.ps1' -Path '${stick}' -Hostname lap-01
		& '${REPO_ROOT}/tools/windows/New-DailyDriverSeed.ps1' -Path '${stick}' -User chris -HomeSizeGB 50
	" </dev/null >/dev/null
	# BOM-free, or jq on the machine would choke.
	[ "$(head -c1 "${stick}/daily-driver-seed/seed.json")" = "{" ]
	[ "$(jq -c 'keys' "${stick}/daily-driver-seed/users/chris.json")" = '["diskSize","realName","userName"]' ]
	SEED_ROOT="${SANDBOX}" SEED_DIR="${stick}/daily-driver-seed" run "${LIBEXEC}/seed-import"
	[ "$status" -eq 0 ]
	[ "$(cat "${SANDBOX}/etc/hostname")" = lap-01 ]
	[ "$(jq -r .diskSize "$(staged chris)")" = 53687091200 ]
	[ ! -e "${stick}/daily-driver-seed" ]
}

@test "seed maker: takes no password or hash" {
	command -v pwsh >/dev/null || skip "pwsh not installed"
	run pwsh -NoLogo -NoProfile -Command "(Get-Command '${REPO_ROOT}/tools/windows/New-DailyDriverSeed.ps1').Parameters.Keys -join ' '"
	[ "$status" -eq 0 ]
	[[ "$output" == *Hostname* ]]
	[[ "$output" != *Password* && "$output" != *Hash* ]]
	refute grep -n 'Read-Host -AsSecureString' "${REPO_ROOT}/tools/windows/New-DailyDriverSeed.ps1"
}

@test "seed maker: scrubs passwords an older version left on the stick" {
	command -v pwsh >/dev/null || skip "pwsh not installed"
	seed="${BATS_TEST_TMPDIR}/s/daily-driver-seed"
	mkdir -p "${seed}/users"
	echo '{"version":1,"hostname":"old","localadmin":{"hashedPassword":"$6$saltsalt$abcdefghijklmnopqrstuv"}}' >"${seed}/seed.json"
	echo '{"userName":"chris","realName":"Chris","diskSize":53687091200,"storage":"luks","passwordChangeNow":true,"secret":{"password":["initial-Passw0rd"]}}' >"${seed}/users/chris.json"
	run pwsh -NoLogo -NoProfile -Command "& '${REPO_ROOT}/tools/windows/New-DailyDriverSeed.ps1' -Path '${BATS_TEST_TMPDIR}/s' -User violet" </dev/null
	[ "$status" -eq 0 ]
	refute grep -rq 'initial-Passw0rd\|saltsalt' "${seed}"
	[ "$(jq -r .hostname "${seed}/seed.json")" = old ]
	[ "$(jq -c 'keys' "${seed}/users/chris.json")" = '["diskSize","realName","userName"]' ]
	[ -f "${seed}/users/violet.json" ]
}
