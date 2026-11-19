$ErrorActionPreference = 'Stop'

# This migration intentionally does NOT deploy anything or edit Firestore Rules,
# firebase.json, CrowdSense, or the old Cloud Function (left unused).
if (-not (Test-Path '.\pubspec.yaml')) {
    throw 'Run from the FYP_New directory containing pubspec.yaml.'
}

$root = (Get-Location).Path
$checks = @(
    @{ Relative='lib\admin\staff\staff_onboarding_repository.dart'; Sha='e099709fd27b7331dc693b579dccfa1f040ff7ed33e4c4182f826a54eb843f13' },
    @{ Relative='lib\admin\staff\staff_portal.dart'; Sha='236870ce7168f5cb6faf4dc42c01b76314ffc93035b26bb3472cc6fab25c71e2' },
    @{ Relative='lib\admin\staff\staff_portal_policy.dart'; Sha='acec493b21fa1ccd30aeaad3a98d801ff164441bb9934f522021e11d94fed6c6' },
    @{ Relative='test\admin\staff_portal_policy_test.dart'; Sha='e4b529c80aa57a1838308cfa64438c1d17947c3c0f090a5144e288c54a6b1a56' }
)

foreach ($item in $checks) {
    $destination = Join-Path $root $item.Relative
    $source = Join-Path $root (Join-Path 'spark_step8_files' $item.Relative)
    if (-not (Test-Path -LiteralPath $destination)) {
        throw "Missing Step 6/7 original file: $destination. Please install the previous Staff steps first."
    }
    if (-not (Test-Path -LiteralPath $source)) {
        throw "Missing Step 8 replacement file: $source. Re-extract ZIP into FYP_New."
    }
    $actual = (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actual -ne $item.Sha) {
        throw "File differs from the Step 6/7 version: $destination. No changes made. Please send the changed file for a safe merge."
    }
}

$uiPath = Join-Path $root 'lib\admin\staff\staff_management_page.dart'
$uiSource = [System.IO.File]::ReadAllText($uiPath)
$oldBanner = 'New employees are provisioned using a secured Firebase Function and start Inactive. Setting a password does not grant operational access. The Staff login gate and shift-based authorization are separate upcoming steps. Never grant legacy admin:true to restricted staff.'
$newBanner = 'Spark plan: employees are registered with Firebase Authentication using an isolated temporary session. Their real email receives a password setup link; Firebase does not create an email inbox. Accounts start Inactive. Only verified, approved staff can see the read-only Staff Portal. Operational tools remain locked until shift and server permissions are implemented.'
$oldError = "    if (s.contains('already-exists')) return 'This email already has a Firebase login. Use a different verified email or ask an administrator to link the existing account.';"
$newError = @'
    if (s.contains('email-already-in-use') || s.contains('already-exists')) {
      return 'This email is already registered in Firebase Authentication. Use a different real inbox or ask an administrator to review the existing account.';
    }
    if (s.contains('operation-not-allowed')) {
      return 'Email/Password sign-in is disabled. Enable it in Firebase Console > Authentication > Sign-in method.';
    }
    if (s.contains('too-many-requests')) {
      return 'Too many signup or email requests. Try again later.';
    }
    if (s.contains('may exist without a Staff Profile')) {
      return 'A Firebase Auth account may have been created without its Staff Profile. Check Firebase Authentication and Firestore before trying again.';
    }
    if (s.contains('not authorized to create staff') || s.contains('verified Admin account')) {
      return 'A verified Administrator account with admin permission is required.';
    }
'@
$oldError = $oldError.Replace("`r`n", "`n")
$newError = $newError.Replace("`r`n", "`n").TrimEnd("`r", "`n")
$normalized = $uiSource.Replace("`r`n", "`n")
if ($normalized.Contains('Spark plan: employees are registered with Firebase Authentication')) {
    throw 'Step 8 already appears to be installed. No changes made.'
}
if (([regex]::Matches($normalized, [regex]::Escape($oldBanner))).Count -ne 1 -or
    ([regex]::Matches($normalized, [regex]::Escape($oldError))).Count -ne 1) {
    throw 'Staff UI does not have the expected Step 6 markers. No changes made; do not overwrite local changes.'
}
$updatedUi = $normalized.Replace($oldBanner, $newBanner).Replace($oldError, $newError)
if ($uiSource.Contains("`r`n")) { $updatedUi = $updatedUi.Replace("`n", "`r`n") }

$newPaths = @(
    'lib\admin\staff\staff_spark_policy.dart',
    'test\admin\staff_spark_policy_test.dart',
    'test\emulator\staff_spark_rules.test.cjs'
)
foreach ($relative in $newPaths) {
    $destination = Join-Path $root $relative
    $source = Join-Path $root (Join-Path 'spark_step8_files' $relative)
    if (-not (Test-Path -LiteralPath $source)) { throw "Missing Step 8 file: $source" }
    if (Test-Path -LiteralPath $destination) {
        throw "Refusing to overwrite existing file: $destination. No changes made."
    }
}

# All validation occurs before any project modification.
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$targets = @($uiPath)
foreach ($item in $checks) { $targets += (Join-Path $root $item.Relative) }
$backups = @()
foreach ($destination in $targets) {
    $backup = "$destination.before-spark-step8-$stamp.bak"
    [System.IO.File]::Copy($destination, $backup)
    $backups += $backup
}

try {
    foreach ($item in $checks) {
        $destination = Join-Path $root $item.Relative
        $source = Join-Path $root (Join-Path 'spark_step8_files' $item.Relative)
        [System.IO.File]::Copy($source, $destination, $true)
    }
    [System.IO.File]::WriteAllText($uiPath, $updatedUi, (New-Object System.Text.UTF8Encoding($false)))
    foreach ($relative in $newPaths) {
        $destination = Join-Path $root $relative
        $source = Join-Path $root (Join-Path 'spark_step8_files' $relative)
        [System.IO.File]::Copy($source, $destination)
    }
} catch {
    for ($i=0; $i -lt $targets.Count; $i++) {
        [System.IO.File]::Copy($backups[$i], $targets[$i], $true)
    }
    foreach ($relative in $newPaths) {
        $destination = Join-Path $root $relative
        if (Test-Path -LiteralPath $destination) { Remove-Item -LiteralPath $destination -Force }
    }
    throw ('Step 8 install failed. Previous versions were restored. ' + $_.Exception.Message)
}

Write-Host 'Step 8 Spark Staff Account Creation installed.' -ForegroundColor Green
Write-Host 'No Cloud Functions, Firebase Rules or billing changes were made.'
Write-Host 'Super Admin session stays in ThemeParkAdmin. Employee signup uses a separate named Firebase app.'
Write-Host 'Backups saved:'
$backups | ForEach-Object { Write-Host "  $_" }
Write-Host 'Next: flutter analyze lib/admin/staff'
Write-Host 'Then: flutter test test/admin/staff_portal_policy_test.dart test/admin/staff_spark_policy_test.dart test/admin/staff_access_test.dart test/admin/staff_records_test.dart'
