<#
.SYNOPSIS
  P0 live resource monitor for Dizzy soak tests.
.DESCRIPTION
  Logs WorkingSet RAM, Private MB, CPU% and GPU MB every -IntervalSec
  seconds while the app runs, and flags budget breaches:
    RAM  > 1800MB (Android-ish) / 2800MB (desktop)
    CPU  > 20% sustained
    GPU  > 2560MB (nvidia-smi, system-wide)
  Sudden 10-100x spikes = unbounded consumer (probe fan-out, VRAM spill).
  Slow growth over 30-40 min = leak (images, timers, subscriptions).

.USAGE
  powershell -NoProfile -ExecutionPolicy Bypass -File scripts/resource_monitor.ps1 `
    -ProcessName Dizzy -Minutes 45 -OutCsv soak_45min.csv
#>
param(
  [string]$ProcessName = 'Dizzy',
  [int]$Minutes = 45,
  [int]$IntervalSec = 10,
  [string]$OutCsv = "soak_$(Get-Date -Format 'yyyyMMdd_HHmm').csv",
  [int]$RamBudgetMb = 2800,
  [double]$CpuBudgetPct = 20.0,
  [int]$GpuBudgetMb = 2560
)

$deadline = (Get-Date).AddMinutes($Minutes)
$rows = @()
$overStreak = 0

function Get-GpuMb {
  try {
    $o = & nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits 2>$null
    if ($LASTEXITCODE -eq 0) { return [int]($o.Trim().Split()[0]) }
  } catch {}
  return $null
}

# Prime CPU counters (first read is always 0).
Get-Counter '\Process(*)\% Processor Time' -ErrorAction SilentlyContinue | Out-Null

'ts,ram_mb,private_mb,cpu_pct,gpu_mb,flag' | Out-File -FilePath $OutCsv -Encoding utf8
Write-Host "Monitoring [$ProcessName] for $Minutes min -> $OutCsv"

while ((Get-Date) -lt $deadline) {
  $procs = Get-Process -Name $ProcessName -ErrorAction SilentlyContinue
  if (-not $procs) {
    Write-Host 'process not running yet, waiting...'
    Start-Sleep -Seconds $IntervalSec
    continue
  }
  $ramMb = [int](($procs | Measure-Object WorkingSet64 -Sum).Sum / 1MB)
  $privMb = [int](($procs | Measure-Object PagedMemorySize64 -Sum).Sum / 1MB)

  Start-Sleep -Seconds 2
  $cpu = 0.0
  try {
    $c = Get-Counter "\Process($ProcessName*)\% Processor Time" -ErrorAction SilentlyContinue
    $cores = [Environment]::ProcessorCount
    if ($cores -lt 1) { $cores = 1 }
    $cpu = (($c.CounterSamples | Measure-Object CookedValue -Sum).Sum / $cores)
  } catch {}
  $gpu = Get-GpuMb

  $flag = 'ok'
  $bad = ($ramMb -gt $RamBudgetMb) -or ($cpu -gt $CpuBudgetPct) -or ($gpu -ne $null -and $gpu -gt $GpuBudgetMb)
  if ($bad) { $overStreak++; if ($overStreak -ge 2) { $flag = 'BREACHx2' } else { $flag = 'over' } }
  else { $overStreak = 0 }

  $line = '{0},{1},{2},{3:0.0},{4},{5}' -f (Get-Date -Format 'HH:mm:ss'), $ramMb, $privMb, $cpu, $gpu, $flag
  $line | Out-File -FilePath $OutCsv -Append -Encoding utf8
  Write-Host $line
  $sleepLeft = $IntervalSec - 2
  if ($sleepLeft -gt 0) { Start-Sleep -Seconds $sleepLeft }
}
Write-Host "Done. CSV: $OutCsv"
