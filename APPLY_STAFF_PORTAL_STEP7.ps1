$ErrorActionPreference = 'Stop'

if (-not (Test-Path '.\pubspec.yaml')) { throw 'Run from the FYP_New project root.' }
$mainPath = Join-Path (Get-Location).Path 'lib\main.dart'
$portalPath = Join-Path (Get-Location).Path 'lib\admin\staff\staff_portal.dart'
$policyPath = Join-Path (Get-Location).Path 'lib\admin\staff\staff_portal_policy.dart'
$testPath = Join-Path (Get-Location).Path 'test\admin\staff_portal_policy_test.dart'
foreach ($path in @($mainPath, $portalPath, $policyPath, $testPath)) {
  if (-not (Test-Path $path)) { throw "Missing file: $path" }
}
$original = [System.IO.File]::ReadAllText($mainPath)
if ($original.Contains("'/staff': (context) => const StaffPortal()")) {
  throw 'Step 7 staff route is already installed. Nothing was changed.'
}
$importMarker = "import 'admin/admin_portal.dart';"
$routeMarker = "        '/admin': (context) => const AdminPortal(),"
if (([regex]::Matches($original, [regex]::Escape($importMarker))).Count -ne 1 -or
    ([regex]::Matches($original, [regex]::Escape($routeMarker))).Count -ne 1) {
  throw 'Unable to locate the expected main.dart import and route. No changes made. Send main.dart for a safe merge.'
}
$updated = $original.Replace($importMarker,
    "$importMarker`nimport 'admin/staff/staff_portal.dart';")
$updated = $updated.Replace($routeMarker,
    "$routeMarker`n        '/staff': (context) => const StaffPortal(),")
# Preserve Windows line endings when main.dart uses CRLF.
if ($original.Contains("`r`n")) {
  $updated = $updated.Replace("`r`n", "`n").Replace("`n", "`r`n")
}
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$backup = "$mainPath.before-staff-step7-$stamp.bak"
[System.IO.File]::Copy($mainPath, $backup)
try {
  [System.IO.File]::WriteAllText($mainPath, $updated, (New-Object System.Text.UTF8Encoding($false)))
} catch {
  [System.IO.File]::Copy($backup, $mainPath, $true)
  throw
}
Write-Host 'Step 7: /staff route installed. Existing Admin Portal and CrowdSense are unchanged.' -ForegroundColor Green
Write-Host "Backup: $backup"
Write-Host 'Next: flutter analyze lib/admin/staff lib/main.dart'
Write-Host 'Then: flutter test test/admin/staff_portal_policy_test.dart'
