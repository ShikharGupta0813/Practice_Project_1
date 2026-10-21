# Remove every fopen log write, route all logging through a helper

Asana: **no task yet** — see "Open question" at the end.
Related: task 1217811081134142 (log directories on fresh deploy), dev PR 13081.

User direction: no `fopen` writing logs anywhere in the codebase; logging goes
through `writeLog` or an equivalent helper; the outcome must be that
`index.html` placeholder files are no longer needed. Size of the change is
explicitly accepted.

---
# PART 1 — In simple words

## What the system does today

The system writes diaries of what it does — 97 folders' worth. Two different
habits exist side by side for doing that.

The tidy habit is a shared helper called `writeLog`. You hand it what you want
recorded and it deals with the file.

The untidy habit is for each piece of code to open the file itself, write to
it, and close it. That happens in **1,106 places across 150 files**.

## What is wrong with it

The untidy habit has three problems.

It does not create the folder it writes into. If the folder is missing the
write fails and nothing says so — the line just vanishes. That is the bug we
already fixed once, by shipping all 97 folders with the code. But that fix
needs a small placeholder file in every folder, and it needs a **new**
placeholder every time anyone adds a folder. Somebody will forget.

It leaks. In four files, a log file is opened and never closed.

And it is scattered. There is no single place to change how logging behaves,
because logging is written out longhand in 1,106 places.

## What we are going to change

Add one small helper that writes a line to a log file and creates the folder
first if it is missing. Then replace all 1,106 hand-written blocks with a call
to it.

After that, folders create themselves the moment they are needed. No
placeholder files, ever again — including for folders nobody has invented yet.

## What could go wrong

The honest risks:

**The logs could change shape.** Support staff and monitoring read these files.
This plan deliberately keeps every log's content, filename and extension
exactly as they are today, so nothing that reads them notices. That is the
single most important constraint and it drives the whole design.

**Twenty-one places overwrite rather than add to their file.** If those were
converted carelessly they would start growing forever instead of resetting.
They are handled separately.

**It is a lot of files.** 150 of them. Mistakes hide in volume, so the work is
split into reviewable batches rather than one enormous change.

**Nothing about this fixes a live bug.** The missing-folder bug is already
fixed by dev PR 13081. This is about making sure it never returns and removing
the placeholder-file chore. Worth being clear so the risk is judged on that
basis, not as an emergency.

---
# PART 2 — The words used here

| Word | What it means, simply |
|---|---|
| `fopen` / `fwrite` / `fclose` | The longhand way to write to a file: open it, write, close it. Three steps, easy to get wrong. |
| Helper | A shared piece of code many places can call, so the same job is written once instead of 1,106 times. |
| Append vs truncate | Append adds to the end of a file. Truncate empties it first. Confusing the two either loses history or lets a file grow without limit. |
| Handle leak | Opening a file and never closing it. The system keeps the file reserved; enough of them and it runs out. |
| `index.html` placeholder | A tiny file used only so an otherwise-empty folder travels with the code. The thing this task removes the need for. |

---
# PART 3 — The technical version

## Root cause

Two logging idioms coexist. `writeLog()`
(`application/helpers/common_helper.php:1776`) is the sanctioned one and, since
dev PR 13081, creates its target directory. The other is longhand `fopen` /
`fwrite` / `fclose`, which does not.

Measured on `onestackcbs`, excluding commented lines and `bkp` files:

```
1,106  fopen sites whose literal path starts ./application/logs/
  150  distinct files
1,430  fwrite calls in those files
```

Path shape is consistent — `./application/logs/` then an optional
sub-directory, then a name usually ending in a date:

```php
fopen("./application/logs/mobile-api/generateAuthToken-log-". date('Y-m-d') . ".php", "a");
fopen("./application/logs/firebase-dynamic-link/firebase-dynamic-link-api-log-" . date('Y-m-d') . ".php", "a");
fopen("./application/logs/center-onboarding-form-" . date('Y-m-d') . ".php", "a");
```

