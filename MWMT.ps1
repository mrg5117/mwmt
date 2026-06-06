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
$script:DryRunOnly = $false
$script:CopyResults = @()

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

function Ask-MwmtYesNo {
    param(
        [string]$Prompt,
        [bool]$Default = $false
    )

    $defaultLabel = if ($Default) { "Y" } else { "N" }
    $answer = Read-Host "$Prompt (Y/N, Enter = $defaultLabel)"
    if ([string]::IsNullOrWhiteSpace($answer)) {
        return $Default
    }
    return ($answer -match '^[Yy]')
}

function New-MwmtSourceObject {
    param(
        [string]$Id,
        [string]$Name,
        [string]$DriveRoot,
        [string]$WindowsPath,
        [string]$UsersPath,
        [bool]$IsLive
    )

    return [pscustomobject]@{
        Id = $Id
        Name = $Name
        DriveRoot = $DriveRoot
        WindowsPath = $WindowsPath
        UsersPath = $UsersPath
        IsLive = $IsLive
    }
}

function New-MwmtManualSource {
    $manualPath = Read-Host "Enter manual Windows source path (example: E:\ or E:\Windows.old)"
    if ([string]::IsNullOrWhiteSpace($manualPath)) { return $null }

    $root = $manualPath.TrimEnd("\")
    $windowsPath = Join-Path $root "Windows"
    $usersPath = Join-Path $root "Users"
    if ((Split-Path -Leaf $root) -ieq "Windows") {
        $windowsPath = $root
        $usersPath = Join-Path (Split-Path -Parent $root) "Users"
    }

    if (-not (Test-Path $usersPath)) {
        Write-MwmtLog "Manual source rejected because Users folder was not found: $usersPath"
        return $null
    }

    return New-MwmtSourceObject "manual" "Manual Windows source ($root)" $root $windowsPath $usersPath $false
}

function Mount-MwmtWindowsImage {
    if (-not (Get-Command Mount-DiskImage -ErrorAction SilentlyContinue)) {
        Write-MwmtLog "Mount-DiskImage is unavailable on this system."
        return
    }

    $imagePath = Read-Host "Enter VHD/VHDX/ISO image path to mount"
    if ([string]::IsNullOrWhiteSpace($imagePath) -or -not (Test-Path $imagePath)) {
        Write-MwmtLog "Image path not found: $imagePath"
        return
    }

    Write-MwmtLog "Mounting image: $imagePath"
    Mount-DiskImage -ImagePath $imagePath | Out-Null
}

function Get-MwmtSource {
    $sources = @()
    $liveUsers = Join-Path $env:SystemDrive "Users"
    if (Test-Path $liveUsers) {
        $sources += New-MwmtSourceObject "live" "Current Windows install ($env:SystemDrive)" "$env:SystemDrive\" (Join-Path $env:SystemDrive "Windows") $liveUsers $true
    }

    Get-PSDrive -PSProvider FileSystem | ForEach-Object {
        $driveRoot = $_.Root
        $windowsPath = Join-Path $driveRoot "Windows"
        $usersPath = Join-Path $driveRoot "Users"
        if ((Test-Path $windowsPath) -and (Test-Path $usersPath) -and ($driveRoot -ne "$env:SystemDrive\")) {
            $sources += New-MwmtSourceObject $_.Name "Offline Windows source ($driveRoot)" $driveRoot $windowsPath $usersPath $false
        }

        $windowsOldPath = Join-Path $driveRoot "Windows.old\Windows"
        $windowsOldUsers = Join-Path $driveRoot "Windows.old\Users"
        if ((Test-Path $windowsOldPath) -and (Test-Path $windowsOldUsers)) {
            $sources += New-MwmtSourceObject "$($_.Name)_WindowsOld" "Offline Windows.old source ($driveRoot Windows.old)" (Join-Path $driveRoot "Windows.old") $windowsOldPath $windowsOldUsers $false
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

function Add-MwmtCopyResult {
    param(
        [string]$SourcePath,
        [string]$DestinationPath,
        [string]$Status,
        [int]$ExitCode = -1
    )

    $script:CopyResults += [pscustomobject]@{
        SourcePath = $SourcePath
        DestinationPath = $DestinationPath
        Status = $Status
        ExitCode = $ExitCode
    }
}

function Get-MwmtFolderSize {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return 0 }
    $size = 0
    Get-ChildItem -Path $Path -Recurse -Force -ErrorAction SilentlyContinue | ForEach-Object {
        if (-not $_.PSIsContainer) { $size += $_.Length }
    }
    return $size
}

function Test-MwmtCloudPlaceholder {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return $false }
    $item = Get-Item -Path $Path -Force -ErrorAction SilentlyContinue
    if (-not $item) { return $false }
    $attributes = $item.Attributes.ToString()
    return ($attributes -match "Offline" -or $attributes -match "RecallOnDataAccess" -or $attributes -match "Unpinned")
}

function Get-MwmtBackupEstimate {
    param(
        [array]$Profiles,
        [array]$Categories,
        [pscustomobject]$Source
    )

    $totalBytes = 0
    $foundItems = 0
    $warnings = @()

    foreach ($profile in $Profiles) {
        foreach ($category in $Categories) {
            foreach ($rule in $category.rules) {
                if ($rule.type -eq "folder") {
                    foreach ($relative in $rule.relativePaths) {
                        $path = Join-Path $profile.Path $relative
                        if (Test-Path $path) {
                            $foundItems++
                            $totalBytes += Get-MwmtFolderSize $path
                            if (Test-MwmtCloudPlaceholder $path) {
                                $warnings += "CloudPlaceholderWarning: $path may contain cloud-only placeholder content."
                            }
                        }
                    }
                }
                if ($rule.type -eq "folderPattern") {
                    foreach ($pattern in $rule.relativePatterns) {
                        Get-ChildItem -Path $profile.Path -Directory -Filter $pattern -ErrorAction SilentlyContinue | ForEach-Object {
                            $foundItems++
                            $totalBytes += Get-MwmtFolderSize $_.FullName
                            if (Test-MwmtCloudPlaceholder $_.FullName) {
                                $warnings += "CloudPlaceholderWarning: $($_.FullName) may contain cloud-only placeholder content."
                            }
                        }
                    }
                }
            }
        }
    }

    return [pscustomobject]@{
        FoundItems = $foundItems
        TotalBytes = $totalBytes
        TotalGB = [math]::Round(($totalBytes / 1GB), 2)
        Warnings = $warnings
    }
}

function Copy-MwmtFolder {
    param(
        [string]$SourcePath,
        [string]$DestinationPath,
        [array]$FolderExclusions,
        [array]$FileExclusions,
        [string]$LogPath
    )

    if (-not (Test-Path $SourcePath)) {
        Add-MwmtCopyResult $SourcePath $DestinationPath "Missing" -1
        return $false
    }
    if ($WhatIfMode -or $script:DryRunOnly) {
        Write-MwmtLog "WHATIF: robocopy $SourcePath -> $DestinationPath"
        Add-MwmtCopyResult $SourcePath $DestinationPath "WhatIf" 0
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
    $ok = ($process.ExitCode -le 7)
    Add-MwmtCopyResult $SourcePath $DestinationPath $(if ($ok) { "Copied" } else { "Failed" }) $process.ExitCode
    return $ok
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
        if ($Rule.absolutePathPatterns) {
            foreach ($pattern in $Rule.absolutePathPatterns) {
                $sourcePattern = $pattern
                if ($Source.DriveRoot -and $Source.DriveRoot -ne "C:\") {
                    $sourcePattern = Join-Path $Source.DriveRoot $pattern.Substring(3)
                }
                Get-ChildItem -Path $sourcePattern -Directory -ErrorAction SilentlyContinue | ForEach-Object {
                    $targetPath = Join-Path $categoryTargetRoot ("absolute_" + ($_.FullName -replace '[\\/:*?"<>|]', '_'))
                    $ok = Copy-MwmtFolder $_.FullName $targetPath $FolderExclusions $FileExclusions $RoboLog
                    Add-MwmtManifestRow $ManifestPath $Profile.Name $Category.name $Rule.name $_.FullName $targetPath $(if ($ok) { "Copied" } else { "MissingOrFailed" })
                }
            }
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
                    Add-MwmtCopyResult $_.FullName $targetPath "Copied" 0
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

function Write-MwmtVerificationSummary {
    param([string]$BackupSet)

    $target = Join-Path $BackupSet "VerificationSummary.txt"
    $copied = @($script:CopyResults | Where-Object { $_.Status -eq "Copied" }).Count
    $failed = @($script:CopyResults | Where-Object { $_.Status -eq "Failed" }).Count
    $missing = @($script:CopyResults | Where-Object { $_.Status -eq "Missing" }).Count
    $whatIf = @($script:CopyResults | Where-Object { $_.Status -eq "WhatIf" }).Count

    $lines = @()
    $lines += "MWMT Verification Summary"
    $lines += "Collected: $(Get-Date -Format s)"
    $lines += "Copied: $copied"
    $lines += "Failed: $failed"
    $lines += "Missing: $missing"
    $lines += "DryRun/WhatIf: $whatIf"
    $lines += ""
    $lines += "Robocopy exit codes 0-7 are treated as successful. Exit code 8 or higher needs review."
    $lines += ""
    $lines += ($script:CopyResults | Format-Table -AutoSize | Out-String)

    $lines | Set-Content -Path $target -Encoding UTF8
    Write-MwmtLog "Verification summary saved to $target"
}

function Export-MwmtWindowsLicense {
    param([string]$BackupSet)

    $target = Join-Path $BackupSet "System\Security\WindowsLicense.txt"
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

    $target = Join-Path $BackupSet "System\Security\BitLocker.txt"
    New-Item -Path (Split-Path -Parent $target) -ItemType Directory -Force | Out-Null
    $lines = @()
    $lines += "BitLocker Export"
    $lines += "Sensitive: BitLocker recovery keys can unlock customer data. Store and dispose of this report carefully."
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
    if (Ask-MwmtYesNo "Mount a VHD/VHDX/ISO image before source detection?" $false) {
        Mount-MwmtWindowsImage
    }
    $sources = @(Get-MwmtSource)
    if (Ask-MwmtYesNo "Add a manual source path?" $false) {
        $manualSource = New-MwmtManualSource
        if ($manualSource) { $sources += $manualSource }
    }
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

    $estimate = Get-MwmtBackupEstimate $selectedProfiles $selectedCategories $source
    Write-MwmtLog "Estimate: $($estimate.FoundItems) folder item(s), about $($estimate.TotalGB) GB before exclusions."
    foreach ($warning in $estimate.Warnings) {
        Write-MwmtLog $warning
    }
    $script:DryRunOnly = Ask-MwmtYesNo "Dry run / estimate only?" $false

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

    Write-MwmtVerificationSummary $backupSet
    Write-MwmtLog "Backup complete. Manifest: $manifestPath"
}

function Get-MwmtBackupSet {
    if (-not (Test-Path $script:BackupRoot)) { return @() }
    Get-ChildItem -Path $script:BackupRoot -Directory | Where-Object {
        Test-Path (Join-Path $_.FullName "manifest.csv")
    } | Sort-Object LastWriteTime -Descending | ForEach-Object {
        [pscustomobject]@{
            Name = "$($_.Name) - $($_.LastWriteTime)"
            Path = $_.FullName
        }
    }
}

function Get-MwmtLiveDestinationProfile {
    $source = New-MwmtSourceObject "live" "Current Windows install ($env:SystemDrive)" "$env:SystemDrive\" (Join-Path $env:SystemDrive "Windows") (Join-Path $env:SystemDrive "Users") $true
    return @(Get-MwmtUserProfile $source)
}

function Copy-MwmtRestoreFolder {
    param(
        [string]$SourcePath,
        [string]$DestinationPath,
        [bool]$Overwrite
    )

    if (-not (Test-Path $SourcePath)) {
        Write-MwmtLog "Restore source missing: $SourcePath"
        return $false
    }
    if ((Test-Path $DestinationPath) -and (-not $Overwrite)) {
        Write-MwmtLog "Skipped existing destination: $DestinationPath"
        return $false
    }
    if ($WhatIfMode) {
        Write-MwmtLog "WHATIF: restore $SourcePath -> $DestinationPath"
        return $true
    }

    $args = @("`"$SourcePath`"", "`"$DestinationPath`"", "/E", "/COPY:DAT", "/DCOPY:DAT", "/R:2", "/W:2", "/XJ", "/FFT", "/TEE", "/NP")
    $process = Start-Process -FilePath "robocopy.exe" -ArgumentList $args -Wait -PassThru -NoNewWindow
    return ($process.ExitCode -le 7)
}

function Copy-MwmtRestoreItem {
    param(
        [string]$SourcePath,
        [string]$DestinationPath,
        [bool]$Overwrite
    )

    if (-not (Test-Path $SourcePath)) {
        Write-MwmtLog "Restore source missing: $SourcePath"
        return $false
    }

    $item = Get-Item -Path $SourcePath -Force
    if ($item.PSIsContainer) {
        return Copy-MwmtRestoreFolder $SourcePath $DestinationPath $Overwrite
    }

    if ((Test-Path $DestinationPath) -and (-not $Overwrite)) {
        Write-MwmtLog "Skipped existing file: $DestinationPath"
        return $false
    }
    if ($WhatIfMode) {
        Write-MwmtLog "WHATIF: restore file $SourcePath -> $DestinationPath"
        return $true
    }

    New-Item -Path (Split-Path -Parent $DestinationPath) -ItemType Directory -Force | Out-Null
    Copy-Item -Path $SourcePath -Destination $DestinationPath -Force
    return $true
}

function Invoke-MwmtRestore {
    $backupSets = @(Get-MwmtBackupSet)
    if ($backupSets.Count -eq 0) {
        Write-MwmtLog "No backup sets found in $script:BackupRoot."
        return
    }

    $backupSet = Select-MwmtSingle "Select backup set to restore" $backupSets
    $manifestPath = Join-Path $backupSet.Path "manifest.csv"
    $manifest = @(Import-Csv -Path $manifestPath)
    if ($manifest.Count -eq 0) {
        Write-MwmtLog "Manifest is empty: $manifestPath"
        return
    }

    $users = @($manifest | Where-Object { $_.UserName -ne "Public" } | Select-Object -ExpandProperty UserName -Unique | ForEach-Object {
        [pscustomobject]@{ Name = $_; Value = $_ }
    })
    $backupUser = Select-MwmtSingle "Select backed-up user" $users

    $categories = @($manifest | Where-Object { $_.UserName -eq $backupUser.Value -or $_.UserName -eq "Public" } | Select-Object -ExpandProperty Category -Unique | ForEach-Object {
        [pscustomobject]@{ Name = $_; Value = $_ }
    })
    $selectedCategories = @(Select-MwmtMany "Select categories to restore" $categories)

    $destinations = @(Get-MwmtLiveDestinationProfile)
    if ($destinations.Count -eq 0) {
        Write-MwmtLog "No live destination profiles found."
        return
    }
    $destinationUser = Select-MwmtSingle "Select restore destination user" $destinations
    $overwrite = Ask-MwmtYesNo "Overwrite existing files during restore?" $false

    foreach ($category in $selectedCategories) {
        $rows = @($manifest | Where-Object {
            ($_.UserName -eq $backupUser.Value -or $_.UserName -eq "Public") -and $_.Category -eq $category.Value -and $_.Status -eq "Copied"
        })
        foreach ($row in $rows) {
            $backupPath = $row.DestinationPath
            if (-not (Test-Path $backupPath)) { continue }

            $sourcePath = $row.SourcePath
            if ($row.UserName -eq "Public") {
                $publicMarker = "\Users\Public\"
                $markerIndex = $sourcePath.IndexOf($publicMarker, [System.StringComparison]::OrdinalIgnoreCase)
                if ($markerIndex -ge 0) {
                    $relative = $sourcePath.Substring($markerIndex + $publicMarker.Length)
                } else {
                    $relative = Split-Path -Leaf $sourcePath
                }
                $targetPath = Join-Path (Join-Path "$env:SystemDrive\Users" "Public") $relative
            } else {
                $userMarker = "\Users\$($backupUser.Value)\"
                $markerIndex = $sourcePath.IndexOf($userMarker, [System.StringComparison]::OrdinalIgnoreCase)
                if ($markerIndex -ge 0) {
                    $relative = $sourcePath.Substring($markerIndex + $userMarker.Length)
                    $targetPath = Join-Path $destinationUser.Path $relative
                } else {
                    $absoluteRestoreRoot = Join-Path $script:ReportsRoot "ManualAbsoluteRestore_$script:Timestamp"
                    $relative = ($sourcePath -replace '[\\/:*?"<>|]', '_')
                    $targetPath = Join-Path $absoluteRestoreRoot $relative
                }
            }

            Copy-MwmtRestoreItem $backupPath $targetPath $overwrite | Out-Null
        }
    }

    Write-MwmtLog "Restore workflow finished. Review the log for skipped or failed items."
}

function Show-MwmtMenu {
    Write-Host ""
    Write-Host "MackTechs Windows Migration Tool (MWMT)"
    Write-Host "  1 = Backup data"
    Write-Host "  2 = Restore / migrate data"
    Write-Host "  3 = Export Windows license and BitLocker only"
    Write-Host "  4 = Mount VHD/VHDX/ISO image"
    Write-Host "  Q = Quit"
    return Read-Host "Choice"
}

Write-MwmtLog "MWMT started from $script:Root"

switch (Show-MwmtMenu) {
    "1" { Invoke-MwmtBackup }
    "2" { Invoke-MwmtRestore }
    "3" {
        $backupSet = Join-Path $script:ReportsRoot "SystemInfo_$script:Timestamp"
        New-Item -Path $backupSet -ItemType Directory -Force | Out-Null
        Export-MwmtWindowsLicense $backupSet
        Export-MwmtBitLockerInfo $backupSet
    }
    "4" { Mount-MwmtWindowsImage }
    default { Write-MwmtLog "MWMT closed." }
}
