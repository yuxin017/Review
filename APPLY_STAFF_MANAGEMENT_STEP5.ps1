$ErrorActionPreference = 'Stop'

function Replace-ExactlyOnce([string]$text, [string]$find, [string]$replace, [string]$label) {
    $count = ([regex]::Matches($text, [regex]::Escape($find))).Count
    if ($count -ne 1) { throw "Cannot safely patch $label (expected one exact code marker, found $count). No original files were changed." }
    return $text.Replace($find, $replace)
}

$root = (Get-Location).Path
if (-not (Test-Path (Join-Path $root 'pubspec.yaml'))) {
    throw 'Run this script in the FYP_New project root (where pubspec.yaml exists).'
}
$ui = Join-Path $root 'lib\admin\staff\staff_management_page.dart'
$records = Join-Path $root 'lib\admin\staff\staff_records_repository.dart'
$repositoryPath = Join-Path $root 'lib\admin\admin_repository.dart'
$shellPath = Join-Path $root 'lib\admin\admin_shell.dart'
foreach ($f in @($ui, $records, $repositoryPath, $shellPath)) {
    if (-not (Test-Path $f)) { throw "Required file is missing: $f" }
}

$repoRaw = [System.IO.File]::ReadAllText($repositoryPath)
$shellRaw = [System.IO.File]::ReadAllText($shellPath)
$repoCRLF = $repoRaw.Contains("`r`n")
$shellCRLF = $shellRaw.Contains("`r`n")
$repo = $repoRaw.Replace("`r`n", "`n")
$shell = $shellRaw.Replace("`r`n", "`n")

if ($repo.Contains('staffRecordsRepository') -and $shell.Contains('StaffManagementPage(')) {
    Write-Host 'Step 5 appears to be integrated already. No changes made.' -ForegroundColor Yellow
    exit 0
}
if ($repo.Contains('staffRecordsRepository') -or $shell.Contains('StaffManagementPage(')) {
    throw 'Partial Staff integration already exists. No files changed. Please inspect existing modifications before retrying.'
}

$repoNew = Replace-ExactlyOnce $repo "import 'photos/photo_admin_repository.dart';`n" "import 'photos/photo_admin_repository.dart';`nimport 'staff/staff_records_repository.dart';`n" 'admin_repository.dart import'
$repoNew = Replace-ExactlyOnce $repoNew "  PhotoAdminRepository? get photoRepository => null;`n" "  PhotoAdminRepository? get photoRepository => null;`n  StaffRecordsRepository? get staffRecordsRepository => null;`n" 'abstract AdminRepository'
$oldGetter = "  PhotoAdminRepository get photoRepository =>`n      FirebasePhotoAdminRepository(db: _db, auth: firebase.auth);`n"
$newGetter = "  PhotoAdminRepository get photoRepository =>`n      FirebasePhotoAdminRepository(db: _db, auth: firebase.auth);`n  @override`n  StaffRecordsRepository get staffRecordsRepository =>`n      StaffRecordsRepository(_db);`n"
$repoNew = Replace-ExactlyOnce $repoNew $oldGetter $newGetter 'FirebaseAdminRepository'

$shellNew = Replace-ExactlyOnce $shell "import 'photos/photo_management.dart';`n" "import 'photos/photo_management.dart';`nimport 'staff/staff_management_page.dart';`n" 'admin_shell.dart import'
$shellNew = Replace-ExactlyOnce $shellNew "('visitors', 'Visitors', Icons.people_outline),`n" "('visitors', 'Visitors', Icons.people_outline),`n                    ('staff', 'Staff Management', Icons.badge_outlined),`n" 'Admin sidebar'
$oldBranch = "        } else if (page == 'tickets') {`n"
$newBranch = "        } else if (page == 'staff') {`n          body = repository.staffRecordsRepository == null`n              ? const AdminCard(child: Text('Staff Management is unavailable. Sign in with an authorized administrator account.'))`n              : StaffManagementPage(repository: repository.staffRecordsRepository!);`n        } else if (page == 'tickets') {`n"
$shellNew = Replace-ExactlyOnce $shellNew $oldBranch $newBranch 'Admin page selection'

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$backupRepo = "$repositoryPath.before-staff-step5-$stamp.bak"
$backupShell = "$shellPath.before-staff-step5-$stamp.bak"
[System.IO.File]::Copy($repositoryPath, $backupRepo)
[System.IO.File]::Copy($shellPath, $backupShell)

if ($repoCRLF) { $repoNew = $repoNew.Replace("`n", "`r`n") }
if ($shellCRLF) { $shellNew = $shellNew.Replace("`n", "`r`n") }
$utf8 = New-Object System.Text.UTF8Encoding($false)
try {
    [System.IO.File]::WriteAllText($repositoryPath, $repoNew, $utf8)
    [System.IO.File]::WriteAllText($shellPath, $shellNew, $utf8)
} catch {
    [System.IO.File]::Copy($backupRepo, $repositoryPath, $true)
    [System.IO.File]::Copy($backupShell, $shellPath, $true)
    throw
}
Write-Host 'Staff Management UI integrated into the existing Admin Portal.' -ForegroundColor Green
Write-Host "Backups saved:`n  $backupRepo`n  $backupShell"
Write-Host 'Next: flutter analyze lib/admin/staff/staff_management_page.dart lib/admin/admin_repository.dart lib/admin/admin_shell.dart'
