param([switch]$VerifyOnly)
$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$target = Join-Path $root 'lib\admin\cameras\live_cameras_panel.dart'
$targetDir = Split-Path $target -Parent
$sourceDir = Join-Path $root 'crowdsense_sources'
if (-not (Test-Path -LiteralPath $target)) {
  throw 'Please extract ALL ZIP files into the FYP_New project root, then run this script there. Missing: lib\admin\cameras\live_cameras_panel.dart'
}
foreach ($filename in @('crowdsense_engine.dart','crowdsense_lab.dart','test\crowdsense_engine_test.dart')) {
  if (-not (Test-Path -LiteralPath (Join-Path $sourceDir ($filename + '.template')))) {
    throw "Missing fixed patch template: $filename. Extract the whole ZIP first."
  }
}

function Replace-Once([string] $original, [string] $find, [string] $replace, [string] $name) {
  # Consistent behavior across Windows PowerShell here-string newline handling.
  $find = $find -replace '(\r?\n)+$', ''
  $replace = $replace -replace '(\r?\n)+$', ''
  $found = [regex]::Matches($original, [regex]::Escape($find))
  if ($found.Count -ne 1) {
    throw "The GitHub source has changed around '$name' ($($found.Count) matches). The original file has NOT been overwritten. Ask ChatGPT for an updated patch."
  }
  return $original.Replace($find, $replace)
}


function Install-Templates() {
  foreach ($filename in @('crowdsense_engine.dart','crowdsense_lab.dart')) {
    $templatePath = Join-Path $sourceDir ($filename + '.template')
    $destPath = Join-Path $targetDir $filename
    [IO.File]::WriteAllText($destPath, [IO.File]::ReadAllText($templatePath), (New-Object Text.UTF8Encoding($false)))
  }
  $testDir = Join-Path $root 'test'
  New-Item -ItemType Directory -Path $testDir -Force | Out-Null
  [IO.File]::WriteAllText((Join-Path $testDir 'crowdsense_engine_test.dart'),
    [IO.File]::ReadAllText((Join-Path $sourceDir 'test\crowdsense_engine_test.dart.template')),
    (New-Object Text.UTF8Encoding($false)))
  # Original ZIP extracted parseable .dart sources into a staging folder.
  # Keep them as text backups to prevent the IDE treating their old relative
  # imports as application code. Do not delete the user's source changes.
  foreach ($legacy in @('crowdsense_engine.dart','crowdsense_lab.dart','test\crowdsense_engine_test.dart')) {
    $from = Join-Path $sourceDir $legacy
    if (Test-Path -LiteralPath $from) {
      $backup = $from + '.legacy-source.txt'
      if (Test-Path -LiteralPath $backup) {
        $backup = $from + '.' + (Get-Date -Format 'yyyyMMddHHmmssfff') + '.legacy-source.txt'
      }
      Move-Item -LiteralPath $from -Destination $backup
    }
  }
}

$source = [IO.File]::ReadAllText($target).Replace("`r`n", "`n")
if ($source.Contains("import 'crowdsense_lab.dart';")) {
  Write-Host 'CrowdSense is already integrated. Refreshing CrowdSense files only.' -ForegroundColor Yellow
  if (-not $VerifyOnly) {
    Install-Templates
  }
  exit 0
}

$script = $source
$find = @'
import 'camera_peer.dart';
'@
$replace = @'
import 'camera_peer.dart';
import 'crowdsense_engine.dart';
import 'crowdsense_lab.dart';
'@
$script = Replace-Once $script $find $replace 'new imports'

$find = @'
  String? _error;

  Future<void> _save
'@
$replace = @'
  String? _error;
  final ValueNotifier<Map<String, CrowdSensorReading>> _sensorReadings =
      ValueNotifier(<String, CrowdSensorReading>{});

  void _onCameraCount(String attractionId, int count) {
    if (!mounted) return;
    _sensorReadings.value = {
      ..._sensorReadings.value,
      attractionId: CrowdSensorReading(count, DateTime.now()),
    };
  }

  @override
  void dispose() {
    _sensorReadings.dispose();
    super.dispose();
  }

  Future<void> _save
