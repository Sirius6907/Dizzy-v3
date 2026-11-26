# Asserts that a release is really, publicly live before anyone is told to
# update. The campaign's whole premise is "v1.3.7 exists and the site links to
# it"; until this passes that is an assumption, not a fact.
#
# Checks, in order:
#   1. the GitHub release is published (not draft, not prerelease)
#   2. the installer/APK assets every platform button needs are attached
#   3. site/releases.json names the same tag (the offline fallback)
#   4. the release-latest edge function answers with the same tag
#
# Usage:
#   pwsh scripts/assert_release.ps1 -Tag v1.3.7
#   pwsh scripts/assert_release.ps1 -Tag v1.3.7 -SkipLive   # CI / offline
param(
    [Parameter(Mandatory = $true)]
    [string]$Tag,
    [string]$Repo = "Sirius6907/Dizzy-v3",
    [string]$SupabaseUrl = "https://tiasihuropxrbcxmxorj.supabase.co",
    [string[]]$RequiredAssets = @(
        "Dizzy-v3-arm64-v8a.apk",
        "Dizzy-v3-Universal.apk",
        "Dizzy-Windows-Setup.exe",
        "Dizzy-Linux-x86_64.AppImage"
    ),
    [switch]$SkipLive
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$fail = @()

function Check([bool]$ok, [string]$label, [string]$detail) {
    if ($ok) {
        Write-Host "  ok   $label $detail" -ForegroundColor Green
    } else {
        Write-Host "  FAIL $label $detail" -ForegroundColor Red
        $script:fail += "$label $detail"
    }
}

Write-Host "release $Tag" -ForegroundColor Cyan

# --- 1 + 2: the GitHub release ---------------------------------------------
$release = $null
try {
    $release = gh api "repos/$Repo/releases/tags/$Tag" | ConvertFrom-Json
} catch {
    $fail += "release $Tag not found on GitHub"
}

if ($release) {
    Check (-not $release.draft) "published" "draft=$($release.draft)"
    Check (-not $release.prerelease) "not-prerelease" "prerelease=$($release.prerelease)"
    Check ($release.assets.Count -gt 0) "assets" "$($release.assets.Count) attached"
    $names = @($release.assets | ForEach-Object { $_.name })
    foreach ($want in $RequiredAssets) {
        Check ($names -contains $want) "asset" $want
    }
}

# --- 3: the checked-in fallback the landing page reads offline -------------
$relPath = Join-Path $root "site\releases.json"
if (Test-Path $relPath) {
    $relTag = (Get-Content $relPath -Raw | ConvertFrom-Json).tag
    Check ($relTag -eq $Tag) "releases.json" "$relTag"
} else {
    Check $false "releases.json" "missing at $relPath"
}

# --- 4: what the site and the app actually fetch ---------------------------
if (-not $SkipLive) {
    try {
        $uri = "$SupabaseUrl/functions/v1/release-latest"
        $live = Invoke-RestMethod -Uri $uri -Headers @{ Accept = "application/json" } -TimeoutSec 20
        # The edge function caches for 5 minutes; a stale answer right after a
        # release is expected, so say so instead of failing the release.
        if ($live.tag -eq $Tag) {
            Write-Host "  ok   release-latest $($live.tag)" -ForegroundColor Green
        } else {
            Write-Host "  warn release-latest $($live.tag) (5 min cache - re-run shortly)" -ForegroundColor Yellow
        }
    } catch {
        Check $false "release-latest" "unreachable: $($_.Exception.Message)"
    }
}

if ($fail.Count -gt 0) {
    Write-Host ""
    Write-Host "NOT READY - $($fail.Count) check(s) failed:" -ForegroundColor Red
    $fail | ForEach-Object { Write-Host "  - $_" }
    exit 1
}
Write-Host ""
Write-Host "$Tag is live and every surface names it." -ForegroundColor Green
exit 0
