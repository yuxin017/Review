$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$liveFile = Join-Path $root 'lib\admin\cameras\crowdsense_lab.dart'
$engineFile = Join-Path $root 'lib\admin\cameras\crowdsense_engine.dart'
$source = Join-Path $root 'crowdsense_sources'
$template = Join-Path $source 'crowdsense_lab.dart.template'
if (-not (Test-Path -LiteralPath (Join-Path $root 'pubspec.yaml'))) {
  throw 'Extract this ZIP into FYP_New root (beside pubspec.yaml), then run this fix again.'
}
if (-not (Test-Path -LiteralPath $liveFile)) {
  throw 'CrowdSense has not yet been installed: lib\admin\cameras\crowdsense_lab.dart is missing. Run install_crowdsense.ps1 first.'
}
$original = [IO.File]::ReadAllText($liveFile)
$updated = $original.Replace("`r`n", "`n")
if ($updated -notmatch "import 'package:flutter/foundation.dart';") {
  $needle = "import 'package:flutter/material.dart';"
  if (-not $updated.Contains($needle)) { throw 'Unexpected CrowdSense source; not overwriting. Please send current file.' }
  $updated = $updated.Replace($needle, "import 'package:flutter/foundation.dart';`n" + $needle)
}
if ($updated.Contains("import '../lib/attractions/models/attraction.dart';")) {
  $updated = $updated.Replace("import '../lib/attractions/models/attraction.dart';", "import '../../attractions/models/attraction.dart';")
}
$backupDir = Join-Path $root '.local'
New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
if ($updated -ne $original.Replace("`r`n", "`n")) {
  $backupPath = Join-Path $backupDir ('crowdsense_lab.before_fix_' + (Get-Date -Format 'yyyyMMdd_HHmmss') + '.dart')
  Copy-Item -LiteralPath $liveFile -Destination $backupPath
  [IO.File]::WriteAllText($liveFile, ($updated.TrimEnd() + "`n"), (New-Object Text.UTF8Encoding($false)))
  Write-Host 'Corrected import in lib\admin\cameras\crowdsense_lab.dart' -ForegroundColor Green
} else {
  Write-Host 'Installed CrowdSense file already has correct imports.' -ForegroundColor Green
}
# The original ZIP left source .dart copies outside lib/. Android Studio then
# flags their relative imports as errors. Preserve copies as text backups.
foreach ($rel in @('crowdsense_lab.dart','crowdsense_engine.dart','test\crowdsense_engine_test.dart')) {
  $path = Join-Path $source $rel
  if (Test-Path -LiteralPath $path) {
    $backup = $path + '.legacy-source.txt'
    if (Test-Path -LiteralPath $backup) {
      $backup = $path + '.' + (Get-Date -Format 'yyyyMMddHHmmssfff') + '.legacy-source.txt'
    }
    Move-Item -LiteralPath $path -Destination $backup
    Write-Host ('Archived old IDE-visible template: ' + $rel) -ForegroundColor Green
  }
}
if ((Test-Path $template) -and -not ([IO.File]::ReadAllText($template)).Contains("import 'package:flutter/foundation.dart';")) {
  throw 'Patch template is outdated. Use the fixed ZIP package to reinstall.'
}
Write-Host 'CrowdSense source fix completed. Rebuild the Web app using your existing project launcher.' -ForegroundColor Cyan
