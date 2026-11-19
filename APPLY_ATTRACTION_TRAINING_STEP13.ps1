$ErrorActionPreference = 'Stop'
# Step 13: safe, additive patch. Never runs firebase deploy.
# Run from the FYP_New root. Keeps all unrelated local work intact.
if (-not (Test-Path '.\pubspec.yaml') -or -not (Test-Path '.\firestore.rules')) {
  throw 'Open this Terminal in the FYP_New folder.'
}
$root = (Get-Location).Path
$payload = Join-Path $root 'step13_payload'
$editorPath = Join-Path $root 'lib\admin\attractions\attraction_editor_page.dart'
$repoPath = Join-Path $root 'lib\admin\attractions\data\admin_attraction_repository.dart'
$staffPath = Join-Path $root 'lib\admin\staff\staff_management_page.dart'
$rulesPath = Join-Path $root 'firestore.rules'
$interfacePath = Join-Path $root 'lib\admin\attractions\data\attraction_training_store.dart'
$dartTestPath = Join-Path $root 'test\admin\attraction_training_policy_test.dart'
$emTestPath = Join-Path $root 'test\emulator\staff_attraction_auto_course.test.cjs'
$targets = @($editorPath,$repoPath,$staffPath,$rulesPath)
foreach ($path in $targets) { if (-not (Test-Path -LiteralPath $path)) {throw "Missing $path. No changes made."} }
foreach ($path in @($interfacePath,$dartTestPath,$emTestPath)) {
  if (Test-Path -LiteralPath $path) {throw "Already exists: $path. No changes made."}
}
foreach ($relative in @(
  'lib\admin\attractions\data\attraction_training_store.dart',
  'test\admin\attraction_training_policy_test.dart',
  'test\emulator\staff_attraction_auto_course.test.cjs',
  'patches\repository_methods.dart.txt',
  'patches\editor_ui.dart.txt',
  'patches\editor_legacy_method.dart.txt'
)) {
  if (-not (Test-Path (Join-Path $payload $relative))) {
    throw "Incomplete Step 13 ZIP: $relative"
  }
}
function ReadLF([string]$path) {
  return [System.IO.File]::ReadAllText($path).Replace("`r`n", "`n")
}
function ReplaceOnce([string]$source,[string]$before,[string]$after,[string]$label) {
  $hits = ([regex]::Matches($source,[regex]::Escape($before))).Count
  if ($hits -ne 1) { throw "Cannot safely update $label (found $hits matches). No changes made." }
  return $source.Replace($before,$after)
}
function PreserveNewlines([string]$original,[string]$updated) {
  if ($original.Contains("`r`n")) {return $updated.Replace("`n","`r`n")}
  return $updated
}

$beforeEditor = [System.IO.File]::ReadAllText($editorPath)
$beforeRepo = [System.IO.File]::ReadAllText($repoPath)
$beforeStaff = [System.IO.File]::ReadAllText($staffPath)
$beforeRules = [System.IO.File]::ReadAllText($rulesPath)
$editor = $beforeEditor.Replace("`r`n","`n")
$repo = $beforeRepo.Replace("`r`n","`n")
$staff = $beforeStaff.Replace("`r`n","`n")
$rules = $beforeRules.Replace("`r`n","`n")
if (-not $rules.Contains('STEP12_COURSE_ATTRACTION_BINDING_V1') -or
    -not $staff.Contains('Future<void> _createCourse() async')) {
  throw 'Step 12 must be installed before Step 13. No changes made.'
}
if ($repo.Contains('createAttractionWithTraining') -or $editor.Contains('Required operator training')) {
  throw 'Step 13 appears to be already installed or partially edited. No changes made.'
}

# Modify only the real attraction editor and repository. No changes to the
# shared model or AdminAttractionStore interface (preserves existing tests).
$repo = ReplaceOnce $repo "import 'admin_attraction_store.dart';" (
  "import 'admin_attraction_store.dart';`nimport 'attraction_training_store.dart';"
) 'Attraction repository imports'
$repo = ReplaceOnce $repo 'class AdminAttractionRepository implements AdminAttractionStore {' (
  'class AdminAttractionRepository implements AdminAttractionStore, AttractionTrainingStore {'
) 'Attraction repository interface'
$repoMethods = ReadLF (Join-Path $payload 'patches\repository_methods.dart.txt')
$repo = ReplaceOnce $repo '  bool _sameFields(Attraction a, Attraction b) {' (
  $repoMethods + '  bool _sameFields(Attraction a, Attraction b) {'
) 'Attraction repository methods'

