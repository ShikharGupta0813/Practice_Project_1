---
description: Re-run a task's verification against the current branch
argument-hint: <task number or gid>
---

Read `.claude/workflow.md` first.

Verify the work for each task in: $ARGUMENTS
Numbers resolve via `.claude/plans/_last_list.json`.

This changes nothing. It only checks and reports.

## Steps

1. Find the task's branch in `.claude/plans/_batch.json` and check it out if you
   are not already on it. If there is no branch yet, say so and stop.

2. **Syntax gate:**
   ```
   powershell -File .claude/bin/verify.ps1
   ```

3. **Run the plan's "How to test" section** from `.claude/plans/<gid>.md`.
   Execute the steps; do not merely restate them.

4. **Confirm the diff is only what the plan said it would be:**
   ```bash
   git diff --stat origin/onestackcbs...HEAD
   ```
   Compare against the plan's "Files and scope" table. Flag any file that
   changed but was not in the plan — that is the failure this step exists to
   catch.

5. **Confirm the branch is based on production, not dev:**
   ```bash
   git log --oneline origin/onestackcbs..HEAD | wc -l
   ```
   A large count means the branch was cut from `onestackcbs-dev` by mistake.
   Say so loudly.

## Do not use local data

Never check local logs or the local database to decide whether something works.
They do not match production. Report what you could verify and what needs a
production check, with the command for it.

## Report

A short pass/fail per check. If everything passes, say so in one line. If
anything fails, say exactly what and what you would do about it — but do not
fix it here unless the user asks.
