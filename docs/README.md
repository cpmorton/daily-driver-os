# Start here

**Just want to install and use the machine? → [GETTING_STARTED.md](GETTING_STARTED.md).**

The rest, in reading order. Each page links to the next level of detail.

1. **[../README.md](../README.md)**: what this image is and how it differs
   from its base.
2. **[GLOSSARY.md](GLOSSARY.md)**: every name used here (Silverblue, bootc,
   Universal Blue, Bluefin, common, finpilot, devmode, homed, ...), bottom of
   the stack up.
3. **[ARCHITECTURE.md](ARCHITECTURE.md)**: which layer owns what, and the
   rules that keep it that way.
4. **[decisions/](decisions/README.md)**: why each choice was made, what was
   rejected, and when to revisit it.
5. **[PROVENANCE.md](PROVENANCE.md)**: the full inventory: every package,
   file, service change, Flatpak and recipe this repository adds, and every
   piece of state a machine creates. On a machine: `ujust provenance <path>`.
6. **[runbooks/](runbooks/)**: doing things. [reinstall](runbooks/reinstall.md),
   [reinstall without a USB stick](runbooks/reinstall-no-usb.md),
   [machine-defaults](runbooks/machine-defaults.md), [first-boot](runbooks/first-boot.md),
   [home-backup](runbooks/home-backup.md), [upgrade](runbooks/upgrade.md),
   [recover](runbooks/recover.md).

The per-user half (git identity, GitHub sign-in) is the separate `dotfiles`
repository; [decision 0003](decisions/0003-two-repositories.md) explains the split,
and [0024](decisions/0024-dotfiles-apply-themselves.md) how it applies itself at login.

## Keeping it true

- A new file, package, service change, Flatpak or recipe needs a row in
  PROVENANCE.md. `tests/contract/daily-driver_test.bats` fails without it.
- A genuinely load-bearing choice gets a decision record; most changes don't
  need one. Supersede old records instead of editing their history.
- Anything marked **[VERIFY]** hasn't been proven on a real machine yet.

Planned structural work is in [WAVE2-followup.md](WAVE2-followup.md).
