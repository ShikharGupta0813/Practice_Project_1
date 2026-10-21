# Self-review a PR with review-pr, using several AI providers in parallel (in WSL).
#
#   powershell -File .claude/bin/self-review.ps1 -Pr 13141
#   powershell -File .claude/bin/self-review.ps1 -Pr 13141 -PlanFile .claude/plans/1217811081134142.md
#
# Always --dry-run: nothing is ever posted to GitHub.
# Each provider's full output is saved to .claude/plans/reviews/<pr>-<provider>.txt
# (review-pr's own cache keeps ONE findings.json per PR, so parallel runs would
# overwrite each other there - we keep stdout per provider instead).
#
# -PlanFile is passed as --business-context, so the reviewer can check the diff
# against what the task was actually supposed to do.
#
# Exit 0 if at least one provider produced a review, 1 if none did.

param(
    [Parameter(Mandatory = $true)]
    [int]$Pr,
    [string]$PlanFile = '',
    [string]$Repo = '',
    [string[]]$Providers = @()
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\config.ps1"
$cfg = Get-ClaudeConfig
if (-not $Repo) { $Repo = $cfg.GITHUB_REPO }
if (-not $Providers -or $Providers.Count -eq 0) {
    $Providers = @($cfg.REVIEW_PROVIDERS -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
}

function ConvertTo-WslPath([string]$WinPath) {
    $full = [System.IO.Path]::GetFullPath($WinPath)
    $drive = $full.Substring(0, 1).ToLower()
    return "/mnt/$drive" + $full.Substring(2).Replace('\', '/')
}

$reviewDir = Join-Path (Split-Path $PSScriptRoot -Parent) 'plans\reviews'
if (-not (Test-Path $reviewDir)) { New-Item -ItemType Directory -Path $reviewDir -Force | Out-Null }
$reviewDirWsl = ConvertTo-WslPath $reviewDir

$contextArg = ''
if ($PlanFile) {
    if (-not (Test-Path $PlanFile)) { Write-Error "Plan file not found: $PlanFile"; exit 1 }
    $contextArg = "--business-context 'file:" + (ConvertTo-WslPath $PlanFile) + "'"  # review-pr requires a type prefix (file:/asana:/notion:)
}

# Build the bash side as a file: passing it inline through wsl mangles quotes.
$lines = @(
    'export PATH="$HOME/.local/bin:$PATH"'
    'cd ~'
    'command -v review-pr >/dev/null || { echo "review-pr is not installed in WSL"; exit 1; }'
)
foreach ($p in $Providers) {
    $outFile = "$reviewDirWsl/$Pr-$p.txt"
    $lines += "( s=`$(date +%s); review-pr $Pr --repo '$Repo' --provider $p --dry-run $contextArg > '$outFile' 2>&1; echo `"EXIT=`$? TOOK=`$(( `$(date +%s) - s ))s`" >> '$outFile' ) &"
}
$lines += 'wait'

$runner = Join-Path $reviewDir '_run.sh'
[System.IO.File]::WriteAllText($runner, (($lines -join "`n") + "`n"), (New-Object System.Text.UTF8Encoding $false))

Write-Output "Reviewing PR #$Pr with: $($Providers -join ', ')$(if ($PlanFile) { "  (business context: $PlanFile)" })"
Write-Output "Runs in parallel in WSL; usually 1-4 minutes...`n"

& wsl -e bash -l (ConvertTo-WslPath $runner) 2>&1 | ForEach-Object { $_ -replace "`0", '' } | Out-Null

$ok = 0
foreach ($p in $Providers) {
    $f = Join-Path $reviewDir "$Pr-$p.txt"
    Write-Output ("=" * 70)
    Write-Output "PROVIDER: $p     (full output: $f)"
    Write-Output ("=" * 70)
    if (-not (Test-Path $f)) { Write-Output "  no output produced"; continue }
    $text = (Get-Content $f -Raw -Encoding UTF8) -replace "`0", ''
    # Drop the long "Files Modified:" list - it is noise for triage.
    $text = ($text -split "`n" | Where-Object { $_ -notmatch '^\s+Files Modified:' }) -join "`n"
    Write-Output $text.TrimEnd()
    if ($text -match 'EXIT=0') { $ok++ }
    if ($text -match 'Argument list too long') {
        Write-Output "`n  NOTE: prompt too large for this provider (>=128 KB passed as one argument)."
        Write-Output "  Known limit of review-pr's antigravity provider - rely on the other review."
    }
    Write-Output ''
}

Remove-Item $runner -Force -ErrorAction SilentlyContinue
if ($ok -eq 0) { Write-Output 'RESULT: no provider produced a review.'; exit 1 }
Write-Output "RESULT: $ok of $($Providers.Count) provider(s) produced a review."
exit 0
