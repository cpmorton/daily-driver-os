#!/usr/bin/env bash

set -xeuo pipefail

###############################################################################
# Claude Code CLI
###############################################################################
# Installed from Anthropic's signed dnf repository, stable channel
# (code.claude.com/docs/en/setup). The Claude desktop app is Debian/Ubuntu-only
# today; chat, connectors and cloud sessions are on claude.ai.
#
# A package-managed install never auto-updates itself, so the CLI updates when
# the image does. build-image.yml rebuilds nightly for that reason.
#
# Machine-wide policy lives in custom/files/etc/claude-code/managed-settings.json.
###############################################################################

readonly KEY_URL=https://downloads.claude.ai/keys/claude-code.asc
readonly KEY_FPR=31DDDE24DDFAB679F42D7BD2BAA929FF1A7ECACE
readonly REPO_FILE=/etc/yum.repos.d/claude-code.repo

echo "::group:: Verify the signing key"

# dnf would stop and ask a human to confirm this fingerprint; CI can't answer,
# so check it here against the one Anthropic documents.
key="$(curl --fail --retry 3 --silent --show-error "${KEY_URL}")"
# Throwaway keyring: gpg creates its homedir on any call, and /root is a real
# image directory now, so a default ~/.gnupg would ship in the image.
GNUPGHOME="$(mktemp -d)"
export GNUPGHOME
fpr="$(gpg --show-keys --with-colons <<<"${key}" | awk -F: '/^fpr/ {print $10; exit}')"
rm -rf "${GNUPGHOME}"
unset GNUPGHOME
if [[ "${fpr}" != "${KEY_FPR}" ]]; then
	echo "::error::claude-code signing key fingerprint mismatch: got '${fpr}'" >&2
	exit 1
fi
keyfile="$(mktemp)"
printf '%s\n' "${key}" >"${keyfile}"
rpm --import "${keyfile}"
rm -f "${keyfile}"

echo "::endgroup::"

echo "::group:: Install claude-code"

cat >"${REPO_FILE}" <<EOF
[claude-code]
name=Claude Code
baseurl=https://downloads.claude.ai/claude-code/rpm/stable
enabled=1
gpgcheck=1
gpgkey=${KEY_URL}
EOF

dnf5 install -y claude-code

# Same convention as every other third-party repository in this image.
sed -i 's/^enabled=1$/enabled=0/' "${REPO_FILE}"

echo "::endgroup::"

echo "::group:: Assertions"

# Not `claude --version`: /root is a real image directory now, and anything
# the CLI writes to its home during the build would ship in the image.
command -v claude
rpm -q claude-code
# The managed policy must parse, or Claude Code refuses to start at all.
python3 -c 'import json, sys; json.load(open(sys.argv[1]))' \
	/etc/claude-code/managed-settings.json

echo "::endgroup::"

echo "::group:: Ship /root empty"

# /root became a real, image-owned directory in 70-daily-driver.sh. Tools run
# as root during the build (gpg, dnf, rpm) may leave dotfiles there, and they
# would ship to every machine. Nothing in this image puts files in /root on
# purpose, so remove whatever landed and say what it was.
find /root -mindepth 1 -maxdepth 1 -print -exec rm -rf {} +

echo "::endgroup::"
