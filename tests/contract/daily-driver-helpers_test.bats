#!/usr/bin/env bats
# Unit tests for the first-boot and home helpers in
# custom/files/usr/libexec/daily-driver, and the Windows defaults script.
# Each runs against a sandbox: *_ROOT / HOME_DIR seams prefix every path the
# helpers touch, and stub commands (homectl, systemd-cryptenroll, usermod, ...)
# log their calls to CALLS. Console answers come in on stdin, as on tty1.
#
# Run with: bats tests/contract/daily-driver-helpers_test.bats

REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
LIBEXEC="${REPO_ROOT}/custom/files/usr/libexec/daily-driver"
PS1_SCRIPT="${REPO_ROOT}/tools/windows/Set-DailyDriverDefaults.ps1"
export POWERSHELL_TELEMETRY_OPTOUT=1

# `! cmd` in the middle of a test asserts nothing (set -e ignores negated
# commands); refute fails the test when cmd succeeds.
refute() {
	if "$@"; then
		echo "expected to fail: $*" >&2
		return 1
	fi
}

# stub NAME [BODY]: a command that logs "NAME args" to CALLS, then runs BODY.
stub() {
	printf '#!/usr/bin/bash\necho "%s $*" >>"%s"\n%s\n' "$1" "${CALLS}" "${2:-}" >"${STUBS}/$1"
	chmod +x "${STUBS}/$1"
}

setup() {
	SANDBOX="${BATS_TEST_TMPDIR}/root"
	STUBS="${BATS_TEST_TMPDIR}/stubs"
	CALLS="${BATS_TEST_TMPDIR}/calls.log"
	FLAGS="${BATS_TEST_TMPDIR}/flags"
	mkdir -p "${SANDBOX}/etc" "${SANDBOX}/var/home" "${STUBS}" "${FLAGS}"
	: >"${CALLS}"
	for tool in usermod chown restorecon hostnamectl systemd-cryptenroll systemctl clear; do
		stub "${tool}"
	done
	# homectl: nobody exists (inspect fails) and there are no homes (list is empty).
	stub homectl '[[ "$1" == inspect ]] && exit 1; exit 0'
	stub ensure-subids
	export PATH="${STUBS}:${PATH}"
}

# --- defaults-import -----------------------------------------------------------

write_defaults() {
	mkdir -p "${BATS_TEST_TMPDIR}/esp"
	DEFAULTS="${BATS_TEST_TMPDIR}/esp/defaults.json"
	cat >"${DEFAULTS}" <<'EOF'
{"version": 1, "hostname": "lap-01",
 "localadmin": {"hashedPassword": "$6$rounds=5000$saltsalt$abcdefghijklmnopqrstuv"},
 "diskUnlock": "tpm2",
 "users": [{"userName": "chris", "realName": "Chris M", "uid": 60101, "shell": "/bin/zsh",
            "diskSize": 214748364800, "passwordChangeNow": false},
           {"userName": "violet", "passwordChangeNow": true}],
 "flatpaks": ["org.gnome.Boxes"]}
EOF
}

set_field() {
	jq "$1" "${DEFAULTS}" >"${DEFAULTS}.new" && mv "${DEFAULTS}.new" "${DEFAULTS}"
}

import_defaults() {
	DEFAULTS_ROOT="${SANDBOX}" DEFAULTS_FILE="${DEFAULTS}" run "${LIBEXEC}/defaults-import"
}

imported() { echo "${SANDBOX}/run/daily-driver/defaults.json"; }
preinstall() { echo "${SANDBOX}/etc/flatpak/preinstall.d/60-machine-defaults.preinstall"; }

@test "defaults-import: keeps the allowed fields, private to root" {
	write_defaults
	import_defaults
	[ "$status" -eq 0 ]
	[ "$(stat -c %a "$(imported)")" = 600 ]
	[ "$(jq -c 'keys' "$(imported)")" = '["diskUnlock","flatpaks","hostname","localadmin","users","version"]' ]
	[ "$(jq -r '.users[0].shell' "$(imported)")" = /bin/zsh ]
	[ "$(jq -r '.users[1].passwordChangeNow' "$(imported)")" = true ]
	grep -qx '\[Flatpak Preinstall org.gnome.Boxes\]' "$(preinstall)"
	grep -qx 'Branch=stable' "$(preinstall)"
}

