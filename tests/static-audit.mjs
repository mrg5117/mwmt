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
  checks.push(["MWMT supports restore placeholder with warning", script.includes("Restore is planned for a later release")]);
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
