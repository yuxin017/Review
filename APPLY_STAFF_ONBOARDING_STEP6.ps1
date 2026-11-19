$ErrorActionPreference = 'Stop'

function Replace-Once([string]$inputText, [string]$from, [string]$to, [string]$label) {
    $n = ([regex]::Matches($inputText, [regex]::Escape($from))).Count
    if ($n -ne 1) { throw "Cannot safely update $label (marker count: $n). No changes made." }
    return $inputText.Replace($from, $to)
}
function Read-Lf([string]$path) { return [System.IO.File]::ReadAllText($path).Replace("`r`n", "`n") }
function New-Utf8([string]$path, [string]$text, [bool]$hadCrLf) {
    if ($hadCrLf) { $text = $text.Replace("`n", "`r`n") }
    [System.IO.File]::WriteAllText($path, $text, (New-Object System.Text.UTF8Encoding($false)))
}

$root = (Get-Location).Path
if (-not (Test-Path '.\pubspec.yaml')) { throw 'Run this from FYP_New project root.' }
$ui = Join-Path $root 'lib\admin\staff\staff_management_page.dart'
$records = Join-Path $root 'lib\admin\staff\staff_records.dart'
$rules = Join-Path $root 'firestore.rules'
$entry = Join-Path $root 'functions\themepark.js'
$nextUi = Join-Path $root 'step6_updated_files\lib\admin\staff\staff_management_page.dart.template'
$nextRecords = Join-Path $root 'step6_updated_files\lib\admin\staff\staff_records.dart.template'
$backend = Join-Path $root 'functions\src\staff_onboarding.js'
$client = Join-Path $root 'lib\admin\staff\staff_onboarding_repository.dart'
$backendTest = Join-Path $root 'functions\test\staff_onboarding.test.cjs'
foreach ($f in @($ui,$records,$rules,$entry,$nextUi,$nextRecords,$backend,$client,$backendTest)) {
    if (-not (Test-Path $f)) { throw "Missing required file: $f" }
}
if ((Read-Lf $entry).Contains('exports.createStaffAccount=onCall(')) {
    throw 'Step 6 appears to be installed already. Stop to avoid duplicate changes.'
}

# Do not overwrite unknown local UI/model edits. These hashes match the Step 5
# and Step 3 source files distributed previously.
$expectedUiHash = '2f602afdc357313ab9c958c36511e4ded61d74b6e80f684b2c939213343c0430'
$expectedRecordsHash = 'c3e499f3f3d6e1eb78285074353f80f5c2ee5a83cfe5527a4181e266507c64b1'
if ((Get-FileHash $ui -Algorithm SHA256).Hash.ToLowerInvariant() -ne $expectedUiHash) {
    throw 'Your staff_management_page.dart differs from the Step 5 source. No changes made; send this file for safe merging.'
}
if ((Get-FileHash $records -Algorithm SHA256).Hash.ToLowerInvariant() -ne $expectedRecordsHash) {
    throw 'Your staff_records.dart differs from the Step 3 source. No changes made; send this file for safe merging.'
}

$oldRules = [System.IO.File]::ReadAllText($rules)
$rulesCRLF = $oldRules.Contains("`r`n")
$ruleText = $oldRules.Replace("`r`n","`n")
$oldEntry = [System.IO.File]::ReadAllText($entry)
$entryCRLF = $oldEntry.Contains("`r`n")
$entryText = $oldEntry.Replace("`r`n","`n")

# Add an optional immutable staff ID. The existing Step 4 profiles (without
# staffId) remain valid; only the trusted backend generates new IDs.
$oldOnly = "'fullName', 'email', 'status', 'eligibleRoles', 'updatedAt'"
$newOnly = "'fullName', 'email', 'status', 'eligibleRoles', 'updatedAt', 'staffId'"
$onlyAt = $ruleText.IndexOf('function workforceProfileValid(data)')
if ($onlyAt -lt 0) { throw 'Step 4 workforce rules not found. No changes made.' }
$onlyEnd = $ruleText.IndexOf('match /staffProfiles/{staffUid}', $onlyAt)
if ($onlyEnd -lt 0) { throw 'Step 4 staffProfiles match not found. No changes made.' }
$ruleBlock = $ruleText.Substring($onlyAt, $onlyEnd-$onlyAt)
$ruleBlock = Replace-Once $ruleBlock "data.keys().hasOnly([`n          $oldOnly`n        ])" "data.keys().hasOnly([`n          $newOnly`n        ])" 'staffProfiles optional staffId'
$ruleBlock = Replace-Once $ruleBlock "&& data.updatedAt == request.time;" "&& (!data.keys().hasAny(['staffId']) ||`n          (data.staffId is string && data.staffId.matches('^STF-[0-9]{5,8}$')))`n        && data.updatedAt == request.time;" 'staffId validation'
$ruleText = $ruleText.Substring(0, $onlyAt) + $ruleBlock + $ruleText.Substring($onlyEnd)
$oldWrite = "      allow create, update: if workforceSuperAdmin()`n        && workforceProfileValid(request.resource.data);"
$newWrite = "      allow create: if workforceSuperAdmin()`n        && workforceProfileValid(request.resource.data);`n      allow update: if workforceSuperAdmin()`n        && workforceProfileValid(request.resource.data)`n        && request.resource.data.get('staffId','') == resource.data.get('staffId','');"
$ruleText = Replace-Once $ruleText $oldWrite $newWrite 'staff ID immutability'

$entryText = Replace-Once $entryText "const {getFirestore,FieldValue}=require('firebase-admin/firestore');" "const {getFirestore,FieldValue}=require('firebase-admin/firestore');`nconst {getAuth}=require('firebase-admin/auth');" 'functions auth import'
$entryText = Replace-Once $entryText "const {onCall}=require('firebase-functions/v2/https');" "const {onCall,HttpsError}=require('firebase-functions/v2/https');" 'functions callable import'
$entryText = Replace-Once $entryText "exports.claimWeatherBenefit=onCall(options,park.claimWeather);" "exports.claimWeatherBenefit=onCall(options,park.claimWeather);`nconst {createStaffAccountHandler}=require('./src/staff_onboarding');`nexports.createStaffAccount=onCall(options,createStaffAccountHandler({auth:getAuth(),db,FieldValue,HttpsError}));" 'functions new export'

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$paths = @($ui,$records,$rules,$entry)
$backups = @()
foreach ($f in $paths) {
    $dest = "$f.before-staff-step6-$stamp.bak"
    [System.IO.File]::Copy($f,$dest)
    $backups += $dest
}
try {
    [System.IO.File]::Copy($nextUi,$ui,$true)
    [System.IO.File]::Copy($nextRecords,$records,$true)
    New-Utf8 $rules $ruleText $rulesCRLF
    New-Utf8 $entry $entryText $entryCRLF
} catch {
    for ($i=0; $i -lt $paths.Count; $i++) {
        [System.IO.File]::Copy($backups[$i],$paths[$i],$true)
    }
    throw ('Step 6 file update failed, originals restored. ' + $_.Exception.Message)
}
Write-Host 'Step 6 Staff Onboarding integrated locally. No Firebase deployment performed.' -ForegroundColor Green
Write-Host 'Backups:'
$backups | ForEach-Object { Write-Host "  $_" }
Write-Host 'Next: node --test functions/test/staff_onboarding.test.cjs'
Write-Host 'Then run: flutter analyze lib/admin/staff lib/admin/admin_repository.dart lib/admin/admin_shell.dart'
Write-Host 'Also run emulator rules tests before any deployment.'