Distribution that matters for the conversion:

```
extension : 932 .php   155 .txt   13 .csv   6 .log
mode      : 1085 "a" (append)   21 "w" (truncate)
location  : 838 into a sub-directory   268 into the logs root
or die(   : 3 sites
```

**Unclosed handles** — four files open more log files than they close:

```
application/libraries/workers/annual_reports/AnnualReports.php   fopen=6  fclose=3
application/modules/cbs/controllers/CronMisReports.php           fopen=31 fclose=29
application/modules/mobile_app/controllers/upi-qr/UpiQr.php      fopen=35 fclose=34
application/third_party/cbs/libraries/Cbs.php                    fopen=16 fclose=15
```

Pre-existing resource leaks; the conversion removes them as a side effect.

**The `.csv` sites are logs, not data exports.** All 13 are named `...-log-...`
— CSV-formatted error logs (`csv-error-yesbank-log-`,
`incomplete-data-yesbank-log-`). They are in scope. This was checked because
excluding them would otherwise have been the safe assumption.

## How it will be fixed

**The key decision: preserve format, do not normalise it.**

The obvious approach — convert every site to `writeLog($array, $folder, $file)`
— was rejected. `writeLog` emits a single pipe-delimited line into a
`<name>-<date>.log` file:

```
|07-09-2026 09:51:49|api_name:equifax-cbr|status:ok|
```

whereas **149 of the 150 files** build multi-line blocks by hand:

```php
$txt1  = "\n-----------------------------------------------------------------------";
$txt1 .= "\nLog Date and Time: " . date('d-m-Y H:i:s') . "\n";
$txt1 .= "api_name : " . $api_name . "\n";
fwrite($myfile, $txt1);
```

Converting those would change the content of every log file, rename 932 files
from `.php` to `.log`, and require a per-site judgement about what becomes a
key and what becomes a value. That is 1,106 opportunities to get it wrong, for
no functional gain.

Instead, add a raw-text sibling to `writeLog` in
`application/helpers/common_helper.php`:

```php
if (!function_exists('writeLogRaw')) {
    /**
     * Append raw pre-formatted text to a file under application/logs,
     * creating the directory first. Replaces hand-rolled
     * fopen/fwrite/fclose blocks so that a missing directory cannot
     * silently discard the write.
     *
     * $relativePath is everything after application/logs/, including any
     * sub-directory and the extension, so existing filenames are preserved
     * exactly.
     */
    function writeLogRaw($text, $relativePath, $mode = 'a')
    {
        $filePath = './application/logs/' . ltrim($relativePath, '/');

        $dir = dirname($filePath);
        if (!is_dir($dir)) {
            mkdir($dir, 0755, true);
        }

        $flags = ($mode === 'w') ? LOCK_EX : (FILE_APPEND | LOCK_EX);

        return file_put_contents($filePath, $text, $flags);
    }
}
```

Conversion then becomes mechanical and lossless:

```php
// before
$myfile = fopen("./application/logs/mobile-api/generateAuthToken-log-". date('Y-m-d') . ".php", "a");
fwrite($myfile, $txt);
fclose($myfile);

// after
writeLogRaw($txt, "mobile-api/generateAuthToken-log-". date('Y-m-d') . ".php");
```

Same directory, same filename, same extension, same bytes. What changes: the
directory is created if absent, the handle cannot leak, and there is one place
to change logging behaviour in future.

Handling of the awkward cases:

- **21 truncate sites** — pass `'w'` explicitly as the third argument.
- **3 `or die(...)` sites** — `or die()` on a logging call is inappropriate in a
  banking request path; replaced with the helper's return value being ignored,
  matching every other logging call. Called out individually in review.
- **Multi-`fwrite` handles** (1,430 writes vs 1,106 opens) — where consecutive
  writes share a handle, concatenate into one string and make one call.
