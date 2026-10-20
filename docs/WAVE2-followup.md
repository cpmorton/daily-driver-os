# Wave 2 — follow-up prompt (not started)

Wave 1 (2026-10-19) cut notification noise, added a [getting-started](GETTING_STARTED.md)
on-ramp, brought the no-USB install into the repo, and relaxed the
decision-record requirement. Wave 2 is the deliberate structural pass. Do it
once the laptop is installed and running Wave 1, iterating in small PRs.

**Overriding goal:** lean *fleet-ready*, not maximally stripped. This repo is
portfolio material (job applications) and may run a future LLC's machines, so it
should demonstrably "get" lab/fleet problems rather than hide them.

## Items

### 2.1 Single user now, multi-user seam later

Assume a single user for now, but keep a clearly documented seam to flip to
multi-user with LDAP/SSO later. Do **not** rip out the `localadmin` + homed
daily-user model ([decision 0005](decisions/0005-accounts-and-access.md),
[0008 superseded by 0017](decisions/0008-homed-users-on-a-separate-partition.md));
put the multi-user path behind a flag/toggle so it can come back cleanly.
Deliverable: name where that flag lives and what it switches.

### 2.2 Release model — done

Mort chose trunk-based releases on 2026-10-20: feature branches into `main`,
and a dispatched release that promotes the signed, tested digest to `:stable`
and records it as a git tag
([decision 0025](decisions/0025-trunk-based-releases.md)). Signing stays
([0013](decisions/0013-image-signing.md)). The `stable` branch is gone, and the
four PR linters were folded into `pr-validation.yml` (13 workflows down to 7).

### 2.3 Build cadence — done in Wave 1

Build on push + daily (14:00 UTC). No further action unless it proves annoying.

### 2.4 Decision records — done in Wave 1

The per-change ADR requirement was relaxed; the 23 records stay as history and
`decisions/README.md` is the single-file index. Provenance
([PROVENANCE.md](PROVENANCE.md)) was kept — it's a real supply-chain artifact.
Open question for Wave 2: is the *row-per-change* provenance gate worth keeping
for a solo project, or should it become advisory? Decide, don't assume.

### 2.5 Boot UX — the real prize

Vision: the machine boots **Windows by default**; hit F12 (or whatever) to reach
GRUB, which presents:

- the current daily-driver image,
- the previous image (rollback),
- a safe mode,
- a **reimage** option (an always-present on-disk installer — the `DDINSTALL`
  partition from [reinstall-no-usb.md](runbooks/reinstall-no-usb.md), kept alive
  permanently rather than as a one-shot).

Not resolved yet. Work needed: decide whether Windows-default is a firmware
boot-order choice or a GRUB-default change; design how the reimage entry is
wired into GRUB; prove the `DDINSTALL`-as-permanent-reinstall path on hardware
(it's currently **[VERIFY]**); and write the decision record for it.

### 2.6 A test box that boots every candidate

Mort's idea (2026-10-20): something that always runs the newest
`:stable-testing`, boots it, runs smoke tests and reports back. This is the
missing gate between "it built and is signed" and "release it": today a release
means "signed and unmodified", not "functionally validated"
([decision 0025](decisions/0025-trunk-based-releases.md)).

Two shapes, cheapest first:

- **A VM boot in CI.** After `build-image.yml` publishes, boot the image in a VM
  on the runner and check that it reaches a login target, that the first-boot
  units are healthy, and that `bootc status` reports the expected digest.
  Check first whether the runner exposes KVM and what upstream
  `projectbluefin/actions` already provides for this; don't assume either.
- **A physical box (hardware in the loop).** A spare machine that follows
  `:stable-testing`, runs `bootc upgrade` and reboots on a schedule, runs the
  same smoke suite, and reports back somewhere CI or the release can read. This
  catches what a VM can't (firmware, TPM2 unlock, GPU, suspend) and is the
  strongest fleet/portfolio story.

Either way, the result should become an input to `release.yml`: refuse, or at
least warn about, a candidate the test box hasn't passed. That calls for a
decision record when it lands.
