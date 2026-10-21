---
description: Push a follow-up fix to a task's existing branch — no new PR, no Asana comment
argument-hint: "<task number | gid | branch> <what to fix>"
---

Read `.claude/workflow.md` and `.claude/docs/known-patterns.md` first.

Make a follow-up change on a task branch that already exists and **push it to
the same branch**. Its open PR(s) pick it up automatically. That is the whole
point: keep the PR updated, nothing more.

**Do NOT:** open a new PR, comment on Asana, change the ledger state, or touch
`onestackcbs` / `onestackcbs-dev` directly.

## Step 1 — find the branch

`$ARGUMENTS` starts with a task number (resolve via
`.claude/plans/_last_list.json`), an Asana gid (look it up in
`.claude/plans/_batch.json`), or a branch name (`sg_cl_...`). If none is
given and the current branch is an `sg_cl_` branch, use that. Otherwise ask.
Stop.

The rest of `$ARGUMENTS` is what to fix. If it is missing or unclear, ask
before touching anything — same rule as `/task-plan`: say what you understand
and what you don't.

## Step 2 — get onto the latest version of that branch

Tasks live in their own worktree. Find it **by branch name**, not by guessing
the folder - new ones are under `../oneStack-worktrees/<branch>`, but older
ones live elsewhere (e.g. `C:/xampp/htdocs/oneStack_bankstaff`):

```bash
git worktree list --porcelain      # pair "worktree <path>" with "branch refs/heads/<name>"
```

**If a worktree for that branch exists**, work there (paths below use
`<worktree>` for whatever path you found) and leave the main folder untouched:

```bash
git -C <worktree> status --porcelain    # must be clean
git -C <worktree> pull --ff-only origin <branch>
```

**If it does not exist** (an older task, or it was cleaned up), recreate it
rather than switching the main folder:

```bash
git worktree add ../oneStack-worktrees/<branch> <branch>   # new ones go here
git -C ../oneStack-worktrees/<branch> pull --ff-only origin <branch>
```

If the working tree is not clean, or the pull cannot fast-forward (the branch
has diverged), STOP and report — never stash, reset or force anything.

## Step 3 — make the change

- Keep it to what was asked. No drive-by improvements.
- Follow the consistency rule: match the neighbouring code of the same kind.
- If the request turns out bigger than a follow-up fix (new behaviour, many
  files, a different task), say so and suggest `/task-plan` instead. Stop.

## Step 4 — verify

```
powershell -File .claude/bin/verify.ps1 -RepoPath <worktree>
```

Must pass. Also run whatever check fits the change (the same idea as `/task-do`
Step 4c). No AI review by default — this is meant to be quick. Run
`.claude/bin/self-review.ps1` only if the user asks.

## Step 5 — commit and push to the same branch

Commit message ends with the usual trailers (`Asana: <gid>` when the task is
known, then the `Co-Authored-By:` line). Then:

```bash
git -C <worktree> push origin <branch>
```

Nothing to switch back to - the work happened in the worktree, so the user's
main folder was never touched. Leave the worktree in place; `/task-status`
removes it once the production PR is merged.

## Report

Short, plain English:

```
Pushed to <branch>: <commit hash> - <one line what changed>

What changed: <1-2 plain sentences>
Before / After: <the few lines that changed>

Open PRs on this branch now include it: <#n (dev/prod, open)>
```

That last line is information, not a question. If the branch's dev PR is
already merged and only the prod PR is open, say so in one sentence — the
change reaches production's PR without having gone through dev — and leave the
decision to the user.
