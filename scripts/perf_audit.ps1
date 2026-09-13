<#
.SYNOPSIS
  P14 perf-gate audit for Dizzy. Fails (exit 1) on any hard-limit violation.
.DESCRIPTION
  Checks, all grep-based on lib/:
   1. No CachedNetworkImage without memCacheWidth in its constructor block.
   2. No precacheImage without ResizeImage (full-res precache = OOM).
   3. No Timer.periodic below 5s in player_screen.dart (radio wakeups).
   4. No hardcoded 150MB/157286400 demuxer bytes outside player_settings.dart.
   5. Every file calling WakelockPlus.enable also calls disable.
   6. AnimatedAmbientBackground + waveform tickers gated (perf/playing flags).
  Run in CI / before every release: a violation = overheat regression.

.USAGE
  powershell -NoProfile -ExecutionPolicy Bypass -File scripts/perf_audit.ps1
#>
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$lib = Join-Path $repo 'lib'
$fail = 0

function Fail($msg) {
  Write-Host "FAIL: $msg" -ForegroundColor Red
  $script:fail++
}
function Ok($msg) { Write-Host "ok: $msg" -ForegroundColor Green }

# ── 1. CachedNetworkImage caps ──────────────────────────────
$uncapped = @()
foreach ($f in Get-ChildItem -Recurse -Filter *.dart $lib) {
  $lines = Get-Content $f.FullName
  for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match 'CachedNetworkImage\(') {
      $block = ($lines[$i..([Math]::Min($i + 14, $lines.Count - 1))] -join "`n")
      if ($block -notmatch 'memCacheWidth') {
        $uncapped += "$($f.FullName):$($i + 1)"
      }
    }
  }
}
if ($uncapped.Count -gt 0) { Fail("uncapped:" + ($uncapped -join " | ")) }
else { Ok('all CachedNetworkImage decode-capped') }

# ── 2. precacheImage must use ResizeImage ───────────────────
$badPre = Select-String -Path "$lib/**/*.dart" -Pattern 'precacheImage\(' | Where-Object {
  $_.Line -notmatch 'ResizeImage' -and
  (Get-Content $_.Path)[0..([Math]::Max(0, $_.LineNumber - 6))] -join "`n" -notmatch 'ResizeImage'
} | ForEach-Object { "$($_.Path):$($_.LineNumber)" }
# Simpler precise check: precacheImage call whose line lacks ResizeImage AND next 4 lines lack it.
$badPre = @()
foreach ($f in Get-ChildItem -Recurse -Filter *.dart $lib) {
  $lines = Get-Content $f.FullName
  for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match 'precacheImage\(') {
      $window = ($lines[$i..([Math]::Min($i + 5, $lines.Count - 1))] -join "`n")
      if ($window -notmatch 'ResizeImage') { $badPre += "$($f.FullName):$($i + 1)" }
    }
  }
}
if ($badPre.Count -gt 0) { Fail("full-res precache:" + ($badPre -join " | ")) }
else { Ok('all precacheImage resize-capped') }

# ── 3. player timers ≥ 5s ───────────────────────────────────
$fast = Select-String -Path (Join-Path $lib 'pages/player/player_screen.dart') -Pattern 'Timer\.periodic\(const Duration\((seconds|milliseconds): (\d+)' |
  Where-Object {
    ($_.Matches[0].Groups[1].Value -eq 'seconds' -and [int]$_.Matches[0].Groups[2].Value -lt 5) -or
    ($_.Matches[0].Groups[1].Value -eq 'milliseconds')
  } | ForEach-Object { "player_screen.dart:$($_.LineNumber): $($_.Line.Trim())" }
if ($fast.Count -gt 0 -and $fast -ne $null) { Fail("sub-5s timers:" + ($fast -join " | ")) }
else { Ok('player timers >= 5s') }

# ── 4. no hardcoded big demuxer bytes outside player_settings ──
$hard = Select-String -Path "$lib/**/*.dart" -Pattern '157286400|104857600' |
  Where-Object { $_.Path -notmatch 'player_settings\.dart' } |
  ForEach-Object { "$($_.Path):$($_.LineNumber)" }
if ($hard.Count -gt 0 -and $hard -ne $null) { Fail("hardcoded demuxer:" + ($hard -join " | ")) }
else { Ok('demuxer bytes centralized') }

# ── 5. wakelock pairing ─────────────────────────────────────
$unpaired = @()
foreach ($f in Get-ChildItem -Recurse -Filter *.dart $lib) {
  $t = Get-Content $f.FullName -Raw
  $en = ([regex]::Matches($t, 'WakelockPlus\.enable\(\)')).Count
  $dis = ([regex]::Matches($t, 'WakelockPlus\.disable\(\)')).Count
  if ($en -gt 0 -and $dis -eq 0) { $unpaired += $f.FullName }
}
if ($unpaired.Count -gt 0) { Fail("wakelock unpaired:" + ($unpaired -join " | ")) }
else { Ok('wakelock enable/disable paired') }

# ── 6. animation gating markers ─────────────────────────────
$gateChecks = @(
  @{ f = 'widgets/common/animated_ambient_background.dart'; p = 'ambientAllowed' },
  @{ f = 'widgets/common/performance_liquid_lens.dart'; p = 'glassAllowed' },
  @{ f = 'widgets/music/music_waveform_seekbar.dart'; p = 'isPlaying' },
  @{ f = 'widgets/audiobook/audiobook_waveform_seekbar.dart'; p = 'isPlaying' },
  @{ f = 'pages/anime/anime_page.dart'; p = 'ambientAllowed' }
)
foreach ($g in $gateChecks) {
  $t = Get-Content (Join-Path $lib $g.f) -Raw
  if ($t -notmatch $g.p) { Fail("$($g.f) missing gate $($g.p)") }
  else { Ok("$($g.f) gated") }
}

if ($fail -gt 0) { Write-Host "`n$fail gate(s) FAILED" -ForegroundColor Red; exit 1 }
Write-Host '`nAll perf gates pass.' -ForegroundColor Green