'@
$script = Replace-Once $script $find $replace 'live sensor collector'

$find = @'
                const SizedBox(height: 16),
                if (assigned.isEmpty)
'@
$replace = @'
                const SizedBox(height: 16),
                CrowdSenseLab(
                  attractions: [
                    ...rides.where((ride) => enabled.contains(ride.id)),
                    ...rides.where((ride) => !enabled.contains(ride.id)),
                  ],
                  readings: _sensorReadings,
                ),
                const SizedBox(height: 16),
                if (assigned.isEmpty)
'@
$script = Replace-Once $script $find $replace 'CrowdSense panel on admin page'

$find = @'
                              store: widget.store,
                              onRemove:
'@
$replace = @'
                              store: widget.store,
                              onCameraCount: _onCameraCount,
                              onRemove:
'@
$script = Replace-Once $script $find $replace 'camera tile callback'

$find = @'
    required this.onRemove,
  });
  final Attraction place;
'@
$replace = @'
    required this.onRemove,
    required this.onCameraCount,
  });
  final Attraction place;
'@
$script = Replace-Once $script $find $replace 'camera tile constructor'

$find = @'
  final VoidCallback? onRemove;
  @override
'@
$replace = @'
  final VoidCallback? onRemove;
  final void Function(String attractionId, int count) onCameraCount;
  @override
'@
$script = Replace-Once $script $find $replace 'camera tile field'

$find = @'
                    session: session,
                  ),
                if (online)
'@
$replace = @'
                    session: session,
                    onCameraCount: widget.onCameraCount,
                  ),
                if (online)
'@
$script = Replace-Once $script $find $replace 'camera viewer callback'

$find = @'
    required this.session,
  });
  final AttractionCameraStore store;
'@
$replace = @'
    required this.session,
    required this.onCameraCount,
  });
  final AttractionCameraStore store;
'@
$script = Replace-Once $script $find $replace 'camera viewer constructor'

$find = @'
  final String attractionId, session;
  @override
'@
$replace = @'
  final String attractionId, session;
  final void Function(String attractionId, int count) onCameraCount;
  @override
'@
$script = Replace-Once $script $find $replace 'camera viewer field'

$find = @'
  bool _showHeat = true, _connected = false;
'@
$replace = @'
  bool _showHeat = true, _connected = false;
  DateTime? _lastCrowdReport;
'@
$script = Replace-Once $script $find $replace 'camera sample throttling field'

$find = @'
        if (heat == null) return;
        setState(() => _heat = heat);
'@
$replace = @'
        if (heat == null) return;
        setState(() => _heat = heat);
        final now = DateTime.now();
        if (_lastCrowdReport == null ||
            now.difference(_lastCrowdReport!) >=
                const Duration(milliseconds: 1200)) {
          _lastCrowdReport = now;
          widget.onCameraCount(widget.attractionId, heat.count);
        }
'@
$script = Replace-Once $script $find $replace 'WebRTC count collector'

if ($VerifyOnly) {
  Write-Host 'All 11 integration anchors matched. No files were changed.' -ForegroundColor Green
  exit 0
}

$backupRoot = Join-Path $root '.local'
New-Item -ItemType Directory -Force -Path $backupRoot | Out-Null
$backupFile = Join-Path $backupRoot ('live_cameras_panel.before_crowdsense_' + (Get-Date -Format 'yyyyMMdd_HHmmss') + '.dart')
Copy-Item -LiteralPath $target -Destination $backupFile
$utf8 = New-Object System.Text.UTF8Encoding($false)
[IO.File]::WriteAllText($target, $script + "`n", $utf8)
Install-Templates
Write-Host "CrowdSense installed successfully! Backup: $backupFile" -ForegroundColor Green
Write-Host 'Next: .\tool\run-app.cmd (use a new terminal if another server is already running)' -ForegroundColor Cyan
Write-Host 'Open Admin > Crowd Monitoring > Live Cameras to see CrowdSense AI.' -ForegroundColor Cyan
