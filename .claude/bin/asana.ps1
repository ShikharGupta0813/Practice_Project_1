# Asana REST helper for the /task-* workflow.
# Reads a Personal Access Token from a file OUTSIDE the repo and never prints it.
#
#   .\.claude\bin\asana.ps1 mytasks              # formatted list (uses comments as description)
#   .\.claude\bin\asana.ps1 mytasks -NoComments  # faster, skips per-task comment fetch
#   .\.claude\bin\asana.ps1 task     -Id <gid>
#   .\.claude\bin\asana.ps1 stories  -Id <gid>
#   .\.claude\bin\asana.ps1 comment  -Id <gid> -Text "PR: https://..."
#   .\.claude\bin\asana.ps1 me

param(
    [Parameter(Mandatory = $true, Position = 0)]
    [ValidateSet('me', 'mytasks', 'task', 'stories', 'comment', 'attachments', 'fetch', 'activity')]
    [string]$Action,

    [string]$Id,
    [string]$Text,
    [string]$Out,
    [int]$Limit = 100,
    [int]$Top = 0,
    [string]$DueOn = '',
    [string]$Since = '',
    [string]$Until = '',
    [switch]$NoComments
)

$ErrorActionPreference = 'Stop'

# Token comes from .claude/config.env (ASANA_TOKEN or ASANA_TOKEN_FILE).
. "$PSScriptRoot\config.ps1"
$Token = Get-AsanaToken
if (-not $Token) {
    Write-Error "No Asana token. Set ASANA_TOKEN_FILE or ASANA_TOKEN in .claude/config.env (copy config.example.env), or run: powershell -File .claude/bin/setup.ps1 . Get a token from https://app.asana.com/0/my-apps -> Personal access tokens."
    exit 1
}

$Headers = @{ 'Authorization' = "Bearer $Token" }
$Base = 'https://app.asana.com/api/1.0'

$TaskFields = 'gid,name,notes,due_on,completed,permalink_url,parent.name'

function Invoke-Asana {
    param([string]$Method, [string]$Url, $Body)
    try {
        if ($Body) {
            $json = $Body | ConvertTo-Json -Depth 10 -Compress
            return Invoke-RestMethod -Method $Method -Uri $Url -Headers $Headers -ContentType 'application/json' -Body $json
        }
        return Invoke-RestMethod -Method $Method -Uri $Url -Headers $Headers
    }
    catch {
        $status = $null
        if ($_.Exception.Response) { $status = [int]$_.Exception.Response.StatusCode }
        switch ($status) {
            401 { Write-Error "Asana rejected the token (401). It may be revoked or mistyped. Regenerate it at https://app.asana.com/0/my-apps"; exit 1 }
            403 { Write-Error "Asana denied access (403). The token lacks permission for this resource."; exit 1 }
            404 { Write-Error "Not found (404). Check the gid: $Id"; exit 1 }
            429 { Write-Error "Rate limited by Asana (429). Wait and retry."; exit 1 }
            default { Write-Error "Asana request failed$(if ($status) { " ($status)" }): $($_.Exception.Message)"; exit 1 }
        }
    }
}

# Strip HTML, collapse whitespace, and shorten to a single readable line.
function Format-Snippet {
    param([string]$Raw, [int]$Max = 260)
    if ([string]::IsNullOrWhiteSpace($Raw)) { return $null }
    $t = $Raw -replace '<[^>]+>', ' '
    $t = $t -replace 'https?://app\.asana\.com/\S+', ''      # drop asana profile/permalink noise
    $t = $t -replace '\s+', ' '
    $t = $t.Trim()
    if ([string]::IsNullOrWhiteSpace($t)) { return $null }
    if ($t.Length -gt $Max) { $t = $t.Substring(0, $Max).TrimEnd() + '...' }
    return $t
}

function Get-Comments {
    param([string]$TaskId)
    $s = (Invoke-Asana GET "$Base/tasks/$TaskId/stories`?opt_fields=created_by.name,text,type").data
    return @($s | Where-Object { $_.type -eq 'comment' })
}

