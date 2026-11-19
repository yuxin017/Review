$ErrorActionPreference = 'Stop'

# Step 9 only redesigns Staff UI and strengthens client-side input checks.
# It deliberately does not edit Firebase Rules, auth users, Cloud Functions,
# AdminShell, CrowdSense or other project modules.
if (-not (Test-Path '.\pubspec.yaml')) {
    throw 'Open PowerShell in FYP_New before running this script.'
}
$root = (Get-Location).Path
$uiPath = Join-Path $root 'lib\admin\staff\staff_management_page.dart'
$policyPath = Join-Path $root 'lib\admin\staff\staff_spark_policy.dart'
$recordsRepoPath = Join-Path $root 'lib\admin\staff\staff_records_repository.dart'
$newValidation = Join-Path $root 'lib\admin\staff\staff_form_validation.dart'
$newTest = Join-Path $root 'test\admin\staff_form_validation_test.dart'
$filesDir = Join-Path $root 'step9_files'

foreach ($path in @($uiPath, $policyPath, $recordsRepoPath)) {
    if (-not (Test-Path -LiteralPath $path)) { throw "Missing required Step 8 file: $path" }
}
if ((Test-Path -LiteralPath $newValidation) -or (Test-Path -LiteralPath $newTest)) {
    throw 'Step 9 files already exist. Refusing to overwrite them. No changes made.'
}

function Read-Lf([string]$path) {
    return [System.IO.File]::ReadAllText($path).Replace("`r`n", "`n")
}
function Replace-ExactlyOnce([string]$inputText, [string]$from, [string]$to, [string]$label) {
    $matches = ([regex]::Matches($inputText, [regex]::Escape($from))).Count
    if ($matches -ne 1) { throw "$label must appear exactly once (found $matches). No changes made." }
    return $inputText.Replace($from, $to)
}
function Replace-Section([string]$inputText, [string]$start, [string]$end, [string]$replacement, [string]$label) {
    $occurrences = ([regex]::Matches($inputText, [regex]::Escape($start))).Count
    if ($occurrences -ne 1) { throw "$label start marker mismatch ($occurrences). No changes made." }
    $a = $inputText.IndexOf($start)
    $b = $inputText.IndexOf($end, $a + $start.Length)
    if ($b -lt 0) { throw "$label end marker missing. No changes made." }
    return $inputText.Substring(0,$a) + $replacement + $inputText.Substring($b)
}

$oldUiRaw = [System.IO.File]::ReadAllText($uiPath)
$oldPolicyRaw = [System.IO.File]::ReadAllText($policyPath)
$oldRecordsRepoRaw = [System.IO.File]::ReadAllText($recordsRepoPath)
$ui = $oldUiRaw.Replace("`r`n", "`n")
$policy = $oldPolicyRaw.Replace("`r`n", "`n")
$recordsRepo = $oldRecordsRepoRaw.Replace("`r`n", "`n")

if (-not $ui.Contains('Spark plan: employees are registered with Firebase Authentication')) {
    throw 'This Staff UI is not the expected Spark Step 8 version. Refusing to overwrite your custom code.'
}
if (-not $ui.Contains('Create Staff Account') -or -not $ui.Contains('Widget _qualifications(')) {
    throw 'Staff UI structure differs from Step 8. No changes made.'
}
if (-not $policy.Contains('class StaffSparkPolicy')) {
    throw 'Staff Spark policy missing. No changes made.'
}

$ui = Replace-ExactlyOnce $ui "import 'package:flutter/material.dart';" "import 'dart:math' as math;`nimport 'package:flutter/material.dart';`nimport '../admin_widgets.dart';`nimport 'staff_form_validation.dart';" 'Flutter imports'
$create = (Read-Lf (Join-Path $filesDir 'NEW_CREATE_METHOD.dartfrag'))
$edit = (Read-Lf (Join-Path $filesDir 'NEW_EDIT_METHOD.dartfrag'))
$build = (Read-Lf (Join-Path $filesDir 'NEW_BUILD_METHOD.dartfrag'))
$ui = Replace-Section $ui '  Future<void> _createStaff() async {' '  Future<void> _resendSetupEmail(' $create 'Create Staff dialog'
$ui = Replace-Section $ui '  Future<void> _editStaff(' '  Future<void> _addTraining(' $edit 'Edit Roles and Status actions'
$startBuild = '  @override' + "`n" + '  Widget build(BuildContext context) => StreamBuilder<List<StaffProfile>>('
if (([regex]::Matches($ui, [regex]::Escape($startBuild))).Count -ne 1) {
    throw 'Staff page build marker mismatch. No changes made.'
}
$buildAt = $ui.IndexOf($startBuild)
$ui = $ui.Substring(0, $buildAt) + $build

