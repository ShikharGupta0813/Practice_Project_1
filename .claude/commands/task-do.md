---
description: Execute an approved plan — branch, fix, commit, push, open the DEV PR
argument-hint: <task number or gid> [more...]
---

Read `.claude/workflow.md` first.

Execute the approved plan for each task in: $ARGUMENTS
Numbers resolve via `.claude/plans/_last_list.json`.

**Refuse** any task with no `.claude/plans/<gid>.md`. Say so, point at
`/task-plan <id>`, and move on. Never improvise a plan here.

## Step 1 — verify the ledger against reality (do not skip)

A previous session may have already done part of this. Run these once per task,
before touching anything:

```bash
git branch --list "sg_cl_<name>"
git log --oneline onestackcbs..sg_cl_<name>      # existing commits?
git status --porcelain                            # uncommitted work?
gh pr list --head sg_cl_<name> --state all --json number,url,state,baseRefName
```

Then act on what you actually found:

| Found | Do |
|---|---|
| Nothing | Start fresh at Step 2 |
| Branch exists, no commits | Reuse it, implement |
| Commits exist, not pushed | Do NOT redo the work — push and open the PR |
| Dev PR already open | Report it and stop; nothing to do |
| Uncommitted changes present | Report them and ask before proceeding |

Correct `.claude/plans/_batch.json` to match what you found, and say plainly if
it had drifted. **Git and GitHub are the truth; the ledger is a hint.**

## Step 2 — new worktree, branched from PRODUCTION

```bash
git fetch origin onestackcbs
git worktree add ../oneStack-worktrees/sg_cl_<name> -b sg_cl_<name> origin/onestackcbs
```

Always cut from `onestackcbs`, never from `onestackcbs-dev` — dev is ~5,100
commits ahead, and a dev-based branch would make the later production PR
unreviewable. Branching from `origin/onestackcbs` means the user's main folder
is never checked out to another branch.

**You stay in the main folder** (that is where `.claude` lives). The worktree
holds code only, so:
- edit files by their full path under `../oneStack-worktrees/sg_cl_<name>/`
- run git there with `git -C ../oneStack-worktrees/sg_cl_<name> ...`
- pass `-RepoPath ../oneStack-worktrees/sg_cl_<name>` to `verify.ps1` and
  `local-review.ps1`

If the worktree already exists (an earlier run), reuse it - do not recreate.
The worktree is removed later by `/task-status`, once the PRODUCTION PR is
merged.

## Step 3 — implement

Follow the plan document. Do not explore beyond the files it names.

Before writing code, read `.claude/docs/known-patterns.md` and follow its
**consistency rule**: write new code the way the neighbouring code of the same
kind already does it, and don't change a codebase-wide convention as a side
effect of this task.

If the plan records decisions the user made in the Asana task (a `CLAUDE-DO`
block — see `/task-plan` Step 1b), those are settled. Implement them as written.
If one turns out to be impossible once you are in the code, stop and say which
instruction and why; do not substitute your own choice for theirs.

A task whose Asana name starts with `Claude_Do` is pre-approved: `/task-plan`
hands straight here without pausing for approval. It changes nothing else — the
verification gate and the dev-PR question at Step 5d still apply in full.

## Step 4 — VERIFY BEFORE COMMITTING (do not skip)

You own the testing. The user is not involved in it. Do not ask them to check
anything, and do not open a PR on unverified work.

**a) Syntax gate — always:**

```
powershell -File .claude/bin/verify.ps1 -RepoPath ../oneStack-worktrees/sg_cl_<name>
```

`RESULT: FAIL` means stop: fix the syntax error and re-run. Never commit or
push past a FAIL. **`-RepoPath` is required** - without it this lints the main
folder instead of the task's code.

**Local logs and the local DB are NOT valid evidence** (see `.claude/workflow.md`).
Verify with syntax checks, code inspection and reproducible local behaviour. If
confirming a fix truly needs production data, say so and give the user the
read-only command to run — do not fake it with local data.

**b) Run the plan's own "How to test" section.** It exists to be executed, not
read. Run whatever it specifies and report the actual output.

**c) Prove you did not change behaviour you were not asked to change.** Pick a
check that fits the task, for example:
- config/routes edits -> count routes before and after, compare a hash
- a function fix -> exercise it with the failing input and a normal input
- a removal -> grep for remaining references to what you removed

Put the evidence in the PR body. If something cannot be verified locally, say
so plainly in the PR rather than implying it was tested.

## Step 5 — commit (locally, do NOT push yet)

Commit each task separately even when a branch carries several.

Commit message ends with:

```
Asana: <gid>

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
```

**Do not push yet** - the AI review comes next, so any fixes can be folded in
before anything reaches GitHub.

## Step 5b — AI review, before pushing

```
powershell -File .claude/bin/local-review.ps1 -RepoPath ../oneStack-worktrees/sg_cl_<name> -PlanFile .claude/plans/<gid>.md
```

