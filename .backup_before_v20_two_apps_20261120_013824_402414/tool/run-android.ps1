param(
    [string]$DeviceId,
    [switch]$Camera
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'project-runtime.ps1')
Set-Location -LiteralPath $script:FypProjectRoot
& (Join-Path $PSScriptRoot 'setup-project.ps1')
$runtime = Get-FypRuntime
Set-FypRuntimeEnvironment $runtime
& (Join-Path $PSScriptRoot 'setup-java.ps1')
if (-not $Camera) {
    & (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe') -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'ensure-account-service.ps1')
    if ($LASTEXITCODE -ne 0) { exit 1 }
}
$sdk = @($env:ANDROID_HOME, $env:ANDROID_SDK_ROOT, (Join-Path $env:LOCALAPPDATA 'Android\sdk')) | Where-Object { $_ -and (Test-Path -LiteralPath (Join-Path $_ 'platform-tools\adb.exe')) } | Select-Object -First 1
if (-not $sdk) { throw 'Install Android SDK Platform Tools in Android Studio first. Web use needs no Android SDK.' }
$adb = Join-Path $sdk 'platform-tools\adb.exe'
if (-not $DeviceId) {
    $devices = @(& $adb devices) | Where-Object { $_ -match '^\S+\s+device$' } | ForEach-Object { ($_ -split '\s+')[0] }
    if (@($devices).Count -ne 1) { throw 'Connect one Android phone and allow USB debugging, or run tool\run-android.cmd DEVICE_ID.' }
    $DeviceId = @($devices)[0]
}
if (-not $Camera) {
    & $adb -s $DeviceId reverse tcp:8787 tcp:8787
    if ($LASTEXITCODE -ne 0) { throw 'USB forwarding failed. Confirm USB debugging on the connected phone.' }
    # PARKSMART_V19_ANDROID_PAYMENT_RETURN: Stripe TEST uses a separate localhost port.
    & $adb -s $DeviceId reverse tcp:8788 tcp:8788
    if ($LASTEXITCODE -ne 0) { throw 'Stripe USB forwarding failed. Reconnect the phone.' }
}
$flutterArgs = @('--no-version-check','run','--no-pub','-d',$DeviceId)
$flutterArgs += '--dart-define-from-file=.local/mobile.defines.json'
if (-not $Camera) {
    # USB-only Stripe TEST. The local server also serves the browser's return-to-app page.
    $flutterArgs += @('--dart-define=LOCAL_STRIPE_API=http://127.0.0.1:8788', '--dart-define=PAYMENT_RETURN_URL=http://127.0.0.1:8788')
}
if ($Camera) { $flutterArgs += @('--release','--dart-define=ATTRACTION_CAMERA_STATION=true') }
& $runtime.flutter @flutterArgs
exit $LASTEXITCODE
