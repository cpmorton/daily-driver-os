#!/usr/bin/env bats
# Unit tests for the first-boot helpers in custom/files/usr/libexec/daily-driver.
# Each runs against a sandbox: SEED_ROOT / USERS_ROOT prefix every path the
# helpers write, and stub commands (usermod, chown, homectl, ...) log calls.
#
# Run with: bats tests/contract/daily-driver-helpers_test.bats

REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
LIBEXEC="${REPO_ROOT}/custom/files/usr/libexec/daily-driver"

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
{"version": 1, "hostname": "chris-laptop",
 "localadmin": {"hashedPassword": "$6$saltsalt$abcdefghijklmnopqrstuv"}}
EOF
	cat >"${SEED}/users/chris.json" <<'EOF'
{"userName": "chris", "realName": "Chris", "diskSize": 107374182400,
 "secret": {"password": ["initial-Passw0rd"]}}
EOF
}

import() {
	SEED_ROOT="${SANDBOX}" SEED_DIR="${SEED}" run "${LIBEXEC}/seed-import"
}

@test "seed-import: applies hostname, localadmin hash and stages the user" {
	write_seed
	mkdir -p "${SEED}/skel/chris/.config" "${SEED}/skel/localadmin"
	echo hi >"${SEED}/skel/chris/.config/hello"
	echo admin >"${SEED}/skel/localadmin/.note"
	import
	[ "$status" -eq 0 ]
	[ "$(cat "${SANDBOX}/etc/hostname")" = chris-laptop ]
	grep -qF 'usermod -p $6$saltsalt$abcdefghijklmnopqrstuv localadmin' "${CALLS}"
	[ -f "${SANDBOX}/var/home/localadmin/.note" ]
	cred="${SANDBOX}/run/credstore/home.create.chris"
	[ "$(stat -c %a "${cred}")" = 600 ] || [ "$(stat -c %a "${cred}")" = 400 ]
	[ "$(stat -c %a "${SANDBOX}/run/credstore")" = 700 ]
	[ "$(jq -r .storage "${cred}")" = luks ]
	[ "$(jq -r .passwordChangeNow "${cred}")" = true ]
	[ "$(jq -r .skeletonDirectory "${cred}")" = /run/daily-driver/skel/chris ]
	[ -f "${SANDBOX}/run/daily-driver/skel/chris/.config/hello" ]
	[ -f "${SANDBOX}/var/lib/daily-driver/seed-imported" ]
}

@test "seed-import: deletes the seed, secrets included, after importing" {
	write_seed
	import
	[ "$status" -eq 0 ]
	[ ! -e "${SEED}" ]
}

@test "seed-import: an explicit passwordChangeNow=false is kept" {
	write_seed
	jq '.passwordChangeNow = false' "${SEED}/users/chris.json" >"${SEED}/x" && mv "${SEED}/x" "${SEED}/users/chris.json"
	import
	[ "$(jq -r .passwordChangeNow "${SANDBOX}/run/credstore/home.create.chris")" = false ]
}

@test "seed-import: a bad localadmin hash changes nothing and keeps the seed" {
	write_seed
	jq '.localadmin.hashedPassword = "plaintext"' "${SEED}/seed.json" >"${SEED}/x" && mv "${SEED}/x" "${SEED}/seed.json"
	import
	[ "$status" -ne 0 ]
	[ ! -s "${CALLS}" ]
	[ ! -e "${SANDBOX}/etc/hostname" ]
	[ -d "${SEED}" ]
	[ ! -e "${SANDBOX}/var/lib/daily-driver/seed-imported" ]
}

