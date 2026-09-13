Write-Host '---TOP RAM---'
Get-Process | Sort-Object WorkingSet64 -Descending | Select-Object -First 12 Name, @{N='RAM_MB';E={[int]($_.WorkingSet64/1MB)}}, Id | Format-Table -AutoSize
Write-Host '---JAVA DETAIL---'
Get-CimInstance Win32_Process -Filter "Name='java.exe' OR Name='javaw.exe'" | Select-Object ProcessId, @{N='RAM_MB';E={[int]($_.WorkingSetSize/1MB)}}, CommandLine | Format-List
Write-Host '---MEMORY---'
$os = Get-CimInstance Win32_OperatingSystem
$total = [int]($os.TotalVisibleMemorySize/1MB)
$free = [int]($os.FreePhysicalMemory/1MB)
Write-Host "Total: ${total}MB  Free: ${free}MB  Used: $($total-$free)MB"