This uses `review-pr --compare <branch> onestackcbs`, review-pr's own
branch-compare mode: the same diff GitHub would show for the PR, reviewed by
claude and antigravity in parallel. Nothing is sent to GitHub. It only sees
**committed** work, which is why Step 5 commits first.

**SHOW THE USER BOTH PROVIDERS' RESULTS IN FULL, EVERY TIME.** Not a summary,
not just a table - the actual review output from claude and from antigravity.
The user wants to read them.

Then triage every finding exactly as described in `.claude/docs/self-review.md`
(suggestions, not orders). Fix only real problems this change introduced that
are inside the task. After fixing: re-run `verify.ps1` and **amend the commit**
(`git commit --amend --no-edit`). If both providers fail, say so and carry on -
never block the task on the reviewer.

## Step 5c — push

```bash
git -C ../oneStack-worktrees/sg_cl_<name> push -u origin sg_cl_<name>
```

Pushing is NOT gated - the branch goes up either way, so approving the PR is
instant. Nothing is created on GitHub by a push alone.

## Step 5d — STOP and ask before opening the dev PR

**Do not open the dev PR on your own.** After showing the reviews and pushing,
ask plainly:

```
Branch pushed: sg_cl_<name>
Review: <n> findings - <n> fixed, <n> dismissed
Open the dev PR?
```

Then WAIT for the user's answer.

- **Yes** -> continue with Step 6.
- **No** -> stop here. The branch is pushed and the work is safe. Do NOT
  comment on Asana and do NOT set `dev_pr_open` in the ledger: neither is true
  until the PR exists. Record the state as `committed` with the branch name.

This applies every single time, for every task in a batch - never assume
approval carries from one task to the next.

## Step 6 — open the DEV pull request (only after a yes)

```bash
gh pr create --base onestackcbs-dev --title "Dev PR : <short> - <gid>" --body "..."
```

Base is **`onestackcbs-dev`**.

**PR title format — follow exactly:**

```
Dev PR : <short description> - <asana_gid>
```

- Starts with `Dev PR : ` (production PRs use `Prod PR : `).
- Keep the description SHORT — a few words naming the thing, not a sentence.
  Good: `UPI Metrics no-data message`. Bad: `UPI Metrics - show "Data not
  found" when a bank has no data`.
- The Asana task gid is ALWAYS last.

Example: `Dev PR : UPI Metrics no-data message - 1214343776994298`

Body: what changed, why, how to verify, the Asana permalink, the plain-English
explanation from Step 9, and the `Asana: <gid>` trailer.

## Step 7 — comment the link on Asana immediately

```
powershell -File .claude/bin/asana.ps1 comment -Id <gid> -Text "Dev PR : <url>"
```

Do this as soon as the PR opens. Do not batch to the end.

## Step 8 — update the ledger

Set state `dev_pr_open` with the PR number and URL. Write it immediately, per
task — a crash must not lose the record.

If the plan flagged this task as needing human review, carry
`"needs_human_review": true` into the ledger entry and say so in the PR body
and in your report.

## Stop conditions

Stop at `dev_pr_open`. **Never open the production PR here** — that is `/prod`,
and only when the user asks. Never merge, never push to `onestackcbs` or
`onestackcbs-dev`, never close the Asana task.

If a task is riskier than the plan assumed, mark it `blocked` with the question,
tell the user, and continue with the remaining tasks rather than halting.

## Step 9 — explain what you did, in simple words

After the PR is open, explain the work to the user in chat. Write it for
someone with NO technical background. This is not optional and it is not a
one-liner.

Also put the same explanation (Parts 1 and 2 below) into the PR body, so a
reviewer gets it too.

Structure:

### 1. What I changed, in plain words

Two or three short sentences. No jargon. What the system did before, what it
does now, and what that means for a real person.

### 2. Why it needed changing

The actual consequence of leaving it alone. Concrete, not abstract.

### 3. Every change, one by one

For EACH edit, in this shape:

```
File: application/libraries/PermissionService.php  (line 28)

What this bit of code does:
  <plain English - what this code is for, as if explaining to a friend>

Before:
  <the old code>

After:
  <the new code>

What changed and why:
  <plain English - what is different now and what that fixes>
```

Show the real code, not a description of it. Keep snippets short — the few
lines that changed, plus a line either side for context.

### 4. New things I used — explain each separately

If the change introduces anything the user has not seen before — a function, a
pattern, a config setting, a language feature — give it its OWN short section:

```
NEW: <the thing>

What it is:      <one or two plain sentences>
Why we used it:  <why it fits here>
It IS like:      <a correct comparison>
It is NOT:       <a common misunderstanding, corrected>
```

The "It IS / It is NOT" pair matters — say what it is, then rule out the wrong
assumption someone would naturally make.

### 5. How I checked it

What you actually ran and what it printed. If something could not be checked
locally, say so plainly and give the production command.

Rules: short sentences, everyday words, explain any technical term in the same
sentence. Never say "as you know". Never assume the reader knows what a
controller, route, slug, session or permission check is.

## Report

Finish with the branch name and the dev PR link. The simple explanation above
IS the report - do not replace it with a one-line summary.
