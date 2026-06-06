# MWMT v2 Audit

Date: 2026-06-06

## Implemented

- Backup workflow with live, offline, Windows.old, manual path, and VHD/VHDX/ISO mount support.
- Restore/migration workflow from `manifest.csv` backup sets to a selected live destination profile.
- Overwrite confirmation for restore.
- Dry-run estimate before backup.
- Verification summary with copied, failed, missing, and dry-run counts.
- Windows license export under `System\Security`.
- BitLocker protector export under `System\Security`.
- Cloud placeholder warning helper for sync-folder estimates.
- Expanded business app rules: QuickBooks, Quicken, TurboTax, Drake, Lacerte, ProSeries, TaxAct, H&R Block, Sage, ACT!.
- Windows smoke test script for parser and JSON validation.
- Release package script for clean zip generation.

## Verification Performed

- `node tests/static-audit.mjs`: 40 checks passed.
- `git diff --check`: clean.

## Not Verified Locally

- PowerShell parser/runtime execution, because PowerShell is not installed on this macOS workstation.
- Actual `robocopy`, `Mount-DiskImage`, `Get-BitLockerVolume`, and `manage-bde.exe` behavior, because those require Windows.

## Risks And Follow-Up

- Restore is conservative and profile-path based. It avoids deleting files and sends absolute-path app folders to a manual review restore area.
- OneDrive placeholder handling is currently warning-oriented. It does not force hydration of cloud-only files.
- Business app rules are a strong starting set, not exhaustive. Add rules from real customer findings over time.
- BitLocker exports can contain recovery secrets. Treat backup sets as sensitive evidence.
