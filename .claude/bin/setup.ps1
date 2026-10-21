# First-run setup and health check.
#
#   powershell -File .claude/bin/setup.ps1          # create config.env, check everything
#   powershell -File .claude/bin/setup.ps1 -Check   # only check, create nothing
#
# Creates .claude/config.env from config.example.env if it is missing, then
# reports what works and what still needs doing. Never asks for a token and
# never prints one.

param(
    [switch]$Check
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\config.ps1"

$claudeDir = Split-Path $PSScriptRoot -Parent
$repoDir   = Split-Path $claudeDir -Parent
$problems  = @()
$warnings  = @()

function Say([string]$state, [string]$what, [string]$detail = '') {
    Write-Output ("  {0,-8} {1}{2}" -f $state, $what, $(if ($detail) { " - $detail" }))
}

Write-Output "`nSetup check for the Asana -> PR automation`n"

# --- config.env -------------------------------------------------------------
$configFile  = Join-Path $claudeDir 'config.env'
$exampleFile = Join-Path $claudeDir 'config.example.env'

if (-not (Test-Path $configFile)) {
    if ($Check) {
        Say 'MISSING' 'config.env' 'run this script without -Check to create it'
        $problems += 'config.env does not exist'
    }
    elseif (Test-Path $exampleFile) {
        Copy-Item $exampleFile $configFile
        Say 'CREATED' 'config.env' 'from config.example.env - open it and fill it in'
        $warnings += 'config.env was just created: edit it before using the commands'
    }
    else {
        Say 'MISSING' 'config.example.env' 'cannot create config.env'
        $problems += 'config.example.env is missing from .claude/'
    }
}
else {
    Say 'OK' 'config.env' 'found'
}

$cfg = Get-ClaudeConfig

Write-Output "`nSettings in use:"
foreach ($key in @('GITHUB_REPO', 'PROD_BRANCH', 'DEV_BRANCH', 'BRANCH_PREFIX', 'WORKTREE_ROOT', 'PHP_BIN', 'REVIEW_PROVIDERS')) {
    Write-Output ("  {0,-18} {1}" -f $key, $cfg[$key])
}
Write-Output ("  {0,-18} {1}" -f 'DB_SCHEMA_DOC', $(if ($cfg.DB_SCHEMA_DOC) { 'set' } else { '(none)' }))

# --- tools ------------------------------------------------------------------
Write-Output "`nTools:"

if (Get-Command git -ErrorAction SilentlyContinue) { Say 'OK' 'git' }
else { Say 'MISSING' 'git'; $problems += 'git is not installed' }

if (Get-Command gh -ErrorAction SilentlyContinue) {
    $ghState = (& gh auth status 2>&1 | Out-String)
    if ($ghState -match 'Logged in to') {
        $who = ([regex]::Match($ghState, 'account (\S+)')).Groups[1].Value
        Say 'OK' 'gh' "logged in as $who"
    }
    else {
        Say 'TODO' 'gh' 'installed but not logged in - run: gh auth login'
        $problems += 'gh is not authenticated (gh auth login)'
    }
}
else {
    Say 'MISSING' 'gh' 'install GitHub CLI, then: gh auth login'
    $problems += 'gh (GitHub CLI) is not installed'
}

if (Test-Path $cfg.PHP_BIN) { Say 'OK' 'php' $cfg.PHP_BIN }
elseif (Get-Command php -ErrorAction SilentlyContinue) { Say 'OK' 'php' 'found on PATH' }
else {
    Say 'TODO' 'php' "not at $($cfg.PHP_BIN) - set PHP_BIN in config.env"
    $warnings += 'no PHP found: the syntax gate will be skipped'
}

# --- Asana ------------------------------------------------------------------
Write-Output "`nAsana:"
$token = Get-AsanaToken
if (-not $token) {
    Say 'TODO' 'token' 'not set - see ASANA_TOKEN_FILE / ASANA_TOKEN in config.env'
    $problems += 'no Asana token: /task and /task-plan will not work'
}
else {
    try {
        $me = Invoke-RestMethod -Uri 'https://app.asana.com/api/1.0/users/me' -Headers @{ Authorization = "Bearer $token" }
        Say 'OK' 'token' "works - $($me.data.name) <$($me.data.email)>"
    }
    catch {
        Say 'FAIL' 'token' 'Asana rejected it (401/403?) - regenerate it'
        $problems += 'the Asana token was rejected'
    }
}

# --- repo -------------------------------------------------------------------
Write-Output "`nRepository:"
$insideRepo = (& git -C $repoDir rev-parse --is-inside-work-tree 2>$null)
if ($insideRepo -ne 'true') {
    Say 'FAIL' 'git repo' "$repoDir is not a git repository"
    $problems += 'this .claude folder is not inside a git repository'
}
else {
    Say 'OK' 'git repo' $repoDir
    foreach ($branchName in @($cfg.PROD_BRANCH, $cfg.DEV_BRANCH)) {
        $found = (& git -C $repoDir ls-remote --heads origin $branchName 2>$null)
        if ($found) { Say 'OK' "branch $branchName" 'exists on origin' }
        else {
            Say 'FAIL' "branch $branchName" 'not found on origin - fix PROD_BRANCH/DEV_BRANCH'
            $problems += "branch '$branchName' does not exist on origin"
        }
    }
    if ((& git -C $repoDir config core.longpaths) -ne 'true') {
        Say 'TODO' 'core.longpaths' 'run: git config core.longpaths true (Windows deep paths)'
        $warnings += 'core.longpaths is not set: worktree checkout can fail on long paths'
    }
    else { Say 'OK' 'core.longpaths' 'true' }
}

# --- AI review (optional) ---------------------------------------------------
Write-Output "`nAI review (optional):"
$wsl = (& wsl -e bash -lc 'command -v review-pr' 2>$null)
if ($wsl) {
    Say 'OK' 'review-pr' 'installed in WSL'
    foreach ($prov in ($cfg.REVIEW_PROVIDERS -split ',')) {
        $provider = $prov.Trim()
        $bin = switch ($provider) { 'antigravity' { 'agy' } default { $provider } }
        $found = (& wsl -e bash -lc "command -v $bin" 2>$null)
        if ($found) { Say 'OK' "provider $provider" }
        else { Say 'TODO' "provider $provider" "'$bin' not found in WSL"; $warnings += "review provider '$provider' is not installed in WSL" }
    }
}
else {
    Say 'TODO' 'review-pr' 'not in WSL - the AI review step will be skipped'
    $warnings += 'review-pr is not installed in WSL: /task-do will skip the AI review'
}

# --- verdict ----------------------------------------------------------------
Write-Output ''
if ($problems.Count -gt 0) {
    Write-Output "RESULT: NOT READY - $($problems.Count) thing(s) to fix:"
    foreach ($p in $problems) { Write-Output "  * $p" }
    foreach ($w in $warnings) { Write-Output "  (optional) $w" }
    exit 1
}
if ($warnings.Count -gt 0) {
    Write-Output 'RESULT: READY, with optional things missing:'
    foreach ($w in $warnings) { Write-Output "  * $w" }
    exit 0
}
Write-Output 'RESULT: READY - everything checks out. Try /task in a new Claude session.'
exit 0
