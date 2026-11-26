# Deploys the two Netlify sites from the source each one is actually published
# from, instead of from whatever the working tree happens to hold.
#
# Why this exists: on 2026-11-26 the landing page was deployed with
# `--dir site` from `main`, which is the OLD Amber Royale page. The public site
# is published from `origin/site/landing-v14` (poster pass, 20 screenshots,
# social.webp/watch-party.webp). That deploy replaced the live page and dropped
# its images. This script reads the right ref every time and refuses to deploy
# a folder that does not look like the site it claims to be.
#
# Usage:
#   pwsh scripts/deploy_sites.ps1 -Target landing -Tag v1.3.7
#   pwsh scripts/deploy_sites.ps1 -Target admin
#   pwsh scripts/deploy_sites.ps1 -Target both -NoDeploy   # resolve + validate only
param(
    [ValidateSet("landing", "admin", "both")]
    [string]$Target = "both",
    # Regenerate releases.json for this tag before deploying the landing page.
    [string]$Tag = "",
    # Which ref holds the live landing page. main's site/ folder is stale.
    [string]$LandingRef = "origin/site/landing-v14",
    # Resolve and validate, then stop before calling netlify.
    [switch]$NoDeploy
)

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
$landingSite = "1dd79969-ea19-40bb-a512-9e025f484103"
$adminSite = "5c9dca14-8c4b-4a10-ac18-c6f2b74dac76"

function Fail([string]$msg) {
    Write-Host "FAIL $msg" -ForegroundColor Red
    exit 1
}

function Deploy([string]$dir, [string]$site, [string]$message) {
    if ($NoDeploy) {
        Write-Host "SKIP deploy ($site) - would publish $dir" -ForegroundColor Yellow
        return
    }
    & netlify deploy --prod --dir $dir --site $site --message $message
    if ($LASTEXITCODE -ne 0) { Fail "netlify deploy exited $LASTEXITCODE for $site" }
}

# --- landing ---------------------------------------------------------------
if ($Target -eq "landing" -or $Target -eq "both") {
    Push-Location $root
    try {
        & git rev-parse --verify --quiet $LandingRef *> $null
        if ($LASTEXITCODE -ne 0) { Fail "ref $LandingRef not found - run 'git fetch origin' first" }

        $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("dizzy-landing-" + [guid]::NewGuid().ToString("N"))
        New-Item -ItemType Directory -Path $tmp | Out-Null
        # zip + Expand-Archive, not tar: bsdtar treats the colon in a Windows
        # -C path as a remote host ("Cannot connect to C:").
        $zip = Join-Path $tmp "site.zip"
        & git archive --format=zip -o $zip $LandingRef site
        if ($LASTEXITCODE -ne 0) { Fail "git archive $LandingRef failed" }
        Expand-Archive -Path $zip -DestinationPath $tmp -Force
        Remove-Item $zip -Force
        $src = Join-Path $tmp "site"
        if (-not (Test-Path $src)) { Fail "$LandingRef has no site/ folder" }

        # The guard that would have caught the regression: the published landing
        # page has its own title and its own screenshot set.
        $index = Join-Path $src "index.html"
        if (-not (Test-Path $index)) { Fail "no index.html in $LandingRef : site" }
        $html = [System.IO.File]::ReadAllText($index)
        if ($html -notmatch "movies, music, manga") {
            Fail "$LandingRef does not look like the live landing page (title marker missing)"
        }
        $shots = @(Get-ChildItem (Join-Path $src "assets\img\shots") -ErrorAction SilentlyContinue)
        if ($shots.Count -lt 20) { Fail "expected 20 screenshots in $LandingRef, found $($shots.Count)" }

        if ($Tag -ne "") {
            & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "gen_site_releases.ps1") -Tag $Tag
            if ($LASTEXITCODE -ne 0) { Fail "gen_site_releases.ps1 -Tag $Tag failed" }
        }
        $rel = Join-Path $root "site\releases.json"
        if (-not (Test-Path $rel)) { Fail "site\releases.json missing - run gen_site_releases.ps1" }
        Copy-Item $rel (Join-Path $src "releases.json") -Force
        $relTag = (Get-Content (Join-Path $src "releases.json") -Raw | ConvertFrom-Json).tag
        Write-Host "landing - $LandingRef - releases.json $relTag - $($shots.Count) shots"

        Deploy $src $landingSite "landing $LandingRef $relTag"
        Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
    } finally {
        Pop-Location
    }
}

# --- admin -----------------------------------------------------------------
if ($Target -eq "admin" -or $Target -eq "both") {
    $dir = Join-Path $root "admin-dashboard"
    $html = [System.IO.File]::ReadAllText((Join-Path $dir "index.html"))
    if ($html -notmatch "Dizzy Control") { Fail "admin-dashboard\index.html does not look like the console" }
    if ($html -notmatch "Update campaign") { Fail "admin panel is missing the update campaign card" }
    Write-Host "admin - admin-dashboard - campaign card present"
    Deploy $dir $adminSite "admin dashboard"
}

Write-Host "done" -ForegroundColor Green
