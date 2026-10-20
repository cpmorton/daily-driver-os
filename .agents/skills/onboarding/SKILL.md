---
name: onboarding
description: >-
  Bootstrap a new image from this template: rename the project, enable
  Actions and Renovate, protect the branch, and reach a first green build.
  Use when forking the template or when setup has stalled.
---

# Onboarding

Take a fresh fork from "Use this template" to a green build on `main`.

Every step has two routes: a `gh` command and a by-hand walkthrough through the
GitHub website (or `git`). They do the same thing, so use whichever suits you —
the by-hand route is written for someone who has never opened these settings
before. Substitute your own `{owner}/{repo}` throughout.

## Before you start

- You need **admin** on the repository for every step below.
- For the `gh` route, run `gh auth login` and authenticate as that admin.
- **Two different Settings pages are involved.** Most steps are in the
  *repository's* settings — open your repository and click **Settings** in the
  top bar. The token in step 5 is in your *account's* settings — click your
  profile picture, top right. They look similar; check the sidebar heading.
- Only step 5 has no shortcut, because only you can mint a personal access
  token.

## 1. Rename the project

See the Quick start in [README.md](../../../README.md#quick-start). Three identity
sites, and `just test-contract` fails when they disagree.

## 2. Enable Actions

Without this no workflow runs at all, including the first build.

- **`gh`** — `gh api -X PUT repos/{owner}/{repo}/actions/permissions -F enabled=true -f allowed_actions=all`
- **By hand:**
  1. Open your repository and click the **Actions** tab.
  2. GitHub shows "Workflows aren't being run on this repository" with a green
     button. Click **I understand my workflows, go ahead and enable them**.
  3. To set the broader permission, go to **Settings → Actions → General**. Under
     **Actions permissions**, select **Allow all actions and reusable
     workflows**, then click **Save**.

## 3. Allow auto-merge

Renovate merges low-risk updates on its own, and it cannot without this.

- **`gh`** — `gh api -X PATCH repos/{owner}/{repo} -F allow_auto_merge=true`
- **By hand:**
  1. In your repository, click **Settings**.
  2. In the left sidebar, click **General**.
  3. Scroll down to **Pull Requests**.
  4. Tick **Allow auto-merge**. This section has no Save button; it applies
     immediately.
  5. **Automatically delete head branches** is optional. The template does not
     depend on it.

## 4. Workflow permissions

Let workflows write: push images, tag releases.

- **`gh`** — `gh api -X PUT repos/{owner}/{repo}/actions/permissions/workflow -f default_workflow_permissions=write`
- **By hand:**
  1. **Settings → Actions → General**.
  2. Scroll down to **Workflow permissions**.
  3. Select **Read and write permissions**.
  4. Click **Save**.

## 5. Create the Renovate token

The one step with no shortcut. Renovate uses this token to push branches and
open pull requests, so it needs to act as you.

### Create the token

1. On any GitHub page, click your profile picture in the top right, then
   **Settings**.
2. In the left sidebar, click **Developer settings**.
3. Under **Personal access tokens**, click **Tokens (classic)**.
4. Click **Generate new token**, then **Generate new token (classic)**.
5. Give it a **Note**, for example `renovate-your-repo`.
6. Set an **Expiration**. The default is 30 days. When it lapses, Renovate stops
   opening pull requests until you replace the secret, so pick a date you will
   notice.
7. Under **Select scopes**, tick:

   - **`repo`** — read and write the repository
   - **`workflow`** — update the files under `.github/workflows/`

8. Click **Generate token**.
9. **Copy the token now.** GitHub shows it once. If you lose it, generate
   another and replace the secret.

> A classic token carries every permission you have, on every repository you can
> reach. If you would rather not, create a fine-grained token instead, scoped to
> this repository, with **Contents: Read and write** and **Workflows: Write**.
>
> **A fine-grained token currently fails the Renovate run.** The "Validate
> RENOVATE_TOKEN" step (`check-token-health` in `projectbluefin/actions`,
> pinned at `837850b`) reads the `X-OAuth-Scopes` header with `grep` under
> `pipefail`. GitHub sends that header only for classic and OAuth tokens, so
> with a fine-grained token the step exits 1 with no message, right after the
> token authenticated. Use a classic token until that action tolerates the
> missing header. Found 2026-09-25: the same fine-grained token got 200 from
> `/user` and no `X-OAuth-Scopes` header.

### Store it as a secret

