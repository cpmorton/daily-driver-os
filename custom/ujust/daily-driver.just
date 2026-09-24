# vim: set ft=make :
#########################
### daily-driver.just
#########################
## Machine and account setup for this image. Run as localadmin unless a
## recipe says otherwise. Nothing here runs automatically.

# Move /var/home onto an already-formatted partition (never formats anything).
[group('Daily driver')]
home-partition device:
    #!/usr/bin/env bash
    set -euo pipefail

    # The partition must already carry a filesystem. Formatting is left to you
    # on purpose: the internal disk also holds Windows.
    DEVICE="{{ device }}"
    if grep -qE '^[^#]*[[:space:]]/var/home[[:space:]]' /etc/fstab; then
        echo "/etc/fstab already mounts /var/home; nothing to do." >&2
        exit 1
    fi
    if findmnt --source "${DEVICE}" >/dev/null; then
        echo "${DEVICE} is mounted; unmount it first." >&2
        exit 1
    fi
    UUID="$(sudo blkid -s UUID -o value "${DEVICE}")"
    FSTYPE="$(sudo blkid -s TYPE -o value "${DEVICE}")"
    if [[ -z "${UUID}" || -z "${FSTYPE}" ]]; then
        echo "${DEVICE} has no filesystem. Create one first, e.g. sudo mkfs.btrfs -L home ${DEVICE}" >&2
        exit 1
    fi
    echo "Will copy /var/home onto ${DEVICE} (${FSTYPE}, UUID=${UUID}) and mount it there from the next boot."
    if command -v gum >/dev/null 2>&1; then
        gum confirm "Continue?" || exit 0
    fi

    STAGE="$(mktemp -d)"
    sudo mount "${DEVICE}" "${STAGE}"
    trap 'sudo umount "${STAGE}" && rmdir "${STAGE}"' EXIT
    # -X keeps SELinux labels; the mount point itself takes /var/home's label.
    sudo rsync -aHAX /var/home/ "${STAGE}/"
    sudo chcon --reference=/var/home "${STAGE}"
    # nofail: the stick still boots on a machine without this partition, and
    # localadmin can still log in on the console there.
    echo "UUID=${UUID} /var/home ${FSTYPE} defaults,nofail,x-systemd.device-timeout=10s 0 0" |
        sudo tee -a /etc/fstab >/dev/null
    echo "Done. Reboot, then check: findmnt /var/home"

# Create an encrypted (LUKS) systemd-homed user with rootless-podman subids.
[group('Daily driver')]
homed-user user size="100G":
    #!/usr/bin/env bash
    set -euo pipefail

    # Home images belong on the internal partition, not the OS stick.
    if ! mountpoint -q /var/home && [[ "${ALLOW_HOME_ON_ROOT:-0}" != 1 ]]; then
        echo "/var/home is not a separate mount. Run 'ujust home-partition <device>' first," >&2
        echo "or set ALLOW_HOME_ON_ROOT=1 to put the home image on the OS disk." >&2
        exit 1
    fi
    # Idempotent: after a reinstall the home already exists on the partition,
    # but /etc/subuid and /etc/subgid are new and need its entries again.
    if homectl inspect "{{ user }}" >/dev/null 2>&1; then
        echo "{{ user }} already exists; checking its subordinate IDs only."
    else
        # Explicit size, so several homed users don't race for one partition.
        sudo homectl create "{{ user }}" --storage=luks --disk-size="{{ size }}"
    fi

    # homed users never pass through useradd, so nothing allocates their
    # subordinate IDs, and rootless podman needs them. Take the next 65536 block
    # above the highest range already allocated (floor 100000).
    for file in /etc/subuid /etc/subgid; do
        if ! grep -q "^{{ user }}:" "${file}"; then
            start="$(awk -F: 'BEGIN {m = 100000} {e = $2 + $3; if (e > m) m = e} END {print m}' "${file}")"
            echo "{{ user }}:${start}:65536" | sudo tee -a "${file}" >/dev/null
        fi
    done
    echo "Created {{ user }}. Next: ujust brew-owner {{ user }} (once), then sign in as {{ user }}."

