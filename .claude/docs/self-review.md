# Self-review: running the AI reviewers on our own work

Findings are **suggestions, not orders**. You decide, finding by finding.

## Two ways to run it

**1. Before the PR exists — the default.** `/task-do` uses this at Step 5b:
committed locally, not yet pushed, so any fixes can be amended in and the PR
arrives clean:

```
powershell -File .claude/bin/local-review.ps1 -PlanFile .claude/plans/<gid>.md
```

This is review-pr's own `--compare <branch> <base>` mode (added upstream
2026-09-24): it diffs the branch against the base's merge-base — the same
"changes since divergence" diff GitHub shows for a PR — and runs the normal
review on it. It never publishes; there is no PR to attach a review to.

**It only sees COMMITTED work.** Uncommitted changes are not reviewed; the
script warns when the working tree is dirty.

**2. On a PR that already exists** - for a PR opened earlier, or on request:

```
powershell -File .claude/bin/self-review.ps1 -Pr <pr_number> -PlanFile .claude/plans/<gid>.md
```

Both run **claude** and **antigravity** in parallel in WSL.

- Nothing is ever posted to GitHub.
- The plan file is passed as `--business-context`, so the reviewers can check
  the diff against what the task was meant to do.
- Takes ~1.5-4 minutes. Full output per provider is saved in
  `.claude/plans/reviews/<pr>-<provider>.txt`.
- If one provider fails (antigravity cannot take prompts >= 128 KB, or returns
  empty), carry on with the other. If **both** fail, say so and skip — never
  block the task on the reviewer.

## Why you must think for yourself

**The reviewers only see the diff.** They don't know the rest of the codebase,
this project's conventions, or what the task asked for beyond the plan. They
regularly flag things that are fine — e.g. a relative log path that
`index.php` already makes safe with `chdir()`. So every finding is checked
against the real code before anything is done about it.

## Triage — put every finding in exactly one bucket

Work through them in this order; the first bucket that fits wins.

| # | Bucket | How to tell | Action |
|---|---|---|---|
| 1 | **False positive** | Check it against the actual code, not just the diff. Wrong on the facts, or already handled elsewhere. | Nothing. |
| 2 | **Contradicts a known pattern** | It "fixes" something listed in `.claude/docs/known-patterns.md` (e.g. TLS verification off on a CBS curl call). | Nothing. Name the pattern. |
| 3 | **Not introduced by this change** | The flagged line/problem existed before this branch: `git blame` shows a commit that is not on this branch, or the line is not in `git diff origin/onestackcbs...HEAD`. | Nothing. Not this task's job. |
| 4 | **Real, introduced here, but outside the task** | Genuine and caused by this change, but fixing it goes beyond what the plan set out to do (new feature, redesign, tests the plan didn't include). | Don't fix. Tell the user. |
| 5 | **Real, introduced here, inside the task** | Genuine, caused by this change, and part of doing the task properly. | **Fix it.** |

Also:
- **Both reviewers found it** -> worth a closer look, not automatically true.
- **Only one found it** -> not automatically false either (antigravity caught
  public CodeIgniter controller methods being callable as URLs; claude didn't).
- **Confidence scores don't decide anything.** A 0.92 can be wrong and a 0.80
  right.
- "Add tests" findings: bucket 4 unless the plan included tests.

## Fixing bucket-5 findings

1. Make the fix, following `.claude/docs/known-patterns.md` and the
   consistency rule.
2. `powershell -File .claude/bin/verify.ps1` — must pass.
3. **Before the PR (compare mode):** the commit is not pushed yet, so amend it
   (`git commit --amend --no-edit`). That is the whole point — the PR arrives
   clean.
   **On an existing PR:** commit on the **same branch** (`Asana: <gid>` trailer
   as usual) and push. **No** Asana comment and no new PR for this.
4. One review round only. Don't re-run the AI review after fixing — the
   verify gate is enough. The user can run it again if they want.

## Report in chat

A short table, one row per finding, both providers merged:

```
| Finding (file:line) | Found by | Bucket | Why | Action |
|---|---|---|---|---|
| Lockout skipped when mobile no. missing (NpciIBMB.php:510) | both | 5 | our new check has `!empty($mobileNo) &&` | fixed in <commit> |
| Relative log path (common_helper.php:1821) | claude | 1 | index.php:260 chdir()s for CLI | none |
```

Then one line: how many fixed, how many dismissed, and anything the user
should decide (bucket 4).