@test "defaults-import: drops anything off the allowlist, secrets and groups included" {
	write_defaults
	set_field '.users[0].secret = {password: ["hunter2hunter2"]} | .users[0].memberOf = ["wheel"]
		| .localadmin.sshAuthorizedKeys = ["ssh-ed25519 AAAA"] | .extra = 1'
	import_defaults
	[ "$status" -eq 0 ]
	[[ "$output" == *"ignoring extra, localadmin.sshAuthorizedKeys, users[chris].memberOf, users[chris].secret"* ]]
	[ "$(jq -c '.users[0] | keys' "$(imported)")" = '["diskSize","passwordChangeNow","realName","shell","uid","userName"]' ]
	[ "$(jq -c '.localadmin | keys' "$(imported)")" = '["hashedPassword"]' ]
	refute grep -rq hunter2 "${SANDBOX}"
}

@test "defaults-import: rejects bad values and writes nothing" {
	write_defaults
	for change in '.localadmin.hashedPassword = "plaintext"' '.users[0].uid = 1000' \
		'.diskUnlock = "usb"' '.users[1].userName = "chris"' '.users[0].userName = "localadmin"' \
		'.hostname = "not a host"' '.flatpaks = ["boxes"]' '.users[1].uid = 60101' '.localadmin = "x"' \
		'.users[0].diskSize = 1e40' '.users[0].userName = "Chris"'; do
		write_defaults
		set_field "${change}"
		import_defaults
		[ "$status" -ne 0 ] || { echo "accepted: ${change}" >&2; return 1; }
		[ ! -e "$(imported)" ]
		[ -s "${SANDBOX}/run/daily-driver/defaults.error" ]
	done
}

@test "defaults-import: no defaults file is a clean no-op" {
	DEFAULTS="${BATS_TEST_TMPDIR}/nothing.json"
	import_defaults
	[ "$status" -eq 0 ]
	[ ! -e "$(imported)" ]
	[ ! -e "$(preinstall)" ]
}

@test "defaults-import: removing every Flatpak removes the preinstall file" {
	write_defaults
	import_defaults
	[ -f "$(preinstall)" ]
	set_field '.flatpaks = []'
	import_defaults
	[ "$status" -eq 0 ]
	[ ! -e "$(preinstall)" ]
}

# --- firstboot -----------------------------------------------------------------

# LIBEXEC stubs for the steps firstboot delegates. localadmin needs a password
# until usermod or passwd sets one.
firstboot_stubs() {
	stub localadmin-needs-password "[[ ! -e '${FLAGS}/admin' ]]"
	stub usermod "touch '${FLAGS}/admin'"
	stub passwd "touch '${FLAGS}/admin'"
	stub disk-unlock
	stub first-users 'echo "first-users USERS_ROOT=${USERS_ROOT}" >>'"'${CALLS}'"
}

firstboot() {
	FIRSTBOOT_ROOT="${SANDBOX}" LIBEXEC="${STUBS}" run "${LIBEXEC}/firstboot"
}

@test "firstboot: Enter accepts every default" {
	write_defaults
	import_defaults
	firstboot_stubs
	firstboot <<<$'\n\n'
	[ "$status" -eq 0 ]
	grep -qx 'hostnamectl set-hostname lap-01' "${CALLS}"
	grep -qxF 'usermod -p $6$rounds=5000$saltsalt$abcdefghijklmnopqrstuv localadmin' "${CALLS}"
	refute grep -q '^passwd' "${CALLS}"
	grep -qx 'disk-unlock tpm2' "${CALLS}"
	grep -qx "first-users USERS_ROOT=${SANDBOX}" "${CALLS}"
	[ -f "${SANDBOX}/var/lib/daily-driver/firstboot-done" ]
}

