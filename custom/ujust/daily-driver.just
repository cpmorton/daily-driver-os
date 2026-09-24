# vim: set ft=make :
#########################
### daily-driver.just
#########################
## Machine and account setup for this image. Run as localadmin unless a
## recipe says otherwise. Nothing here runs automatically.

# Create an encrypted (LUKS) systemd-homed user with rootless-podman subids.
[group('Daily driver')]
homed-user user size="100G":
    #!/usr/bin/env bash
    set -euo pipefail

    # Idempotent: an existing user only gets its subordinate IDs checked.
    if homectl inspect "{{ user }}" >/dev/null 2>&1; then
        echo "{{ user }} already exists; checking its subordinate IDs only."
    else
        # Explicit size, so several homed users don't race for the free space.
        sudo homectl create "{{ user }}" --storage=luks --disk-size="{{ size }}"
    fi
    sudo /usr/libexec/daily-driver/ensure-subids "{{ user }}"
    echo "Done. {{ user }} can sign in at the login screen."

# Hand the Homebrew prefix and its update timers to one user (default: localadmin).
[group('Daily driver')]
brew-owner user:
    #!/usr/bin/env bash
    set -euo pipefail

    # ublue-os/brew hands /home/linuxbrew to UID 1000: localadmin here. Homebrew
    # has one owner; to let a daily (homed, UID 60001+) user brew install, give
    # it to them.
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

# Re-detect Windows and rewrite its boot menu entry (dual-boot machines).
[group('Daily driver')]
windows-entry:
    #!/usr/bin/env bash
    set -euo pipefail
    sudo rm -f /var/lib/daily-driver/windows-entry-checked
    if [[ -e /boot/grub2/custom.cfg ]]; then
        echo "/boot/grub2/custom.cfg exists. Delete it first to regenerate:"
        echo "  sudo unshare -m sh -c 'mount -o remount,rw /boot && rm /boot/grub2/custom.cfg'"
        exit 1
    fi
    sudo /usr/libexec/daily-driver/windows-boot-entry

# Print localadmin's password hash, for the secret store that seeds new machines.
[group('Daily driver')]
localadmin-hash:
    #!/usr/bin/env bash
    set -euo pipefail
    # The hash is what the seed stick carries (never the password). Store it in
    # your password manager; New-DailyDriverSeed.ps1 -LocalAdminHash takes it.
    sudo getent shadow localadmin | cut -d: -f2
