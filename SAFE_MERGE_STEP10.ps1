$ErrorActionPreference = 'Stop'

# Only repairs a Step 10 installation blocked by formatting/line-ending changes
# in staff_management_page.dart. Never overwrites actual custom logic.
if (-not (Test-Path '.\pubspec.yaml')) {
    throw 'Run this from your FYP_New project root.'
}
$root = (Get-Location).Path
$current = Join-Path $root 'lib\admin\staff\staff_management_page.dart'
$reference = Join-Path $root 'REFERENCE_complete_staff_management_page.dart.txt'
$step10 = Join-Path $root 'APPLY_STAFF_STEP10.ps1'
$expectedSha = '051a09c7d225c8121ed20f0af69ce2d3777d38ae0200f46e6112871edba33a2c'
foreach ($p in @($current, $reference, $step10)) {
    if (-not (Test-Path -LiteralPath $p)) { throw "Missing expected file: $p. No changes made." }
}
if ((Get-FileHash -LiteralPath $reference -Algorithm SHA256).Hash.ToLowerInvariant() -ne $expectedSha) {
    throw 'Step 9 reference does not match the known original. No changes made.'
}
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$backup = "$current.before-step10-safe-merge-$stamp.bak"
$work = Join-Path $root ".staff-step10-compare-$stamp"
New-Item -ItemType Directory -Path $work -Force | Out-Null
$utf8 = New-Object System.Text.UTF8Encoding($false)
function Write-Lf([string]$from,[string]$to) {
    $s = [System.IO.File]::ReadAllText($from).Replace("`r`n", "`n")
    [System.IO.File]::WriteAllText($to,$s,$utf8)
}
try {
    $localCopy = Join-Path $work 'local.dart'
    $baseCopy = Join-Path $work 'baseline.dart'
    Write-Lf $current $localCopy
    Write-Lf $reference $baseCopy
    $localSha = (Get-FileHash -LiteralPath $localCopy -Algorithm SHA256).Hash.ToLowerInvariant()
    $baseSha = (Get-FileHash -LiteralPath $baseCopy -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($baseSha -ne $expectedSha) { throw 'Baseline cannot be normalized safely.' }
    if ($localSha -ne $baseSha) {
        # Compare their formatted representations, without changing original files.
        & dart format $localCopy $baseCopy | Out-Null
        if ($LASTEXITCODE -ne 0) { throw 'Dart formatter could not check your local edits.' }
        $localSha = (Get-FileHash -LiteralPath $localCopy -Algorithm SHA256).Hash.ToLowerInvariant()
        $baseSha = (Get-FileHash -LiteralPath $baseCopy -Algorithm SHA256).Hash.ToLowerInvariant()
    }
    if ($localSha -ne $baseSha) {
        Write-Host 'STOP: Your file contains changes beyond formatting or line endings.' -ForegroundColor Yellow
        Write-Host "No existing file was changed. Please upload: $current"
        throw 'Safe merge stopped: additional Staff UI edits need manual review.'
    }
    Write-Host 'Your file is equivalent to the known Step 9 version after formatting.' -ForegroundColor Green
    [System.IO.File]::Copy($current, $backup)
    # Give the original Step 10 installer its exact validated baseline.
    try {
        [System.IO.File]::Copy($reference,$current,$true)
        & $step10
        Write-Host 'Step 10 installed successfully. No custom logic was overwritten.' -ForegroundColor Green
        Write-Host "Original backup: $backup"
    } catch {
        [System.IO.File]::Copy($backup,$current,$true)
        throw "Step 10 failed. Original Staff UI restored from backup. $($_.Exception.Message)"
    }
} finally {
    if (Test-Path -LiteralPath $work) { Remove-Item -LiteralPath $work -Recurse -Force }
}
