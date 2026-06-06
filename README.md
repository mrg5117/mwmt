# MackTechs Windows Migration Tool (MWMT)

MWMT is a portable PowerShell tool for technician-led Windows data backup and migration work.

MWMT detects live and offline Windows sources, lets the operator select user profiles and data categories, copies selected data with `robocopy`, and writes logs plus a manifest to the same drive the tool runs from.

## Run

On Windows, right-click `START-MWMT.bat` and choose **Run as administrator**.

## Current Workflows

- Backup data from a live Windows install or mounted/offline Windows drive.
- Restore or migrate selected backup categories to a live destination user profile.
- Mount a VHD, VHDX, or ISO image using Windows `Mount-DiskImage`.
- Add a manual Windows source path when automatic detection is not enough.
- Run a dry-run estimate before copying.
- Export available Windows licensing information.
- Export visible BitLocker recovery protector information.

Restore never deletes files. It prompts before overwrite and sends absolute application folders to a manual review restore area instead of writing them to root paths blindly.

## Backup Categories

- Personal folders: Desktop, Documents, Downloads, Pictures, Music, Videos, Favorites, user fonts.
- Web browsers: Chrome, Edge, Firefox, Brave, Opera, Vivaldi.
- Mail: Outlook data locations, signatures, PST/OST search, Thunderbird, Windows Live Mail.
- Business apps: QuickBooks, Quicken, TurboTax common folders and file extensions.
- Expanded business apps: Drake, Lacerte, ProSeries, TaxAct, H&R Block, Sage, ACT!.
- Cloud sync folders: OneDrive, Dropbox, Google Drive.
- Public data: Public Desktop, Documents, Downloads, Pictures, Music, Videos.

## Release Package

On Windows, create a clean zip package with:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\New-ReleasePackage.ps1 -Version 1.0.0
```

The package excludes `.git`, `Backups`, `Reports`, and `dist`.

## Smoke Test

On Windows, run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-MWMT.ps1
```

This checks PowerShell parser syntax and JSON config validity.

## Notes

Windows 10/11 digital licenses may not expose a reusable product key. BitLocker recovery passwords can only be exported if they are visible to the running system and account. BitLocker reports are sensitive and are saved under `System\Security` inside the backup/report set.

MWMT does not use Fab's AutoBackup code. The category-driven workflow is implemented from scratch using PowerShell and Windows built-ins.
