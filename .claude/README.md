# Asana → PR automation for Claude Code

A set of slash commands that take a task from Asana all the way to a pull
request: read the task, plan it, write the code, AI-review it, and open the PR —
stopping for your approval at each point that matters.

Built for a CodeIgniter 3 PHP repo on Windows, with the AI reviewers running in
WSL. Most of it is plain Markdown, so adapting it is mostly find-and-replace —
see **[What you must change](#what-you-must-change)**.

---

## The flow

```
/task                 see your Asana tasks
   |
/task-plan <n>        read the task + the code, write a plan document
   |                  (asks questions first if anything is unclear)
   |   >> you read the plan and approve
   |
/task-do <n>          worktree -> code -> syntax check -> commit
   |                  -> AI review (2 providers, shown to you)
   |                  -> fix + amend -> push
   |   >> STOPS and asks: open the dev PR?
   |
   |                  dev PR -> Asana comment -> ledger
   |   >> dev PR gets merged by your team
   |
/prod <n>             production PR (refuses if dev PR is not merged)
   |
/task-status          detects the merged prod PR, marks it done,
                      removes the worktree
```

Side commands: `/task-fix` (follow-up push to the same branch), `/task-check`
(re-verify), `/task-resume` (continue after a session died), `/standup`
(what moved since yesterday), `/learn` (teach it a deliberate pattern).

---

## Worktrees — one per task, always

**Every task gets its own checkout.** Nothing is ever built in your main folder.

```bash
# created by /task-do, always NEW, always from the production branch
git fetch origin onestackcbs
git worktree add ../oneStack-worktrees/sg_cl_<name> -b sg_cl_<name> origin/onestackcbs
```

| Rule | Why |
|---|---|
| **Always a new worktree per task** | tasks never collide, and a half-finished one can sit untouched |
| **Branched from the PRODUCTION branch**, never from dev | a dev-based branch would drag thousands of unrelated commits into the production PR |
| **Your main folder is never switched** | no `git checkout` under your feet while you are working in it |
| **Removed only when the PRODUCTION PR is MERGED** | the branch may still need changes while the PR is in review |
| **Never removed with `--force`** | a worktree holding uncommitted work is reported, not deleted |

Who does what:

- `/task-do` creates it (and reuses it if a previous run left one).
- `/task-fix` works inside it, and recreates it if it was already cleaned up.
- `/prod` leaves it alone.
- `/task-status` removes it once it sees the production PR merged.

**`.claude` is NOT inside the worktree.** It is untracked, so a worktree
contains code only — no commands, no scripts, no plans. That is deliberate: one
ledger, one set of plans, no drift. Two consequences:

1. **Always run Claude from the main folder.** Starting a session inside a
   worktree means none of these commands exist.
2. **Pass `-RepoPath <worktree>`** to `verify.ps1` and `local-review.ps1`, or
   they will inspect the main folder instead of the task's code.

### Where they live

New worktrees are created under `../oneStack-worktrees/<branch>`. **Existing
ones may be anywhere** - an established repo often has worktrees made by hand in
other folders (this repo has several at `C:/xampp/htdocs/oneStack_<name>`).

So the commands **look a worktree up by BRANCH, never by guessing the folder**:

```bash
git worktree list --porcelain     # pairs "worktree <path>" with "branch refs/heads/<name>"
```

`/task-fix` and `/task-status` both resolve the path this way, so they work
regardless of where a worktree was created.

Two things they leave alone:

- **`.claude/worktrees/*`** - Claude Code's own internal worktrees, not tasks.
- Any worktree with uncommitted changes - reported, never force-removed.

To see or clean them up by hand:

```bash
git worktree list
git worktree remove <path>
git worktree prune          # tidy up records of folders deleted manually
```

## Requirements

**Required** — without these nothing works:

| Tool | Why | Install |
|---|---|---|
| **An agent** | runs all of this. Claude Code is what it was built for; see [Using Antigravity instead of Claude Code](#using-antigravity-instead-of-claude-code) | [claude.com/claude-code](https://claude.com/claude-code) — desktop app, terminal, or IDE extension |
| **Windows PowerShell 5.1** | every helper script | ships with Windows |
| **git** | branches, worktrees | [git-scm.com](https://git-scm.com) |
| **`gh` (GitHub CLI)** | creating PRs | `winget install GitHub.cli` then `gh auth login` |
| **Asana token** | reading tasks, posting PR links | app.asana.com → My Settings → Apps → Personal access tokens |

**Optional** — each adds one feature; everything else keeps working without it:

| Tool | Adds | Install |
|---|---|---|
| **PHP** | the `php -l` syntax gate | any PHP, e.g. XAMPP. Without it the gate is skipped |
| **WSL** | runs the AI reviewers | `wsl --install` in an admin PowerShell |
| **[review-pr](https://github.com/OneStackIndia/AI-Code-Reviewer)** | the AI review itself | inside WSL: `sudo apt install pipx && pipx install git+<repo-url>` |
| **`claude` CLI in WSL** | review provider | inside WSL: `curl -fsSL https://claude.ai/install.sh \| bash`, then `claude` once to log in |
| **`agy` CLI in WSL** | second review provider (Antigravity) | inside WSL: `curl -fsSL https://antigravity.google/cli/install.sh \| bash`, then `agy` once to log in |

The review step is genuinely optional: if it fails or isn't installed, the
commands say so and carry on.

---

## Commands

All live in `.claude/commands/`. The file name is the command name:
`task-plan.md` → `/task-plan`.

Tasks can be referred to **by list number** (from `/task`) or by **Asana gid**.
Numbers are resolved through `.claude/plans/_last_list.json`.

### `/task` — list your Asana tasks

```
/task              all open tasks
/task 10           the 10 soonest-due
/task today        due today   (also: tomorrow, yesterday)
/task 05-09-2026   due that day (also yyyy-mm-dd)
/task upi          filter by text
```

Prints each task's full name, gid, due date, parent, and a description (falling
back to the task's comments, since Asana descriptions are often empty). Ends
with three short blocks: what can be done **together**, what must be done **in
order**, what to do **on its own** — plus rough time estimates.

Changes nothing. Task numbers stay stable even when the view is filtered.

### `/task-plan <n|gid> [more]` — understand the task, write a plan

Reads the Asana task, its comments and any attachments, then reads the real
code before writing anything.

- If anything is unclear it **stops and asks first**, listing what it
  understood, what it ruled out, what it checked in the code, and its questions.
- If the task is simple and unambiguous it goes straight to the plan.
- Writes **one document**: `.claude/plans/<gid>.md`, in three parts — plain
  English first (what the system does today, what is wrong, what will change,
  what could go wrong), then a glossary, then the technical detail (root cause,
  files and scope, steps, how to test, whether a human must review it).
- Evidence rules: whole-word searches, counts verified by eye, `file:line` for
  every claim. Never quotes an unverified number.

Touches no code.

### `/task-do <n|gid> [more]` — do the work

Refuses to run without an approved plan file. In order:

1. Reconciles the ledger against git and GitHub (never trusts the ledger).
2. Creates a **worktree** at `../oneStack-worktrees/<branch>` from
   `origin/<prod-branch>`, so your main folder is never switched.
3. Writes the code, following `.claude/docs/known-patterns.md`.
4. Syntax gate (`verify.ps1`) — must pass.
5. Commits locally **without pushing**.
6. **AI review** of the branch with both providers, shown to you **in full**.
   Real problems introduced by this change get fixed and amended into the commit.
7. Pushes the branch.
8. **Stops and asks before opening the dev PR.** Every time, for every task.

On "yes": opens the dev PR, comments the link on Asana, updates the ledger, and
explains every change in plain English with before/after snippets.
On "no": the branch stays pushed, nothing on Asana, nothing claimed in the ledger.

Never merges, never pushes to the base branches, never closes the Asana task.

### `/prod <n|gid> [more]` — the production PR

Reuses the same branch and opens a second PR against the production branch.
Refuses when: there is no dev PR, **the dev PR is not merged**, the branch is
not pushed, a prod PR already exists, or the commit list looks unexpectedly
large (the sign of a branch cut from the wrong base).

Leaves the worktree in place — `/task-status` removes it after the merge.

### `/task-fix <n|gid|branch> <what to fix>` — follow-up push

For a task whose branch already exists. Pulls the branch in its worktree
(recreating the worktree if needed), makes the fix, verifies, commits and
pushes to the **same branch**, so existing PRs pick it up.

No new PR, no Asana comment, no ledger change.

### `/task-check <n|gid>` — re-verify

Read-only. Runs the syntax gate, executes the plan's own "How to test" steps,
confirms the diff matches the plan's file list, and confirms the branch is based
on the production branch. Reports pass/fail; fixes nothing unless asked.

### `/task-status` — the truth, not the ledger

Checks every task against git and `gh`, corrects the ledger where it drifted,
and prints a table: state, commits, dev PR, prod PR, open questions. When it
sees a **merged production PR** it marks the task `done` and removes the
worktree (never with `--force`).

### `/task-resume` — after a session died

The one to run in a fresh chat. Reconciles everything, reports exactly what is
half-finished (uncommitted edits, unpushed commits, missing PRs), and asks
before continuing.

### `/standup <optional start date>` — what moved

Every activity from **yesterday 00:00 until now** (from Friday if yesterday was
a weekend), grouped by task: Asana status, dev PR and prod PR state, and each
event in plain words. Plus PRs with no Asana activity.

### `/learn <what is deliberate>` — teach it a convention

Records something that *looks* wrong but is intentional into
`.claude/docs/known-patterns.md`, after checking the code and past commits to
confirm it, with counts and exceptions. Run it whenever a plan or review gets
something wrong for the same reason twice.

---

## Helper scripts (`.claude/bin/`)

| Script | What it does | Parameters |
|---|---|---|
| `asana.ps1` | all Asana REST calls | `<action>` = `me`, `mytasks`, `task`, `stories`, `comment`, `attachments`, `fetch`, `activity`; `-Id <gid>`, `-Text "..."`, `-Top <n>`, `-DueOn <date\|today\|tomorrow\|yesterday>`, `-Since`, `-Until`, `-Out <dir>`, `-NoComments`, `-Limit <n>` |
| `verify.ps1` | `php -l` on changed files | `-RepoPath <worktree>` (**required when using worktrees**), `-Base <ref>` (default `origin/onestackcbs`), `-Files "a.php,b.php"` |
| `local-review.ps1` | AI review of a branch **before** any PR | `-RepoPath <worktree>`, `-PlanFile <plan.md>`, `-Base <branch>` (default `onestackcbs`), `-Providers claude,antigravity` |
| `self-review.ps1` | AI review of an **existing** PR | `-Pr <number>` (required), `-PlanFile`, `-Repo owner/name`, `-Providers` |
| `check-tooling.ps1` | checks these scripts for syntax errors, stray control characters and PowerShell case collisions | none |
| `nightly-report.ps1` | renders a nightly run's `report.json` as `report.html` | `-RunDir <folder>` (default: most recent), `-Open` |
| `setup.ps1` | creates `config.env` and health-checks the whole setup | `-Check` (check only, create nothing) |
| `config.ps1` | shared settings loader — every script reads `config.env` through it | dot-sourced, not run directly |

Examples:

```powershell
powershell -File .claude/bin/asana.ps1 mytasks -Top 10
powershell -File .claude/bin/asana.ps1 comment -Id 1234567890 -Text "Dev PR : https://..."
powershell -File .claude/bin/verify.ps1 -RepoPath ../oneStack-worktrees/sg_cl_foo
powershell -File .claude/bin/local-review.ps1 -RepoPath ../oneStack-worktrees/sg_cl_foo -PlanFile .claude/plans/123.md
```

---

## Supporting files

| Path | Purpose |
|---|---|
| `CLAUDE.md` | loaded into **every** session: stack, conventions, branch rules. Keep it short — every line costs context in every chat |
| `workflow.md` | the shared rulebook all commands read: branching, worktrees, PR rules, Asana access |
| `docs/known-patterns.md` | things that look wrong but are deliberate, so plans and reviews stop flagging them. Grown by `/learn` |
| `docs/self-review.md` | how to triage AI review findings — the five buckets |
| `docs/architecture.md` | deep reference for the codebase, read on demand |
| `docs/how-this-works.md` | plain-English explanation of how all of this works |
| `plans/<gid>.md` | one plan per task |
| `plans/_batch.json` | the ledger: which task is at which stage |
| `plans/_last_list.json` | list number → Asana gid, written by `/task` |
| `plans/reviews/` | full AI review output per provider |

**Keep `plans/` out of version control.** It is local progress, and it changes
constantly.

---

## Setup for a new person

Four steps. You edit **one file**.

### 0. Put the folder in your repo

Clone it so that `.claude/` sits in the **root of your repository**, next to
your code:

```bash
cd your-repo
git clone <this-repo-url> .claude
```

(Or, if you were handed a zip, unzip it to the same place.) The result:

```
your-repo/
  .claude/          <- this folder
  src/ or application/ ...
  .git/
```

Everything below is run from that repo root, not from inside `.claude`.

### 1. Run the setup script

```powershell
powershell -File .claude/bin/setup.ps1
```

It copies `config.example.env` to `config.env`, then checks git, `gh`, PHP,
your Asana token, the branches, and the WSL review tools — and prints exactly
what is still missing.

### 2. Fill in `.claude/config.env`

Everything per-person lives here. Anything you leave out keeps its default.

| Key | What it is |
|---|---|
| `ASANA_TOKEN_FILE` *or* `ASANA_TOKEN` | your Asana Personal Access Token (file path, or the token itself) |
| `GITHUB_REPO` | `owner/name` |
| `PROD_BRANCH` / `DEV_BRANCH` | your production and dev branches. **Same value for both** if you use one branch — then ignore `/prod` |
| `BRANCH_PREFIX` | your initials, e.g. `ab_cl_` |
| `COAUTHOR_LINE` | commit trailer — change it if you use a different AI, empty for none |
| `WORKTREE_ROOT` | where new worktrees are created |
| `PHP_BIN` | path to PHP for the syntax gate |
| `REVIEW_PROVIDERS` | `claude`, `antigravity`, or both |
| `DB_SCHEMA_DOC` | link to your production schema doc, if you have one |

**`config.env` is git-ignored. Never commit or share it.** GitHub needs no
token here — `gh auth login` keeps its own.

Re-run `setup.ps1 -Check` until it says **READY**.

### 3. Log in to the things it uses

```bash
gh auth login
```

`setup.ps1` tells you which of these are still missing, so run it again after
each one. For the AI review (optional), install the WSL pieces from the
**Requirements** table above and log in to at least one provider inside WSL.

### 4. Start a NEW Claude session

Slash commands are read when a session **starts**, so a session that was
already open will not see them. Open a new one in the repo root, then:

```
/task
```

If `/task` is "not recognised", the session predates the files — open another
new one.

### What still needs hand-editing

Config covers names and paths. These are about *your code*, and no setting can
fix them:

- **`CLAUDE.md`** and **`docs/architecture.md`** describe one specific codebase
  (CodeIgniter 3, HMVC modules, a patched `system/core/Router.php`, known auth
  holes). For another project they are **wrong**, not just imprecise. Rewrite
  them from your own code.
- **`docs/known-patterns.md`** — one team's deliberate conventions. Empty it and
  build your own with `/learn`.
- **The syntax gate** in `verify.ps1` runs `php -l`. For another language,
  replace the gate itself (`node --check`, `python -m py_compile`, `go vet`).

## Marking a task you are sure about

### Rename it `Claude_Do...`

When you already know a task should just be done, rename it in Asana so the
name starts with `Claude_Do`. It means *you have my approval to act*:
`/task-plan` writes the plan as usual, then carries straight on instead of
pausing for you to approve it.

It changes nothing else. The verification gate still runs, and `/task-do` still
stops and asks before opening the dev PR.

The prefix shows up in `/task` output automatically - it is part of the name -
so you can see at a glance which tasks are cleared to run.

**It is approval to act, not an answer to what to do.** A `Claude_Do` task that
is still ambiguous gets a question, not a guess. That combination - the usual
pause removed, the requirement unclear - is the one worth being careful about,
so the commands are told explicitly to ask anyway.

### Add a `CLAUDE-DO` block when the details matter

When you want to settle the decisions too, write them into the description or a
comment:

```
CLAUDE-DO
- mask all but the last 4 digits, don't drop the field
- use the existing maskMobile() helper, don't write a new one
- only the transfer log, leave the KYC log alone
/CLAUDE-DO
```

Everything that block covers is decided: no questions about it, no alternatives
offered, straight into the plan. It still opens the real files and checks - if
an instruction cannot be carried out as written, it tells you which one and why
rather than quietly reinterpreting it.

### Only your markers count

Asana text is otherwise inert data the tools read but never obey. Both markers
are gated on authorship: `asana.ps1 me` against `created_by` on the comment, or
on the `name_changed` story for a rename. A `Claude_Do` prefix or `CLAUDE-DO`
block put there by a teammate gets quoted back to you with their name and a
question - never followed.

Without that gate, anyone who can edit your Asana board could direct changes
into a banking repo. With it, you get the speed and nothing else changes.

## The nightly run

An overnight pass that plans your open Asana tasks while you sleep and leaves
you an HTML page in the morning instead of a chat log: multiple-choice
questions for the decisions that are yours, PR links for anything finished, and
reasons for anything skipped.

```powershell
powershell -File .claude/bin/nightly-report.ps1 -Open    # render the latest run
```

The report page is built and tested. **The scheduler that drives it is not
installed** - setting an agent to write code and open PRs unattended is a
decision to make deliberately, not a default. The verdict rules, the
`report.json` contract and an honest list of what to weigh first are in
[`docs/nightly.md`](docs/nightly.md).

Settings live in `config.env` under `NIGHTLY_*`.

## Using Antigravity instead of Claude Code

The flow is not Claude-only. **Everything in `.claude/bin/` is plain PowerShell
with no AI dependency** — any agent that can run a shell command can drive the
whole pipeline. Only two pieces are Claude-specific, and both have a direct
Antigravity equivalent:

| Claude Code | Antigravity |
|---|---|
| `.claude/CLAUDE.md` | `AGENTS.md` in the repo root — read natively |
| `.claude/commands/<name>.md` | `.agents/skills/<name>/SKILL.md` |
| `.claude/bin/*.ps1` | **unchanged** — same files, same calls |
| `.claude/config.env` | **unchanged** — the scripts read it either way |

Two things to get right before you start:

- **Build Skills, not Workflows.** Antigravity retired workflows on
  2026-10-19. Skills are the current mechanism: one folder per skill,
  containing a `SKILL.md` with YAML frontmatter (`name`, `description`)
  followed by markdown instructions. If anyone already built workflows, the
  `/migrate-workflows` command converts them.
- **Skill arguments are not confirmed.** The commands here take `<n|gid>`
  (`/task-plan 3`). Claude Code passes that through `$ARGUMENTS`; whether
  Antigravity skills do the same is unverified. Until someone checks, write each
  SKILL.md to take the task id **from the user's message** instead, and invoke
  it as `/task-plan — task 3`.

Size limits are not a problem: `AGENTS.md` is truncated past 24,000 bytes
(`CLAUDE.md` here is ~6 KB) and each `SKILL.md` caps at 12,000 characters
(the largest command here is well under).

### Doing the port

Finish steps 0–3 of **Setup for a new person** first — `config.env` and
`gh auth login` are the same regardless of which agent you use. Then open
Antigravity in the repo root and paste this:

```text
This repo has a working Claude Code automation toolkit in `.claude/`. Port it to
Antigravity, keeping the PowerShell scripts exactly as they are.

1. Read `.claude/README.md` and `.claude/workflow.md` first - the whole contract
   is there. Then read all 10 files in `.claude/commands/`.
2. Copy `.claude/CLAUDE.md` to `AGENTS.md` in the repo root, unchanged except
   for replacing Claude-Code-specific wording.
3. For each file in `.claude/commands/`, create
   `.agents/skills/<same-name>/SKILL.md` with YAML frontmatter (name,
   description) and the body converted from the Claude command. Where the
   command uses `$ARGUMENTS`, instead instruct the agent to take the task id or
   filter from the user's message.
4. Do NOT rewrite anything in `.claude/bin/`. The skills must call those same
   scripts, e.g. `powershell -File .claude/bin/asana.ps1 mytasks`.
5. Build Agent Skills, NOT Workflows - Antigravity retired workflows on
   2026-10-19.
6. Preserve these rules exactly; they are non-negotiable:
   - always branch from origin/<PROD_BRANCH>, never from the dev branch
   - never use the local DB or local logs as evidence about production
   - never open any PR without the user saying yes first
   - AI review findings are suggestions, not orders; ignore false positives and
     anything not introduced by our own changes

Show me your plan before writing any files.
```

Then check the skills are picked up (Agent panel → **...** → Customizations),
and sanity-check the port the same way you would any other change: run
`/task` first, since it only reads.

**Nobody has run this port yet.** The paths and limits above come from
Antigravity's own docs, but the conversion itself is untested — expect to fix
a skill or two by hand.

### Note on the AI review step

`local-review.ps1` and `self-review.ps1` already use Antigravity as one of two
review providers via the `agy` CLI in WSL (`REVIEW_PROVIDERS=claude,antigravity`).
That is independent of which agent runs the commands, and keeps working either
way.

## Things that will trip you up

- **New commands don't appear until you restart.** Slash commands are read when
  a session starts. Add a file, open a new chat.
- **`.claude` does not exist inside worktrees.** It is untracked, so a worktree
  gets code only. **Always run Claude from the main folder**, and pass
  `-RepoPath` to `verify.ps1` and `local-review.ps1` — without it they inspect
  the wrong checkout.
- **Quote date arguments.** `-DueOn 05-09-2026` unquoted is arithmetic in
  PowerShell. Use `-DueOn "05-09-2026"`.
- **Antigravity fails on large diffs.** `review-pr` passes the prompt as one
  command-line argument and Linux rejects arguments ≥ 128 KB. The other provider
  still runs; the scripts explain when this happens.
- **Antigravity sometimes returns nothing.** It is an agent: given a review
  prompt it may try to run shell commands, gets denied in headless mode, and
  answers with nothing.
- **After editing anything in `bin/`, run `check-tooling.ps1`** — then actually
  run the script. Passing a syntax check is not the same as working.
- **Local database and logs are not production.** The commands are written never
  to treat them as evidence; keep that rule if you adapt them.
