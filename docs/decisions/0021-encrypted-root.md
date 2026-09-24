# 0021. The Linux root is encrypted; it unlocks by TPM2, security key or passphrase

- **Status:** Accepted
- **Date:** 2026-09-23
- **Amends:** [0017](0017-dual-boot-internal-disk.md) (what goes in the
  free space), [0010](0010-var-journal-tmp.md) (swap)

## Context

Daily users' homes were already LUKS images, but the rest of the Linux
partition was not: localadmin's home, saved Wi-Fi passwords, homed's signing
key, `/etc` and all of `/var` sat in the clear. The administrator wants
encrypted filesystems, and a choice per machine of how the disk unlocks.

## Decision

- **Encrypt the root in the installer:** tick *Encrypt my data* under
  Installation Destination. Anaconda makes a LUKS2 volume with the passphrase
  typed there. The kickstart can't pre-select it without taking over
  partitioning, which stays manual beside Windows.
- **Choose the unlock method at first boot**, defaulting to the machine
  defaults' `diskUnlock` ([0020](0020-machine-defaults-on-the-esp.md)), or
  later with `ujust disk-unlock`:
  - `tpm2`: the TPM unlocks it with no typing. Enrolled with
    `systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=7`: PCR 7 measures the
    Secure Boot state, so kernel and bootc updates don't break it.
  - `tpm2-pin`: the TPM plus a PIN at every boot.
  - `fido2`: a security key (YubiKey), touched at every boot; a spare can be
    enrolled.
  - `passphrase`: the installer's passphrase at every boot.
  The installer passphrase always stays as a fallback, and first boot offers a
  recovery key (text and QR code) for the password manager. A new choice
  replaces the old one: enrolling wipes earlier TPM and FIDO2 slots
  (`--wipe-slot=tpm2,fido2`, which never removes the slot just added),
  choosing `passphrase` wipes them outright, and a new recovery key replaces
  the old one.
- **No kernel arguments or crypttab edits.** When no key file is configured,
  `systemd-cryptsetup` tries every LUKS2 token through libcryptsetup's token
  plugins before asking for a passphrase, so enrolling is all it takes.
- **The image rebuilds its initramfs.** dracut adds TPM2 and FIDO2 support only
  on request, and TPM2 only when `tpm2-tools` is installed; the base image's
  initramfs has neither. `build/70-daily-driver.sh` installs `tpm2-tools` and
  `libfido2`, adds both modules
  (`/usr/lib/dracut/dracut.conf.d/50-daily-driver-unlock.conf`), regenerates
  the initramfs with `--no-hostonly --add ostree`, and fails the build unless
  the result contains ostree's `ostree-prepare-root`, `systemd-cryptsetup` and
  both token plugins.
- **Swap stays Fedora's zram**: compressed RAM, sized to RAM up to 8 GiB,
  never written to disk, so there is no swap key to protect or rotate. `/tmp`
  is tmpfs (half of RAM), and its pages swap to zram under pressure.

## Alternatives

- **Unencrypted root, encrypted homes only:** leaves localadmin's home, Wi-Fi
  secrets and homed's signing key readable from the disk.
- **Encrypted disk swap with a new random key every boot:** needs a partition
  of its own, found by label (a wrong reference on a dual-boot disk wipes
  Windows). A swap *file* would need dm-crypt over a loop device, which can
  deadlock under memory pressure. zram gives the same at-rest guarantee.
- **Signed PCR policies (`systemd-pcrlock`, PCR 11):** survive firmware
  updates too, but need a signed UKI boot chain that bootc on Fedora doesn't
  ship yet.
- **`systemd-cryptenroll --firstboot`:** newer systemd has its own wizard, but
  it offers passphrases, recovery keys and FIDO2, not TPM2.
- **`rpm-ostree initramfs --enable` on each machine:** local state that
  `bootc upgrade` refuses to carry; the image does it once for every machine.

## Consequences

- PCR 7 changes when the Secure Boot databases change: firmware updates, and
  Microsoft's current rollover from its 2011 Secure Boot certificates. The
  TPM then refuses, the passphrase prompt appears, and `ujust disk-unlock`
  re-enrolls. Keep the passphrase or the recovery key reachable.
- With `tpm2`, a stolen laptop boots to the login screen without a disk
  secret; the users' homes still need their own passwords. Worse, PCR 7
  doesn't cover the kernel command line, so editing the GRUB entry (`e`) to
  boot `emergency.target` still unlocks the disk and gives a root shell
  (root is locked, but `SYSTEMD_SULOGIN_FORCE` skips that): localadmin's
  home, Wi-Fi secrets and the system are exposed, though not the users'
  homes. `tpm2-pin` or `fido2` close this at the cost of a PIN or a touch at
  boot; a GRUB password would too, but isn't built yet.
- A lost security key: unlock with the passphrase or recovery key, then enroll
  a new one (`ujust disk-unlock fido2`).
- Rebuilding the initramfs in the image is the riskiest line in the build:
  the assertions catch a missing module, but only a real boot proves it.

## Verification

Source read: systemd's `src/cryptsetup/cryptsetup.c` (token plugins tried when
no key file is set), `man/crypttab.xml`, `man/systemd-cryptenroll.xml`
(every option used); dracut-ng's `71systemd-cryptsetup`, `73tpm2-tss` and
`73fido2` modules (opt-in, `tpm2` binary required); Fedora's zram default
(Changes/Scale_ZRAM_to_full_memory_size); systemd's `units/tmp.mount`.
`tests/contract/daily-driver-helpers_test.bats` covers every method's
`systemd-cryptenroll` call, TPM absence, retries and the unencrypted-root
warning. [VERIFY on hardware: the rebuilt initramfs boots; TPM2, TPM2 + PIN and
FIDO2 each unlock at boot; the passphrase fallback appears when the TPM
refuses.]

## Revisit when

Fedora bootc ships signed UKIs (then bind to PCR 11 with signed policies), or
a machine needs hibernation.
