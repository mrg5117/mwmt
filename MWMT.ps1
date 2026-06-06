# MackTechs Windows Migration Tool (MWMT)
# Portable backup, migration, and restore helper for Windows technicians.

param(
    [switch]$WhatIfMode
)

$ErrorActionPreference = "SilentlyContinue"
$script:Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$script:ConfigDir = Join-Path $script:Root "Config"
$script:BackupRoot = Join-Path $script:Root "Backups"
$script:ReportsRoot = Join-Path $script:Root "Reports"
$script:Timestamp = Get-Date -Format "yyyy-MM-dd_HHmmss"

foreach ($dir in @($script:BackupRoot, $script:ReportsRoot)) {
    if (-not (Test-Path $dir)) {
        New-Item -Path $dir -ItemType Directory -Force | Out-Null
    }
}

$script:ReportFile = Join-Path $script:ReportsRoot "MWMT_$($env:COMPUTERNAME)_$script:Timestamp.txt"

function Write-MwmtLog {
    param([string]$Message)
    $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')  $Message"
    Write-Host $Message
    Add-Content -Path $script:ReportFile -Value $line -Encoding UTF8
}

function Get-MwmtJson {
    param([string]$Path)
    return Get-Content -Path $Path -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Get-MwmtSource {
    $sources = @()
    $liveUsers = Join-Path $env:SystemDrive "Users"
    if (Test-Path $liveUsers) {
        $sources += [pscustomobject]@{
            Id = "live"
            Name = "Current Windows install ($env:SystemDrive)"
            DriveRoot = "$env:SystemDrive\"
            WindowsPath = Join-Path $env:SystemDrive "Windows"
            UsersPath = $liveUsers
            IsLive = $true
        }
    }

    Get-PSDrive -PSProvider FileSystem | ForEach-Object {
        $driveRoot = $_.Root
        $windowsPath = Join-Path $driveRoot "Windows"
        $usersPath = Join-Path $driveRoot "Users"
        if ((Test-Path $windowsPath) -and (Test-Path $usersPath) -and ($driveRoot -ne "$env:SystemDrive\")) {
            $sources += [pscustomobject]@{
                Id = $_.Name
                Name = "Offline Windows source ($driveRoot)"
                DriveRoot = $driveRoot
                WindowsPath = $windowsPath
                UsersPath = $usersPath
                IsLive = $false
            }
        }
    }

    return $sources
}

function Get-MwmtUserProfile {
    param([pscustomobject]$Source)

    $excluded = @("All Users", "Default", "Default User", "Public", "desktop.ini")
    Get-ChildItem -Path $Source.UsersPath -Directory -Force | Where-Object {
        $excluded -notcontains $_.Name
    } | ForEach-Object {
        [pscustomobject]@{
            Name = $_.Name
            Path = $_.FullName
            SourceId = $Source.Id
        }
    }
}

function Select-MwmtSingle {
    param(
        [string]$Title,
        [array]$Items
    )

    Write-MwmtLog ""
    Write-MwmtLog $Title
    for ($i = 0; $i -lt $Items.Count; $i++) {
        Write-Host ("  [{0}] {1}" -f ($i + 1), $Items[$i].Name)
    }
    do {
        $answer = Read-Host "Select one"
        $index = [int]$answer - 1
    } while ($index -lt 0 -or $index -ge $Items.Count)

    return $Items[$index]
}

function Select-MwmtMany {
    param(
        [string]$Title,
        [array]$Items
    )

    Write-MwmtLog ""
    Write-MwmtLog $Title
    for ($i = 0; $i -lt $Items.Count; $i++) {
        Write-Host ("  [{0}] {1}" -f ($i + 1), $Items[$i].Name)
    }
    Write-Host "  [A] All"
    $answer = Read-Host "Select numbers separated by commas, or A"
    if ($answer -match '^[Aa]$') { return $Items }

    $selected = @()
    foreach ($part in ($answer -split ",")) {
        $index = [int]($part.Trim()) - 1
        if ($index -ge 0 -and $index -lt $Items.Count) {
            $selected += $Items[$index]
        }
    }
    return $selected
}

function Select-MwmtCategory {
    param([array]$Categories)
    return Select-MwmtMany -Title "Select backup categories" -Items $Categories
}

function New-MwmtBackupSet {
    param([pscustomobject]$Source)
    $safeSource = ($Source.Id -replace '[\\/:*?"<>|]', '_')
    $target = Join-Path $script:BackupRoot "$safeSource`_$script:Timestamp"
    New-Item -Path $target -ItemType Directory -Force | Out-Null
    return $target
}

function Copy-MwmtFolder {
    param(
        [string]$SourcePath,
        [string]$DestinationPath,
        [array]$FolderExclusions,
        [array]$FileExclusions,
        [string]$LogPath
    )

    if (-not (Test-Path $SourcePath)) { return $false }
    if ($WhatIfMode) {
        Write-MwmtLog "WHATIF: robocopy $SourcePath -> $DestinationPath"
        return $true
    }

    New-Item -Path $DestinationPath -ItemType Directory -Force | Out-Null
    $args = @(
        "`"$SourcePath`"",
        "`"$DestinationPath`"",
        "/E", "/COPY:DAT", "/DCOPY:DAT", "/R:2", "/W:2", "/XJ", "/FFT", "/TEE", "/NP",
        "/LOG+:`"$LogPath`""
    )
    if ($FolderExclusions.Count -gt 0) {
        $args += "/XD"
        $args += $FolderExclusions
    }
    if ($FileExclusions.Count -gt 0) {
        $args += "/XF"
        $args += $FileExclusions
    }

    Write-MwmtLog "Copying $SourcePath"
    $process = Start-Process -FilePath "robocopy.exe" -ArgumentList $args -Wait -PassThru -NoNewWindow
    return ($process.ExitCode -le 7)
}

function Add-MwmtManifestRow {
    param(
        [string]$ManifestPath,
        [string]$UserName,
        [string]$Category,
        [string]$Item,
        [string]$SourcePath,
        [string]$DestinationPath,
        [string]$Status
    )

    $row = [pscustomobject]@{
        Timestamp = Get-Date -Format "s"
        UserName = $UserName
        Category = $Category
        Item = $Item
        SourcePath = $SourcePath
        DestinationPath = $DestinationPath
        Status = $Status
    }
    $row | Export-Csv -Path $ManifestPath -NoTypeInformation -Append
}

function Resolve-MwmtRoot {
    param(
        [string]$RootName,
        [pscustomobject]$Source,
        [pscustomobject]$Profile
    )

    switch ($RootName) {
        "profile" { return $Profile.Path }
        "publicDocuments" { return (Join-Path $Source.UsersPath "Public\Documents") }
        "driveRoot" { return $Source.DriveRoot }
        default { return $Profile.Path }
    }
}

function Invoke-MwmtRule {
    param(
        [pscustomobject]$Source,
        [pscustomobject]$Profile,
        [pscustomobject]$Category,
        [pscustomobject]$Rule,
        [string]$BackupSet,
        [string]$ManifestPath,
        [array]$FolderExclusions,
        [array]$FileExclusions,
        [string]$RoboLog
    )

    $userTargetRoot = Join-Path $BackupSet $Profile.Name
    $categoryTargetRoot = Join-Path $userTargetRoot $Category.id

    if ($Rule.type -eq "folder") {
        foreach ($relative in $Rule.relativePaths) {
            $sourcePath = Join-Path $Profile.Path $relative
            $targetPath = Join-Path $categoryTargetRoot $relative
            $ok = Copy-MwmtFolder $sourcePath $targetPath $FolderExclusions $FileExclusions $RoboLog
            Add-MwmtManifestRow $ManifestPath $Profile.Name $Category.name $Rule.name $sourcePath $targetPath $(if ($ok) { "Copied" } else { "MissingOrFailed" })
        }
    }

    if ($Rule.type -eq "folderPattern") {
        foreach ($pattern in $Rule.relativePatterns) {
            Get-ChildItem -Path $Profile.Path -Directory -Filter $pattern -ErrorAction SilentlyContinue | ForEach-Object {
                $targetPath = Join-Path $categoryTargetRoot $_.Name
                $ok = Copy-MwmtFolder $_.FullName $targetPath $FolderExclusions $FileExclusions $RoboLog
                Add-MwmtManifestRow $ManifestPath $Profile.Name $Category.name $Rule.name $_.FullName $targetPath $(if ($ok) { "Copied" } else { "MissingOrFailed" })
            }
        }
    }

    if ($Rule.type -eq "extensionSearch") {
        foreach ($rootName in $Rule.roots) {
            $rootPath = Resolve-MwmtRoot $rootName $Source $Profile
            foreach ($pattern in $Rule.patterns) {
                Get-ChildItem -Path $rootPath -File -Recurse -Filter $pattern -ErrorAction SilentlyContinue | ForEach-Object {
                    $relative = $_.FullName.Substring($rootPath.Length).TrimStart("\")
                    $targetPath = Join-Path (Join-Path $categoryTargetRoot $Rule.name) $relative
                    if (-not $WhatIfMode) {
                        New-Item -Path (Split-Path -Parent $targetPath) -ItemType Directory -Force | Out-Null
                        Copy-Item -Path $_.FullName -Destination $targetPath -Force
                    }
                    Add-MwmtManifestRow $ManifestPath $Profile.Name $Category.name $Rule.name $_.FullName $targetPath "Copied"
                }
            }
        }
    }

    if ($Rule.type -eq "publicFolders") {
        foreach ($relative in $Rule.relativePaths) {
            $sourcePath = Join-Path (Join-Path $Source.UsersPath "Public") $relative
            $targetPath = Join-Path (Join-Path $BackupSet "Public") $relative
            $ok = Copy-MwmtFolder $sourcePath $targetPath $FolderExclusions $FileExclusions $RoboLog
            Add-MwmtManifestRow $ManifestPath "Public" $Category.name $Rule.name $sourcePath $targetPath $(if ($ok) { "Copied" } else { "MissingOrFailed" })
        }
    }
}

function Export-MwmtWindowsLicense {
    param([string]$BackupSet)

    $target = Join-Path $BackupSet "System\WindowsLicense.txt"
    New-Item -Path (Split-Path -Parent $target) -ItemType Directory -Force | Out-Null

    $lines = @()
    $lines += "Windows License Export"
    $lines += "Computer: $env:COMPUTERNAME"
    $lines += "Collected: $(Get-Date -Format s)"
    $lines += ""
    $lines += "DigitalProductId and BackupProductKeyDefault are not always reusable on Windows 10/11 digital-license systems."
    $lines += ""

    $softwareProtection = Get-CimInstance -ClassName SoftwareLicensingProduct | Where-Object {
        $_.PartialProductKey -and $_.LicenseStatus -eq 1
    } | Select-Object Name, Description, PartialProductKey, LicenseStatus
    $lines += "Licensed products:"
    $lines += ($softwareProtection | Format-List | Out-String)

    $keyPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SoftwareProtectionPlatform"
    $backupKey = (Get-ItemProperty -Path $keyPath -Name BackupProductKeyDefault -ErrorAction SilentlyContinue).BackupProductKeyDefault
    if ($backupKey) {
        $lines += "BackupProductKeyDefault: $backupKey"
    } else {
        $lines += "BackupProductKeyDefault: not available"
    }

    $lines | Set-Content -Path $target -Encoding UTF8
    Write-MwmtLog "Windows license info saved to $target"
}

function Export-MwmtBitLockerInfo {
    param([string]$BackupSet)

    $target = Join-Path $BackupSet "System\BitLocker.txt"
    New-Item -Path (Split-Path -Parent $target) -ItemType Directory -Force | Out-Null
    $lines = @()
    $lines += "BitLocker Export"
    $lines += "Computer: $env:COMPUTERNAME"
    $lines += "Collected: $(Get-Date -Format s)"
    $lines += ""

    if (Get-Command Get-BitLockerVolume -ErrorAction SilentlyContinue) {
        $volumes = Get-BitLockerVolume
        $lines += ($volumes | Format-List | Out-String)
    } else {
        $lines += "Get-BitLockerVolume is unavailable on this system."
    }

    if (Get-Command manage-bde.exe -ErrorAction SilentlyContinue) {
        $lines += ""
        $lines += "manage-bde -protectors -get output:"
        Get-PSDrive -PSProvider FileSystem | ForEach-Object {
            $drive = "$($_.Name):"
            $lines += ""
            $lines += "Drive $drive"
            $lines += (& manage-bde.exe -protectors -get $drive 2>&1 | Out-String)
        }
    }

    $lines | Set-Content -Path $target -Encoding UTF8
    Write-MwmtLog "BitLocker info saved to $target"
}

function Invoke-MwmtBackup {
    $categoryConfig = Get-MwmtJson (Join-Path $script:ConfigDir "Categories.json")
    $exclusionConfig = Get-MwmtJson (Join-Path $script:ConfigDir "Exclusions.json")
    $sources = @(Get-MwmtSource)
    if ($sources.Count -eq 0) {
        Write-MwmtLog "No Windows sources found."
        return
    }

    $source = Select-MwmtSingle "Select backup source" $sources
    $profiles = @(Get-MwmtUserProfile $source)
    if ($profiles.Count -eq 0) {
        Write-MwmtLog "No user profiles found at $($source.UsersPath)."
        return
    }

    $selectedProfiles = @(Select-MwmtMany "Select users to back up" $profiles)
    $selectedCategories = @(Select-MwmtCategory $categoryConfig.categories)
    if ($selectedProfiles.Count -eq 0 -or $selectedCategories.Count -eq 0) {
        Write-MwmtLog "No users or categories selected."
        return
    }

    $backupSet = New-MwmtBackupSet $source
    $manifestPath = Join-Path $backupSet "manifest.csv"
    $roboLog = Join-Path $backupSet "robocopy.log"
    Write-MwmtLog "Backup set: $backupSet"

    Export-MwmtWindowsLicense $backupSet
    Export-MwmtBitLockerInfo $backupSet

    foreach ($profile in $selectedProfiles) {
        foreach ($category in $selectedCategories) {
            foreach ($rule in $category.rules) {
                Invoke-MwmtRule $source $profile $category $rule $backupSet $manifestPath $exclusionConfig.defaultFolderExclusions $exclusionConfig.defaultFileExclusions $roboLog
            }
        }
    }

    Write-MwmtLog "Backup complete. Manifest: $manifestPath"
}

function Show-MwmtMenu {
    Write-Host ""
    Write-Host "MackTechs Windows Migration Tool (MWMT)"
    Write-Host "  1 = Backup data"
    Write-Host "  2 = Restore / migrate data"
    Write-Host "  3 = Export Windows license and BitLocker only"
    Write-Host "  Q = Quit"
    return Read-Host "Choice"
}

Write-MwmtLog "MWMT started from $script:Root"

switch (Show-MwmtMenu) {
    "1" { Invoke-MwmtBackup }
    "2" { Write-MwmtLog "Restore is planned for a later release. Use backup mode first." }
    "3" {
        $backupSet = Join-Path $script:ReportsRoot "SystemInfo_$script:Timestamp"
        New-Item -Path $backupSet -ItemType Directory -Force | Out-Null
        Export-MwmtWindowsLicense $backupSet
        Export-MwmtBitLockerInfo $backupSet
    }
    default { Write-MwmtLog "MWMT closed." }
}
