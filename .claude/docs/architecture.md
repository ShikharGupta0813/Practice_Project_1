# core-php architecture map

Read on demand, not auto-loaded. Facts verified against the code on
`onestackcbs`, September 2026. Where something is unresolved it says so rather
than guessing.

---

## 1. Framework and layout

- **CodeIgniter 3.1.10**, with **HMVC** via `third_party/MX` (wiredesignz).
  `application/core/MY_Router.php` is a one-line subclass of `MX_Router`.
- Two modules under `application/modules/`:
  - `cbs/` — core banking. 80 controllers, plus `models/` and `views/`.
  - `mobile_app/` — mobile and API surface. ~677 files.
- Non-module code sits in `application/controllers/` (`Auth.php`, `Homepage.php`,
  `admin/`, a few others), `application/models/` (104), `application/libraries/`.

## 2. `system/` IS modified — do not assume it is stock

CodeIgniter's core is normally untouchable, but here it is not.
`system/core/Router.php` (~line 170) has been patched to load extra route files:

```php
if (file_exists(APPPATH.'config/cbs-routes.php'))       { include(...); }
if (file_exists(APPPATH.'config/'.ENVIRONMENT.'/cbs-routes.php')) { include(...); }
```

Consequences:

- **Upgrading or reinstalling CodeIgniter would silently break all CBS routing.**
- Route resolution cannot be reasoned about from `application/` alone.
- Before concluding "framework behaviour is standard", check `system/core/`
  for other local patches.

## 3. Routing

Route definitions live in **four** possible places, all merged:

| File | Notes |
|---|---|
| `application/config/routes.php` | ~2,970 lines, the main file |
| `application/config/cbs-routes.php` | ~1,770 lines, loaded by the patched Router |
| `application/config/<ENVIRONMENT>/routes.php` | per-environment overrides |
| `application/config/<ENVIRONMENT>/cbs-routes.php` | per-environment overrides |

`ENVIRONMENT` comes from `$_SERVER['CI_ENV']` in `index.php`, defaulting to
`development`. Config directories present: `production`, `sandbox`, `public`,
`common`, `admin`.

**Practical rules:**
- Always grep BOTH main route files. A route may be in either.
- Later definitions overwrite earlier ones for the same key — an environment
  file can silently change a route's target.
- Routes point into modules, e.g.
  `$route['admin/get-soundbox-checker-details'] = 'mobile_app/configuration/SoundboxChecker/get_...'`
- Never read these files whole; grep for the specific route.

## 4. Controller hierarchy

`application/core/MY_Controller.php` defines four classes in one file:

```
CI_Controller
└── MY_Controller          (line 5)    — common bootstrap for everything
    ├── Auth_Controller    (line 318)
    │   └── Admin_Controller (line 92) — admin surface
    └── Public_Controller  (line 375)  — unauthenticated surface
```

Note the class order in the file is not the inheritance order; `Admin_Controller`
is declared before its parent.

### What `MY_Controller::__construct()` does on EVERY request

- Adds `third_party/ion_auth` to the package path; loads `ion_auth`,
  `form_validation`, `template`, `common/mobile_detect`.
- Loads `ProductMaster` and `PartnerMaster` libraries and immediately calls
  `load_and_cache_data()` on both. **Every request pays this cost.**
- Loads `PermissionService`.
- Mobile detection, populating `$this->data['mobile'|'ios'|'android']`.
- **Session timeout:** if `$_SESSION['__ci_last_regenerate']` is older than
  30 minutes, it destroys the session, logs out via ion_auth and redirects to
  `auth/login`. This is hand-rolled, not CI's session expiry.

### `Admin_Controller`

Requires `ion_auth->logged_in()` AND `ion_auth->is_admin()`. On failure:
- AJAX requests get an inline `<script>` redirect (not a 401/403).
- Normal requests redirect to `auth/login`.

Then loads admin config, `page_title`, `breadcrumbs`, `core_model`, menu helper
and admin language files.

## 5. Authorisation — `PermissionService`

`application/libraries/PermissionService.php`:
- `checkPermission($params = [], $redirect = true)`
- `deny($redirect)` (private)

### The known hole (tracked in Asana)

In `MY_Controller.php` around line 335+:

```php
if ($this->router->class === 'auth') { return; }   // auth controller skipped
$segment1 = $this->uri->segment(1);
$segment2 = $this->uri->segment(2);
if ($segment1 === 'admin') {
    if ($segment2 === 'homepage-view' || $segment2 === 'homepage') { return; }
    ... derives $url_slug and $url_action from the URL ...
}
```

The permission logic sits **inside** `if ($segment1 === 'admin')`. Any route
whose first URI segment is not `admin` never reaches the check. The slug and
action are derived from the URL by splitting `segment2` on `-` and treating the
last part as the action when it is one of `view|add|edit|delete`.

**Never assume a controller is protected because it extends `Auth_Controller`.
Check the actual URI shape.** Three additional fail-open paths (no access row,
slug not found, missing Referer) are covered by the same Asana task.

## 6. REST / API surface

`application/config/rest.php` drives `REST_Controller` subclasses.

Current live values — both tracked in Asana as CRITICAL:

```php
$config['rest_auth']         = FALSE;
$config['rest_valid_logins'] = ['admin' => '1234'];
$config['rest_enable_keys']  = FALSE;
```

