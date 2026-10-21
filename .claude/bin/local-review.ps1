# AI-review the current BRANCH before any PR exists, using review-pr's own
# --compare mode (added upstream 2026-09-24).
#
#   powershell -File .claude/bin/local-review.ps1
#   powershell -File .claude/bin/local-review.ps1 -PlanFile .claude/plans/<gid>.md
#   powershell -File .claude/bin/local-review.ps1 -Base onestackcbs-dev
#
# `review-pr --compare <branch> <base>` diffs the branch against the base's
# merge-base - the same "changes since divergence" diff GitHub shows for a PR -
# and runs the normal review on it. It never publishes: there is no PR to
# attach a review to.
#
# NOTE: --compare works on COMMITTED work only. Commit first (don't push), then
# review; fixes can be amended in before the PR is opened.
#
# Runs claude and antigravity in parallel inside WSL. Output per provider:
# .claude/plans/reviews/local-<branch>-<provider>.txt
# Exit 0 if at least one provider produced a review, 1 if none, 2 if nothing to review.

param(
    [string]$Base = '',
    [string]$PlanFile = '',
    [string]$RepoPath = '',
    [string[]]$Providers = @()
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\config.ps1"
$cfg = Get-ClaudeConfig
if (-not $Base) { $Base = $cfg.PROD_BRANCH }
if (-not $Providers -or $Providers.Count -eq 0) {
    $Providers = @($cfg.REVIEW_PROVIDERS -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
}

function ConvertTo-WslPath([string]$WinPath) {
    $full = [System.IO.Path]::GetFullPath($WinPath)
    return "/mnt/" + $full.Substring(0, 1).ToLower() + $full.Substring(2).Replace('\', '/')
}

$claudeDir = Split-Path $PSScriptRoot -Parent
if (-not $RepoPath) { $RepoPath = Split-Path $claudeDir -Parent }
$reviewDir = Join-Path $claudeDir 'plans\reviews'
if (-not (Test-Path $reviewDir)) { New-Item -ItemType Directory -Path $reviewDir -Force | Out-Null }

$branch = (& git -C $RepoPath rev-parse --abbrev-ref HEAD).Trim()
$safeBranch = $branch -replace '[^A-Za-z0-9_.-]', '_'

if ($branch -eq $Base) { Write-Output "Already on $Base - nothing to compare."; exit 2 }

# --compare only sees committed work. Warn about anything still uncommitted.
$dirty = @(& git -C $RepoPath status --porcelain | Where-Object { $_ })
if ($dirty.Count -gt 0) {
    Write-Output "WARNING: $($dirty.Count) uncommitted change(s) will NOT be reviewed - commit first:"
    $dirty | Select-Object -First 8 | ForEach-Object { Write-Output "    $_" }
    Write-Output ''
}

$commits = @(& git -C $RepoPath log --oneline "$Base..HEAD" | Where-Object { $_ })
if ($commits.Count -eq 0) {
    Write-Output "No commits on '$branch' since '$Base' - nothing to review."
    exit 2
}

$contextArg = ''
if ($PlanFile) {
    if (-not (Test-Path $PlanFile)) { Write-Error "Plan file not found: $PlanFile"; exit 1 }
    $contextArg = "--business-context 'file:" + (ConvertTo-WslPath $PlanFile) + "'"  # review-pr requires a type prefix (file:/asana:/notion:)
}

$repoWsl = ConvertTo-WslPath $RepoPath
$outWsl  = ConvertTo-WslPath $reviewDir

$lines = @(
    'export PATH="$HOME/.local/bin:$PATH"'
    "cd '$repoWsl' || exit 1"
    'command -v review-pr >/dev/null || { echo "review-pr is not installed in WSL"; exit 1; }'
)
foreach ($p in $Providers) {
    $out = "$outWsl/local-$safeBranch-$p.txt"
    $lines += "( s=`$(date +%s); review-pr --compare '$branch' '$Base' --provider $p --dry-run $contextArg > '$out' 2>&1; echo `"EXIT=`$? TOOK=`$(( `$(date +%s) - s ))s`" >> '$out' ) &"
}
$lines += 'wait'

$runner = Join-Path $reviewDir '_local_run.sh'
[System.IO.File]::WriteAllText($runner, (($lines -join "`n") + "`n"), (New-Object System.Text.UTF8Encoding $false))

Write-Output "Reviewing branch '$branch' vs '$Base'  ($($commits.Count) commit(s))"
Write-Output "Providers: $($Providers -join ', ')$(if ($PlanFile) { "   plan: $PlanFile" })"
Write-Output "Nothing is sent to GitHub. Usually 1-5 minutes...`n"

& wsl -e bash -l (ConvertTo-WslPath $runner) 2>&1 | ForEach-Object { $_ -replace "`0", '' } | Out-Null

$ok = 0
foreach ($p in $Providers) {
    $f = Join-Path $reviewDir "local-$safeBranch-$p.txt"
    Write-Output ("=" * 70)
    Write-Output "PROVIDER: $p     (full output: $f)"
    Write-Output ("=" * 70)
    if (-not (Test-Path $f)) { Write-Output '  no output produced'; continue }
    $text = (Get-Content $f -Raw -Encoding UTF8) -replace "`0", ''
    $text = ($text -split "`n" | Where-Object { $_ -notmatch '^\s+Files Modified:' }) -join "`n"
    Write-Output $text.TrimEnd()
    if ($text -match 'EXIT=0') { $ok++ }
    if ($text -match 'Argument list too long') {
        Write-Output "`n  NOTE: diff too large for antigravity - review-pr passes the prompt as a"
        Write-Output '  single argument and Linux rejects arguments >= 128 KB. Use the other review.'
    }
    if ($text -match 'empty response') {
        Write-Output "`n  NOTE: antigravity returned nothing. It is an agent: given a review prompt"
        Write-Output '  it may try to run shell commands, which headless mode denies, and then it'
        Write-Output '  answers with nothing. Use the other review.'
    }
    Write-Output ''
}

Remove-Item $runner -Force -ErrorAction SilentlyContinue
if ($ok -eq 0) { Write-Output 'RESULT: no provider produced a review.'; exit 1 }
Write-Output "RESULT: $ok of $($Providers.Count) provider(s) produced a review."
exit 0