# No extra Firebase permissions: only stronger frontend validation.
$policy = Replace-ExactlyOnce $policy "import 'staff_access.dart';" "import 'staff_access.dart';`nimport 'staff_form_validation.dart';" 'Spark policy import'
$oldValidation = @'
    final name = fullName.trim();
    final address = normalizeEmail(email);
    if (name.length < 2 || name.length > 120) {
      throw ArgumentError('Staff name must be between 2 and 120 characters.');
    }
    if (address.length > 254 ||
        !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(address)) {
      throw ArgumentError('Enter a real email address owned by the employee.');
    }
'@
$newValidationCode = @'
    final nameError = StaffFormValidation.fullName(fullName);
    if (nameError != null) throw ArgumentError(nameError);
    final emailError = StaffFormValidation.email(email);
    if (emailError != null) throw ArgumentError(emailError);
'@
$policy = Replace-ExactlyOnce $policy $oldValidation $newValidationCode 'Spark account validation'

# Apply identical name/email validation when editing staff profiles.
$recordsRepo = Replace-ExactlyOnce $recordsRepo "import 'staff_access.dart';" "import 'staff_access.dart';`nimport 'staff_form_validation.dart';" 'Staff repository validation import'
$oldRepoCheck = @'
    if (name.length < 2 || !address.contains('@')) {
      throw ArgumentError('Provide a staff name and a valid email.');
    }
'@
$newRepoCheck = @'
    final nameError = StaffFormValidation.fullName(name);
    if (nameError != null) throw ArgumentError(nameError);
    final emailError = StaffFormValidation.email(address);
    if (emailError != null) throw ArgumentError(emailError);
'@
$recordsRepo = Replace-ExactlyOnce $recordsRepo $oldRepoCheck $newRepoCheck 'Staff repository data validation'

$validationSource = Join-Path $filesDir 'lib\admin\staff\staff_form_validation.dart'
$testSource = Join-Path $filesDir 'test\admin\staff_form_validation_test.dart'
foreach ($source in @($validationSource,$testSource)) {
    if (-not (Test-Path -LiteralPath $source)) { throw "Step 9 archive is incomplete: $source" }
}

# The previous versions are kept even if an unexpected write fails.
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$uiBackup = "$uiPath.before-step9-ui-$stamp.bak"
$policyBackup = "$policyPath.before-step9-ui-$stamp.bak"
$recordsRepoBackup = "$recordsRepoPath.before-step9-ui-$stamp.bak"
[System.IO.File]::Copy($uiPath,$uiBackup)
[System.IO.File]::Copy($policyPath,$policyBackup)
[System.IO.File]::Copy($recordsRepoPath,$recordsRepoBackup)
try {
    if ($oldUiRaw.Contains("`r`n")) { $ui = $ui.Replace("`n", "`r`n") }
    if ($oldPolicyRaw.Contains("`r`n")) { $policy = $policy.Replace("`n", "`r`n") }
    if ($oldRecordsRepoRaw.Contains("`r`n")) { $recordsRepo = $recordsRepo.Replace("`n", "`r`n") }
    $enc = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($uiPath, $ui, $enc)
    [System.IO.File]::WriteAllText($policyPath, $policy, $enc)
    [System.IO.File]::WriteAllText($recordsRepoPath, $recordsRepo, $enc)
    [System.IO.File]::Copy($validationSource, $newValidation)
    [System.IO.File]::Copy($testSource, $newTest)
} catch {
    [System.IO.File]::Copy($uiBackup,$uiPath,$true)
    [System.IO.File]::Copy($policyBackup,$policyPath,$true)
    [System.IO.File]::Copy($recordsRepoBackup,$recordsRepoPath,$true)
    if (Test-Path $newValidation) { Remove-Item -LiteralPath $newValidation -Force }
    if (Test-Path $newTest) { Remove-Item -LiteralPath $newTest -Force }
    throw "Step 9 could not be installed. Previous files restored. $($_.Exception.Message)"
}
Write-Host 'Staff Management UI redesigned successfully.' -ForegroundColor Green
Write-Host 'Existing Firebase staff accounts and records were NOT modified.'
Write-Host 'Backups:'
Write-Host "  $uiBackup"
Write-Host "  $policyBackup"
Write-Host "  $recordsRepoBackup"
Write-Host 'Next: flutter analyze lib/admin/staff'
Write-Host 'Next: flutter test test/admin/staff_form_validation_test.dart test/admin/staff_spark_policy_test.dart test/admin/staff_access_test.dart test/admin/staff_records_test.dart'
