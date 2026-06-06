# Windows smoke tests for MWMT.
# Run from the repository root on Windows:
#   powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-MWMT.ps1

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$scriptPath = Join-Path $root "MWMT.ps1"
$categoriesPath = Join-Path $root "Config\Categories.json"
$exclusionsPath = Join-Path $root "Config\Exclusions.json"

if (-not (Test-Path $scriptPath)) { throw "Missing MWMT.ps1" }
if (-not (Test-Path $categoriesPath)) { throw "Missing Categories.json" }
if (-not (Test-Path $exclusionsPath)) { throw "Missing Exclusions.json" }

$tokens = $null
$errors = $null
[System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$errors) | Out-Null
if ($errors.Count -gt 0) {
    $errors | ForEach-Object { Write-Host $_.Message -ForegroundColor Red }
    throw "PowerShell parser found $($errors.Count) error(s)."
}

$categories = Get-Content -Path $categoriesPath -Raw -Encoding UTF8 | ConvertFrom-Json
$exclusions = Get-Content -Path $exclusionsPath -Raw -Encoding UTF8 | ConvertFrom-Json
if (-not $categories.categories) { throw "Categories.json has no categories array." }
if (-not $exclusions.defaultFolderExclusions) { throw "Exclusions.json has no defaultFolderExclusions." }

Write-Host "MWMT Windows smoke tests passed."
