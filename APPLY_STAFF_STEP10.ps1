$ErrorActionPreference = 'Stop'

# Step 10 keeps all existing modules and Spark onboarding. A narrow set of
# known staff files is modified after version checks, with automatic backups.
if (-not (Test-Path '.\pubspec.yaml')) {
    throw 'Open the Terminal in your FYP_New project root first.'
}
$root = (Get-Location).Path
$payload = Join-Path $root 'step10_files'

function Read-Lf([string]$path) {
    return [System.IO.File]::ReadAllText($path).Replace("`r`n", "`n")
}
function Replace-Once([string]$s, [string]$before, [string]$after, [string]$label) {
    $n = ([regex]::Matches($s,[regex]::Escape($before))).Count
    if ($n -ne 1) { throw "Could not safely patch $label (matches: $n). No changes made." }
    return $s.Replace($before,$after)
}
function Restore-LineEndings([string]$source,[string]$value) {
    if ($source.Contains("`r`n")) { return $value.Replace("`n", "`r`n") }
    return $value
}

$expected = @(
    @{rel='lib\admin\staff\staff_management_page.dart'; sha='051a09c7d225c8121ed20f0af69ce2d3777d38ae0200f46e6112871edba33a2c'},
    @{rel='lib\admin\staff\staff_portal.dart'; sha='5fb9fa6f121143f830e430cfaa152af926502fe907bb5cddbe2572c036596b57'},
    @{rel='lib\admin\staff\staff_records_repository.dart'; sha='379719407f476067b2f371ea901bc8cb0e379e382def90db5640ccbf2392dc04'}
)
foreach ($entry in $expected) {
    $path=Join-Path $root $entry.rel
    $incoming=Join-Path $payload $entry.rel
    if (-not (Test-Path -LiteralPath $path)) { throw "Missing existing file: $path" }
    if (-not (Test-Path -LiteralPath $incoming)) { throw "Missing package file: $incoming" }
    $actual=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actual -ne $entry.sha) {
        throw "This file has additional edits: $path. STOP: no changes made. Send me this file for a safe merge."
    }
}
$new = @(
    'lib\admin\staff\staff_dialog_frame.dart',
    'lib\admin\staff\staff_email_check.dart',
    'lib\admin\staff\staff_training_catalog.dart',
    'test\admin\staff_email_check_test.dart',
    'test\emulator\staff_step10_rules.test.cjs'
)
foreach ($rel in $new) {
    if (-not (Test-Path -LiteralPath (Join-Path $payload $rel))) {
        throw "Incomplete Step 10 package: $rel"
    }
    if (Test-Path -LiteralPath (Join-Path $root $rel)) {
        throw "Refusing to overwrite existing file: $rel"
    }
}
$rulesFile=Join-Path $root 'firestore.rules'
$rulesOriginal=[System.IO.File]::ReadAllText($rulesFile)
$rules=$rulesOriginal.Replace("`r`n","`n")
if ($rules.Contains('match /staffEmailVerifications/{staffUid}')) {
    throw 'Step 10 Firestore rules appear to be installed already. No changes made.'
}
$oldCreate=@'
      allow create: if workforceSuperAdmin()
        && workforceProfileValid(request.resource.data);
'@
$newCreate=@'
      allow create: if workforceSuperAdmin()
        && workforceProfileValid(request.resource.data)
        && request.resource.data.status == 'inactive';
'@
$rules=Replace-Once $rules $oldCreate $newCreate 'Staff profile initial Inactive status'
$oldUpdate=@'
      allow update: if workforceSuperAdmin()
        && workforceProfileValid(request.resource.data)
        && request.resource.data.get('staffId','') == resource.data.get('staffId','');
'@
$newUpdate=@'
      allow update: if workforceSuperAdmin()
        && workforceProfileValid(request.resource.data)
        && request.resource.data.get('staffId','') == resource.data.get('staffId','')
        // Firebase Auth email must be changed through a separate trusted flow.
        && request.resource.data.email == resource.data.email
        // An already-active legacy profile may be edited without changing
        // its status; every NEW transition to Active requires verified proof.
        && (request.resource.data.status != 'active'
          || resource.data.status == 'active'
          || (exists(/databases/$(database)/documents/staffEmailVerifications/$(staffUid))
            && get(/databases/$(database)/documents/staffEmailVerifications/$(staffUid)).data.email == request.resource.data.email));
'@
$rules=Replace-Once $rules $oldUpdate $newUpdate 'block unverified staff activation'
$rules=Replace-Once $rules "    function workforceQualificationValid(data) {" ((Read-Lf (Join-Path $payload 'STAFF_RULE_ADDITIONS.txt')) + "    function workforceQualificationValid(data) {") 'Staff verification and training catalog rules'

