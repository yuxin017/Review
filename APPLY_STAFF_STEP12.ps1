$ErrorActionPreference = 'Stop'
# Step 12: Immutable Course -> Attraction association and Spark Staff Portal.
# Does not deploy Firebase or delete any data.
if (-not (Test-Path -LiteralPath '.\pubspec.yaml') -or
    -not (Test-Path -LiteralPath '.\lib\admin\staff\staff_management_page.dart')) {
  throw 'Open PowerShell in the FYP_New project folder.'
}
$root = (Get-Location).Path
$payload = Join-Path $root 'step12_payload'
function Read-Lf([string]$path) {
  return [System.IO.File]::ReadAllText($path).Replace("`r`n", "`n")
}
function Replace-Once([string]$source, [string]$before, [string]$after, [string]$label) {
  $count = ([regex]::Matches($source, [regex]::Escape($before))).Count
  if ($count -ne 1) {
    throw "Cannot safely patch $label (found $count matches). No changes made."
  }
  return $source.Replace($before, $after)
}
# Hashes from the published Step 11 / earlier Spark packages. Unrecognized
# edits must be manually merged, never overwritten.
$expected = @{
  'lib\admin\staff\staff_training_catalog.dart' = 'f46569390c8e0d340e176daa387c9fff810e624d07afe5d92acaaa5e541e59b1'
  'lib\admin\staff\staff_management_page.dart' = '52862a236a5bdf0dc88079c1d0159fecd79484e2ee39787f22f7fbe5ff3d788b'
  'lib\admin\staff\staff_records_repository.dart' = '25710be8d11fd70f4e90248a729bb7784b5fdb637ee94a0d028425e10a2cd060'
}
$acceptablePortal = @(
  '304507267aafbd60735fb9d726085d1d45c46d1d9248a98914cc96a756c9d177', # Step 11
  '236870ce7168f5cb6faf4dc42c01b76314ffc93035b26bb3472cc6fab25c71e2', # Step 7 (old staff-claim gate)
  '5fb9fa6f121143f830e430cfaa152af926502fe907bb5cddbe2572c036596b57', # Step 8
  'd08790ea3cb6897c49860cb438f76e49aac0d560d7fbcbbed88524d2c0da5a33'  # Step 10
)
foreach ($rel in $expected.Keys) {
  $path = Join-Path $root $rel
  $source = Join-Path $payload $rel
  if (-not (Test-Path -LiteralPath $path) -or -not (Test-Path -LiteralPath $source)) {
    throw "Missing $rel. No changes made."
  }
  $hash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
  if ($hash -ne $expected[$rel]) {
    throw "This file has additional edits: $rel. No changes made. Please upload it for safe merging."
  }
}
$portalRel = 'lib\admin\staff\staff_portal.dart'
$portalPath = Join-Path $root $portalRel
if (-not (Test-Path -LiteralPath $portalPath)) {throw 'Staff Portal file is missing.'}
$portalHash = (Get-FileHash -LiteralPath $portalPath -Algorithm SHA256).Hash.ToLowerInvariant()
if ($acceptablePortal -notcontains $portalHash) {
  throw "The Staff Portal has additional edits. No changes made. Please upload $portalRel."
}
$testRel = 'test\emulator\staff_course_binding.test.cjs'
$testTarget = Join-Path $root $testRel
if (Test-Path -LiteralPath $testTarget) { throw 'Step 12 test file already exists. No changes made.' }
$testSource = Join-Path $payload $testRel
if (-not (Test-Path -LiteralPath $testSource)) { throw 'Step 12 package is incomplete.' }
$rulesPath = Join-Path $root 'firestore.rules'
$originalRules = [System.IO.File]::ReadAllText($rulesPath)
$rules = $originalRules.Replace("`r`n", "`n")
if (-not $rules.Contains('STEP10_TRAINING_CATALOGUE_HOTFIX_V1') -or
    -not $rules.Contains('match /staffEmailVerifications/{staffUid}')) {
  throw 'Step 10 verification and training hotfix must be installed first.'
}
$oldValidation = @'
    function workforceTrainingCourseValid(data) {
      return data.keys().hasOnly(['title', 'roleCode', 'active', 'updatedAt'])
        && data.keys().hasAll(['title', 'roleCode', 'active', 'updatedAt'])
        && data.title is string && data.title.size() >= 4 && data.title.size() <= 120
        && data.roleCode in [
          'operations_manager', 'attraction_operator', 'admission_staff',
          'photographer', 'photo_counter_staff', 'marketing_staff',
          'customer_support'
        ]
        && data.active is bool
        && data.updatedAt == request.time;
    }
'@
$newValidation = @'
    // STEP12_COURSE_ATTRACTION_BINDING_V1
    function workforceTrainingCourseValid(data) {
      return data.keys().hasOnly(['title', 'roleCode', 'active', 'updatedAt', 'attractionId'])
        && data.keys().hasAll(['title', 'roleCode', 'active', 'updatedAt'])
        && data.title is string && data.title.size() >= 4 && data.title.size() <= 120
        && data.roleCode in [
          'operations_manager', 'attraction_operator', 'admission_staff',
          'photographer', 'photo_counter_staff', 'marketing_staff',
          'customer_support'
        ]
        && data.active is bool
        && (data.roleCode != 'attraction_operator'
          ? data.get('attractionId', '') == ''
          : (data.get('attractionId', '') is string
            && data.get('attractionId', '').size() >= 1
            && data.get('attractionId', '').size() <= 128
            && exists(/databases/$(database)/documents/attractions/$(data.attractionId))))
        && data.updatedAt == request.time;
    }
