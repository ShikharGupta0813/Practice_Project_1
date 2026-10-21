# OneStack core-php — project guide

Loaded every session. Keep this SHORT and stable. Deep detail belongs in
`.claude/docs/` and is read on demand, not every chat.

## Stack

- **CodeIgniter 3.1.10**. NOTE: `system/core/Router.php` IS locally patched to
  load `cbs-routes.php` — `system/` is not stock. Do not assume framework
  behaviour is standard; see `.claude/docs/architecture.md`.
- **HMVC** via `MY_Loader`/`MY_Router`. Two modules under `application/modules/`:
  - `cbs/` — core banking (80 controllers)
  - `mobile_app/` — mobile/API surface (677 files)
- PHP with Composer deps: phpspreadsheet, mpdf, guzzle, razorpay, google/apiclient.
- ~4,300 PHP files, 104 models in `application/models/`.

## Setup

`composer install` after clone. XAMPP-based local stack; app root is the repo root.

## Environment

`index.php` reads `$_SERVER['CI_ENV']`, defaulting to `development`.
Per-environment config lives in parallel dirs:
`application/config/{production,sandbox,public,common,admin}/`.
**Check which env dir applies before changing any config value** — editing only
`application/config/foo.php` may not affect production.

## Controller hierarchy — `application/core/MY_Controller.php`

```
CI_Controller
└── MY_Controller
    ├── Auth_Controller
    │   └── Admin_Controller     <- admin surface
    └── Public_Controller        <- unauthenticated surface
```

Permission checks run via `application/libraries/PermissionService.php`.
**Known issue (tracked in Asana):** `checkPermission()` is called inside a
`segment(1) === 'admin'` conditional, so non-admin routes bypass it, and three
paths fail open. Do not assume a controller is protected because it extends
`Auth_Controller`.

## REST / API

`application/config/rest.php` drives `REST_Controller` subclasses.
**Known issue (tracked in Asana):** `rest_auth = FALSE` and
`rest_valid_logins = ['admin' => '1234']` are live. Treat every REST endpoint as
currently unauthenticated until that task ships.

## Routing

Routes are split across FOUR merged files — grep, never read whole:
- `application/config/routes.php` (~2,970 lines)
- `application/config/cbs-routes.php` (~1,770 lines)
- `application/config/<ENVIRONMENT>/routes.php` and `.../cbs-routes.php`

Check all of them before concluding an endpoint is unreachable; a later file
silently overwrites an earlier route of the same key.

## Conventions

- Match surrounding style: this is CI3-era procedural-flavoured PHP, not modern
  framework code. Do not introduce new patterns mid-file.
- DB access via CI query builder or raw SQL. **Parameterise raw SQL** — there is
  an open batch of injection fixes; do not add to it.
- Logging goes through `application/libraries/AppLog.php` and
  `application/logs/`. **Never log secrets, tokens, or PII** (PAN, DOB, mobile).
  There are open tasks removing exactly this.

## Git — read before branching

- **Always cut branches from `onestackcbs`**, NEVER from `onestackcbs-dev`.
  Dev is ~5,100 commits ahead; a dev-based branch makes the production PR
  unreviewable. This is a hard rule.
- Two PRs per task: dev PR to `onestackcbs-dev` first (`/task-do`), production
  PR to `onestackcbs` second (`/prod`, only when asked). **Neither PR is opened
  without the user saying yes.**
- Branch naming: `sg_cl_<name>`. See `.claude/workflow.md`.
- **One worktree per task**: `../oneStack-worktrees/sg_cl_<name>`, created from
  `origin/onestackcbs`, removed by `/task-status` once the PRODUCTION PR is
  merged. `.claude` exists only in the MAIN folder, so always run Claude from
  `C:\xampp\htdocs\oneStackLocal` and pass `-RepoPath <worktree>` to
  `verify.ps1` and `local-review.ps1`.

## Local environment is not production

The local XAMPP DB and `application/logs/` DIFFER from production. Never use
them as evidence for what production does. Read local source code freely; for
log/DB facts, give the user a read-only production command and wait.

**Production DB schema** (tables, columns, keys, indexes) is documented in the
Notion data dictionary — see `/task-plan`. Open it only when a task actually
needs schema facts, not on every plan.

## Deeper reference

`.claude/docs/architecture.md` — routing, auth, autoload, integrations, the
`system/` patch. Read it before planning anything non-trivial.

## Deliberate patterns — read before planning, changing or reviewing

`.claude/docs/known-patterns.md` lists things that look wrong but are
intentional (e.g. curl TLS verification off, `error_reporting(E_ERROR)`).
**Consistency rule:** write new code the way the neighbouring code of the same
kind does; never change a codebase-wide convention as a side effect of a task.
Review findings that contradict an entry are false positives. Add entries with
`/learn`.

## Settings

Per-person values (branch names, prefix, repo, worktree root, Asana token) live
in `.claude/config.env` — see `.claude/config.example.env` and
`.claude/bin/setup.ps1`. Branch names written in these docs are defaults, not
constants; read `config.env` when a value matters.

## Task automation

`/task`, `/task-plan`, `/task-do`, `/task-fix`, `/task-check`, `/prod`,
`/task-status`, `/task-resume`, `/standup`, `/learn`.
Contract in `.claude/workflow.md`. State in `.claude/plans/`.
Verification gate: `.claude/bin/verify.ps1`.
AI review (rules in `.claude/docs/self-review.md`):
`.claude/bin/local-review.ps1` reviews the branch **before** any PR exists, via
review-pr's own `--compare` mode (committed work only; `/task-do` uses this at
Step 5b so PRs arrive clean);
`.claude/bin/self-review.ps1` reviews an existing PR.
