# Regenerates site/releases.json from the latest GitHub release (default: latest published).
# Usage: pwsh scripts/gen_site_releases.ps1 [-Tag v1.3.5]
param(
    [string]$Tag = ""
)

$ErrorActionPreference = "Stop"

if ($Tag -eq "") {
    $release = gh api repos/Sirius6907/Dizzy-v3/releases/latest | ConvertFrom-Json
} else {
    $release = gh api "repos/Sirius6907/Dizzy-v3/releases/tags/$Tag" | ConvertFrom-Json
}

$out = [ordered]@{
    tag    = $release.tag_name
    name   = $release.name
    assets = @(
        $release.assets | ForEach-Object {
            [ordered]@{
                url            = $_.browser_download_url
                name           = $_.name
                size           = $_.size
                download_count = $_.download_count
            }
        }
    )
}

$json = ConvertTo-Json -InputObject ([PSCustomObject]$out) -Compress -Depth 5
$dest = Join-Path $PSScriptRoot "..\site\releases.json"
# BOM-less UTF-8: a leading EF BB BF breaks JSON.parse in the site's
# main.js (fetch → r.json()). PS 5.1's `-Encoding utf8` writes a BOM.
[System.IO.File]::WriteAllText($dest, $json, [System.Text.UTF8Encoding]::new($false))
Write-Host "Wrote $dest"
Write-Host "tag: $($release.tag_name) | assets: $($release.assets.Count)"