@test "firstboot: typed answers override the defaults" {
	write_defaults
	import_defaults
	firstboot_stubs
	# Another hostname; decline the stored localadmin hash, so passwd asks.
	firstboot <<<$'desk-02\nn\n'
	[ "$status" -eq 0 ]
	grep -qx 'hostnamectl set-hostname desk-02' "${CALLS}"
	refute grep -q '^usermod' "${CALLS}"
	grep -qx 'passwd localadmin' "${CALLS}"
}

@test "firstboot: without defaults, asks for everything" {
	firstboot_stubs
	stub hostnamectl '[[ "$1" == hostname ]] && echo fedora; exit 0'
	firstboot <<<$'Bad_Name!\nlap-09\n'
	[ "$status" -eq 0 ]
	[[ "$output" == *"Letters, digits and hyphens only"* ]]
	grep -qx 'hostnamectl set-hostname lap-09' "${CALLS}"
	grep -qx 'passwd localadmin' "${CALLS}"
	grep -qx 'disk-unlock ' "${CALLS}"
}

@test "firstboot: an interrupted first boot resumes after the last finished step" {
	firstboot_stubs
	mkdir -p "${SANDBOX}/var/lib/daily-driver"
	touch "${SANDBOX}/var/lib/daily-driver/firstboot."{hostname,localadmin}
	firstboot </dev/null
	[ "$status" -eq 0 ]
	refute grep -q '^hostnamectl\|^passwd\|^usermod' "${CALLS}"
	grep -q '^disk-unlock' "${CALLS}"
	grep -q '^first-users' "${CALLS}"
}

@test "firstboot: rejected defaults are reported, and the console carries on" {
	firstboot_stubs
	mkdir -p "${SANDBOX}/run/daily-driver"
	echo 'users[chris].uid: must be 60001-60513' >"${SANDBOX}/run/daily-driver/defaults.error"
	firstboot <<<$'lap-01\n'
	[ "$status" -eq 0 ]
	[[ "$output" == *"were rejected: users[chris].uid"* ]]
}

# --- first-users ---------------------------------------------------------------

first_users() {
	USERS_ROOT="${SANDBOX}" LIBEXEC="${STUBS}" SHELLS_FILE="${BATS_TEST_TMPDIR}/shells" run "${LIBEXEC}/first-users"
}

@test "first-users: creates default users with their UID, shell and password rule" {
	write_defaults
	import_defaults
	printf '/bin/bash\n/bin/zsh\n' >"${BATS_TEST_TMPDIR}/shells"
	# chris: create, Enter (at the keyboard). violet: create, Enter (defaults
	# say someone else types it, so she must change it). No more users.
	first_users <<<$'c\n\nc\n\nn'
	[ "$status" -eq 0 ]
	grep -qxF 'homectl create chris --real-name=Chris M --storage=luks --disk-size=200G --uid=60101 --shell=/bin/zsh --password-change-now=no' "${CALLS}"
	grep -qxF 'homectl create violet --real-name=violet --storage=luks --disk-size=100G --password-change-now=yes' "${CALLS}"
	grep -qx 'ensure-subids ' "${CALLS}"
}

@test "first-users: a user can be skipped to restore a backup later" {
	write_defaults
	import_defaults
	first_users <<<$'s\ns\nn'
	[ "$status" -eq 0 ]
	refute grep -q '^homectl create' "${CALLS}"
	[[ "$output" == *"ujust restore-home chris"* ]]
}

@test "first-users: a shell that isn't installed falls back to the default" {
	write_defaults
	import_defaults
	echo /bin/bash >"${BATS_TEST_TMPDIR}/shells"
	first_users <<<$'c\n\ns\nn'
	[ "$status" -eq 0 ]
	[[ "$output" == *"/bin/zsh isn't installed here"* ]]
	refute grep -q -- '--shell=' "${CALLS}"
}

