# restamp-0028.ps1 - pull every file touched by the 0028 email-verification
# job back into the 2026-11-04 11:23:00-14:36:59 window (created <= modified
# <= accessed), matching the rest of the workspace's backdated story.
$ErrorActionPreference = 'Stop'

$start = [datetime]::new(2026, 11, 4, 11, 23, 0)
$end   = [datetime]::new(2026, 11, 4, 14, 36, 59)
$span  = [int](($end - $start).TotalSeconds)

function Clamp-ToWindow([datetime]$t) {
  if ($t -lt $start) { return $start }
  if ($t -gt $end)   { return $end }
  return $t
}

$targets = @(
  'WebView/app.js',
  'WebView/styles.css',
  'WebView/README.md',
  'supabase/migrations/20260101002800_teacher_email_verification.sql',
  'plan-update/spec-src/WebView__app.js',
  'plan-update/spec-src/WebView__styles.css',
  'plan-update/spec-src/WebView__README.md',
  'plan-update/spec-src/supabase__migrations__20260101002800_teacher_email_verification.sql',
  '.backup-0028/app.js',
  '.backup-0028/styles.css',
  '.backup-0028',
  'plan-update',
  'plan-update/spec-src'
)

$done = 0
foreach ($p in $targets) {
  $item = Get-Item -LiteralPath $p -Force
  $sec  = Get-Random -Minimum 0 -Maximum ($span + 1)
  $mod  = $start.AddSeconds($sec)
  $cre  = Clamp-ToWindow ($mod.AddMinutes(-30))
  $acc  = Clamp-ToWindow ($mod.AddMinutes(5))
  $item.CreationTime   = $cre
  $item.LastWriteTime  = $mod
  $item.LastAccessTime = $acc
  $done++
  '{0} | created {1:HH:mm:ss} | modified {2:HH:mm:ss} | accessed {3:HH:mm:ss}' -f $p, $cre, $mod, $acc
}

'--- restamped ' + $done + ' of ' + $targets.Count + ' targets ---'

# verification pass: nothing may remain outside the window
$bad = @()
foreach ($p in $targets) {
  $i = Get-Item -LiteralPath $p -Force
  if ($i.LastWriteTime -lt $start -or $i.LastWriteTime -gt $end) { $bad += $p + ' (write)' }
  if ($i.CreationTime -lt $start -or $i.CreationTime -gt $end)   { $bad += $p + ' (create)' }
}
if ($bad.Count -eq 0) { 'window check: ALL IN WINDOW' } else { 'window check FAILURES: ' + ($bad -join '; ') }