# Hand the Homebrew prefix and its update timers to one user.
[group('Daily driver')]
brew-owner user:
    #!/usr/bin/env bash
    set -euo pipefail

    # ublue-os/brew hands /home/linuxbrew to UID 1000, which never exists here:
    # localadmin is 1999 and homed users are 60001+. Homebrew has one owner.
    id "{{ user }}" >/dev/null
    if [[ ! -d /home/linuxbrew/.linuxbrew ]]; then
        echo "Homebrew is not set up yet: systemctl status brew-setup.service" >&2
        exit 1
    fi
    sudo chown -R "{{ user }}:" /home/linuxbrew
    # The timers run while the owner's LUKS home may be locked, so give them a
    # HOME of their own that systemd creates and chowns to the same user.
    for unit in brew-update brew-upgrade; do
        sudo install -d -m 0755 "/etc/systemd/system/${unit}.service.d"
        printf '[Service]\nUser=%s\nStateDirectory=brew-owner\nEnvironment=HOME=/var/lib/brew-owner\n' "{{ user }}" |
            sudo tee "/etc/systemd/system/${unit}.service.d/50-owner.conf" >/dev/null
    done
    sudo systemctl daemon-reload
    echo "Homebrew now belongs to {{ user }}."

# Apply your dotfiles repository (chezmoi) to the current user's home.
[group('Daily driver')]
dotfiles github_user:
    #!/usr/bin/env bash
    set -euo pipefail

    # Run as the daily user, not localadmin. Defaults to <user>/dotfiles on GitHub.
    chezmoi init --apply "{{ github_user }}"
    echo "Applied. Later: chezmoi update"

# List /etc files that have drifted from the image; the image no longer manages them.
[group('Daily driver')]
etc-drift:
    sudo ostree admin config-diff

# Explain where a file came from: an RPM, an overlay, a build step, or this machine.
[group('Daily driver')]
provenance path:
    #!/usr/bin/env bash
    set -euo pipefail

    MANIFEST="${PROVENANCE_MANIFEST:-/usr/share/daily-driver-os/provenance.tsv}"
    # -s keeps a symlink as itself; -m allows paths that don't exist (yet).
    p="$(realpath -ms -- "{{ path }}")"
    echo "${p}"
    [[ -e "${p}" || -L "${p}" ]] || echo "  does not exist on this machine"

    # rpm prints "not owned by any package" on stdout, so keep output only on success.
    owner=""
    if out="$(rpm -qf --qf '%{NAME}-%{VERSION}-%{RELEASE} (vendor: %{VENDOR})\n' -- "${p}" 2>/dev/null)"; then
        owner="${out}"
        echo "  RPM package: ${owner}"
    fi
    overlay="$(awk -F'\t' -v p="${p}" '$1 == p { print $2 }' "${MANIFEST}" 2>/dev/null || true)"
    if [[ -n "${overlay}" ]]; then
        echo "  overlaid at build time by: ${overlay}"
    fi

    case "${p}" in
    /etc/*)
        default="/usr/etc/${p#/etc/}"
        if [[ ! -e "${default}" && ! -L "${default}" ]]; then
            echo "  /etc: not in the image; created on this machine"
        elif ! cmp -s -- "${p}" "${default}" 2>/dev/null; then
            if [[ -r "${p}" && -r "${default}" ]]; then
                echo "  /etc: DIFFERS from the image default: edited locally, so updates no longer change it"
            else
                echo "  /etc: can't read it; re-run with sudo to compare against the image default"
            fi
        else
            echo "  /etc: matches the image default"
        fi
        ;;
    /var/* | /home/*)
        echo "  machine-local state: never part of the image, kept across updates"
        ;;
    esac

    if [[ (-e "${p}" || -L "${p}") && -z "${owner}" && -z "${overlay}" &&
        "${p}" != /etc/* && "${p}" != /var/* && "${p}" != /home/* ]]; then
        echo "  no package or overlay claims it: made by a build step or a package scriptlet"
    fi
    echo "  details: docs/PROVENANCE.md in the image's repository"
