---
description: Everything that moved since yesterday morning, with each task's Asana, dev PR and prod PR status
argument-hint: "[a start date like 17-09-2026; default: yesterday, or Friday on a Monday]"
---

Produce the standup update: **every activity from the start of yesterday until
right now**, grouped by task, with each task's current status.

## Step 1 — decide the window

- Default: from **yesterday 00:00 until now**.
- **Monday rule:** if yesterday was Saturday or Sunday, start from the most
  recent **Friday** instead, and say which day you started from.
- If `$ARGUMENTS` gives a start date, start from that date instead.

The end is always now. Passing `-Until tomorrow` means "until the end of
today", which in practice is "until now":

```
powershell -File .claude/bin/asana.ps1 activity -Since yesterday -Until tomorrow
```

For a specific start date, quote it: `-Since "18-09-2026" -Until tomorrow`
(unquoted, PowerShell does the arithmetic before the script sees it).

This lists every task assigned to the user with activity in the window —
comments, assignments, due-date changes, completions — each with its time,
plus the task's Asana `Status` field when it is set.

## Step 2 — PR status for each task

For every task in the Asana output, look up its PRs. PR titles end with the
Asana gid and bodies carry `Asana: <gid>`, so search by gid:

```bash
gh pr list --repo OneStackIndia/core-php --state all --search "<gid>" --json number,title,state,baseRefName,mergedAt,createdAt,url
```

- base `onestackcbs-dev` -> **Dev PR**; base `onestackcbs` -> **Prod PR**.
- State: open / merged (with date) / closed-unmerged.
- Older PRs may not carry the gid. Fall back to PR links in the task's
  comments ("Dev PR : https://...") and to `.claude/plans/_batch.json`.

Then catch PR activity that has **no** Asana activity — PRs the user created
or that got merged inside the window:

```bash
gh pr list --repo OneStackIndia/core-php --author "@me" --state all --limit 40 --json number,title,state,baseRefName,createdAt,mergedAt,url
```

Keep those whose `createdAt` or `mergedAt` falls in the window and attach
them to their task (gid at the end of the title), or list them separately if
no task matches.

## Step 3 — write it

Output exactly this shape:

```
Standup - <Weekday D Month>   (activity since <Weekday D Month> 00:00)

1. <short task name> (<gid>)
   Asana: <Status field, or "no status set">   <COMPLETED if completed>
   Dev PR: #<n> <open|merged D Mon|closed>    Prod PR: #<n> <state> | none
   Activity:
   - <Day HH:MM> <who>: <what happened, plain words>
   - ...
   So: <one plain sentence - where this task stands now>

2. ...

PRs with no Asana activity: #<n> <title> (<state>)        <- omit if none
Waiting on me: <things>                                    <- omit if none
Waiting on others: <reviews / merges / answers>            <- omit if none
```

## Rules

- **Show every activity** from the Asana output — nothing is summarised away.
  Only Asana's automatic "you have a task due" reminders are already dropped.
- **Shorten task names.** `CRITICAL - Parameterise the eleven raw-SQL sites in
  §3.3 (numeric-context SQL injection)` becomes `SQL injection fixes`. Keep the
  gid.
- Rewrite activity lines into plain words: "Dev PR : https://.../13237" ->
  "opened Dev PR #13237"; "changed the due date to Friday" -> "moved the due
  date to Fri 25 Sep". Say who did it — "you" for the user, names for others.
- The `So:` line states **where the task stands**, not what was done:
  "Dev PR merged, prod PR not opened yet" — not "worked on it".
- Never invent progress. A task that only had its due date moved says exactly
  that.
- If nothing happened in the window: `Nothing moved since <day>.` and stop.
- No advice or next steps unless asked.