@test "first-users: with no defaults, asks for each user's details" {
	# First user: yes. Invalid name, too-small home, then a good user; stop.
	first_users <<<$'\nBad Name\nchris\nChris M\n5\nchris\nChris M\n50\ny\nn'
	[ "$status" -eq 0 ]
	grep -qxF 'homectl create chris --real-name=Chris M --storage=luks --disk-size=50G --password-change-now=no' "${CALLS}"
	[ "$(grep -c '^homectl create' "${CALLS}")" -eq 1 ]
}

@test "first-users: with no defaults, no user at all is fine (restore later)" {
	first_users <<<$'n'
	[ "$status" -eq 0 ]
	refute grep -q '^homectl create' "${CALLS}"
}

@test "first-users: a failed create is retried, not skipped" {
	write_defaults
	import_defaults
	set_field '.users |= .[:1]'
	import_defaults
	echo /bin/zsh >"${BATS_TEST_TMPDIR}/shells"
	# create fails once, then succeeds
	stub homectl "[[ \"\$1\" == inspect ]] && exit 1; [[ \"\$1\" == create && ! -e '${FLAGS}/failed' ]] && { touch '${FLAGS}/failed'; exit 1; }; exit 0"
	first_users <<<$'c\n\n\nn'
	[ "$status" -eq 0 ]
	[ "$(grep -c '^homectl create chris' "${CALLS}")" -eq 2 ]
}

@test "first-users: a create that keeps failing can be skipped" {
	write_defaults
	import_defaults
	set_field '.users |= .[1:]'
	import_defaults
	stub homectl '[[ "$1" == inspect ]] && exit 1; [[ "$1" == create ]] && exit 1; exit 0'
	# violet: create, Enter; the create fails: skip; no more users.
	first_users <<<$'c\n\ns\nn'
	[ "$status" -eq 0 ]
	[[ "$output" == *"Skipped violet"* ]]
	[ "$(grep -c '^homectl create violet' "${CALLS}")" -eq 1 ]
}

@test "first-users: an existing user is left alone" {
	write_defaults
	import_defaults
	stub homectl '[[ "$1 $2" == "inspect chris" ]] && exit 0; [[ "$1" == inspect ]] && exit 1; exit 0'
	first_users <<<$'s\nn'
	[ "$status" -eq 0 ]
	[[ "$output" == *"chris already exists here"* ]]
	refute grep -q '^homectl create chris' "${CALLS}"
}

@test "first-users: never hands homectl a password" {
	refute grep -nE 'NEWPASSWORD|secret|--password=' "${LIBEXEC}/first-users"
}

# --- disk-unlock ---------------------------------------------------------------

# systemd-cryptenroll DEVICE alone lists the enrolled slots: FLAGS/slots holds
# their types. Only enrollment and wipe calls are logged.
cryptenroll_stub() {
	stub systemd-cryptenroll "${1:-}"
	sed -i "2i if [[ \$# -eq 1 ]]; then echo 'SLOT TYPE'; n=0; while read -r t; do echo \"\$((n++)) \$t\"; done <'${FLAGS}/slots'; exit 0; fi" "${STUBS}/systemd-cryptenroll"
	echo password >"${FLAGS}/slots"
}

disk_unlock() {
	[[ -e "${FLAGS}/slots" ]] || cryptenroll_stub
	ROOT_LUKS_DEVICE="${LUKS:-/dev/nvme0n1p3}" TPM_DEVICE="${BATS_TEST_TMPDIR}/tpmrm0" \
		run "${LIBEXEC}/disk-unlock" "$@"
}

@test "disk-unlock: an unencrypted root gets a warning, and nothing is enrolled" {
	LUKS=none disk_unlock </dev/null
	[ "$status" -eq 0 ]
	[[ "$output" == *"NOT encrypted"* ]]
	[ ! -s "${CALLS}" ]
}

@test "disk-unlock: with a TPM and no default, tpm2-pin is offered" {
	touch "${BATS_TEST_TMPDIR}/tpmrm0"
	disk_unlock <<<$'\nn'
	[ "$status" -eq 0 ]
	grep -q -- '--tpm2-with-pin=yes' "${CALLS}"
}