- **~8 files writing inside a loop** (`CustomerAccountImport.php`,
  `CustomerMaster.php`, `Cron.php`, `CustomerProfileManagement.php`,
  `CbsCustomerAccountImport.php`, `Cbs_pay_credit.php`,
  `Npci_upi_RespAuthDetails.php`, `NpciNonFinancialCron.php`) — accumulate into
  a buffer and write once after the loop, so the file is not reopened per
  iteration.

**Then the placeholder files go.** Once no code path depends on a
pre-existing directory, the 98 `index.html` files added by PR 13081 are
removed, and `.gitignore` returns to ignoring the whole `application/logs`
tree. Directory-listing protection is preserved by a **single**
`application/logs/.htaccess` containing `Require all denied`, which covers every
sub-directory including future ones — one file instead of 98, and stronger,
since it blocks `.txt` and `.csv` which the root `.htaccess` deny-list does not.

**Finally, a CI guard** in `.github/workflows/pr-quality-check.yaml` that fails
any PR *adding* an `fopen`/`file_put_contents` targeting `application/logs/`.
Inspects added lines only. Without this the count starts climbing again the
week after this merges, and the whole exercise is wasted.

## Files and scope

| File | What changes |
|---|---|
| `application/helpers/common_helper.php` | Add `writeLogRaw()` (~20 lines) |
| 150 files across `application/` | Replace 1,106 `fopen`/`fwrite`/`fclose` blocks with `writeLogRaw()` calls |
| `application/logs/**/index.html` | 98 files deleted |
| `application/logs/.htaccess` | New, 1 line |
| `.gitignore` | Revert the log rules to a simple whole-tree ignore |
| `.github/workflows/pr-quality-check.yaml` | Add the guard step |

Roughly **1,106 call sites, 152 files touched, ~250 files changed** counting the
98 deletions. **Large** — this is the biggest change in the current batch by an
order of magnitude.

**Evidence**

```
grep -rnE "fopen\s*\(\s*[\"']\.?/?application/logs/" --include=*.php application/ \
  | grep -vE ":[0-9]+:\s*(//|#|\*)" | grep -v bkp
-> 1,106 sites / 150 files
inspected: sampled ~25 across CommonFunctions.php, npci_upi, third_party/yesbank,
   mobile-api and the cbs controllers; all genuine uncommented log writes.

extensions : grep -oE "\.(php|log|txt|csv)\"" -> 932 / 6 / 155 / 13
modes      : grep -oE '"(a|w)"\s*\)'          -> 1085 append / 21 truncate
fwrite     : 1,430 across the same 150 files
or die(    : 3
```

Not verified: whether any of the 1,106 sites is reached by a code path that
depends on the file handle beyond the write itself (e.g. passed to another
function). Sampling found none, but 1,106 sites were not each read. The batch
review in the Plan below is where that gets caught.

## Plan

Executed as **one branch, many commits** — one commit per batch, so review can
proceed batch by batch while the change lands atomically.

1. `git checkout onestackcbs && git pull origin onestackcbs`
2. `git checkout -b sg_cl_fopen_to_writelograw`
3. Commit 1 — add `writeLogRaw()` to `common_helper.php`. Nothing calls it yet.
4. Commits 2-N — convert in batches, ordered lowest-risk first so the pattern is
   proven before it reaches payment code:
   - batch A: `application/libraries/` (non-npci)
   - batch B: `application/modules/mobile_app/controllers/` excluding npci/upi
   - batch C: `application/modules/cbs/`
   - batch D: `application/third_party/`
   - batch E: `application/libraries/npci_*` and `npci-upi` controllers — the
     payment paths, converted last and reviewed hardest
   Within each batch: convert, then run the per-batch checks below.
5. Commit N+1 — the 21 truncate sites, isolated in their own commit so the
   `'w'` argument is visible to a reviewer rather than buried.