function Resolve-Day {
    param([string]$Value)
    if (-not $Value) { return $null }
    switch ($Value.ToLower()) {
        'today'     { return (Get-Date).Date }
        'yesterday' { return (Get-Date).Date.AddDays(-1) }
        'tomorrow'  { return (Get-Date).Date.AddDays(1) }
    }
    foreach ($fmt in @('dd-MM-yyyy','yyyy-MM-dd','d-M-yyyy','dd/MM/yyyy','yyyy/MM/dd','d/M/yyyy')) {
        try { return [datetime]::ParseExact($Value, $fmt, [Globalization.CultureInfo]::InvariantCulture).Date }
        catch { }
    }
    return $null
}

switch ($Action) {

    'me' {
        (Invoke-Asana GET "$Base/users/me").data | ConvertTo-Json -Depth 6
    }

    'mytasks' {
        $me = (Invoke-Asana GET "$Base/users/me").data
        $ws = $me.workspaces[0].gid

        $searchUrl = "$Base/workspaces/$ws/tasks/search" +
               "?assignee.any=me&completed=false&limit=$Limit" +
               "&sort_by=due_date&sort_ascending=true" +
               "&opt_fields=$TaskFields"

        $allTasks = @((Invoke-Asana GET $searchUrl).data)

        # Index the FULL list, always. -Top only limits what is DISPLAYED.
        # Numbering is positional in the same sorted order, so entry 9 means the
        # same task whether the user ran /task or /task 5. Writing only the
        # displayed subset would silently invalidate higher numbers.
        $index = @{}
        $i = 0
        foreach ($t in $allTasks) { $i++; $index["$i"] = $t.gid }

        # -DueOn filters to a single due date. Accepts today/tomorrow/yesterday,
        # dd-MM-yyyy, or yyyy-MM-dd. Numbering stays tied to the full list, so
        # /task-plan <n> keeps working even when the view is filtered.
        $tasks = $allTasks
        if ($DueOn) {
            $target = $null
            switch ($DueOn.ToLower()) {
                'today'     { $target = (Get-Date).Date }
                'tomorrow'  { $target = (Get-Date).Date.AddDays(1) }
                'yesterday' { $target = (Get-Date).Date.AddDays(-1) }
                default {
                    # Loop one format at a time: PowerShell 5.1 does not reliably
                    # bind the string[] overload of TryParseExact.
                    foreach ($fmt in @('dd-MM-yyyy','yyyy-MM-dd','d-M-yyyy','dd/MM/yyyy','yyyy/MM/dd','d/M/yyyy')) {
                        try {
                            $target = [datetime]::ParseExact($DueOn, $fmt,
                                        [Globalization.CultureInfo]::InvariantCulture).Date
                            break
                        }
                        catch { }
                    }
                }
            }
            if (-not $target) {
                Write-Error "Could not read the date '$DueOn'. Use today, tomorrow, yesterday, dd-MM-yyyy or yyyy-MM-dd."
                exit 1
            }
            $stamp = $target.ToString('yyyy-MM-dd')
            $tasks = @($allTasks | Where-Object { $_.due_on -eq $stamp })
        }

        # -Top N keeps the N soonest-due tasks (undated ones sort last).
        if ($Top -gt 0) { $tasks = @($tasks | Select-Object -First $Top) }

        $lookup = @{}
        foreach ($k in $index.Keys) { $lookup[$index[$k]] = $k }

        $n = 0
        $sb = New-Object System.Text.StringBuilder

        foreach ($t in $tasks) {
            $n++
            $num = if ($lookup.ContainsKey($t.gid)) { $lookup[$t.gid] } else { "$n" }

            $due = if ($t.due_on) { $t.due_on } else { 'no due date' }
            $parent = if ($t.parent -and $t.parent.name) { $t.parent.name.Trim() } else { $null }

            # Description: notes if present, else the task's comments.
            $desc = Format-Snippet $t.notes
            $commentCount = 0
            if (-not $desc -and -not $NoComments) {
                $comments = Get-Comments $t.gid
                $commentCount = $comments.Count
                foreach ($c in ($comments | Select-Object -Last 3)) {
                    $snip = Format-Snippet $c.text
                    if ($snip) { $desc = $snip }      # keep the last comment with real content
                }
            }

            [void]$sb.AppendLine("$num. $($t.name.Trim())")
            [void]$sb.AppendLine("   ID: $($t.gid)   Due: $due")
            if ($parent) { [void]$sb.AppendLine("   Part of: $parent") }
            if ($desc) {
                $label = if ($commentCount -gt 0) { "From comments ($commentCount)" } else { 'Description' }
                [void]$sb.AppendLine("   ${label}: $desc")
            }
            else {
                [void]$sb.AppendLine('   No description or comments.')
            }
            [void]$sb.AppendLine('')
        }

        # Save S.No -> gid so the user can refer to a task by its number.
        $indexPath = Join-Path $PSScriptRoot '..\plans\_last_list.json'
        $index | ConvertTo-Json -Depth 3 | Set-Content -Path $indexPath -Encoding utf8

        $header = if ($DueOn) {
            if ($n -eq 0) { "No tasks due $DueOn ($stamp)." } else { "$n task(s) due $DueOn ($stamp), of $($allTasks.Count) open." }
        } elseif ($Top -gt 0) { "Showing the $n soonest-due of $($allTasks.Count) open tasks." }
        else { "$n open tasks assigned to you." }
        Write-Output "$header`n"
        Write-Output $sb.ToString().TrimEnd()
    }

    'task' {
        if (-not $Id) { Write-Error 'task requires -Id <gid>'; exit 1 }
        (Invoke-Asana GET "$Base/tasks/$Id`?opt_fields=$TaskFields").data | ConvertTo-Json -Depth 6
    }

    'stories' {
        if (-not $Id) { Write-Error 'stories requires -Id <gid>'; exit 1 }
        Get-Comments $Id | ConvertTo-Json -Depth 6
    }

    'attachments' {
        if (-not $Id) { Write-Error 'attachments requires -Id <task_gid>'; exit 1 }
        $a = (Invoke-Asana GET "$Base/attachments`?parent=$Id&opt_fields=name,resource_subtype,size,download_url,permanent_url,created_at").data
        if (-not $a -or @($a).Count -eq 0) { Write-Output '[]'; break }
        @($a) | ConvertTo-Json -Depth 6
    }

    'fetch' {
        if (-not $Id) { Write-Error 'fetch requires -Id <task_gid>'; exit 1 }

        $dir = if ($Out) { $Out } else { Join-Path $PSScriptRoot "..\plans\attachments\$Id" }
        $a = @((Invoke-Asana GET "$Base/attachments`?parent=$Id&opt_fields=name,resource_subtype,size,download_url").data)

        if ($a.Count -eq 0) { Write-Output 'No attachments on this task.'; break }
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }

        foreach ($att in $a) {
            $name = $att.name
            if ([string]::IsNullOrWhiteSpace($name)) { $name = "attachment_$($att.gid)" }
            # Strip characters Windows will not accept in a filename.
            $name = ($name -replace '[<>:"/\|?*]', '_').Trim()
            $dest = Join-Path $dir $name

            if (-not $att.download_url) {
                Write-Output "SKIP (no download_url, subtype=$($att.resource_subtype)): $name"
                continue
            }
            try {
                # download_url is a presigned link - do NOT send the Asana auth header.
                Invoke-WebRequest -Uri $att.download_url -OutFile $dest -UseBasicParsing -ErrorAction Stop
                $kb = [math]::Round((Get-Item $dest).Length / 1KB, 1)
                Write-Output "SAVED  $dest  (${kb} KB)"
            }
            catch {
                Write-Output "FAILED $name : $($_.Exception.Message)"
            }
        }
    }

    'activity' {
        $fromDay = Resolve-Day ($(if ($Since) { $Since } else { 'yesterday' }))
        if (-not $fromDay) { Write-Error "Could not read -Since '$Since'."; exit 1 }
        $toDay = if ($Until) { Resolve-Day $Until } else { $fromDay.AddDays(1) }
        if (-not $toDay) { Write-Error "Could not read -Until '$Until'."; exit 1 }
        if ($toDay -le $fromDay) { $toDay = $fromDay.AddDays(1) }

        $me = (Invoke-Asana GET "$Base/users/me").data
        $ws = $me.workspaces[0].gid
        $myGid = $me.gid

        # Pre-filter on modified_at so we only pull stories for tasks that moved.
        $fromIso = $fromDay.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss.fffZ')
        $searchUrl = "$Base/workspaces/$ws/tasks/search" +
                     "?assignee.any=me&limit=100&modified_at.after=$fromIso" +
                     "&opt_fields=gid,name,completed,completed_at,due_on,permalink_url,custom_fields.name,custom_fields.display_value"
        $candidates = @((Invoke-Asana GET $searchUrl).data)

        Write-Output "Activity $($fromDay.ToString('yyyy-MM-dd')) to $($toDay.AddDays(-1).ToString('yyyy-MM-dd'))"
        Write-Output "$($candidates.Count) task(s) modified in or after that window; showing those with activity inside it.`n"

        $found = 0
        foreach ($t in $candidates) {
            $events = @()
            foreach ($st in (Invoke-Asana GET "$Base/tasks/$($t.gid)/stories`?opt_fields=created_at,created_by.name,created_by.gid,text,type,resource_subtype").data) {
                $when = [datetime]::Parse($st.created_at).ToLocalTime()
                if ($when -lt $fromDay -or $when -ge $toDay) { continue }
                $who = if ($st.created_by -and $st.created_by.name) { $st.created_by.name } else { 'someone' }
                $mine = ($st.created_by -and $st.created_by.gid -eq $myGid)
                $txt = Format-Snippet $st.text 300
                if (-not $txt) { continue }

                # Keep every real activity (comments, assignments, due-date and
                # status changes, completions). Only Asana's own automatic
                # reminders are dropped - nobody actually did those.
                if ($txt -match 'have a task due') { continue }

                # "Shikhar Gupta assigned to X" -> "assigned to X" when it is our own story.
                if ($mine -and $who) { $txt = $txt -replace ('^' + [regex]::Escape($who) + '\s+'), '' }
                $events += [pscustomobject]@{ When = $when; Who = $who; Mine = $mine; Kind = $st.type; Text = $txt }
            }
            if ($events.Count -eq 0) { continue }
            $found++

            $state = if ($t.completed) { ' [COMPLETED]' } else { '' }
            Write-Output "$($t.name.Trim())$state"
            Write-Output "   ID: $($t.gid)"
            $statusField = @($t.custom_fields | Where-Object { $_.name -eq 'Status' -and $_.display_value }) | Select-Object -First 1
            if ($statusField) { Write-Output "   Status: $($statusField.display_value)" }
            foreach ($e in ($events | Sort-Object When)) {
                $tag = if ($e.Mine) { 'me' } else { $e.Who }
                Write-Output "   - $($e.When.ToString('ddd dd MMM HH:mm')) [$tag] $($e.Text)"
            }
            Write-Output ''
        }
        if ($found -eq 0) { Write-Output 'No Asana activity in that window.' }
    }

    'comment' {
        if (-not $Id)   { Write-Error 'comment requires -Id <gid>'; exit 1 }
        if (-not $Text) { Write-Error 'comment requires -Text "..."'; exit 1 }
        $body = @{ data = @{ text = $Text } }
        $r = Invoke-Asana POST "$Base/tasks/$Id/stories" $body
        "Comment posted: $($r.data.gid)"
    }
}
