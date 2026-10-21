# Shared configuration loader.
#
# Reads .claude/config.env (the per-person file, never shared) and falls back to
# built-in defaults. Dot-source it:
#
#     . "$PSScriptRoot\config.ps1"
#     $cfg = Get-ClaudeConfig
#     $cfg.PROD_BRANCH
#
# config.env format: plain KEY=VALUE lines, # for comments, quotes optional.
# Values from the file win. Environment variables win over both, so CI or a
# one-off run can override anything without editing files.

function Get-ClaudeConfig {
    $claudeDir = Split-Path $PSScriptRoot -Parent

    # Defaults: what this repo uses. A coworker overrides these in config.env.
    $cfg = @{
        PROD_BRANCH      = 'onestackcbs'
        DEV_BRANCH       = 'onestackcbs-dev'
        BRANCH_PREFIX    = 'sg_cl_'
        GITHUB_REPO      = 'OneStackIndia/core-php'
        WORKTREE_ROOT    = '../oneStack-worktrees'
        PHP_BIN          = 'C:\xampp\php\php.exe'
        REVIEW_PROVIDERS = 'claude,antigravity'
        ASANA_TOKEN      = ''
        ASANA_TOKEN_FILE = (Join-Path $env:USERPROFILE '.claude\.asana_token')
        DB_SCHEMA_DOC    = ''
        COAUTHOR_LINE    = 'Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>'
    }

    $configFile = Join-Path $claudeDir 'config.env'
    if (Test-Path $configFile) {
        foreach ($line in (Get-Content $configFile -Encoding UTF8)) {
            $trimmed = $line.Trim()
            if (-not $trimmed -or $trimmed.StartsWith('#')) { continue }
            $split = $trimmed.IndexOf('=')
            if ($split -lt 1) { continue }
            $key = $trimmed.Substring(0, $split).Trim()
            $val = $trimmed.Substring($split + 1).Trim()
            # strip one layer of surrounding quotes
            if ($val.Length -ge 2 -and (($val[0] -eq '"' -and $val[-1] -eq '"') -or ($val[0] -eq "'" -and $val[-1] -eq "'"))) {
                $val = $val.Substring(1, $val.Length - 2)
            }
            # Expand %USERPROFILE% and friends - people write those in .env files
            # and PowerShell does not expand them on its own.
            if ($val -match '%\w+%') { $val = [Environment]::ExpandEnvironmentVariables($val) }
            if ($val -ne '') { $cfg[$key] = $val }
        }
    }

    # Environment variables take precedence over the file.
    foreach ($key in @($cfg.Keys)) {
        $fromEnv = [Environment]::GetEnvironmentVariable($key)
        if ($fromEnv) { $cfg[$key] = $fromEnv }
    }

    return $cfg
}

# Returns the Asana token, or $null. Never prints it.
function Get-AsanaToken {
    $cfg = Get-ClaudeConfig
    if ($cfg.ASANA_TOKEN) { return $cfg.ASANA_TOKEN.Trim() }
    if ($cfg.ASANA_TOKEN_FILE -and (Test-Path $cfg.ASANA_TOKEN_FILE)) {
        $fromFile = (Get-Content $cfg.ASANA_TOKEN_FILE -Raw -Encoding UTF8).Trim()
        if ($fromFile) { return $fromFile }
    }
    return $null
}
