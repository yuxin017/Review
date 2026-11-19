$ErrorActionPreference = 'Stop'
if (-not (Test-Path '.\pubspec.yaml') -or -not (Test-Path '.\lib\admin\staff\staff_management_page.dart')) {
  throw 'Open a terminal in your FYP_New project folder.'
}
$root = (Get-Location).Path
$payload = Join-Path $root 'step11_payload'
$expected = @{
  'lib\admin\staff\staff_form_validation.dart' = 'e1303441e18a616ddfc5f4660f3d26a921beceded98ea93d7a9ec17028e16810'
  'lib\admin\staff\staff_management_page.dart' = '51a8a5a3bd84c838ef87fed3dcaa3a37eefd9b7dc1ee670ac14dbdd8d9a6672a'
  'lib\admin\staff\staff_records_repository.dart' = '243dfbd9993ecbfe99fb1668ea73c4bc5eb0c5a1a1b4f47b06430ec81a859fef'
  'lib\admin\staff\staff_portal.dart' = 'd08790ea3cb6897c49860cb438f76e49aac0d560d7fbcbbed88524d2c0da5a33'
  'lib\admin\staff\staff_email_check.dart' = 'e906f7744b0c815df13e537145e3fa88d25bc0458b5e19405db22082261f37bc'
  'lib\admin\staff\staff_training_catalog.dart' = '2e12755f25d1b7c82b27288aceb00232508b54ed6b65ab7484b14491e5be76c9'
}
$targets = @($expected.Keys | Sort-Object)
foreach ($rel in $targets) {
  $dest = Join-Path $root $rel
  $source = Join-Path $payload $rel
  if (-not (Test-Path -LiteralPath $source) -or -not (Test-Path -LiteralPath $dest)) {
    throw "Missing file: $rel. No changes made."
  }
  $hash = (Get-FileHash -LiteralPath $dest -Algorithm SHA256).Hash.ToLowerInvariant()
  if ($hash -ne $expected[$rel]) {
    throw "File has newer edits: $rel. No changes made. Please upload this Dart file for a safe merge."
  }
}
$newFiles = @(
  'lib\admin\staff\staff_training_batch_policy.dart',
  'test\admin\staff_training_batch_policy_test.dart',
  'test\emulator\staff_training_batch.test.cjs'
)
foreach ($rel in $newFiles) {
  if (-not (Test-Path -LiteralPath (Join-Path $payload $rel))) {
    throw "Package incomplete: $rel. No changes made."
  }
  if (Test-Path -LiteralPath (Join-Path $root $rel)) {
    throw "Existing file at $rel. No changes made."
  }
}

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$backups = @()
foreach ($rel in $targets) {
  $path = Join-Path $root $rel
  $backup = "$path.before-staff-step11-$stamp.bak"
  Copy-Item -LiteralPath $path -Destination $backup -ErrorAction Stop
  $backups += @{path=$path; backup=$backup}
}
$created = @()
try {
  foreach ($rel in $targets) {
    Copy-Item -LiteralPath (Join-Path $payload $rel) -Destination (Join-Path $root $rel) -Force
  }
  foreach ($rel in $newFiles) {
    $path = Join-Path $root $rel
    $dir = Split-Path -Parent $path
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    Copy-Item -LiteralPath (Join-Path $payload $rel) -Destination $path
    $created += $path
  }
} catch {
  foreach ($b in $backups) {
    Copy-Item -LiteralPath $b.backup -Destination $b.path -Force
  }
  foreach ($p in $created) {
    if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Force }
  }
  throw "Installation stopped and restored backups: $($_.Exception.Message)"
}
Write-Host 'Step 11 Staff training UI installed. Existing data was not changed.' -ForegroundColor Green
Write-Host 'No Firebase Rules or Cloud Functions were deployed.'
Write-Host 'Run: flutter analyze lib/admin/staff'
Write-Host 'Run: flutter test test/admin/staff_training_batch_policy_test.dart test/admin/staff_email_check_test.dart'
Write-Host 'Run: firebase emulators:exec --config firebase.staff-emulators.json --only auth,firestore --project demo-themepark-fyp "node --test test/emulator/staff_training_batch.test.cjs"'
Write-Host 'Run: .\tool\run-app.cmd -Restart'
