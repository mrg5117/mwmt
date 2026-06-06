# MackTechs Windows Migration Tool (MWMT)

MWMT is a portable PowerShell tool for technician-led Windows data backup and migration work.

Version 1 is backup-first. It detects live and offline Windows sources, lets the operator select user profiles and data categories, copies selected data with `robocopy`, and writes logs plus a manifest to the same drive the tool runs from.

## Run

On Windows, right-click `START-MWMT.bat` and choose **Run as administrator**.

## Current Workflows

- Backup data from a live Windows install or mounted/offline Windows drive.
- Export available Windows licensing information.
- Export visible BitLocker recovery protector information.

Restore and full migration mapping are planned for the next release. The current restore menu item is intentionally non-destructive.

## Backup Categories

- Personal folders: Desktop, Documents, Downloads, Pictures, Music, Videos, Favorites, user fonts.
- Web browsers: Chrome, Edge, Firefox, Brave, Opera, Vivaldi.
- Mail: Outlook data locations, signatures, PST/OST search, Thunderbird, Windows Live Mail.
- Business apps: QuickBooks, Quicken, TurboTax common folders and file extensions.
- Cloud sync folders: OneDrive, Dropbox, Google Drive.
- Public data: Public Desktop, Documents, Downloads, Pictures, Music, Videos.

## Notes

Windows 10/11 digital licenses may not expose a reusable product key. BitLocker recovery passwords can only be exported if they are visible to the running system and account.

MWMT does not use Fab's AutoBackup code. The category-driven workflow is implemented from scratch using PowerShell and Windows built-ins.
