# Self-check for the .claude tooling scripts.
# Run this after ANY edit to a file in .claude/bin/ — those scripts are
# gitignored, so verify.ps1 (which works off git diff) never sees them.
#
#   powershell -File .claude/bin/check-tooling.ps1
#
# Exit 0 = all clear. Exit 1 = something is wrong; fix before using the script.

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent          # .claude
$binDir = Join-Path $root 'bin'
$failed = @()

Write-Output "Checking PowerShell tooling in $binDir`n"

foreach ($f in (Get-ChildItem -Path $binDir -Filter '*.ps1' | Sort-Object Name)) {

    $issues = @()

    # 1) Syntax: parse without executing.
    $tokens = $null; $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile(
        $f.FullName, [ref]$tokens, [ref]$errors)
    if ($errors -and $errors.Count -gt 0) {
        foreach ($e in $errors) {
            $issues += "syntax: line $($e.Extent.StartLineNumber): $($e.Message)"
        }
    }

    # 2) Control characters. A stray BEL (0x07) from a bad \a escape silently
    #    corrupts paths — this actually happened in asana.ps1.
    $raw = [System.IO.File]::ReadAllText($f.FullName)
    $ctrl = @()
    for ($i = 0; $i -lt $raw.Length; $i++) {
        $c = [int]$raw[$i]
        if ($c -lt 9 -or $c -eq 11 -or $c -eq 12 -or ($c -ge 14 -and $c -lt 32)) {
            $ctrl += "0x{0:X2} at offset {1}" -f $c, $i
        }
    }
    if ($ctrl.Count -gt 0) { $issues += "control chars: $($ctrl -join ', ')" }

    # 3) Parameter/variable case collisions. PowerShell variables are
    #    case-INSENSITIVE, so a typed param like [string]$Out silently coerces
    #    any later $out — this is what broke mytasks.
    $declared = [regex]::Matches($raw, '\[\w+(\[\])?\]\s*\$(\w+)\s*[,)=]') |
        ForEach-Object { $_.Groups[2].Value } |
        Select-Object -Unique
    foreach ($d in $declared) {
        # Search case-INSENSITIVELY for other spellings assigned to, then
        # compare case-sensitively. .NET regex is case-sensitive by default,
        # which is exactly why the first version of this check missed the bug.
        $others = [regex]::Matches($raw, '\$(' + [regex]::Escape($d) + ')\s*=',
                                   [System.Text.RegularExpressions.RegexOptions]::IgnoreCase) |
            ForEach-Object { $_.Groups[1].Value } |
            Where-Object { $_ -cne $d } |
            Select-Object -Unique
        foreach ($o in $others) {
            $issues += "case collision: parameter `$$d is also assigned as `$$o (PowerShell vars are case-insensitive, so the typed param coerces it)"
        }
    }

    if ($issues.Count -eq 0) {
        Write-Output "  OK    $($f.Name)"
    }
    else {
        Write-Output "  FAIL  $($f.Name)"
        foreach ($i in $issues) { Write-Output "        $i" }
        $failed += $f.Name
    }
}

# Python helpers: compile them, and check for CRLF (a .py run under WSL with
# Windows line endings fails in confusing ways).
foreach ($f in (Get-ChildItem -Path $binDir -Filter '*.py' | Sort-Object Name)) {
    $issues = @()
    $py = (Get-Command python -ErrorAction SilentlyContinue)
    if ($py) {
        # Same trap as verify.ps1: under $ErrorActionPreference='Stop' a native
        # command's stderr becomes a thrown ErrorRecord, so a genuinely broken
        # .py would crash this checker instead of being reported as FAIL.
        $prevEap = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        $null = & $py.Source -m py_compile $f.FullName 2>&1
        $compileExit = $LASTEXITCODE
        $ErrorActionPreference = $prevEap
        if ($compileExit -ne 0) { $issues += "syntax: py_compile failed" }
    }
    $bytes = [System.IO.File]::ReadAllBytes($f.FullName)
    $crlf = 0
    for ($i = 1; $i -lt $bytes.Length; $i++) { if ($bytes[$i] -eq 10 -and $bytes[$i - 1] -eq 13) { $crlf++ } }
    if ($crlf -gt 0) { $issues += "$crlf CRLF line ending(s) - use LF, this runs under WSL" }

    if ($issues.Count -eq 0) { Write-Output "  OK    $($f.Name)" }
    else {
        Write-Output "  FAIL  $($f.Name)"
        foreach ($i in $issues) { Write-Output "        $i" }
        $failed += $f.Name
    }
}

Write-Output ''
if ($failed.Count -gt 0) {
    Write-Output "RESULT: FAIL - $($failed.Count) script(s) need fixing: $($failed -join ', ')"
    exit 1
}
Write-Output 'RESULT: PASS'
Write-Output ''
Write-Output 'LIMITATION: the case-collision check is not scope-aware, so a'
Write-Output 'function parameter and an unrelated script variable can be flagged'
Write-Output 'even though they never collide. Rename rather than ignore - the'
Write-Output 'pattern is confusing regardless.'
Write-Output ''
Write-Output 'NOTE: syntax passing is not the same as working. Also RUN the'
Write-Output 'script you changed (e.g. asana.ps1 mytasks -Top 3) before relying on it.'
exit 0