@test "seed-import: a user without an initial password is rejected" {
	write_seed
	jq 'del(.secret)' "${SEED}/users/chris.json" >"${SEED}/x" && mv "${SEED}/x" "${SEED}/users/chris.json"
	import
	[ "$status" -ne 0 ]
	[[ "$output" == *"secret.password is required"* ]]
	[ ! -e "${SANDBOX}/run/credstore" ]
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

@test "seed-import: localadmin SSH keys are ignored, not applied" {
	write_seed
	jq '.localadmin.sshAuthorizedKeys = ["ssh-ed25519 AAAA test"]' "${SEED}/seed.json" >"${SEED}/x" && mv "${SEED}/x" "${SEED}/seed.json"
	import
	[ "$status" -eq 0 ]
	[[ "$output" == *"ignoring localadmin.sshAuthorizedKeys"* ]]
	[ ! -e "${SANDBOX}/var/home/localadmin/.ssh" ]
}

@test "seed-import: no seed directory is a clean no-op" {
	rm -rf "${SEED}"
	import
	[ "$status" -eq 0 ]
	[ ! -s "${CALLS}" ]
	[ -f "${SANDBOX}/var/lib/daily-driver/seed-imported" ]
}

@test "first-users: seeded credentials go through homectl firstboot, no prompt" {
	creds="${BATS_TEST_TMPDIR}/creds"
	mkdir -p "${creds}" "${SANDBOX}/run/credstore"
	echo '{}' >"${creds}/home.create.chris"
	echo '{}' >"${SANDBOX}/run/credstore/home.create.chris"
	printf '#!/usr/bin/bash\necho "ensure-subids $*" >>"%s"\n' "${CALLS}" >"${STUBS}/ensure-subids"
	chmod +x "${STUBS}/ensure-subids"
	printf '#!/usr/bin/bash\necho "homectl OVERRIDE=${SYSTEMD_HOME_FIRSTBOOT_OVERRIDE:-} $*" >>"%s"\n' "${CALLS}" >"${STUBS}/homectl"
	CREDENTIALS_DIRECTORY="${creds}" USERS_ROOT="${SANDBOX}" LIBEXEC="${STUBS}" run "${LIBEXEC}/first-users" </dev/null
	[ "$status" -eq 0 ]
	grep -qx 'homectl OVERRIDE=0 firstboot' "${CALLS}"
	grep -qx 'ensure-subids ' "${CALLS}"
	[ ! -e "${SANDBOX}/run/credstore/home.create.chris" ]
	[ -f "${SANDBOX}/var/lib/daily-driver/users-created" ]
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
	# Read-Host is stubbed so the maker's password prompt answers itself.
	pwsh -NoLogo -NoProfile -Command "
		function global:Read-Host { param([switch]\$AsSecureString, [string]\$Prompt)
			ConvertTo-SecureString 'initial-Passw0rd' -AsPlainText -Force }
		& '${REPO_ROOT}/tools/windows/New-DailyDriverSeed.ps1' -Path '${stick}' -Hostname lap-01 -LocalAdminHash '\$y\$j9T\$abcdefgh\$ijklmnop'
		& '${REPO_ROOT}/tools/windows/New-DailyDriverSeed.ps1' -Path '${stick}' -User chris -HomeSizeGB 50
	" >/dev/null
	# BOM-free, or jq on the machine would choke.
	[ "$(head -c1 "${stick}/daily-driver-seed/seed.json")" = "{" ]
	SEED_ROOT="${SANDBOX}" SEED_DIR="${stick}/daily-driver-seed" run "${LIBEXEC}/seed-import"
	[ "$status" -eq 0 ]
	[ "$(cat "${SANDBOX}/etc/hostname")" = lap-01 ]
	grep -qF 'usermod -p $y$j9T$abcdefgh$ijklmnop localadmin' "${CALLS}"
	cred="${SANDBOX}/run/credstore/home.create.chris"
	[ "$(jq -r '.secret.password[0]' "${cred}")" = initial-Passw0rd ]
	[ "$(jq -r .diskSize "${cred}")" = 53687091200 ]
	[ ! -e "${stick}/daily-driver-seed" ]
}

@test "seed maker: refuses a plaintext localadmin password" {
	command -v pwsh >/dev/null || skip "pwsh not installed"
	run pwsh -NoLogo -NoProfile -Command "& '${REPO_ROOT}/tools/windows/New-DailyDriverSeed.ps1' -Path '${BATS_TEST_TMPDIR}/s' -LocalAdminHash 'hunter2'"
	[ "$status" -ne 0 ]
	[ ! -e "${BATS_TEST_TMPDIR}/s/daily-driver-seed/seed.json" ]
}
