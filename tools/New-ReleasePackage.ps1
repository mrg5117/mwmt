# Creates a clean MWMT release zip without git metadata, reports, or backup payloads.

param(
    [string]$Version = (Get-Date -Format "yyyyMMdd-HHmmss")
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$distRoot = Join-Path $root "dist"
$stage = Join-Path $distRoot "MWMT"
$zip = Join-Path $distRoot "MWMT-$Version.zip"

if (Test-Path $stage) { Remove-Item -Path $stage -Recurse -Force }
if (-not (Test-Path $distRoot)) { New-Item -Path $distRoot -ItemType Directory -Force | Out-Null }

$excludeDirs = @(".git", "Backups", "Reports", "dist")
$excludeFiles = @("*.log", "*.tmp")

New-Item -Path $stage -ItemType Directory -Force | Out-Null
Get-ChildItem -Path $root -Force | Where-Object {
    $excludeDirs -notcontains $_.Name
} | ForEach-Object {
    $target = Join-Path $stage $_.Name
    if ($_.PSIsContainer) {
        Copy-Item -Path $_.FullName -Destination $target -Recurse -Force -Exclude $excludeFiles
    } else {
        Copy-Item -Path $_.FullName -Destination $target -Force
    }
}

if (Test-Path $zip) { Remove-Item -Path $zip -Force }
Compress-Archive -Path (Join-Path $stage "*") -DestinationPath $zip -Force
Write-Host "Release package created: $zip"