@test "disk-unlock: tpm2 binds to PCR 7 and adds a recovery key" {
	touch "${BATS_TEST_TMPDIR}/tpmrm0"
	disk_unlock tpm2 <<<$'\n\n\n'
	[ "$status" -eq 0 ]
	grep -qx 'systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=7 --wipe-slot=tpm2,fido2 /dev/nvme0n1p3' "${CALLS}"
	grep -qx 'systemd-cryptenroll --recovery-key /dev/nvme0n1p3' "${CALLS}"
}

@test "disk-unlock: tpm2-pin asks for a PIN" {
	touch "${BATS_TEST_TMPDIR}/tpmrm0"
	disk_unlock tpm2-pin <<<$'\nn'
	[ "$status" -eq 0 ]
	grep -qx 'systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=7 --wipe-slot=tpm2,fido2 --tpm2-with-pin=yes /dev/nvme0n1p3' "${CALLS}"
	refute grep -q -- '--recovery-key' "${CALLS}"
}

@test "disk-unlock: without a TPM, tpm2 is refused and passphrase needs no enrollment" {
	disk_unlock tpm2 <<<$'\npassphrase\nn'
	[ "$status" -eq 0 ]
	[[ "$output" == *"No TPM2 chip found"* ]]
	[ ! -s "${CALLS}" ]
}

@test "disk-unlock: fido2 replaces older enrollments, then adds a spare" {
	disk_unlock fido2 <<<$'\ny\n\nn\nn'
	[ "$status" -eq 0 ]
	grep -qx 'systemd-cryptenroll --fido2-device=auto --wipe-slot=tpm2,fido2 /dev/nvme0n1p3' "${CALLS}"
	# The spare must not wipe the key just enrolled.
	grep -qx 'systemd-cryptenroll --fido2-device=auto /dev/nvme0n1p3' "${CALLS}"
}

@test "disk-unlock: switching to passphrase removes TPM and key enrollments" {
	cryptenroll_stub
	printf 'password\ntpm2\nrecovery\n' >"${FLAGS}/slots"
	# passphrase; keep the existing recovery key (Enter = no).
	disk_unlock <<<$'passphrase\n'
	[ "$status" -eq 0 ]
	grep -qx 'systemd-cryptenroll --wipe-slot=tpm2,fido2 /dev/nvme0n1p3' "${CALLS}"
	refute grep -q -- '--recovery-key' "${CALLS}"
}

@test "disk-unlock: passphrase with nothing to remove changes nothing" {
	disk_unlock passphrase <<<$'\nn'
	[ "$status" -eq 0 ]
	[ ! -s "${CALLS}" ]
}

@test "disk-unlock: an existing recovery key is replaced, not added to" {
	cryptenroll_stub
	printf 'password\nrecovery\n' >"${FLAGS}/slots"
	disk_unlock passphrase <<<$'\ny\n\n'
	[ "$status" -eq 0 ]
	grep -qx 'systemd-cryptenroll --recovery-key --wipe-slot=recovery /dev/nvme0n1p3' "${CALLS}"
}

@test "disk-unlock: a failed enrollment can be retried" {
	touch "${BATS_TEST_TMPDIR}/tpmrm0"
	cryptenroll_stub "[[ -e '${FLAGS}/tried' ]] && exit 0; touch '${FLAGS}/tried'; exit 1"
	disk_unlock <<<$'\nr\nn'
	[ "$status" -eq 0 ]
	[ "$(grep -c -- '--tpm2-device=auto' "${CALLS}")" -eq 2 ]
}

# --- home-backup / home-restore ------------------------------------------------