$editor = ReplaceOnce $editor "import 'data/admin_attraction_store.dart';" (
  "import 'data/admin_attraction_store.dart';`nimport 'data/attraction_training_store.dart';"
) 'Attraction editor import'
$editor = ReplaceOnce $editor '  final _name = TextEditingController();' (
  "  final _name = TextEditingController();`n  final _trainingTitle = TextEditingController();"
) 'Attraction course field'
$editor = ReplaceOnce $editor '    _name.dispose();' (
  "    _name.dispose();`n    _trainingTitle.dispose();"
) 'Attraction course disposal'
$oldCreate = @'
      if (_original == null) {
        await widget.store.createAttraction(replacement);
      } else {
'@
$newCreate = @'
      if (_original == null) {
        if (_isRide) {
          final store = widget.store;
          if (store is! AttractionTrainingStore) {
            throw StateError('Training is unavailable.');
          }
          final selectedTitle = _trainingTitle.text.trim();
          final courseTitle = selectedTitle.isEmpty
              ? AttractionTrainingPolicy.defaultTitle(_name.text)
              : selectedTitle;
          await store.createAttractionWithTraining(
            replacement,
            courseTitle: courseTitle,
          );
        } else {
          await widget.store.createAttraction(replacement);
        }
      } else {
'@
$editor = ReplaceOnce $editor $oldCreate $newCreate 'Create attraction and course'
$editor = ReplaceOnce $editor @'
                      controller: _name,
                      enabled: !busy,
'@ @'
                      controller: _name,
                      enabled: !busy,
                      onChanged: _isRide ? (_) => setState(() {}) : null,
'@ 'Update course name hint while naming attraction'
$legacy = ReadLF (Join-Path $payload 'patches\editor_legacy_method.dart.txt')
$editor = ReplaceOnce $editor '  Future<void> _reloadLatest() async {' (
  $legacy + '  Future<void> _reloadLatest() async {'
) 'Existing attraction training action'
$trainingUi = ReadLF (Join-Path $payload 'patches\editor_ui.dart.txt')
$mapSection = @'
                    const SizedBox(height: 24),
                    const Text(
                      'Map position',
'@
$editor = ReplaceOnce $editor $mapSection ($trainingUi + $mapSection) 'Required operator training section'
# Keep all errors short and understandable. Details remain in debug logs.
$editor = ReplaceOnce $editor @'
              'Firebase denied this save (permission-denied). Your admin access or database rules need to be checked. Your entered details have been kept.',
'@ @'
              "You don't have permission to save this.",
'@ 'Permission error wording'
$editor = ReplaceOnce $editor @'
              'Unable to save the $_itemName (${error.code}). Your entered details have been kept. Please try again.',
'@ @'
              "Couldn't save changes. Try again.",
'@ 'Default save error wording'

$editor = ReplaceOnce $editor @'
              'Please sign in again before saving. Your entered details have been kept.',
'@ @'
              'Please sign in again.',
'@ 'Sign-in error wording'
$editor = ReplaceOnce $editor @'
              'The save could not be confirmed. Check your connection and retry; your entered details have been kept.',
'@ @'
              'Connection failed. Try again.',
'@ 'Connection error wording'
$editor = ReplaceOnce $editor @'
              'Unable to save the $_itemName. Your entered details have been kept. Please try again.',
'@ @'
              "Couldn't save changes. Try again.",
'@ 'Unexpected save error wording'

# Staff -> Course Catalogue becomes the place for non-ride courses only.
# Existing ride courses, links and recorded qualifications are preserved.
$staff = ReplaceOnce $staff 'StaffRole.values.where((r) => r != StaffRole.superAdmin)' 'StaffRole.values.where((r) => r != StaffRole.superAdmin && r != StaffRole.attractionOperator)' 'Staff course role picker'
$staff = ReplaceOnce $staff @'
          subtitle: 'Create once; supervisors will select it when recording training.',
'@ @'
          subtitle: 'For ride training, use Park Facilities.',
'@ 'New course helper text'
$staff = ReplaceOnce $staff @'
        subtitle: 'Standardized courses shared across all staff records.',
'@ @'
        subtitle: 'Ride courses are created in Park Facilities.',
'@ 'Course catalogue helper text'

# Remove redundant ride selection from the non-ride Staff Course editor.
$staff = ReplaceOnce $staff @'
    String? selectedRideId;
    final ridesFuture = widget.repository.db.collection('attractions').get();
'@ '' 'Unused Staff ride selectors'
$staff = ReplaceOnce $staff @'
                onChanged: busy ? null : (v) => update(() {
                   role = v ?? role;
                   selectedRideId = null;
                 }),
'@ @'
                onChanged: busy ? null : (v) => update(() => role = v ?? role),
'@ 'Staff course role change'
# Use an exact start and end sentinel; no course fields outside this form change.
$rideStart = '               if (role == StaffRole.attractionOperator) ...['
$rideEnd = '               if (formError != null) _InlineError(formError!),'
$startIndex = $staff.IndexOf($rideStart,[StringComparison]::Ordinal)
$endIndex = $staff.IndexOf($rideEnd,$startIndex,[StringComparison]::Ordinal)
if ($startIndex -lt 0 -or $endIndex -lt $startIndex -or
    $staff.IndexOf($rideStart,$startIndex+1,[StringComparison]::Ordinal) -ne -1) {
  throw 'Cannot safely remove the old Staff ride selector. No changes made.'
}
$staff = $staff.Substring(0,$startIndex) + $staff.Substring($endIndex)
$staff = ReplaceOnce $staff @'
                 if (role == StaffRole.attractionOperator && selectedRideId == null) {
                   update(() => formError = 'Select an attraction.');
                   return;
                 }
'@ '' 'Remove redundant Staff ride validation'
$staff = ReplaceOnce $staff @'
                  await _catalog.createCourse(
                       title: title.text, role: role,
                       attractionId: selectedRideId ?? '');
'@ @'
                  await _catalog.createCourse(
                       title: title.text, role: role);
'@ 'Non-ride catalogue save'

# Atomic ride+course creation needs existsAfter, since the ride did not exist
# before the batched write. The old existence check remains in place.
$oldRule = 'exists(/databases/$(database)/documents/attractions/$(data.attractionId))'
$newRule = '(exists(/databases/$(database)/documents/attractions/$(data.attractionId)) || existsAfter(/databases/$(database)/documents/attractions/$(data.attractionId)))'
$rules = ReplaceOnce $rules $oldRule $newRule 'Course reference after atomic attraction creation'
$rules = ReplaceOnce $rules '// STEP12_COURSE_ATTRACTION_BINDING_V1' (
  '// STEP12_COURSE_ATTRACTION_BINDING_V1' + "`n    // STEP13_ATTRACTION_AUTO_COURSE_V1"
) 'Step 13 marker'

# All preflight checks passed. Backup first, then atomically restore on failures.
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$backups = @()
foreach ($path in $targets) {
  $backup = "$path.before-step13-$stamp.bak"
  Copy-Item -LiteralPath $path -Destination $backup -ErrorAction Stop
  $backups += @{path=$path;backup=$backup}
}
$encoding = New-Object System.Text.UTF8Encoding($false)
try {
  [System.IO.File]::WriteAllText($repoPath,(PreserveNewlines $beforeRepo $repo),$encoding)
  [System.IO.File]::WriteAllText($editorPath,(PreserveNewlines $beforeEditor $editor),$encoding)
  [System.IO.File]::WriteAllText($staffPath,(PreserveNewlines $beforeStaff $staff),$encoding)
  [System.IO.File]::WriteAllText($rulesPath,(PreserveNewlines $beforeRules $rules),$encoding)
  foreach ($item in @(
    @{src='lib\admin\attractions\data\attraction_training_store.dart'; dest=$interfacePath},
    @{src='test\admin\attraction_training_policy_test.dart'; dest=$dartTestPath},
    @{src='test\emulator\staff_attraction_auto_course.test.cjs'; dest=$emTestPath}
  )) {
    $dir = Split-Path -Parent $item.dest
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    Copy-Item -LiteralPath (Join-Path $payload $item.src) -Destination $item.dest
  }
} catch {
  foreach ($b in $backups) { Copy-Item -LiteralPath $b.backup -Destination $b.path -Force }
  foreach ($p in @($interfacePath,$dartTestPath,$emTestPath)) {
    if (Test-Path -LiteralPath $p) {Remove-Item -LiteralPath $p -Force}
  }
  throw "Step 13 was rolled back: $($_.Exception.Message)"
}
Write-Host 'Step 13 installed locally. Ride and course are saved together.' -ForegroundColor Green
Write-Host 'Existing attractions can create a linked course from Edit Attraction.'
Write-Host 'Staff Course Catalogue now adds non-ride courses only.'
Write-Host 'Do NOT deploy Firestore Rules until emulator tests pass.'
