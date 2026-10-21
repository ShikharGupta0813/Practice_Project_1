# Turn a nightly run's report.json into report.html.
#
#   powershell -File .claude/bin/nightly-report.ps1 -RunDir .claude/plans/nightly/2026-10-20
#   powershell -File .claude/bin/nightly-report.ps1            # most recent run
#   powershell -File .claude/bin/nightly-report.ps1 -Open      # and open it
#
# Pure formatting: reads JSON, writes HTML, changes nothing else. The page is
# self-contained (no CDN, no fonts, no network) so it works from file://.
#
# Questions render as multiple choice. You pick, the page remembers your picks
# in localStorage, and one button copies a paste-ready block for Claude.

param(
    [string]$RunDir = '',
    [switch]$Open
)

$ErrorActionPreference = 'Stop'
$claudeDir = Split-Path $PSScriptRoot -Parent

if (-not $RunDir) {
    $root = Join-Path $claudeDir 'plans\nightly'
    if (-not (Test-Path $root)) { Write-Output 'No nightly runs yet.'; exit 1 }
    $latest = Get-ChildItem $root -Directory -ErrorAction SilentlyContinue |
                Sort-Object Name -Descending | Select-Object -First 1
    if (-not $latest) { Write-Output 'No nightly runs yet.'; exit 1 }
    $RunDir = $latest.FullName
}
if (-not (Test-Path $RunDir)) { Write-Output "No such run folder: $RunDir"; exit 1 }
$RunDir = (Resolve-Path $RunDir).Path

$jsonPath = Join-Path $RunDir 'report.json'
if (-not (Test-Path $jsonPath)) { Write-Output "No report.json in $RunDir"; exit 1 }
$report = Get-Content $jsonPath -Raw -Encoding UTF8 | ConvertFrom-Json

function E([string]$s) {
    if ($null -eq $s) { return '' }
    $s.Replace('&', '&amp;').Replace('<', '&lt;').Replace('>', '&gt;').Replace('"', '&quot;')
}

$tasks = @($report.tasks)
$auto = @($tasks | Where-Object { "$($_.verdict)".ToUpper() -eq 'AUTO' })
$ask  = @($tasks | Where-Object { "$($_.verdict)".ToUpper() -eq 'ASK' })
$skip = @($tasks | Where-Object { "$($_.verdict)".ToUpper() -eq 'SKIP' })

$sb = New-Object System.Text.StringBuilder
function W([string]$s) { [void]$sb.AppendLine($s) }

W '<!doctype html><html lang="en"><head><meta charset="utf-8">'
W '<meta name="viewport" content="width=device-width,initial-scale=1">'
W ('<title>Overnight run ' + (E $report.date) + '</title>')

