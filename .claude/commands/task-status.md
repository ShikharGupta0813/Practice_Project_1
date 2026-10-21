---
description: Show reconciled status of the current task batch
---

Read `.claude/workflow.md` first.

Report the true state of the current batch. Do not trust the ledger.

1. Read `.claude/plans/_batch.json`. If missing, say there is no active batch.
2. Reconcile every task against reality:
   - `git branch --list "sg_cl_*"` and `git branch -r --list "origin/sg_cl_*"`
   - `git log --oneline onestackcbs..<branch>` for commits
   - `git status --porcelain` for uncommitted work
   - `gh pr list --head <branch> --state all --json number,url,state,baseRefName`
   - `git log onestackcbs..HEAD --grep="Asana:" ` as a fallback if the ledger looks corrupt
3. If a task's PRODUCTION PR is merged, set its state to `done` **and remove
   its worktree** - that is the end of the task's life.

   **Find the worktree by BRANCH, never by assuming the folder.** New ones are
   created under `../oneStack-worktrees/<branch>`, but older ones live
   elsewhere (e.g. `C:/xampp/htdocs/oneStack_bankstaff`):

   ```bash
   git worktree list --porcelain      # pair each "worktree <path>" with its "branch refs/heads/<name>"
   git worktree remove <the path for that branch>
   ```

   Rules:
   - **Never pass `--force`.** A worktree holding uncommitted work is reported,
     not deleted, so the user can look at it.
   - **Never touch `.claude/worktrees/*`** - those belong to Claude Code itself,
     not to tasks.
   - Say which worktrees you removed, with their paths.
 If its DEV PR
   is merged but the production PR is still open, leave it `prod_pr_open` and
   say so - that task is not finished. Confirm merges with
   `gh pr view <n> --json state,mergedAt`; never infer a merge from the ledger.

4. Rewrite the ledger to match what you found, and explicitly report any state
   that had drifted.
5. Print a table: task gid, short name, branch, state, commits, DEV PR, PROD PR, and for
   anything `blocked` the open question.
6. Summarise: done / awaiting /prod / in flight / blocked / not started.
   Also list any `sg_cl_*` branch with no open PR and no ledger entry - leftover
   branches accumulate and are worth pruning.

Make no code changes. This command is read-only apart from correcting the ledger.
