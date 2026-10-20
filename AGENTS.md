# AGENTS.md

Working notes for agents in this repository. `overview` maps how the image is
assembled and says which skill covers what; the procedures live under
`.agents/skills/`.

## Gates

These hold for every change:

- **Conventional Commits** — `<type>[scope]: <description>`.
- **Validate before committing.** `just lint` shellchecks every tracked shell
  script, `just check` verifies Justfile syntax, and `just test-unit` runs the
  suite. `just validate-brewfiles` and `just validate-flatpaks` cover those
  files. The `validate` status check runs shellcheck and hadolint on a pull
  request.
- **Confirm before pushing** — show the diff and wait.

## Branches and releases

`main` is the only long-lived branch; work reaches it from feature branches by
PR, and every push publishes `:stable-testing`. A release is a dispatch of
`release.yml`: it promotes the exact signed digest `main` already built to
`:stable` and a `:<version>` tag, never rebuilding, and records git tag
`v<version>`. The README owns the release table and the release's current
limits.

## Pull request comments

One comment per PR event; fold new findings into the existing one. Report what
ran, whether it passed, and what blocked — nothing else. When the only finding
is "tests pass", post nothing. Mention someone only to ask for a specific
action, and do it inside the combined comment.

## Attribution

End every commit with:

    Assisted-by: <Model> via <Tool>

## Self-improvement

Ship the work and update the owning skill in the same PR, not a follow-up. A
skill is the home for durable learning; a changelog, a session note, or an
"append here" section is not. When a workaround or convention surprised you,
the next agent needs it.

## Ownership

Humans triage and approve; agents work only on assigned or `3-clanker-queue`
issues. Keep changes to this repository: `ublue-os/*` is read-only. The shared
lifecycle and labels are in
[projectbluefin/common's label workflow](https://github.com/projectbluefin/common/blob/main/docs/skills/label-workflow.md).
