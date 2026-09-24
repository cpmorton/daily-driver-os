#!/usr/bin/env bats
# Contract: the properties this image promises that a careless edit could
# silently undo. Static checks against the repository; the build phases assert
# the same things again against the real image.
#
# Run with: bats tests/contract/daily-driver_test.bats

REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
CONTAINERFILE="${REPO_ROOT}/Containerfile"
PHASE="${REPO_ROOT}/build/70-daily-driver.sh"
FILES="${REPO_ROOT}/custom/files"

# Line number of the first line matching a fixed string, or empty.
line_of() {
	grep -nF -- "$2" "$1" | head -n1 | cut -d: -f1
}

@test "Containerfile: upstream's /opt -> /var/opt symlink step is gone" {
	# Its rm -rf /opt would delete Chrome from the image.
	run grep -E '^RUN .*ln -s /var/opt /opt' "${CONTAINERFILE}"
	[ "$status" -ne 0 ]
}

@test "Containerfile: daily-driver phases run after packages and before cleanup" {
	packages="$(line_of "${CONTAINERFILE}" '/ctx/build/20-packages-and-services.sh')"
	daily="$(line_of "${CONTAINERFILE}" '/ctx/build/70-daily-driver.sh')"
	claude="$(line_of "${CONTAINERFILE}" '/ctx/build/75-claude.sh')"
	cleanup="$(line_of "${CONTAINERFILE}" '/ctx/build/90-cleanup.sh')"
	[ -n "${packages}" ] && [ -n "${daily}" ] && [ -n "${claude}" ] && [ -n "${cleanup}" ]
	[ "${packages}" -lt "${daily}" ]
	[ "${daily}" -lt "${claude}" ]
	[ "${claude}" -lt "${cleanup}" ]
}

@test "70-daily-driver: /opt becomes real before Chrome is installed" {
	real="$(line_of "${PHASE}" 'for dir in /opt /usr/local /root; do')"
	chrome="$(line_of "${PHASE}" 'google-chrome-stable \')"
	[ -n "${real}" ] && [ -n "${chrome}" ]
	[ "${real}" -lt "${chrome}" ]
}

@test "70-daily-driver: rootful podman is disabled and masked" {
	grep -qx 'systemctl disable podman.socket' "${PHASE}"
	grep -qE '^systemctl mask \\$' "${PHASE}"
	grep -qE '^[[:space:]]+podman\.socket \\$' "${PHASE}"
	grep -qx 'systemctl --global enable podman.socket' "${PHASE}"
}

@test "70-daily-driver: root is locked" {
	grep -qx 'passwd -l root' "${PHASE}"
}

@test "localadmin: UID avoids the installer's first user and homed's range" {
	uid="$(awk '$1 == "u" && $2 == "localadmin" {print $3}' "${FILES}/usr/lib/sysusers.d/50-localadmin.conf")"
	[ -n "${uid}" ]
	[ "${uid}" -ne 1000 ]
	[ "${uid}" -lt 60001 ] || [ "${uid}" -gt 60513 ]
	grep -qE '^m[[:space:]]+localadmin[[:space:]]+wheel$' "${FILES}/usr/lib/sysusers.d/50-localadmin.conf"
}

@test "localadmin: pam_access allows local logins only" {
	grep -qx -- '-:localadmin:ALL EXCEPT LOCAL' "${FILES}/etc/security/access.d/50-localadmin.conf"
}

@test "sshd: no root, no localadmin" {
	grep -qx 'PermitRootLogin no' "${FILES}/etc/ssh/sshd_config.d/10-hardening.conf"
	grep -qx 'DenyUsers localadmin' "${FILES}/etc/ssh/sshd_config.d/10-hardening.conf"
}

@test "journald: journal is volatile" {
	grep -qx 'Storage=volatile' "${FILES}/usr/lib/systemd/journald.conf.d/60-volatile.conf"
}

@test "claude-code: managed settings are valid JSON" {
	# Claude Code refuses to start when a managed settings file does not parse.
	python3 -c 'import json, sys; json.load(open(sys.argv[1]))' \
		"${FILES}/etc/claude-code/managed-settings.json"
}

@test "public repo: no password hashes anywhere in the image inputs" {
	# crypt(3) prefixes: yescrypt, sha512, sha256, bcrypt, md5.
	run grep -rIEn '\$(y|6|5|2[aby]|1)\$[./A-Za-z0-9]{8,}' \
		"${REPO_ROOT}/build" "${REPO_ROOT}/custom" "${REPO_ROOT}/iso" "${CONTAINERFILE}"
	[ "$status" -ne 0 ]
}

@test "ujust: recipe names are unique across custom/ujust" {
	# 10-overlay.sh concatenates every file into one 60-custom.just, where a
	# duplicate name is a parse error for every ujust command.
	dupes="$(find "${REPO_ROOT}/custom/ujust" -name '*.just' -exec \
		grep -hoE '^[a-z][a-z0-9_-]*' {} + | sort | uniq -d)"
	[ -z "${dupes}" ]
}

@test "custom/files: nothing targets /opt, /usr/local or /root" {
	# 10-overlay.sh copies custom/files while these are still symlinks into
	# /var; 70-daily-driver.sh then replaces them with empty directories and
	# 90-cleanup.sh prunes /var, so such files would silently vanish.
	[ ! -e "${FILES}/opt" ]
	[ ! -e "${FILES}/usr/local" ]
	[ ! -e "${FILES}/root" ]
}
