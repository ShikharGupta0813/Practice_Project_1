---
description: List my open Asana tasks (optionally just the N soonest-due)
argument-hint: "[number of tasks, or filter text]"
---

List the user's open Asana tasks.

1. Decide what `$ARGUMENTS` is, and run the matching command:

   | `$ARGUMENTS` | Command |
   |---|---|
   | empty | `mytasks` |
   | a plain number N | `mytasks -Top N` |
   | `today` / `tomorrow` / `yesterday` | `mytasks -DueOn today` (etc.) |
   | a date (`05-09-2026`, `2026-09-05`) | `mytasks -DueOn "05-09-2026"` |
   | anything else | `mytasks`, then show only entries whose name or description contain the text (case-insensitive) |

   Full form: `powershell -File .claude/bin/asana.ps1 mytasks <args>`

   **Always QUOTE a date argument.** Unquoted, PowerShell evaluates
   `05-09-2026` as arithmetic before the script sees it.

   Task numbers come from the full task list, so a filtered view shows its real
   numbers (4, 5, 6 rather than 1, 2, 3). That is intended — `/task-plan 5`
   keeps working. Never renumber them.

2. If the script exits non-zero, show the actual error text and STOP. Do not
   fall back to another method and do not invent a list.

3. **Reproduce the ENTIRE task list in your reply, verbatim.**

   The user CANNOT see tool output — in their UI it collapses to a single line
   like "Listed 15 soonest-due Asana tasks". If you do not paste the list into
   your own message, they see NOTHING but your closing analysis. This has
   already happened once; do not repeat it.

   Copy the script's output exactly: every task, its number, name, ID, Due,
   "Part of", and description line. Do not restyle it, do not turn it into a
   table, do not re-number it, do not summarise it, do not add severity labels,
   and do not skip entries to save space. If the list is long, it is still
   printed in full.

   The response is: the full list first, then the closing analysis. Never the
   analysis alone.

4. Then add a closing analysis, in exactly these three blocks. Keep each line
   short. Leave a block out entirely if it has nothing real in it — never pad.

```
Can be done together (same files or same fix):
- <numbers>: <the shared thing, few words>

Must be done in order (one depends on another):
- <number> then <number>: <why the first has to land first>

Do on its own (risky or unrelated):
- <number>: <why it should not be batched>

Tell me which to plan - by number, by name, or several at once.
```

5. Then add a SECOND, separate box below that one, with rough time estimates:

```
Rough time to do:
- <numbers>: <estimate> - <why, few words>
- <numbers>: <estimate> - <why, few words>
```

Rules for the estimate box:
- **A separate box from the analysis.** Do not merge them.
- Use plain ranges: `few lines, under an hour`, `half a day`, `1-2 days`,
  `3-5 days`, `a week or more`.
- Group tasks with the same estimate on one line rather than repeating.
- Base it on: how many files change, whether it touches auth/money/customer
  data, whether it needs coordination or review, and whether the scope is
  actually known. A task naming one `file.php:line` is small; one saying
  "eleven sites" or "thirteen patterns" is not.
- If the scope cannot be judged from the title, say `unknown until planned`
  rather than inventing a number.
- These are ROUGH. Say so once, at the end: `Estimates are rough - planning
  will sharpen them.`
- Cover every task shown. No other commentary.

Rules:
- **Keep the three kinds separate.** Do not merge "do together" and "do in
  order" into one list — they mean different things. Two tasks touching the
  same file get ONE branch; two tasks where one depends on the other get
  SEPARATE branches in sequence.
- "Can be done together" = same file, or the same kind of fix in one area.
  Same file is the strongest reason, since those must share a branch anyway.
- "Must be done in order" = doing the second before the first would be wrong,
  wasted, or would break something. Say which comes first and why.
- "Do on its own" = touches authentication, permissions, money, or customer
  records; or is large enough to need its own review. Keep this short.
- At most 3 bullets per block. If nothing genuinely groups, write
  `Nothing here obviously overlaps.` and drop the blocks.
- No branch names, no severity ranking, no advice on what to do first, no
  commentary on the tasks themselves.

Nothing else goes in the response. Do not read source files, do not plan, do
not spawn agents.