- **`gh`** — `gh secret set RENOVATE_TOKEN --repo {owner}/{repo}`, then paste the
  token when prompted.
- **By hand:**
  1. Back in your repository, go to **Settings → Secrets and variables →
     Actions**.
  2. Click **New repository secret**.
  3. Name it exactly **`RENOVATE_TOKEN`**.
  4. Paste the token into **Secret**, then click **Add secret**.

## 6. Protect `main`

Require the `validate` and `image-build` checks, so nothing lands without
passing shellcheck and hadolint and without the image still building. Renovate's
auto-merge waits only for required checks, so `image-build` is what stops a
digest bump that breaks the build.

- **`gh`**:

  ```bash
  gh api -X PUT repos/{owner}/{repo}/branches/main/protection --input - <<'JSON'
  {
    "required_status_checks": {"strict": false, "contexts": ["validate", "image-build"]},
    "enforce_admins": false,
    "required_pull_request_reviews": null,
    "restrictions": null
  }
  JSON
  ```

- **By hand:**
  1. **Settings → Branches** (newer repositories keep this under **Rules**).
  2. Click **Add branch protection rule**, or **Add classic branch protection
     rule**.
  3. **Branch name pattern**: `main`.
  4. Tick **Require status checks to pass before merging**.
  5. In the search box, type `validate` and select the **validate** check, then
     do the same for **image-build**. The names must match exactly. A check that
     has never run does not appear in the list — open a pull request first if
     one is missing.
  6. **Require a pull request before merging** is optional. The template's
     convention is that `main` takes no direct pushes, but the setting is what
     enforces it.
  7. Click **Create**, or **Save changes**.

## 7. Create the labels

The shared label workflow uses the lifecycle set. When a label is missing, the step that
applies it fails, and the failure is easy to miss.

- **`gh`** — one call per label:
  `gh label create <name> --repo {owner}/{repo} --color <hex> --force`
  (`--force` updates a label that already exists, so the block is safe to
  re-run.)
- **By hand** — **Issues → Labels → New label**, then name, colour, and
  description, one at a time. Ten labels is tedious; the `gh` route is worth
  it here even if you did everything else by hand.

Required:

| Label | Colour |
|---|---|
| `1-triage` | `FBCA04` |
| `2-discussing` | `D876E3` |
| `3-human-queue` | `1D76DB` |
| `3-clanker-queue` | `0E8A16` |
| `4-review` | `0052CC` |
| `blocked` | `B60205` |
| `hold` | `6E7781` |

Optional: `area/ci`, `kind/bug`, `priority/p1` (all `ededed`), and GitHub's
defaults.

## 8. Enable issues

The issue templates in `.github/ISSUE_TEMPLATE/` only appear when issues are on.

- **`gh`** — `gh api -X PATCH repos/{owner}/{repo} -F has_issues=true`
- **By hand:**
  1. **Settings → General**.
  2. Scroll to **Features**.
  3. Tick **Issues**.
  4. Click **Save**.

## Verify

Run every check and compare against the values in this skill:

```bash
gh api repos/{owner}/{repo} --jq '{auto_merge: .allow_auto_merge, issues: .has_issues}'
gh api repos/{owner}/{repo}/actions/permissions
gh api repos/{owner}/{repo}/actions/permissions/workflow
gh api repos/{owner}/{repo}/branches --jq '.[].name'
gh api repos/{owner}/{repo}/branches/main/protection --jq '.required_status_checks.contexts'
gh secret list --repo {owner}/{repo}
```

Done when `main` requires `validate`, `RENOVATE_TOKEN` is set, and a push to `main` that changes
more than documentation produces a green `Build and Push Image` run and a
`:stable-testing` image. Documentation-only pushes are skipped by `paths-ignore`.

## Failure modes

- **The first build never starts** — Actions were never enabled (step 2).
- **`validate` is not offered as a check** — it has never run. Push something
  that is not documentation-only and try again.
- **Renovate opens no pull requests** — the token is missing, expired, or lacks
  the `workflow` scope (step 5).
- **"Validate RENOVATE_TOKEN" fails with no message** — the token is
  fine-grained; see the note in step 5. **"invalid or expired (HTTP 401)"** —
  the saved value is not a live token: blank, cut short, or replaced by a later
  regeneration.
- **A pull request never shows `validate` as required** — the check name in
  step 6 is not exactly `validate`.
- **The first release fails at the signature check** — the candidate image is
  unsigned; see the `ci` skill.
