# Staff Workforce Step 4. Patch LOCAL Firestore rules only.
# Does not deploy, does not touch Flutter / CrowdSense / database.
$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$rulesPath = Join-Path $root 'firestore.rules'
$additionPath = Join-Path $root 'staff_rules_addition.txt'
if (-not (Test-Path -LiteralPath $rulesPath)) { throw 'Run this script from the FYP project root (firestore.rules not found).' }
if (-not (Test-Path -LiteralPath $additionPath)) { throw 'staff_rules_addition.txt missing. Extract the entire Step 4 ZIP to FYP_New.' }
$rules = [System.IO.File]::ReadAllText($rulesPath)
$addition = [System.IO.File]::ReadAllText($additionPath)
if ($rules.Contains('match /staffProfiles/{staffUid}') -or $rules.Contains('match /staffQualifications/{qualificationId}')) {
  Write-Host 'Staff rules already exist. No changes made. Inspect manually before running again.' -ForegroundColor Yellow
  exit 0
}
if (-not $rules.Contains('function isAdmin()')) { throw 'Existing isAdmin() helper not found; refusing to patch unknown rules version.' }
$anchor = '    match /visitors/{visitorId} {'
$index = $rules.IndexOf($anchor, [StringComparison]::Ordinal)
if ($index -lt 0) { throw 'Visitor collection anchor not found; refusing to patch unknown rules version.' }
$backup = Join-Path $root ('firestore.rules.before-staff-step4-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.bak')
Copy-Item -LiteralPath $rulesPath -Destination $backup -ErrorAction Stop
$rulesNew = $rules.Insert($index, $addition + [Environment]::NewLine)
[System.IO.File]::WriteAllText($rulesPath, $rulesNew, [System.Text.UTF8Encoding]::new($false))
Write-Host 'Step 4 staff security rules inserted (LOCAL ONLY, NOT DEPLOYED).' -ForegroundColor Green
Write-Host ('Backup: ' + $backup)
Write-Host 'Next: run local emulator tests. Do NOT deploy until they pass.' -ForegroundColor Cyan