$css = @'
<style>
:root{--bg:#0f1115;--card:#171a21;--line:#262b36;--fg:#e6e8ee;--dim:#9aa3b2;
--ok:#4ec9a0;--ask:#e8b84b;--skip:#8b93a3;--accent:#7aa2f7}
*{box-sizing:border-box}
body{margin:0;padding:32px 16px 76px;background:var(--bg);color:var(--fg);
font:16px/1.6 -apple-system,Segoe UI,Roboto,sans-serif}
.wrap{max-width:860px;margin:0 auto}
h1{font-size:26px;margin:0 0 4px}
.sub{color:var(--dim);margin:0 0 28px;font-size:14px}
.tally{display:flex;gap:10px;flex-wrap:wrap;margin:0 0 32px}
.pill{background:var(--card);border:1px solid var(--line);border-radius:999px;
padding:7px 15px;font-size:14px}
.pill b{font-size:17px;margin-right:5px}
h2{font-size:14px;letter-spacing:.09em;text-transform:uppercase;color:var(--dim);
margin:36px 0 14px;font-weight:600}
.card{background:var(--card);border:1px solid var(--line);border-left-width:3px;
border-radius:10px;padding:18px 20px;margin:0 0 14px}
.card.ok{border-left-color:var(--ok)}
.card.ask{border-left-color:var(--ask)}
.card.skip{border-left-color:var(--skip)}
.name{font-weight:650;font-size:17px;margin:0 0 6px}
.meta{color:var(--dim);font-size:13px;margin:0 0 12px}
.meta code,.name code{background:#0b0d11;padding:2px 6px;border-radius:4px;font-size:12px}
.why{margin:0 0 12px}
.why .lab{color:var(--dim);font-size:13px;display:block;margin-bottom:2px}
a{color:var(--accent)}
.q{border-top:1px solid var(--line);margin-top:16px;padding-top:16px}
.qt{font-weight:600;margin:0 0 11px}
label{display:flex;gap:11px;align-items:flex-start;padding:10px 12px;
border:1px solid var(--line);border-radius:8px;margin-bottom:7px;cursor:pointer;
background:#0f1319;transition:border-color .12s}
label:hover{border-color:#3a4254}
label.sel{border-color:var(--accent);background:#141a27}
input[type=radio]{margin-top:5px;accent-color:var(--accent);flex:none}
.key{font-weight:700;color:var(--dim);flex:none;width:17px}
.rec{font-size:11px;color:var(--ok);border:1px solid var(--ok);border-radius:4px;
padding:1px 6px;margin-left:8px;white-space:nowrap}
.hint{color:var(--dim);font-size:13px;margin:8px 0 0}
.bar{position:fixed;left:0;right:0;bottom:0;background:#12151b;
border-top:1px solid var(--line);padding:13px 16px;display:flex;
gap:14px;align-items:center;justify-content:center}
button{background:var(--accent);color:#0b0d11;border:0;border-radius:8px;
padding:11px 20px;font-size:15px;font-weight:650;cursor:pointer}
button.ghost{background:transparent;color:var(--dim);border:1px solid var(--line)}
#status{color:var(--dim);font-size:14px}
.empty{color:var(--dim);font-style:italic;padding:4px 0 10px}
pre{background:#0b0d11;border:1px solid var(--line);border-radius:8px;
padding:14px;overflow:auto;font-size:13px;white-space:pre-wrap}
</style>
'@
W $css
W '</head><body><div class="wrap">'

W ('<h1>Overnight run &mdash; ' + (E $report.date) + '</h1>')
$note = ''
if ($report.planOnly) { $note = ' &middot; plan-only, nothing was executed' }
elseif ($report.dryRun) { $note = ' &middot; dry run' }
W ('<p class="sub">Started ' + (E $report.startedAt) + ' &middot; ' + (E $report.repo) + $note + '</p>')

W '<div class="tally">'
W ('<span class="pill"><b>' + $auto.Count + '</b>done</span>')
W ('<span class="pill"><b>' + $ask.Count + '</b>need you</span>')
W ('<span class="pill"><b>' + $skip.Count + '</b>skipped</span>')
W '</div>'

# ------------------------------------------------------------- your decisions
W '<h2>Your decisions</h2>'
if ($ask.Count -eq 0) { W '<p class="empty">Nothing waiting on you.</p>' }
foreach ($t in $ask) {
    W '<div class="card ask">'
    W ('<p class="name">' + (E $t.name) + '</p>')
    W ('<p class="meta"><code>' + (E $t.gid) + '</code> &middot; ' + (E "$($t.files)") +
        ' file(s) &middot; risk ' + (E $t.risk) + ' &middot; confidence ' + (E $t.confidence) + '</p>')
    if ($t.summary) { W ('<p class="why"><span class="lab">What this is</span>' + (E $t.summary) + '</p>') }
    if ($t.reason) { W ('<p class="why"><span class="lab">Why it stopped</span>' + (E $t.reason) + '</p>') }
    foreach ($q in @($t.questions)) {
        $qid = "$($t.gid)_$($q.id)"
        W '<div class="q">'
        W ('<p class="qt">' + (E $q.text) + '</p>')
        foreach ($o in @($q.options)) {
            $rec = ''
            if ("$($o.key)" -eq "$($q.recommend)") { $rec = '<span class="rec">suggested</span>' }
            W ('<label><input type="radio" name="' + (E $qid) + '" value="' + (E $o.key) +
                '"><span class="key">' + (E $o.key) + '</span><span>' + (E $o.text) + $rec + '</span></label>')
        }
        if ($q.why) { W ('<p class="hint">Suggested ' + (E $q.recommend) + ' &mdash; ' + (E $q.why) + '</p>') }
        W '</div>'
    }
    W '</div>'
}

# ----------------------------------------------------------------------- done
W '<h2>Done while you slept</h2>'
if ($auto.Count -eq 0) { W '<p class="empty">Nothing was executed.</p>' }
foreach ($t in $auto) {
    W '<div class="card ok">'
    W ('<p class="name">' + (E $t.name) + '</p>')
    # Every element parenthesised: in PowerShell the comma binds tighter than +,
    # so an unbracketed 'a' + $x, 'b' + $y silently builds the wrong array.
    $bits = @(
        ('<code>' + (E $t.gid) + '</code>'),
        ((E "$($t.files)") + ' file(s)'),
        ('risk ' + (E $t.risk))
    )
    if ($t.branch) { $bits += ('branch <code>' + (E $t.branch) + '</code>') }
    W ('<p class="meta">' + ($bits -join ' &middot; ') + '</p>')
    if ($t.summary) { W ('<p class="why">' + (E $t.summary) + '</p>') }
    if ($t.pr) {
        W ('<p><a href="' + (E $t.pr) + '" target="_blank" rel="noreferrer">Review the pull request &rarr;</a></p>')
    }
    elseif ($t.executed) { W '<p class="hint">Branch pushed, no PR opened.</p>' }
    else { W '<p class="hint">Execution did not finish cleanly &mdash; read the log before trusting this one.</p>' }
    W '</div>'
}

# -------------------------------------------------------------------- skipped
W '<h2>Skipped</h2>'
if ($skip.Count -eq 0) { W '<p class="empty">Nothing skipped.</p>' }
foreach ($t in $skip) {
    W '<div class="card skip">'
    $label = if ($t.name) { E $t.name } else { E $t.gid }
    W ('<p class="name">' + $label + '</p>')
    W ('<p class="meta"><code>' + (E $t.gid) + '</code></p>')
    if ($t.reason) { W ('<p class="why">' + (E $t.reason) + '</p>') }
    W '</div>'
}

W '<h2>Paste this back to Claude</h2>'
W '<pre id="out">Pick your answers above.</pre>'
W '</div>'
W '<div class="bar"><button id="copy">Copy answers</button>'
W '<button class="ghost" id="clear">Clear</button><span id="status"></span></div>'

$js = @'
<script>
var KEY = "nightly-" + document.title;
function load() {
  try {
    var s = localStorage.getItem(KEY); if (!s) return;
    var d = JSON.parse(s);
    Object.keys(d).forEach(function (n) {
      var el = document.querySelector('input[name="' + n + '"][value="' + d[n] + '"]');
      if (el) { el.checked = true; }
    });
  } catch (e) { }
}
function save() {
  var d = {};
  document.querySelectorAll('input[type=radio]:checked').forEach(function (el) { d[el.name] = el.value; });
  try { localStorage.setItem(KEY, JSON.stringify(d)); } catch (e) { }
  return d;
}
function paint() {
  document.querySelectorAll('label').forEach(function (l) {
    var r = l.querySelector('input');
    l.classList.toggle('sel', !!(r && r.checked));
  });
  var d = save(), by = {};
  Object.keys(d).forEach(function (n) {
    var i = n.indexOf("_");
    var g = n.slice(0, i), q = n.slice(i + 1);
    (by[g] = by[g] || []).push(q + "=" + d[n]);
  });
  var gids = Object.keys(by);
  var out = document.getElementById("out");
  if (!gids.length) { out.textContent = "Pick your answers above."; return; }
  out.textContent = gids.map(function (g) {
    return "/task-plan " + g + " - my answers: " + by[g].sort().join(", ") +
           ". Update the plan with these, then run /task-do " + g + ".";
  }).join("\n\n");
}
document.addEventListener("change", function (e) {
  if (e.target && e.target.type === "radio") { paint(); }
});
document.getElementById("copy").addEventListener("click", function () {
  var t = document.getElementById("out").textContent;
  var st = document.getElementById("status");
  navigator.clipboard.writeText(t).then(function () {
    st.textContent = "Copied."; setTimeout(function () { st.textContent = ""; }, 2000);
  }, function () {
    var r = document.createRange(); r.selectNode(document.getElementById("out"));
    getSelection().removeAllRanges(); getSelection().addRange(r);
    st.textContent = "Press Ctrl+C.";
  });
});
document.getElementById("clear").addEventListener("click", function () {
  document.querySelectorAll('input[type=radio]').forEach(function (r) { r.checked = false; });
  try { localStorage.removeItem(KEY); } catch (e) { }
  paint();
});
load(); paint();
</script>
'@
W $js
W '</body></html>'

$outPath = Join-Path $RunDir 'report.html'
[System.IO.File]::WriteAllText($outPath, $sb.ToString(), (New-Object System.Text.UTF8Encoding $false))
Write-Output "Wrote $outPath  ($($auto.Count) done, $($ask.Count) need you, $($skip.Count) skipped)"
if ($Open) { Start-Process $outPath }
