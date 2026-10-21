---
description: Open the production PR for a task that already has a dev PR
argument-hint: <task number or gid> [more...]
---

Read `.claude/workflow.md` first.

Open the **production** pull request for each task in: $ARGUMENTS
Numbers resolve via `.claude/plans/_last_list.json`.

This reuses the SAME branch that `/task-do` already created. It does not write
code, does not create a branch, and does not commit.

## Step 1 — verify before opening anything

For each task, find its branch in `.claude/plans/_batch.json`, then check:

```bash
git branch --list "sg_cl_<name>"
gh pr list --head sg_cl_<name> --state all --json number,url,state,baseRefName,mergedAt
git log --oneline origin/onestackcbs..sg_cl_<name>   # what production would receive
```

**Refuse to proceed if:**

| Condition | Why |
|---|---|
| No dev PR exists yet | Dev goes first. Point at `/task-do`. |
| Dev PR exists but is NOT merged | Production must not get code dev has not accepted. Report its state and STOP unless the user explicitly says to go anyway. |
| The branch is not pushed | Nothing to open a PR from. |
| A production PR already exists | Report its URL and stop. |
| The commit list is large or unexpected | Almost certainly branched off `onestackcbs-dev` by mistake — a production PR would carry ~5,100 unrelated commits. **Stop and tell the user.** Do not open it. |

That last check is the important one. Confirm the diff is only this task's
work before opening a PR against production.

## Step 2 — open the production PR

```bash
gh pr create --base onestackcbs --title "Prod PR : <short> - <gid>" --body "..."
```

**PR title format — follow exactly:**

```
Prod PR : <short description> - <asana_gid>
```

- Starts with `Prod PR : ` here (dev PRs use `Dev PR : `).
- Keep the description SHORT — a few words naming the thing, not a sentence.
  Good: `UPI Metrics no-data message`. Bad: `UPI Metrics - show "Data not
  found" when a bank has no data`.
- The Asana task gid is ALWAYS last.

Example: `Prod PR : UPI Metrics no-data message - 1214343776994298`

Body: what changed, why, how to verify, the Asana permalink, a link to the dev
PR, and the `Asana: <gid>` trailer.

## Step 3 — comment on Asana

```
powershell -File .claude/bin/asana.ps1 comment -Id <gid> -Text "Production PR : <url>"
```

## Step 4 — update the ledger

Set state `prod_pr_open` with the production PR number and URL, keeping the dev
PR details. Write immediately.

## Worktree

Leave the task's worktree in place. It is removed by `/task-status` once the
production PR is **merged**, not when it is opened - the branch may still need
changes while the PR is in review.

## Stop conditions

Never merge either PR. Never push to `onestackcbs` or `onestackcbs-dev`. Never
close the Asana task.

## Report

One or two lines per task: production PR link, and the commit count it carries.
Nothing more.
