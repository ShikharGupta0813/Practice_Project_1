---
description: Resume an interrupted task batch in a fresh session
---

Read `.claude/workflow.md` first.

This is the command to run in a NEW chat after a session ended mid-batch.
Assume you have no memory of the previous session; the files and git are your
only context.

1. Run the full reconciliation described in `/task-status`. Report drift.
2. Present the picture plainly, e.g.:
   "7 tasks have PRs open. Task X is on `sg_cl_foo` with 2 commits and
   uncommitted changes in 3 files. Tasks Y and Z are approved but not started."
3. For anything half-finished, say specifically what remains — uncommitted
   edits, unpushed commits, or no PR yet.
4. For anything `blocked`, surface the open question and wait for an answer.
5. **Ask before continuing.** Then resume per `/task-do` for the tasks the
   user confirms.

Never assume approval carries over from the previous session for work that had
not already started. Tasks already at `branched` or later were approved before,
and may continue once the user confirms the resume.
