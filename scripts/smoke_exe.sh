#!/bin/bash
# Smoke launch fresh-built dizzy.exe + 2-min resource monitor, then kill.
cd C:/Users/opcha/Downloads/Dizzy-v3
APP_DIR=C:/Users/opcha/Downloads/Dizzy-v3/release-artifacts/windows-x64
powershell -NoProfile -Command 'Start-Process -FilePath "C:/Users/opcha/Downloads/Dizzy-v3/release-artifacts/windows-x64/dizzy.exe" -WorkingDirectory "C:/Users/opcha/Downloads/Dizzy-v3/release-artifacts/windows-x64"'
echo "launched, waiting 15s for boot..."
sleep 15
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/resource_monitor.ps1 -ProcessName dizzy -Minutes 2 -IntervalSec 10 -OutCsv smoke_20260913.csv
echo "===MONITOR DONE==="
cat smoke_20260913.csv 2>/dev/null | head -n 20
taskkill /F /IM dizzy.exe 2>&1 | head -n 3
echo "SMOKE DONE"