Treat every REST endpoint as unauthenticated until that task ships.

## 7. Autoloading — large and eager

`application/config/autoload.php` autoloads a very large library list on every
request: the whole `npci_upi/*` family (Pay, ChkTxn, Mandate, BalEnq,
Complaint, ...), `npci_imps/*`, `npci_ibmb/*`, `npci_bbps_bou/*`,
`npci_ekyc/*`, transaction processors, worker factories, plus `database`,
`common/DbTable`, `common/Logger`, `common/CommonFunctions`, `OneStackCurl`.

Also autoloaded: helpers `alert, date_format, common, permission, url,
onestackcurl`; models `common/CommonModel`, `Npci_model`, `Ibmb_model`;
timezone forced to `Asia/Kolkata`.

**Implication:** a change to any autoloaded library affects every request in the
application. Treat edits there as high blast radius.

## 8. Payments / banking integrations

Visible from libraries, autoload and `third_party/`:

- **UPI / NPCI** — `npci_upi`, `npci_imps`, `npci_ibmb`, `npci_benedetails`
- **BBPS** — `npci_bbps_bou`, `bbps_indusind`, `bbps_kotak`, `bbps_npci`
- **eKYC** — `npci_ekyc`, `authbridge`
- **Cards** — `libraries/CardServices`
- **Gateways** — Razorpay (composer), billdesk, airtelUpi
- **Transaction processors** — `ITransactionProcessor` with implementations for
  cash-in, fund transfer, loan EMI / foreclosure / prepayment / other charges
- **AWS** — `AwsBucketFileTransfer`, `AwsBucketFunctions`, `AwsKMSFunctions`

## 9. Logging

- `application/libraries/AppLog.php`, `common/Logger`, config `applog.php`.
- Files under `application/logs/`, with subdirectories such as `logs/upi/`.
- `.gitignore:31` ignores `/application/logs/*`, so **log subdirectories do not
  exist on a fresh deployment** — the cause of the bare-`fopen()` TypeError
  batch in Asana.
- **Never log secrets or PII.** Open tasks exist for exactly this: Kotak OAuth
  client_id/secret written to `logs/upi/access-token-<date>.txt`, and
  credit-bureau request bodies (PAN/DOB/mobile).

## 10. Composer dependencies

`phpoffice/phpspreadsheet ^1.22`, `mpdf/mpdf ^8.0`, `google/apiclient 2.15.0`,
`christian-riesen/base32 ^1.6`, `miladrahimi/phpcrypt ^5.0`,
`stymiee/php-simple-encryption ^1.0`, `razorpay/razorpay 2.*`,
`guzzlehttp/guzzle ^7.8`, `flow/jsonpath ^0.5.0`.

Setup is `composer install` after clone. `vendor/` is present in the tree.

## 11. Branch topology — read before branching

- `onestackcbs` — production, and GitHub's default branch.
- `onestackcbs-dev` — **~5,109 commits AHEAD** of `onestackcbs`
  (`onestackcbs` has 1 commit not in dev).

**Always cut feature branches from `onestackcbs`.** A branch cut from
`onestackcbs-dev` and PR'd to production would carry ~5,100 unrelated commits.

905 files (490 PHP) differ between the two branches, so a file can look
materially different on each.

**This is deliberately NOT checked when planning.** All fixes are written
against PRODUCTION (`onestackcbs`) only. Dev is treated as a staging area, not
a second target. If a dev PR conflicts, Shikhar resolves it by hand — do not
contort a fix to suit both versions.

## 12. Open questions

Things not yet verified — do not assume either way:

- Whether the `system/core/Router.php` patch is the only core modification.
- Whether every environment config dir is actually deployed, or some are stale.
- How `sandbox`/`public` environments are selected in practice.


## 13. Code-graph tooling — trialled and removed

Graphify (tree-sitter knowledge graph) was installed, run over `application/`
(20,405 nodes / 35,913 edges), and then removed. Recorded so it is not
re-attempted without new reason.

**Why removed — grep matched it exactly, and faster:**

| Question | Graph | grep | grep time |
|---|---|---|---|
| Classes extending `REST_Controller` | 22 | 22 | 1.6s |
| Classes extending `Mobile_Controller` | 45 | 45 | 1.6s |
| Duplicate `checkPermission` definitions | 2 | 2 (+ a related third) | <1s |

**Costs it carried:**
- Scope had to be chosen and maintained (`application/` only; `assets/` with
  1,866 JS files, `siteload/`, `soundbox_ota/` were all excluded and would each
  have needed a decision).
- Rebuild ~142s even with a warm cache, manual, never automatic.
- Went stale on every `git pull`; needed its own staleness checker.
- Queries 30-180s each (22 MB reload) versus sub-second grep.
- Wrote a cache dir into the tracked `application/` tree.

**The fatal gap:** CodeIgniter's dynamic loading
(`$this->load->library('X')` then `$this->x->method()`) is invisible to static
AST analysis. `affected "PermissionService"` returned NOTHING while grep found
182 calling files. It could not answer "what calls this" — the question blast
radius actually depends on.

**Conclusion:** for this codebase, grep is complete, always current, and needs
no configuration. Use it.
