---
description: Remember a deliberate pattern so plans, fixes and reviews stop treating it as a bug
argument-hint: "<what is deliberate, in your own words>  (empty = learn from the last correction in this chat)"
---

Record a deliberate pattern in `.claude/docs/known-patterns.md`.

## What to learn

- If `$ARGUMENTS` is given, that is the pattern, in the user's own words.
- If it is empty, learn from the **most recent correction the user made in this
  conversation** (e.g. "no, that's intentional", "we always do it this way").
  If there is no such correction, ask what to learn and stop.

## Step 1 — read the existing list

Read `.claude/docs/known-patterns.md` first. If an entry already covers this,
**update that entry** instead of adding a duplicate. If the new pattern
contradicts an existing one, show both and ask which is right. Stop.

## Step 2 — check it against the code (evidence, not assumption)

The user is usually right about how the team works, but the entry must be
precise, so verify before writing. Follow the evidence rules in
`/task-plan` (Step 2b): whole-word matches, eyeball the hits, separate raw hits
from real usages, never quote an unverified count.

1. **How widespread is it?** Search the whole repo for the pattern and count
   it — with the opposite case too, so you know the split.
   Example for "we don't verify TLS on curl":
   ```bash
   git grep -hoE "CURLOPT_SSL_VERIFYPEER\s*(,|=>)\s*[A-Za-z0-9]+" -- 'application/*.php' | sort | uniq -c
   ```
2. **Where is it?** Group by module/folder. A pattern that holds in `cbs/` may
   not hold in `mobile_app/`.
3. **What are the exceptions?** Find every place that does it the *other* way,
   with `file:line`. Exceptions are often deliberate too — record them so
   nobody "normalises" them.
4. **Check shared helpers.** If there is a central helper for this kind of code
   (e.g. `libraries/OneStackCurl.php` for curl), check what *it* does — calls
   through it may follow different rules than raw calls.
5. **Was it done on purpose? Look at past commits.**
   ```bash
   git log -S "<distinctive code>" --oneline --reverse -- application/ | head
   git log --grep "<keyword>" -i --oneline | head
   ```
   A commit that deliberately introduced or kept it (its message says why) is
   the strongest evidence. Quote it.

If the evidence **contradicts** what the user said — e.g. they say "all CBS
calls skip TLS" but half of them verify — do not write the entry. Show the
numbers and ask. Stop.

## Step 3 — write the entry

Append (or update) in this exact shape:

```markdown
## <short name of the pattern>

- **Looks wrong:** <why a reviewer or AI would flag it>
- **Actually:** <why it is this way / that it is the team's norm>
- **Rule:** <what to do - usually "match the neighbouring code of the same
  kind; don't change it unless the task is about it">
- **Exceptions:** <file:line of places that deliberately differ, or "none found">
- **Evidence (<date>):** <the search you ran and the counts; commit hashes>
- **Added:** <date>, from <the user / the review of PR #n / task gid>
```

Rules:
- Every pattern is subject to **the consistency rule** at the top of the file —
  don't restate it in each entry.
- Plain, short lines. This file is read by every plan, fix and review, so
  padding costs every future task.
- Never write secrets, tokens, customer data or real credentials into it.

## Step 4 — confirm in chat

Reply with only:

```
Learned: <short name>
<the Rule line>
Evidence: <one line - counts / exceptions>
```

Do not change any code. This command only updates the patterns file.
