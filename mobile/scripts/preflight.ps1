param(
    [string]$ApiBaseUrl = "http://127.0.0.1:8000",
    [string]$AppToken = $env:APP_TOKEN,
    [string]$DeviceId = "mobile-preflight",
    [string]$Python = "python",
    [switch]$SkipBackendCheck
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
$OutputEncoding = [System.Text.UTF8Encoding]::new()
$env:PYTHONUTF8 = "1"
$env:PYTHONIOENCODING = "utf-8"

if ([string]::IsNullOrWhiteSpace($AppToken)) {
    $AppToken = "dev-token-change-me"
}

$ApiBaseUrl = $ApiBaseUrl.TrimEnd("/")

if (-not $SkipBackendCheck) {
    Write-Host "Checking backend health: $ApiBaseUrl"
    $health = Invoke-RestMethod -Uri "$ApiBaseUrl/api/health" -Method Get -TimeoutSec 5
    if ($health.status -ne "ok") {
        throw "Backend health check did not return ok."
    }

    Write-Host "Checking app token with device config API"
    $headers = @{ "X-App-Token" = $AppToken }
    $config = Invoke-RestMethod `
        -Uri "$ApiBaseUrl/api/devices/$DeviceId/config" `
        -Method Get `
        -Headers $headers `
        -TimeoutSec 10
    if ($config.device_id -ne $DeviceId) {
        throw "Device config check returned an unexpected device_id."
    }
}
else {
    Write-Host "Skipping backend check"
}

Write-Host "Checking elderly UX red lines"
& $Python scripts/check_elderly_red_lines.py
if ($LASTEXITCODE -ne 0) {
    throw "Elderly UX red-line check failed."
}

Write-Host "Resolving Flutter dependencies"
flutter pub get

Write-Host "Running Dart analysis"
dart analyze

Write-Host "Running Flutter tests"
flutter test

Write-Host "Mobile preflight passed"
Write-Host "Run app with:"
Write-Host "flutter run --dart-define=API_BASE_URL=$ApiBaseUrl --dart-define=APP_TOKEN=$AppToken"
