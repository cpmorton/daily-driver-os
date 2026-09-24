# Start here

Read in this order. Each page links to the next level of detail.

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
6. **[runbooks/](runbooks/)**: doing things. [first-boot](runbooks/first-boot.md),
   [upgrade](runbooks/upgrade.md), [reinstall](runbooks/reinstall.md),
   [recover](runbooks/recover.md).

The per-user half (git identity, GitHub sign-in) is the separate `dotfiles`
repository; [decision 0003](decisions/0003-two-repositories.md) explains the split.

## Keeping it true

- A new file, package, service change, Flatpak or recipe needs a row in
  PROVENANCE.md. `tests/contract/daily-driver_test.bats` fails without it.
- A new choice with alternatives needs a decision record. Supersede old ones
  instead of editing their history.
- Anything marked **[VERIFY]** hasn't been proven on a real machine yet.
