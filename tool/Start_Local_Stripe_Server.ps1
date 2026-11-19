param([Parameter(Mandatory=$true)][string]$ProjectPath)
$ErrorActionPreference = 'Stop'
$project = (Resolve-Path -LiteralPath $ProjectPath).Path
$entry = Join-Path $project 'functions\local_stripe_server.cjs'
if (-not (Test-Path -LiteralPath $entry)) {throw 'Run Apply_Local_Stripe_Spark.ps1 first.'}
$path = Read-Host 'Full path of Firebase service-account JSON (keep it PRIVATE)'
$path = $path.Trim().Trim('"')
if (-not (Test-Path -LiteralPath $path)) {throw 'Service account file not found.'}
$env:GOOGLE_APPLICATION_CREDENTIALS = (Resolve-Path -LiteralPath $path).Path
$env:FIREBASE_PROJECT_ID = 'themeparksmartmanagement'
$secureStripe = Read-Host 'Paste Stripe SANDBOX sk_test key (hidden)' -AsSecureString
$secureWebhook = Read-Host 'Paste whsec shown by stripe listen (hidden)' -AsSecureString
$env:STRIPE_SECRET_KEY = ([System.Net.NetworkCredential]::new('', $secureStripe)).Password
$env:STRIPE_WEBHOOK_SECRET = ([System.Net.NetworkCredential]::new('', $secureWebhook)).Password
if (-not $env:STRIPE_SECRET_KEY.StartsWith('sk_test_')) {throw 'This is not a sandbox sk_test key.'}
if (-not $env:STRIPE_WEBHOOK_SECRET.StartsWith('whsec_')) {throw 'Invalid webhook secret format.'}
Push-Location (Join-Path $project 'functions')
try {
  if (-not (Test-Path -LiteralPath 'node_modules\firebase-admin')) {
    Write-Host 'Installing backend dependencies...'
    npm ci --omit=dev
    if ($LASTEXITCODE -ne 0) {throw 'npm ci failed.'}
  }
  $env:LOCAL_STRIPE_PORT = '8788'
  node .\local_stripe_server.cjs
} finally {
  Pop-Location
  Remove-Item Env:STRIPE_SECRET_KEY -ErrorAction SilentlyContinue
  Remove-Item Env:STRIPE_WEBHOOK_SECRET -ErrorAction SilentlyContinue
}
