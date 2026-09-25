#!/usr/bin/env bash

set -xeuo pipefail

###############################################################################
# Daily-driver phase
###############################################################################
# Runs after 20-packages-and-services.sh and before 90-cleanup.sh. The files it
# configures (units, sysusers.d, sshd and pam_access drop-ins, journald policy)
# already landed from custom/files via 10-overlay.sh; this phase installs
# packages and flips switches.
#
#   1. /opt, /usr/local, /root become real, image-owned directories
#   2. Chrome, VS Code, gh, chezmoi, systemd-homed, and the Docker-compatible
#      front end to rootless podman (podman-docker, podman-compose)
#   3. root locked; first boot on tty1: hostname, localadmin's password,
#      disk unlock and daily users, offering the machine defaults (EFI partition)
#   4. PAM: homed + pam_access (localadmin: local logins only)
#   5. rootful podman off, rootless per-user socket on
#   6. initramfs rebuilt with TPM2 and FIDO2 unlock for the encrypted root
#   7. assertions: fail the build rather than ship a missing control
#
# Nothing secret belongs here: the repository and the image are public.
###############################################################################

shopt -s nullglob

readonly ADMIN=localadmin # identity: custom/files/usr/lib/sysusers.d/50-localadmin.conf

echo "::group:: Real /opt, /usr/local and /root"

# The Silverblue base ships these as symlinks into /var. Under composefs a real
# directory is read-only at runtime and versioned with the image, which is the
# point. It must happen before any package unpacks into /opt (Chrome does),
# and before 90-cleanup.sh prunes /var.
for dir in /opt /usr/local /root; do
	if [[ -L "${dir}" ]]; then
		echo "replacing symlink ${dir} -> $(readlink "${dir}")"
		rm "${dir}"
	fi
	mkdir -p "${dir}"
done
chmod 0700 /root
chmod 0755 /opt /usr/local
# FHS skeleton, so nothing trips over a missing /usr/local/bin on PATH.
mkdir -p /usr/local/{bin,etc,include,lib,lib64,libexec,sbin,share,src}

echo "::endgroup::"

echo "::group:: Third-party repositories"

# VS Code: repository definition from code.visualstudio.com/docs/setup/linux.
rpm --import https://packages.microsoft.com/keys/microsoft.asc
cat >/etc/yum.repos.d/vscode.repo <<'EOF'
[code]
name=Visual Studio Code
baseurl=https://packages.microsoft.com/yumrepos/vscode
enabled=1
autorefresh=1
type=rpm-md
gpgcheck=1
gpgkey=https://packages.microsoft.com/keys/microsoft.asc
EOF

# Chrome: Fedora ships this repository (disabled) with its signing key in
# fedora-workstation-repositories.
dnf5 install -y fedora-workstation-repositories
dnf5 config-manager setopt google-chrome.enabled=1

echo "::endgroup::"

echo "::group:: Packages"

# gh and chezmoi come from Fedora rather than Homebrew: the brew prefix has a
# single owner (see `ujust brew-owner`), and bootstrap tools must work for
# every account on the first login.
# /usr/bin/homectl is a file provide, so dnf picks whichever subpackage ships
# systemd-homed on this release instead of this script hardcoding the split.
# podman-docker: /usr/bin/docker runs podman, so tools that hardcode `docker`
# (VS Code Dev Containers by default) use rootless podman with no per-user
# settings. See docs/decisions/0006-rootless-podman-only.md.
# tpm2-tools and libfido2: dracut adds TPM2 and FIDO2 unlock to the initramfs
# only when these are present (docs/decisions/0021-encrypted-root.md).
# zstd: `ujust backup-home` compresses home images with it.
dnf5 install -y \
	google-chrome-stable \
	code \
	podman-docker \
	podman-compose \
	gh \
	chezmoi \
	/usr/bin/homectl \
	tpm2-tools \
	libfido2 \
	zstd

# docker-compose -> podman-compose: the Dev Containers extension's default
# compose command. It lives in /usr/local/bin because /usr/local only became a
# real, image-owned directory at the top of this phase; custom/files runs
# earlier and can't place files there.
ln -sfn /usr/bin/podman-compose /usr/local/bin/docker-compose

echo "::endgroup::"

echo "::group:: Accounts"

# Root: locked password, the same state the Fedora installer's "lock root"
# option produces. The shell stays, so `sudo -i` and emergency sulogin work.
passwd -l root