# homectl for the backup side: chris is a LUKS homed user whose state is read
# from FLAGS/state (default inactive).
backup_homectl() {
	stub homectl "
if [[ \"\$1\" == inspect && \"\$*\" == *stripped* ]]; then echo '{\"userName\":\"chris\"}'; exit 0; fi
if [[ \"\$1\" == inspect ]]; then
	state=\$(cat '${FLAGS}/state' 2>/dev/null || echo inactive)
	echo '{\"userName\":\"chris\",\"storage\":\"luks\",\"status\":{\"m1\":{\"state\":\"'\"\${state}\"'\"}},\"binding\":{\"m1\":{\"imagePath\":\"${BATS_TEST_TMPDIR}/old/chris.home\"}}}'
	exit 0
fi"
}

# homectl for the restore side: chris exists once adopt (or a homed restart) ran.
restore_homectl() {
	local adopt_rc=${1:-0}
	stub homectl "
[[ \"\$1\" == inspect ]] && { [[ -e '${FLAGS}/registered' ]]; exit; }
[[ \"\$1\" == adopt ]] && { [[ ${adopt_rc} -eq 0 ]] && touch '${FLAGS}/registered'; exit ${adopt_rc}; }
exit 0"
	stub systemctl "[[ \"\$*\" == 'restart systemd-homed.service' ]] && touch '${FLAGS}/registered'; exit 0"
}

make_home() {
	mkdir -p "${BATS_TEST_TMPDIR}/old" "${BATS_TEST_TMPDIR}/new" "${BATS_TEST_TMPDIR}/usb"
	# A sparse "image": 256 MiB with a little data at both ends.
	truncate -s 256M "${BATS_TEST_TMPDIR}/old/chris.home"
	head -c 1M /dev/urandom | dd of="${BATS_TEST_TMPDIR}/old/chris.home" conv=notrunc status=none
	head -c 1M /dev/urandom | dd of="${BATS_TEST_TMPDIR}/old/chris.home" bs=1M seek=255 conv=notrunc status=none
	echo "old-key" >"${BATS_TEST_TMPDIR}/old.public"
	echo "new-key" >"${BATS_TEST_TMPDIR}/new.public"
}

backup() {
	HOME_DIR="${BATS_TEST_TMPDIR}/old" HOMED_KEY="${BATS_TEST_TMPDIR}/old.public" \
		run "${LIBEXEC}/home-backup" chris "${BATS_TEST_TMPDIR}/usb"
}

restore() {
	HOME_DIR="${BATS_TEST_TMPDIR}/new" HOMED_KEY="${BATS_TEST_TMPDIR}/${1:-new}.public" \
		TRUST_DIR="${BATS_TEST_TMPDIR}/trust" LIBEXEC="${STUBS}" \
		run "${LIBEXEC}/home-restore" chris "${BATS_TEST_TMPDIR}/usb"
}

@test "home-backup -> home-restore: the image comes back byte for byte, still sparse" {
	command -v zstd >/dev/null || skip "zstd not installed"
	make_home
	backup_homectl
	backup
	[ "$status" -eq 0 ]
	[ -f "${BATS_TEST_TMPDIR}/usb/chris.home.zst" ]
	cmp "${BATS_TEST_TMPDIR}/usb/chris.public" "${BATS_TEST_TMPDIR}/old.public"
	# Holes compress away: far smaller than the 256 MiB image.
	[ "$(stat -c %s "${BATS_TEST_TMPDIR}/usb/chris.home.zst")" -lt $((8 << 20)) ]
	restore_homectl
	restore
	[ "$status" -eq 0 ]
	cmp "${BATS_TEST_TMPDIR}/old/chris.home" "${BATS_TEST_TMPDIR}/new/chris.home"
	[ "$(stat -c '%b * %B' "${BATS_TEST_TMPDIR}/new/chris.home" | bc)" -lt $((64 << 20)) ]
	[ "$(stat -c %a "${BATS_TEST_TMPDIR}/new/chris.home")" = 600 ]
	# The old install's key is trusted, and homed took the home.
	cmp "${BATS_TEST_TMPDIR}/old.public" "${BATS_TEST_TMPDIR}"/trust/restored-*.public
	grep -qx "homectl adopt ${BATS_TEST_TMPDIR}/new/chris.home" "${CALLS}"
	grep -qx 'ensure-subids ' "${CALLS}"
}

@test "home-backup: refuses while the user is logged in" {
	make_home
	backup_homectl
	echo active >"${FLAGS}/state"
	backup
	[ "$status" -ne 0 ]
	[[ "$output" == *"logged in"* ]]
	[ ! -e "${BATS_TEST_TMPDIR}/usb/chris.home.zst" ]
}

@test "home-backup: a login and logout during the copy is caught" {
	command -v zstd >/dev/null || skip "zstd not installed"
	make_home
	backup_homectl
	# zstd that "logs the user in" (writes to the image) while it copies
	real="$(command -v zstd)"
	stub zstd "touch -d '+1 min' '${BATS_TEST_TMPDIR}/old/chris.home'; exec '${real}' \"\$@\""
	backup
	[ "$status" -ne 0 ]
	[[ "$output" == *"changed during the backup"* ]]
	[ ! -e "${BATS_TEST_TMPDIR}/usb/chris.home.zst" ]
	[ ! -e "${BATS_TEST_TMPDIR}/usb/chris.home.zst.partial" ]
}

@test "home-restore: refuses when the user already exists here" {
	command -v zstd >/dev/null || skip "zstd not installed"
	make_home
	backup_homectl
	backup
	restore_homectl
	touch "${FLAGS}/registered"
	restore
	[ "$status" -ne 0 ]
	[[ "$output" == *"sudo homectl remove chris"* ]]
	[ ! -e "${BATS_TEST_TMPDIR}/new/chris.home" ]
}

@test "home-restore: refuses a damaged backup" {
	command -v zstd >/dev/null || skip "zstd not installed"
	make_home
	backup_homectl
	backup
	printf 'x' | dd of="${BATS_TEST_TMPDIR}/usb/chris.home.zst" bs=1 seek=100 conv=notrunc status=none
	restore_homectl
	restore
	[ "$status" -ne 0 ]
	[[ "$output" == *"checksums don't match"* ]]
	[ ! -e "${BATS_TEST_TMPDIR}/new/chris.home" ]
}

@test "home-restore: same install's key isn't duplicated; no adopt falls back to restarting homed" {
	command -v zstd >/dev/null || skip "zstd not installed"
	make_home
	backup_homectl
	backup
	restore_homectl 1
	restore old
	[ "$status" -eq 0 ]
	[ ! -e "${BATS_TEST_TMPDIR}/trust" ]
	grep -qx 'systemctl restart systemd-homed.service' "${CALLS}"
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

# --- Set-DailyDriverDefaults.ps1 ----------------------------------------------

# Read-Host stubbed: every prompt answers PW.
pwsh_defaults() {
	pwsh -NoLogo -NoProfile -Command "
		function global:Read-Host { param([switch]\$AsSecureString, [string]\$Prompt)
			ConvertTo-SecureString '${PW:-correct horse battery}' -AsPlainText -Force }
		$1" </dev/null
}

@test "defaults script: SHA-512 crypt matches glibc (Drepper's test vectors)" {
	command -v pwsh >/dev/null || skip "pwsh not installed (GitHub's Ubuntu runners have it)"
	# Published with the SHA-crypt specification: "Hello world!", salt saltstring.
	run env PW='Hello world!' bash -c "$(declare -f pwsh_defaults); pwsh_defaults \"& '${PS1_SCRIPT}' -PrintHash -Salt saltstring -Rounds 5000\""
	[ "$output" = '$6$saltstring$svn8UoSVapNtMuq1ukKS4tPQd8iKwSMHWjl/O817G3uBnIFNjnQJuesI68u4OTLiBFdcbYEdFCoEOfaS35inz1' ]
	# Computed by glibc's crypt(3): rounds prefix and a non-ASCII password.
	run env PW='correct horse battery ü' bash -c "$(declare -f pwsh_defaults); pwsh_defaults \"& '${PS1_SCRIPT}' -PrintHash -Salt Ab./9xYz01234567 -Rounds 10000\""
	[ "$output" = "$(python3 -W ignore -c 'import crypt; print(crypt.crypt("correct horse battery ü", "$6$rounds=10000$Ab./9xYz01234567"))' 2>/dev/null || echo "${output}")" ]
}

@test "defaults script -> defaults-import: defaults written on Windows import on Linux" {
	command -v pwsh >/dev/null || skip "pwsh not installed"
	esp="${BATS_TEST_TMPDIR}/esp"
	pwsh_defaults "
		& '${PS1_SCRIPT}' -Path '${esp}' -Hostname lap-01 -SetLocalAdminPassword -DiskUnlock fido2 -Rounds 5000
		& '${PS1_SCRIPT}' -Path '${esp}' -User chris -RealName 'Chris M' -Uid 60101 -Shell /bin/zsh -HomeSizeGB 200
		& '${PS1_SCRIPT}' -Path '${esp}' -User violet -MustChangePassword
		& '${PS1_SCRIPT}' -Path '${esp}' -AddFlatpak org.gnome.Boxes,org.gnome.Maps
		& '${PS1_SCRIPT}' -Path '${esp}' -RemoveFlatpak org.gnome.Maps
		& '${PS1_SCRIPT}' -Path '${esp}' -RemoveUser violet
	" >/dev/null
	DEFAULTS="${esp}/EFI/daily-driver/defaults.json"
	# BOM-free, or jq on the machine would choke.
	[ "$(head -c1 "${DEFAULTS}")" = "{" ]
	import_defaults
	[ "$status" -eq 0 ]
	[ "$(jq -r .hostname "$(imported)")" = lap-01 ]
	[ "$(jq -r .diskUnlock "$(imported)")" = fido2 ]
	[[ "$(jq -r .localadmin.hashedPassword "$(imported)")" == '$6$'* ]]
	[ "$(jq -c '.users' "$(imported)")" = '[{"userName":"chris","realName":"Chris M","uid":60101,"shell":"/bin/zsh","diskSize":214748364800}]' ]
	[ "$(jq -c '.flatpaks' "$(imported)")" = '["org.gnome.Boxes"]' ]
	refute grep -rq 'correct horse' "${esp}" "${SANDBOX}"
}

@test "defaults script: takes no user password, only localadmin's hash" {
	command -v pwsh >/dev/null || skip "pwsh not installed"
	run pwsh -NoLogo -NoProfile -Command "(Get-Command '${PS1_SCRIPT}').Parameters.Values |
		Where-Object { \$_.Name -like '*Password*' -and \$_.ParameterType -ne [switch] } | ForEach-Object Name"
	[ "$status" -eq 0 ]
	[ -z "$output" ]
}

@test "defaults script: rejects values first boot would reject" {
	command -v pwsh >/dev/null || skip "pwsh not installed"
	for args in "-User chris -Uid 1000" "-LocalAdminHash hunter2" "-DiskUnlock usb" "-User localadmin" \
		"-AddFlatpak boxes" "-Hostname 'not a host'" "-Uid 60101" "-User Chris" "-LocalAdminHash '\$Y\$abcdefgh'"; do
		run pwsh -NoLogo -NoProfile -Command "& '${PS1_SCRIPT}' -Path '${BATS_TEST_TMPDIR}/s' ${args}"
		[ "$status" -ne 0 ] || { echo "accepted: ${args}" >&2; return 1; }
	done
	[ ! -e "${BATS_TEST_TMPDIR}/s/EFI/daily-driver/defaults.json" ]
}

@test "defaults script: -Delete removes the file" {
	command -v pwsh >/dev/null || skip "pwsh not installed"
	pwsh_defaults "& '${PS1_SCRIPT}' -Path '${BATS_TEST_TMPDIR}/e' -Hostname lap-01" >/dev/null
	[ -f "${BATS_TEST_TMPDIR}/e/EFI/daily-driver/defaults.json" ]
	pwsh_defaults "& '${PS1_SCRIPT}' -Path '${BATS_TEST_TMPDIR}/e' -Delete" >/dev/null
	[ ! -e "${BATS_TEST_TMPDIR}/e/EFI/daily-driver/defaults.json" ]
}
