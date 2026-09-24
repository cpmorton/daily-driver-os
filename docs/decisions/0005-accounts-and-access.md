# 0005. Accounts: root locked, localadmin local-only, no password in the image

- **Status:** Accepted
- **Date:** 2026-09-23

## Amendments

- 2026-09-23, [0018](0018-provisioning-seed-stick.md): localadmin is UID 1000, not 1999, and its password comes from the seed stick's hash when one is present (tty1 prompt otherwise). The access rules below are unchanged.
- 2026-09-23, [0019](0019-no-seeded-passwords.md): no seeded hash after all; localadmin's password is always typed on tty1 at first boot. No SSH key either.
- 2026-09-23, [0020](0020-machine-defaults-on-the-esp.md): localadmin's password may come from a hash in the machine defaults (EFI partition), offered at first boot; otherwise typed there. Still no SSH key.

## Context

One break-glass administrator, never reachable remotely; no root logins; daily
users are not administrators.

## Decision

- **root:** password locked (`passwd -l root` in the build, `rootpw --lock` in
  the installer kickstart). The shell stays, so `sudo -i` and the emergency
  shell work.
- **localadmin:** UID 1999, in `wheel`, created at boot by
  `/usr/lib/sysusers.d/50-localadmin.conf`. Its password is typed on tty1 at
  first boot (`localadmin-firstboot.service`, ordered before GDM).
- **Remote access:** `/etc/security/access.d/50-localadmin.conf` refuses
  localadmin wherever `PAM_RHOST` is set, wired in by authselect's
  `with-pamaccess`; the sshd drop-in adds `DenyUsers localadmin` and
  `PermitRootLogin no`. sshd itself is not enabled.
- **Other escape hatches masked:** `debug-shell.service` (root shell on tty9)
  and `gnome-remote-desktop.service` (system RDP through GDM).

## Alternatives

- **Baked password hash:** rejected in [0002](0002-public-and-secret-free.md).
- **`useradd` at build time:** the account would live in the image's
  `/etc/passwd` and drift; sysusers.d is bootc's recommended pattern.
- **Match sshd only (`DenyUsers`):** misses every other remote PAM service;
  pam_access covers them all.

## Verification

- sudo's source: it sets `PAM_RHOST` only when its `pam_rhost` flag is on,
  which defaults on only for Solaris (`#ifdef __sun__`). On Linux, sudo counts
  as `LOCAL`. The build fails if sudoers ever turns `pam_rhost` on.
- Linux-PAM's source: pam_access reads `/etc/security/access.d/*.conf`. The
  build checks the installed module supports it.
- authselect's `local` profile: `pam_access` runs before `pam_systemd_home` in
  the account stack, so the rule also applies to homed users.

## Consequences

- Recovery with root locked needs the GRUB command line
  (`docs/runbooks/recover.md`). Anyone with physical access can do the same.
- An installer-created user would be an unrestricted admin: create none.

## Revisit when

A remote-admin need appears (use a separate, key-only account, not localadmin),
or `gnome-remote-desktop` is shown to set `PAM_RHOST`.