6. Commit N+2 — the ~8 loop sites, buffered.
7. Commit N+3 — delete the 98 `index.html` files, add
   `application/logs/.htaccess`, revert the `.gitignore` log rules.
8. Commit N+4 — the CI guard.
9. Full verification pass, then push and open the DEV PR.

## How to test

**Per batch, before moving on:**

```
powershell -File .claude/bin/verify.ps1
```

Expect `RESULT: PASS`. Every batch touches PHP, so this is a real gate here.

```
git diff --numstat onestackcbs -- <batch path> | awk '{a+=$1; d+=$2} END {print a" added, "d" deleted"}'
```

Deletions should be roughly 3× the fopen count for that batch (open + write +
close) and additions roughly 1×. A large mismatch means something other than a
log write was altered.

**Whole-change checks, before the PR:**

1 — no `fopen` targeting logs survives:

```
grep -rnE "fopen\s*\(\s*[\"']\.?/?application/logs/" --include=*.php application/ \
  | grep -vE ":[0-9]+:\s*(//|#|\*)" | grep -v bkp
```

Expect **zero output**.

2 — no orphaned `fwrite`/`fclose` left behind on a removed handle:

```
php -l on every changed file (covered by verify.ps1)
grep -rn "fwrite(\$myfile" --include=*.php application/ | wc -l
```

Expect `0` for the second, since `$myfile` is the dominant handle name.

3 — filenames are unchanged. Extract every path literal before and after and
diff the sets:

```
git show onestackcbs:<file> | grep -oE "application/logs/[^\"']*" | sort -u > /tmp/before.txt
grep -oE "application/logs/[^\"']*" <file> | sort -u > /tmp/after.txt
diff /tmp/before.txt /tmp/after.txt
```

Expect no differences across the whole change. **This is the most important
check in the plan** — it is what proves no log changed name, location or
extension.

4 — the 21 truncate sites kept truncate semantics:

```
grep -rn "writeLogRaw(.*, *'w')" --include=*.php application/ | wc -l
```

Expect `21`.

5 — behavioural test of the helper itself, run directly:

```bash
# a nested directory that does not exist
php -r "require 'application/helpers/common_helper.php'; ..."
```
Assert: directory created, file written, content byte-identical to what the
old `fopen`/`fwrite` pair produced for the same input, and `'w'` truncates
while the default appends.

6 — logs still land, end to end. Exercise one converted path locally and
confirm the file appears with the expected name and content.

7 — placeholders are gone and protection remains:

```
git ls-files application/logs/ | grep -c index.html    -> expect 0
git ls-files application/logs/.htaccess                -> must print the path
```

8 — the CI guard actually fires. Push a throwaway commit adding an `fopen` into
`application/logs/` and confirm the workflow fails, then drop it.

**Production, read-only, after deployment:** confirm log files are still being
written with their existing names:

```bash
ls -lt /var/www/vhosts/onestack-app-prod/application/logs/ | head -20
ls -lt /var/www/vhosts/onestack-app-prod/application/logs/npci/ | head -10
```

Timestamps must be current. A directory that stops receiving files means a
converted path is wrong.

## Needs human review

`yes` — 1,106 call sites across the payment, UPI, NPCI and customer-import
paths. No single change is risky, but the volume means a reviewer must confirm
the filename-preservation check (test 3) passed rather than reading every hunk,
and must look closely at batch E, which touches live payment code.

## Open question

This has no Asana task. It is a follow-up to 1217811081134142 rather than part
of it — that task's fix is already in dev PR 13081 and should not be held up by
this. Needs either its own task, or an explicit decision to track it under the
existing one.

**Recommendation: let PR 13081 merge first, unchanged.** It fixes the live bug
now, is already reviewed, and this migration then removes the 98 placeholder
files it added as its final commit. Rewriting 13081 to wait for a 150-file
migration would leave the silent-log-loss bug open for however long this takes.
