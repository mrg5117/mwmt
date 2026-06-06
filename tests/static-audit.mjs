import { existsSync, readFileSync } from "node:fs";
import { resolve } from "node:path";

const root = resolve(new URL("..", import.meta.url).pathname);
const read = (path) => readFileSync(resolve(root, path), "utf8");

const checks = [
  ["START-MWMT.bat exists", existsSync(resolve(root, "START-MWMT.bat"))],
  ["MWMT.ps1 exists", existsSync(resolve(root, "MWMT.ps1"))],
  ["Category rules exist", existsSync(resolve(root, "Config", "Categories.json"))],
  ["Exclusion rules exist", existsSync(resolve(root, "Config", "Exclusions.json"))],
  ["README exists", existsSync(resolve(root, "README.md"))],
  ["Release package script exists", existsSync(resolve(root, "tools", "New-ReleasePackage.ps1"))],
  ["Windows smoke test script exists", existsSync(resolve(root, "tests", "Test-MWMT.ps1"))],
];

if (existsSync(resolve(root, "Config", "Categories.json"))) {
  const categories = JSON.parse(read("Config/Categories.json"));
  checks.push(["Categories include Personal", categories.categories.some((c) => c.id === "personal")]);
  checks.push(["Categories include Browsers", categories.categories.some((c) => c.id === "browsers")]);
  checks.push(["Categories include Mail", categories.categories.some((c) => c.id === "mail")]);
  checks.push(["Categories include Business Apps", categories.categories.some((c) => c.id === "business_apps")]);
  const businessText = JSON.stringify(categories.categories.find((c) => c.id === "business_apps") ?? {});
  checks.push(["Business Apps include QuickBooks", businessText.includes("QuickBooks") && businessText.includes("*.QBW")]);
  checks.push(["Business Apps include Quicken", businessText.includes("Quicken") && businessText.includes("*.QDF")]);
  checks.push(["Business Apps include TurboTax", businessText.includes("TurboTax") && businessText.includes("*.tax")]);
  checks.push(["Business Apps include Drake Lacerte ProSeries", ["Drake", "Lacerte", "ProSeries"].every((name) => businessText.includes(name))]);
  checks.push(["Business Apps include TaxAct HRBlock Sage ACT", ["TaxAct", "H&R Block", "Sage", "ACT!"].every((name) => businessText.includes(name))]);
  const browserText = JSON.stringify(categories.categories.find((c) => c.id === "browsers") ?? {});
  checks.push(["Browsers include Chrome Edge Firefox Brave", ["Chrome", "Edge", "Firefox", "Brave"].every((name) => browserText.includes(name))]);
  const mailText = JSON.stringify(categories.categories.find((c) => c.id === "mail") ?? {});
  checks.push(["Mail includes Outlook and Thunderbird", mailText.includes("Outlook") && mailText.includes("Thunderbird")]);
}

if (existsSync(resolve(root, "MWMT.ps1"))) {
  const script = read("MWMT.ps1");
  checks.push(["MWMT has source detection", script.includes("function Get-MwmtSource")]);
  checks.push(["MWMT has user profile detection", script.includes("function Get-MwmtUserProfile")]);
  checks.push(["MWMT has category selection", script.includes("function Select-MwmtCategory")]);
  checks.push(["MWMT uses robocopy", script.includes("robocopy.exe")]);
  checks.push(["MWMT writes manifest", script.includes("manifest.csv")]);
  checks.push(["MWMT backs up Windows license info", script.includes("function Export-MwmtWindowsLicense")]);
  checks.push(["MWMT backs up BitLocker info", script.includes("function Export-MwmtBitLockerInfo")]);
  checks.push(["MWMT supports offline Windows sources", script.includes("Get-PSDrive -PSProvider FileSystem") && script.includes("Windows") && script.includes("Users")]);
  checks.push(["MWMT supports restore workflow", script.includes("function Invoke-MwmtRestore") && script.includes("Select restore destination user")]);
  checks.push(["MWMT prompts before overwrite", script.includes("Ask-MwmtYesNo") && script.includes("Overwrite existing files")]);
  checks.push(["MWMT supports VHD mounting helper", script.includes("function Mount-MwmtWindowsImage") && script.includes("Mount-DiskImage")]);
  checks.push(["MWMT supports Windows.old sources", script.includes("Windows.old") && script.includes("Offline Windows.old source")]);
  checks.push(["MWMT supports manual source path", script.includes("function New-MwmtManualSource") && script.includes("Enter manual Windows source path")]);
  checks.push(["MWMT supports dry run estimate", script.includes("function Get-MwmtBackupEstimate") && script.includes("Dry run / estimate only")]);
  checks.push(["MWMT warns about OneDrive placeholders", script.includes("function Test-MwmtCloudPlaceholder") && script.includes("CloudPlaceholderWarning")]);
  checks.push(["MWMT writes verification summary", script.includes("function Write-MwmtVerificationSummary") && script.includes("VerificationSummary.txt")]);
  checks.push(["MWMT stores sensitive exports under System/Security", script.includes("System\\Security\\WindowsLicense.txt") && script.includes("System\\Security\\BitLocker.txt")]);
  checks.push(["MWMT has release package command documented", read("README.md").includes("New-ReleasePackage.ps1")]);
}

if (existsSync(resolve(root, "tests", "Test-MWMT.ps1"))) {
  const testScript = read("tests/Test-MWMT.ps1");
  checks.push(["Windows smoke test parses MWMT", testScript.includes("Parser]::ParseFile")]);
  checks.push(["Windows smoke test validates JSON", testScript.includes("ConvertFrom-Json")]);
}

if (existsSync(resolve(root, "tools", "New-ReleasePackage.ps1"))) {
  const releaseScript = read("tools/New-ReleasePackage.ps1");
  checks.push(["Release script excludes git and backups", releaseScript.includes(".git") && releaseScript.includes("Backups") && releaseScript.includes("Reports")]);
  checks.push(["Release script creates zip", releaseScript.includes("Compress-Archive")]);
}

let failed = 0;
for (const [label, ok] of checks) {
  if (ok) {
    console.log(`ok - ${label}`);
  } else {
    failed += 1;
    console.error(`not ok - ${label}`);
  }
}

if (failed > 0) {
  console.error(`\n${failed} static audit check(s) failed.`);
  process.exit(1);
}

console.log(`\n${checks.length} static audit checks passed.`);
