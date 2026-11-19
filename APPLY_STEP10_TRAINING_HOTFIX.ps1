$ErrorActionPreference = 'Stop'
# Fixes a Step 10 rules regression and migrates the obsolete Step 4 emulator test.
# Never deploys Firebase, resets Git, deletes staff records, or touches unrelated files.

if (-not (Test-Path -LiteralPath '.\pubspec.yaml')) {
    throw 'Run this in the FYP_New project root.'
}
$root = (Get-Location).Path
$rulesPath = Join-Path $root 'firestore.rules'
$testPath = Join-Path $root 'test\emulator\staff_rules.test.cjs'
$testPayload = Join-Path $root 'step10_training_hotfix\staff_rules_step10_corrected.test.cjs'
foreach ($p in @($rulesPath,$testPath,$testPayload)) {
    if (-not (Test-Path -LiteralPath $p)) { throw "Missing expected file: $p" }
}
function Read-Lf([string]$path) {
    return [System.IO.File]::ReadAllText($path).Replace("`r`n", "`n")
}
function Restore-Endings([string]$original, [string]$updated) {
    if ($original.Contains("`r`n")) { return $updated.Replace("`n", "`r`n") }
    return $updated
}
function Replace-Once([string]$source, [string]$before, [string]$after, [string]$what) {
    $count = ([regex]::Matches($source, [regex]::Escape($before))).Count
    if ($count -ne 1) { throw "Cannot safely patch $what (found $count matches). Nothing was changed." }
    return $source.Replace($before,$after)
}

$originalRules = [System.IO.File]::ReadAllText($rulesPath)
$rules = $originalRules.Replace("`r`n","`n")
if (-not $rules.Contains('match /staffEmailVerifications/{staffUid}') -or
    -not $rules.Contains('match /staffTrainingCourses/{courseId}')) {
    throw 'Step 10 rules are not installed. No changes made.'
}
if ($rules.Contains('STEP10_TRAINING_CATALOGUE_HOTFIX_V1')) {
    throw 'This training hotfix is already present. No changes made.'
}

$start = $rules.IndexOf('    function workforceQualificationValid(data) {')
if ($start -lt 0) { throw 'Qualification rule validator was not found.' }
$end = $rules.IndexOf('    match /staffQualifications/{qualificationId} {', $start)
if ($end -lt 0) { throw 'Qualification rule match was not found.' }
$validator = $rules.Substring($start,$end-$start)
$oldKeys = "          'completedAt', 'expiresAt', 'updatedAt', 'courseId'"
$newKeys = "          'completedAt', 'expiresAt', 'updatedAt'"
if (([regex]::Matches($validator,[regex]::Escape($oldKeys))).Count -ne 2) {
    throw 'Unexpected qualification key list layout; refuse to alter unrelated rules.'
}
$first = $validator.IndexOf($oldKeys)
$second = $validator.IndexOf($oldKeys, $first + $oldKeys.Length)
$validator = $validator.Substring(0,$second) + $newKeys + $validator.Substring($second+$oldKeys.Length)
# hasOnly retains optional courseId; hasAll allows historical records missing courseId
$rules = $rules.Substring(0,$start) + $validator + $rules.Substring($end)

$oldMatch = @'
    match /staffQualifications/{qualificationId} {
      allow get, list: if workforceSuperAdmin()
        || (signedIn() && resource.data.staffUid == request.auth.uid);
      allow create: if workforceSuperAdmin()
        && workforceQualificationValid(request.resource.data)
        && workforceQualificationMatchesCourse(request.resource.data);
      allow update: if workforceSuperAdmin()
        && resource.data.staffUid == request.resource.data.staffUid
        && workforceQualificationValid(request.resource.data);
      allow delete: if false;
    }
'@
$newMatch = @'
    // STEP10_TRAINING_CATALOGUE_HOTFIX_V1
    // New approvals require a real course. Historical records can only be revoked.
    match /staffQualifications/{qualificationId} {
      allow get, list: if workforceSuperAdmin()
        || (signedIn() && resource.data.staffUid == request.auth.uid);
      allow create: if workforceSuperAdmin()
        && workforceQualificationValid(request.resource.data)
        && request.resource.data.keys().hasAll(['courseId'])
        && workforceQualificationMatchesCourse(request.resource.data);
      allow update: if workforceSuperAdmin()
        && resource.data.staffUid == request.resource.data.staffUid
        && workforceQualificationValid(request.resource.data)
        && request.resource.data.diff(resource.data).affectedKeys().hasOnly(['status','updatedAt'])
        && resource.data.status == 'approved'
        && request.resource.data.status == 'revoked';
      allow delete: if false;
    }
'@
$rules = Replace-Once $rules $oldMatch $newMatch 'staff qualification permissions'

# This old emulator test (from Step 4) used to approve arbitrary text courses.
# Step 10 already made the initial profile inactive; ensure it is that exact
# known fixture before replacing with the updated catalogue tests.
$oldTest = [System.IO.File]::ReadAllText($testPath)
$normalizedTest = $oldTest.Replace("`r`n","`n")
if (-not $normalizedTest.Contains("status:str('inactive'),eligibleRoles")) {
    throw 'Earlier Step 4 test fixture is not in the expected Step 10 form.'
}
$shaObj = [System.Security.Cryptography.SHA256]::Create()
try {
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($normalizedTest)
    $checksum = [BitConverter]::ToString($shaObj.ComputeHash($bytes)).Replace('-','').ToLowerInvariant()
} finally {
    $shaObj.Dispose()
}
if ($checksum -ne '5637accc9171c2a9598dc0ae58f1de056787ab85a7836fe35a1feb68ea9f655e') {
    throw "Earlier Staff test contains extra edits ($checksum). Nothing was changed. Please send the test file for safe merging."
}
$newTest = Read-Lf $testPayload
if (-not $newTest.Contains('historical no-course qualifications can still be revoked safely')) {
    throw 'Updated test payload is incomplete.'
}

# All preflight checks have succeeded. Back up BOTH originals before writing.
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$rulesBackup = "$rulesPath.before-step10-training-hotfix-$stamp.bak"
$testBackup = "$testPath.before-step10-training-hotfix-$stamp.bak"
[System.IO.File]::Copy($rulesPath,$rulesBackup)
[System.IO.File]::Copy($testPath,$testBackup)
$encoding = New-Object System.Text.UTF8Encoding($false)
try {
    [System.IO.File]::WriteAllText($rulesPath,(Restore-Endings $originalRules $rules),$encoding)
    [System.IO.File]::WriteAllText($testPath,(Restore-Endings $oldTest $newTest),$encoding)
} catch {
    [System.IO.File]::Copy($rulesBackup,$rulesPath,$true)
    [System.IO.File]::Copy($testBackup,$testPath,$true)
    throw "Training hotfix failed; originals restored. $($_.Exception.Message)"
}
Write-Host 'Step 10 training rules + legacy test corrected locally.' -ForegroundColor Green
Write-Host 'New qualifications require an active registered course; legacy records can be revoked.'
Write-Host 'Backups saved:'
Write-Host "  $rulesBackup"
Write-Host "  $testBackup"
Write-Host 'No Firebase deployment was performed.'