'@
$rules = Replace-Once $rules $oldValidation $newValidation 'Course binding rules'
$oldCourseUpdate = @'
      allow update: if workforceSuperAdmin()
        && workforceTrainingCourseValid(request.resource.data)
        && request.resource.data.title == resource.data.title
        && request.resource.data.roleCode == resource.data.roleCode;
'@
$newCourseUpdate = @'
      allow update: if workforceSuperAdmin()
        && workforceTrainingCourseValid(request.resource.data)
        && request.resource.data.title == resource.data.title
        && request.resource.data.roleCode == resource.data.roleCode
        && (resource.data.get('attractionId','') == ''
          || request.resource.data.attractionId == resource.data.attractionId);
'@
$rules = Replace-Once $rules $oldCourseUpdate $newCourseUpdate 'Course attribution immutability'
$oldCourseMatch = @'
    function workforceQualificationMatchesCourse(data) {
      return !data.keys().hasAny(['courseId'])
        || (exists(/databases/$(database)/documents/staffTrainingCourses/$(data.courseId))
          && get(/databases/$(database)/documents/staffTrainingCourses/$(data.courseId)).data.active == true
          && get(/databases/$(database)/documents/staffTrainingCourses/$(data.courseId)).data.title == data.title
          && get(/databases/$(database)/documents/staffTrainingCourses/$(data.courseId)).data.roleCode == data.roleCode);
    }
'@
$newCourseMatch = @'
    function workforceQualificationMatchesCourse(data) {
      return !data.keys().hasAny(['courseId'])
        || (exists(/databases/$(database)/documents/staffTrainingCourses/$(data.courseId))
          && get(/databases/$(database)/documents/staffTrainingCourses/$(data.courseId)).data.active == true
          && get(/databases/$(database)/documents/staffTrainingCourses/$(data.courseId)).data.title == data.title
          && get(/databases/$(database)/documents/staffTrainingCourses/$(data.courseId)).data.roleCode == data.roleCode
          && get(/databases/$(database)/documents/staffTrainingCourses/$(data.courseId)).data.get('attractionId', '') == data.attractionId);
    }
'@
$rules = Replace-Once $rules $oldCourseMatch $newCourseMatch 'Qualification requires exact Course attraction'
# Preflight done: all changed files are backed up BEFORE writing anything.
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$paths = @($expected.Keys | ForEach-Object {Join-Path $root $_}) + @($portalPath,$rulesPath)
$backups = @()
foreach ($p in $paths) {
  $backup = "$p.before-staff-step12-$stamp.bak"
  Copy-Item -LiteralPath $p -Destination $backup -ErrorAction Stop
  $backups += @{source=$p;backup=$backup}
}
$encoding = New-Object System.Text.UTF8Encoding($false)
try {
  foreach ($rel in $expected.Keys) {
    Copy-Item -LiteralPath (Join-Path $payload $rel) -Destination (Join-Path $root $rel) -Force
  }
  Copy-Item -LiteralPath (Join-Path $payload $portalRel) -Destination $portalPath -Force
  $finalRules = if ($originalRules.Contains("`r`n")) { $rules.Replace("`n", "`r`n") } else { $rules }
  [System.IO.File]::WriteAllText($rulesPath,$finalRules,$encoding)
  $directory = Split-Path -Parent $testTarget
  if (-not (Test-Path -LiteralPath $directory)) { New-Item -ItemType Directory -Path $directory -Force | Out-Null }
  Copy-Item -LiteralPath $testSource -Destination $testTarget
} catch {
  foreach ($item in $backups) { Copy-Item -LiteralPath $item.backup -Destination $item.source -Force }
  if (Test-Path -LiteralPath $testTarget) { Remove-Item -LiteralPath $testTarget -Force }
  throw "Installation rolled back after an error: $($_.Exception.Message)"
}
Write-Host 'Step 12 installed locally. No existing staff data was changed.' -ForegroundColor Green
Write-Host 'Ride courses now link to an attraction in Course Catalogue.'
Write-Host 'Staff Portal uses the Spark staff-profile sign-in gate.'
Write-Host 'LOCAL Firestore Rules updated. NOT deployed.' -ForegroundColor Yellow
Write-Host 'Next: flutter analyze lib/admin/staff'
Write-Host 'Next: firebase emulators:exec --config firebase.staff-emulators.json --only auth,firestore --project demo-themepark-fyp "node --test test/emulator/staff_course_binding.test.cjs test/emulator/staff_rules.test.cjs test/emulator/staff_spark_rules.test.cjs test/emulator/staff_step10_rules.test.cjs test/emulator/staff_training_batch.test.cjs"'
