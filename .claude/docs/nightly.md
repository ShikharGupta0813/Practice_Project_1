# The nightly run

Use the evening hours to plan tomorrow's tasks, so the morning starts with
decisions to make rather than tasks to read.

The idea: at a fixed time a Claude session wakes up, works through your open
Asana tasks, writes a plan for each one, and sorts them into three piles —
ready to run, blocked on a decision you have to make, and not safe to plan
tonight. You get an HTML page, not a chat transcript.

**Status: half-built.** The report page is finished and tested. The scheduler
that drives it is not, and the reason is worth reading before you set it up —
see [Why the scheduler is not installed](#why-the-scheduler-is-not-installed).

---

## What you see in the morning

`.claude/plans/nightly/<date>/report.html` — a self-contained page (no network,
no CDN, opens from `file://`) with three sections:

**Your decisions.** Every question as multiple choice, 2-4 options, one marked
*suggested* with a one-line reason. You click. The page remembers your answers
in the browser, so you can close it and come back. The button at the bottom
copies a paste-ready block:

```
/task-plan 1217811081134142 - my answers: q1=A, q2=B. Update the plan with
these, then run /task-do 1217811081134142.
```

Paste that into Claude and the task carries on from where it stopped.

**Done while you slept** — what was finished, with the PR link.

**Skipped** — what could not be planned, and why.

Nothing in the page requires reading a chat log. That is the whole point.

---

## The three verdicts

Every task lands in exactly one pile. The rules are deliberately strict,
because a task wrongly marked AUTO costs far more than one wrongly marked ASK.

**AUTO** — all of these must hold:

- the plan has no open questions and no assumption that could flip the design
- every fact is verifiable from source code in this repo alone
- it touches at most `NIGHTLY_AUTO_MAX_FILES` files (default 6)
- no DB schema change, no migration, no new dependency
- no change under `application/config/<environment>/` for any environment
- it does not touch authentication, permission, session, payment, settlement
  or transaction-posting logic
- it does not need production logs or production DB rows as evidence

**ASK** — the work is clear but a decision is yours. Becomes multiple choice.

**SKIP** — unclear, needs production evidence, needs someone else, or too big.

When torn between AUTO and ASK, the answer is ASK.

That list is not decoration. This is a core banking system, and the two
categories that cause real damage — auth logic and money movement — are
excluded by name rather than left to judgement.

---

## report.json

The renderer reads this and nothing else. Anything that can produce this shape
can drive the page.

```json
{
  "date": "2026-10-20",
  "startedAt": "2026-10-20 21:00",
  "repo": "OneStackIndia/core-php",
  "devBranch": "onestackcbs-dev",
  "planOnly": false,
  "dryRun": false,
  "tasks": [
    {
      "gid": "1217811081134142",
      "name": "Block unauthorized access to admin reports",
      "verdict": "AUTO|ASK|SKIP",
      "confidence": "high|medium|low",
      "reason": "one sentence, plain English, why this verdict",
      "summary": "two sentences: what is wrong, and what the change does",
      "files": 4,
      "risk": "low|medium|high",
      "questions": [
        {
          "id": "q1",
          "text": "What should a user without permission see?",
          "options": [
            {"key": "A", "text": "A 403 page saying access denied"},
            {"key": "B", "text": "Redirect to their dashboard silently"}
          ],
          "recommend": "A",
          "why": "matches how the rest of the admin surface behaves"
        }
      ],
      "planned": true,
      "executed": false,
      "branch": "",
      "pr": "",
      "planLog": "",
      "doLog": ""
    }
  ]
}
```

`questions` is `[]` for AUTO and SKIP. `reason` and `summary` are read
half-awake: short sentences, no jargon, no file paths.

Render it:

```powershell
powershell -File .claude/bin/nightly-report.ps1 -RunDir .claude/plans/nightly/2026-10-20
powershell -File .claude/bin/nightly-report.ps1            # most recent run
powershell -File .claude/bin/nightly-report.ps1 -Open      # and open it
```

The script only formats. It reads JSON and writes HTML; it touches nothing
else, so it is safe to re-run at any time.

---

## Settings

In `.claude/config.env`:

| Key | Default | What it does |
|---|---|---|
| `NIGHTLY_MAX_TASKS` | `4` | how many tasks one night may touch |
| `NIGHTLY_AUTO_MAX_FILES` | `6` | above this, AUTO is downgraded to ASK |
| `NIGHTLY_OPEN_DEV_PR` | `false` | whether a finished task may open its dev PR |
| `NIGHTLY_TIMEOUT_MINUTES` | `25` | per task, per phase |

`NIGHTLY_OPEN_DEV_PR` defaults to **false** on purpose. Turning it on means a
PR appears in the team's repo with nobody awake — see below.

---

## Why the scheduler is not installed

Two attempts were made to build the part that runs this on a timer. Both were
refused by Claude's own safety classifier, under "Create Unsafe Agents":

1. A PowerShell orchestrator that launched headless `claude -p` sessions with
   permission prompts disabled.
2. A desktop scheduled task doing the same work — including a reduced version
   that only planned and never wrote code.

The refusal is not arbitrary. What was being built is an agent that writes code
and opens pull requests in a production banking repository with no human
present, and an assistant setting that up for itself is the exact thing the
guard exists to prevent.

**Setting it up yourself is a different matter.** It is your repository and your
account, and the desktop app has a scheduled-tasks UI built for this. The
material you need is in this document: the verdict rules, the JSON contract, and
the renderer. What follows is what to weigh before you do.

### What to weigh

- **Unattended PRs break a rule you wrote.** `workflow.md` says neither PR is
  opened without you saying yes. An overnight run that opens dev PRs overrides
  that. Start with `NIGHTLY_OPEN_DEV_PR=false` — you still get branches and
  commits to look at, and you open the PR yourself in the morning.
- **Start plan-only.** A week of planning-only runs tells you how good the
  verdicts are before anything is allowed to write code. If the AUTO pile keeps
  containing things you would not have approved, the rules need tightening, not
  the cap raising.
- **Keep the cap low.** Four tasks is not timidity. A bad night with a cap of
  four is four branches to delete.
- **Scheduled tasks only run while the desktop app is open.** If the app is
  closed when 9 PM passes, the run happens at next launch instead. A laptop
  asleep at 9 PM runs nothing.
- **Review the diffs, not the summaries.** The report says what Claude believes
  it did. The diff says what it did.

### The least-risk version

If you want only the part that pays off while you sleep, schedule the planning
and keep execution in your hands:

- the run calls `/task-plan` only, never `/task-do` or `/prod`
- it writes nothing outside `.claude/plans/`
- it creates no branches, no commits, no PRs

You still wake up to finished plans and a page of multiple-choice questions.
What you lose is waking up to finished PRs; what you gain is that nothing
reached the repository without you.
