# Pre-PR verification gate.
# Lints every PHP file changed on the current branch relative to a base ref.
#
#   .\.claude\bin\verify.ps1                     # vs origin/onestackcbs
#   .\.claude\bin\verify.ps1 -Base onestackcbs
#   .\.claude\bin\verify.ps1 -Files "a.php,b.php"
#   .\.claude\bin\verify.ps1 -RepoPath ..\oneStack-worktrees\sg_cl_foo
#
# -RepoPath matters for worktrees: Claude runs from the MAIN folder (that is
# where .claude lives) while the code under test sits in the worktree. Without
# it this would lint the main checkout instead of the task's code.
#
# Exit 0 = all clear. Exit 1 = something failed (do NOT open a PR).

param(
    [string]$Base = '',
    [string]$Files = '',
    [string]$RepoPath = ''
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\config.ps1"
$cfg = Get-ClaudeConfig
if (-not $Base) { $Base = 'origin/' + $cfg.PROD_BRANCH }

# Which checkout are we linting? Default: wherever we are.
if ($RepoPath) {
    if (-not (Test-Path $RepoPath)) { Write-Output "RESULT: FAIL - no such path: $RepoPath"; exit 1 }
    $repo = (Resolve-Path $RepoPath).Path
}
else {
    $repo = (& git rev-parse --show-toplevel 2>$null)
    if (-not $repo) { $repo = (Get-Location).Path }
    # git returns forward slashes on Windows; normalise so path trimming works.
    $repo = (Resolve-Path $repo).Path
}

# Find a PHP binary. XAMPP's is the likely one on this machine.
$php = $null
foreach ($c in @($cfg.PHP_BIN, 'php')) {
    try {
        $cmd = Get-Command $c -ErrorAction SilentlyContinue
        if ($cmd) { $php = $cmd.Source; break }
    } catch {}
}

if (-not $php) {
    Write-Output 'SKIP: no PHP binary found - syntax check not run.'
    Write-Output 'RESULT: SKIPPED'
    exit 0
}

# Which files changed?
if ($Files) {
    $changed = $Files -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ }
}
else {
    $tracked   = @(& git -C $repo diff --name-only $Base 2>$null)
    $untracked = @(& git -C $repo ls-files --others --exclude-standard 2>$null)
    $changed   = @($tracked + $untracked | Sort-Object -Unique)
}

# git prints paths relative to the checkout root, so resolve them against it.
$phpFiles = @(
    $changed |
        Where-Object { $_ -match '\.php$' } |
        ForEach-Object { if ([System.IO.Path]::IsPathRooted($_)) { $_ } else { Join-Path $repo $_ } } |
        Where-Object { Test-Path $_ }
)

if ($phpFiles.Count -eq 0) {
    Write-Output 'No changed PHP files to lint.'
    Write-Output 'RESULT: PASS'
    exit 0
}

Write-Output "Linting $($phpFiles.Count) changed PHP file(s) in $repo with $php`n"

$failed = @()
foreach ($f in $phpFiles) {
    $shown = $f.Replace($repo, '').TrimStart('\', '/')
    # PowerShell 5.1 turns a native command's stderr into an ErrorRecord, which
    # $ErrorActionPreference='Stop' then throws on - so a REAL syntax error used
    # to crash this script instead of reporting FAIL. Relax it for the call and
    # judge the result by the exit code.
    $prevEap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $out = & $php -l $f 2>&1
    $lintExit = $LASTEXITCODE
    $ErrorActionPreference = $prevEap
    if ($lintExit -eq 0) {
        Write-Output "  OK    $shown"
    }
    else {
        Write-Output "  FAIL  $shown"
        Write-Output "        $($out -join ' ')"
        $failed += $shown
    }
}

Write-Output ''
if ($failed.Count -gt 0) {
    Write-Output "RESULT: FAIL - $($failed.Count) file(s) have syntax errors. Do not open a PR."
    exit 1
}

Write-Output 'RESULT: PASS'
exit 0