# localadmin: sysusers.d creates it (UID 1000), locked, at boot. First boot
# sets its password from the machine defaults' hash (written to the EFI
# partition from Windows) or asks on tty1, so no hash ever enters the image.
# Daily users' passwords are always typed on tty1.
# See docs/decisions/0020-machine-defaults-on-the-esp.md.
chmod 0755 /usr/libexec/daily-driver/*
systemctl enable localadmin-home.service
systemctl enable daily-driver-defaults.service
systemctl enable daily-driver-firstboot.service
# Superseded by daily-driver-firstboot.service, which works when localadmin
# already exists (upstream's wizard skips then).
systemctl mask systemd-homed-firstboot.service

echo "::endgroup::"

echo "::group:: PAM"

# authselect owns /etc/pam.d on Fedora; never hand-edit it. Re-select the
# current profile with its current features plus ours, so whatever the base
# enabled (fingerprint, mdns, ...) survives.
if current="$(authselect current --raw 2>/dev/null)"; then
	read -r profile features <<<"${current}"
else
	profile=local
	features=""
fi
# shellcheck disable=SC2086 # features is a word list by design
authselect select "${profile}" ${features} with-systemd-homed with-pamaccess --force
authselect current

# The localadmin rule ships as /etc/security/access.d/50-localadmin.conf.
# LOCAL means PAM_RHOST is unset: console, GDM, su, sudo, polkit. sshd sets it.

echo "::endgroup::"

echo "::group:: Services"

# 10-overlay.sh enables the *system* podman.socket, which is the rootful API.
# This image is rootless-only: turn it off and give every user their own.
systemctl disable podman.socket
systemctl mask \
	podman.socket \
	podman.service \
	podman-restart.service \
	podman-auto-update.service \
	podman-auto-update.timer
systemctl --global enable podman.socket
systemctl --global enable vscode-devcontainers-ext.service

systemctl enable systemd-homed.service

# Dual boot: add Windows to bootc's static GRUB menu.
systemctl enable windows-boot-entry.service

# No root shell on tty9 via a kernel argument.
systemctl mask debug-shell.service
# GNOME "Remote Login" (system RDP) authenticates through GDM's PAM stack.
# Until it is proven to set PAM_RHOST, it could bypass the localadmin rule.
systemctl mask gnome-remote-desktop.service

echo "::endgroup::"

echo "::group:: Initramfs: TPM2 and FIDO2 unlock"

# The base image's initramfs was built without tpm2-tools, so it can't unlock
# the root with a TPM. Rebuild it now that the packages above are installed,
# with the modules 50-daily-driver-unlock.conf adds. --no-hostonly and
# --add ostree match how the base image built it; a missing ostree module
# would make the image unbootable, so the assertions below check for it.
# See docs/decisions/0021-encrypted-root.md.
mapfile -t kernels < <(find /usr/lib/modules -mindepth 1 -maxdepth 1 -type d -printf '%f\n')
if [[ "${#kernels[@]}" -ne 1 ]]; then
	echo "expected exactly one kernel in /usr/lib/modules, found: ${kernels[*]}" >&2
	exit 1
fi
INITRAMFS="/usr/lib/modules/${kernels[0]}/initramfs.img"
DRACUT_NO_XATTR=1 dracut --no-hostonly --reproducible --add ostree --tmpdir /tmp \
	--force --kver "${kernels[0]}" "${INITRAMFS}"

echo "::endgroup::"

echo "::group:: Provenance manifest"

# Which overlay put each non-RPM file in the image, for `ujust provenance`.
# Same order as 10-overlay.sh, so a later source wins: common/shared, then
# ublue-os/brew, then this repository's custom/files. RPM-owned files are
# answered at runtime by `rpm -qf` instead.
readonly MANIFEST=/usr/share/daily-driver-os/provenance.tsv
mkdir -p "$(dirname "${MANIFEST}")"
{
	for source in \
		"projectbluefin/common shared/=/ctx/oci/common/shared" \
		"ublue-os/brew=/ctx/oci/brew" \
		"this repository, custom/files/=/ctx/custom/files"; do
		label="${source%%=*}"
		root="${source#*=}"
		(cd "${root}" && find . -mindepth 1 ! -type d ! -path ./README.md -printf '/%P\n') |
			sed "s|\$|\t${label}|"
	done
	printf '%s\t%s\n' /usr/local/bin/docker-compose "this repository, build/70-daily-driver.sh"
} | awk -F'\t' '{ last[$1] = $2 } END { for (p in last) print p "\t" last[p] }' |
	LC_ALL=C sort >"${MANIFEST}"

echo "::endgroup::"

echo "::group:: Finalise repositories"

# Upstream convention: disable every repository this phase enabled. The image
# already carries the packages; a booted bootc host does not dnf install.
dnf5 config-manager setopt google-chrome.enabled=0 code.enabled=0

echo "::endgroup::"

echo "::group:: Assertions"

# Fail the build loudly rather than ship an image missing a control.
for dir in /opt /usr/local /root; do
	[[ -d "${dir}" && ! -L "${dir}" ]]
done
test -e /usr/bin/google-chrome-stable
test -d /opt/google/chrome
for bin in code gh chezmoi homectl podman-compose; do
	command -v "${bin}"
done
# Docker front end: the shim runs podman, compose resolves, the environment
# points at the per-user socket, and nothing points at a rootful one.
grep -q 'exec /usr/bin/podman' /usr/bin/docker
[[ "$(readlink -f /usr/local/bin/docker-compose)" == /usr/bin/podman-compose ]]
# shellcheck disable=SC2016 # matching the literal ${XDG_RUNTIME_DIR} in the file
grep -qF 'DOCKER_HOST=unix://${XDG_RUNTIME_DIR}/podman/podman.sock' \
	/usr/lib/environment.d/60-docker-host.conf
# An empty file, not a /dev/null link: bootc's var-tmpfiles lint cannot follow
# an absolute symlink out of the image root. systemd treats both as a mask.
[[ -f /etc/tmpfiles.d/podman-docker.conf && ! -L /etc/tmpfiles.d/podman-docker.conf ]]
[[ ! -s /etc/tmpfiles.d/podman-docker.conf ]]
if grep -qF /run/docker.sock <<<"$(systemd-tmpfiles --cat-config)"; then
	echo "the system /run/docker.sock entry is not masked" >&2
	exit 1
fi
git config --system --get init.defaultBranch
# Provenance manifest: covers this repository's files and upstream's overlays.
grep -qP '^/etc/gitconfig\tthis repository' "${MANIFEST}"
grep -qP '^/usr/lib/systemd/system/brew-setup.service\tublue-os/brew$' "${MANIFEST}"
test -x /usr/sbin/mkhomedir_helper
for helper in defaults-import disk-unlock ensure-subids firstboot first-users home-backup \
	home-restore localadmin-needs-password windows-boot-entry; do
	test -x "/usr/libexec/daily-driver/${helper}"
done
# localadmin is UID 1000, which is what ublue-os/brew hands the prefix to.
grep -qE '^u[[:space:]]+localadmin[[:space:]]+1000[[:space:]]' /usr/lib/sysusers.d/50-localadmin.conf

# PAM wiring, on both stacks: system-auth (console, GDM, sudo) and
# password-auth (sshd).
for stack in system-auth password-auth; do
	grep -q pam_systemd_home.so "/etc/pam.d/${stack}"
	grep -q pam_access.so "/etc/pam.d/${stack}"
done
# The access.d drop-in only works if this pam_access reads access.d.
grep -q 'access\.d' "$(find /usr/lib64/security /usr/lib/security -name pam_access.so -print -quit 2>/dev/null)"
grep -qxF -- "-:${ADMIN}:ALL EXCEPT LOCAL" /etc/security/access.d/50-localadmin.conf
# sudo on Linux leaves PAM_RHOST unset (pam_rhost defaults on only for
# Solaris). If sudoers ever turns it on, LOCAL stops matching and localadmin
# loses sudo, which is the only reason the account exists.
if grep -rqsE '^[[:space:]]*Defaults.*\bpam_rhost\b' /etc/sudoers /etc/sudoers.d; then
	echo "::error::sudoers enables pam_rhost; localadmin would be denied sudo" >&2
	exit 1
fi
# sysusers' `m localadmin wheel` needs wheel in /etc/group, not only altfiles.
grep -q '^wheel:' /etc/group

# Root locked. shadow-utils prints "L", older passwd printed "LK".
passwd -S root | grep -Eq '^root (L|LK) '

# sshd drop-in: tracked by git as 0644, sshd wants it private like Fedora's own.
chmod 0600 /etc/ssh/sshd_config.d/10-hardening.conf
grep -qx 'PermitRootLogin no' /etc/ssh/sshd_config.d/10-hardening.conf

# /tmp is tmpfs: Fedora wires tmp.mount into local-fs.target. Assert it.
test -e /usr/lib/systemd/system/local-fs.target.wants/tmp.mount

# The rebuilt initramfs can boot this image and unlock its root by TPM2 or a
# security key, and a passphrase is always the fallback.
initramfs_files="$(lsinitrd "${INITRAMFS}")"
for needed in ostree-prepare-root systemd-cryptsetup \
	libcryptsetup-token-systemd-tpm2.so libcryptsetup-token-systemd-fido2.so; do
	grep -qF "${needed}" <<<"${initramfs_files}" || {
		echo "initramfs lacks ${needed}" >&2
		exit 1
	}
done

# Rootful podman is really off.
[[ "$(systemctl is-enabled podman.socket 2>/dev/null || true)" == masked ]]

echo "::endgroup::"

shopt -u nullglob

echo "Daily-driver phase complete!"