$oldKey = "          'completedAt', 'expiresAt', 'updatedAt'"
$newKey = "          'completedAt', 'expiresAt', 'updatedAt', 'courseId'"
# The field list appears twice (hasOnly and hasAll) inside this ONE function.
# Restrict the edit to the qualification validation block, not other modules.
$start = $rules.IndexOf('    function workforceQualificationValid(data) {')
$finish = $rules.IndexOf('    match /staffQualifications/{qualificationId} {', $start)
if ($start -lt 0 -or $finish -lt 0) { throw 'Qualification rules section is missing.' }
$qBlock = $rules.Substring($start, $finish - $start)
if (([regex]::Matches($qBlock, [regex]::Escape($oldKey))).Count -ne 2) {
    throw 'Qualification key lists have changed. No changes made.'
}
$qBlock = $qBlock.Replace($oldKey, $newKey)
$rules = $rules.Substring(0, $start) + $qBlock + $rules.Substring($finish)
$oldCourseCheck=@'
        && data.title.size() <= 160
        && data.status in ['approved', 'revoked']
'@
$newCourseCheck=@'
        && data.title.size() <= 160
        && (!data.keys().hasAny(['courseId'])
          || (data.courseId is string && data.courseId.size() >= 1 && data.courseId.size() <= 128))
        && data.status in ['approved', 'revoked']
'@
$rules=Replace-Once $rules $oldCourseCheck $newCourseCheck 'qualification course ID validation'
$oldCourseCreate=@'
      allow create: if workforceSuperAdmin()
        && workforceQualificationValid(request.resource.data);
'@
$newCourseCreate=@'
      allow create: if workforceSuperAdmin()
        && workforceQualificationValid(request.resource.data)
        && workforceQualificationMatchesCourse(request.resource.data);
'@
$rules=Replace-Once $rules $oldCourseCreate $newCourseCreate 'server validation against course catalogue'

# Existing emulator test encoded the OLD business rule that admins could
# create an ACTIVE staff profile. This must now be replaced with INACTIVE.
$legacyTest=Join-Path $root 'test\emulator\staff_rules.test.cjs'
if (-not (Test-Path -LiteralPath $legacyTest)) { throw 'Missing earlier Staff Emulator test.' }
$legacyOriginal=[System.IO.File]::ReadAllText($legacyTest)
$legacy=Read-Lf $legacyTest
$legacy=Replace-Once $legacy "status:str('active'),eligibleRoles" "status:str('inactive'),eligibleRoles" 'obsolete emulator test fixture'

# Do not modify anything until ALL content checks have succeeded.
$modified=@($rulesFile,$legacyTest) + @($expected | ForEach-Object { Join-Path $root $_.rel })
$backups=@()
$stamp=Get-Date -Format 'yyyyMMdd-HHmmss'
foreach ($file in $modified) {
    $backup="$file.before-staff-step10-$stamp.bak"
    [System.IO.File]::Copy($file,$backup)
    $backups += $backup
}
$created=@()
try {
    foreach ($entry in $expected) {
        [System.IO.File]::Copy((Join-Path $payload $entry.rel),(Join-Path $root $entry.rel),$true)
    }
    $enc=New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($rulesFile,(Restore-LineEndings $rulesOriginal $rules),$enc)
    [System.IO.File]::WriteAllText($legacyTest,(Restore-LineEndings $legacyOriginal $legacy),$enc)
    foreach ($rel in $new) {
        $dest=Join-Path $root $rel
        $destParent=Split-Path -Parent $dest
        if (-not (Test-Path $destParent)) {
            New-Item -ItemType Directory -Path $destParent -Force | Out-Null
        }
        [System.IO.File]::Copy((Join-Path $payload $rel),$dest)
        $created += $dest
    }
} catch {
    for ($i=0; $i -lt $modified.Count; $i++) {
        [System.IO.File]::Copy($backups[$i],$modified[$i],$true)
    }
    foreach ($path in $created) {
        if (Test-Path $path) { Remove-Item -LiteralPath $path -Force }
    }
    throw "Step 10 installation failed. Original files restored. $($_.Exception.Message)"
}
Write-Host 'Staff Step 10 installed. Accounts and Firebase data are untouched.' -ForegroundColor Green
Write-Host 'No Firebase deployment was performed.'
Write-Host 'Backups:'
$backups | ForEach-Object { Write-Host "  $_" }
Write-Host 'Next: flutter analyze lib/admin/staff'
Write-Host 'Next: flutter test test/admin/staff_email_check_test.dart test/admin/staff_form_validation_test.dart test/admin/staff_spark_policy_test.dart test/admin/staff_records_test.dart'
Write-Host 'Next: run Firebase emulator tests BEFORE deploying rules'
