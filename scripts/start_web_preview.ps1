param(
    [int]$WebPort = 8082,
    [int]$BackendPort = 8003,
    [string]$AppToken = $env:APP_TOKEN,
    [string]$Python = "",
    [switch]$SkipBuild
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
$OutputEncoding = [System.Text.UTF8Encoding]::new()
$env:PYTHONUTF8 = "1"
$env:PYTHONIOENCODING = "utf-8"

if ([string]::IsNullOrWhiteSpace($AppToken)) {
    $AppToken = "dev-token-change-me"
}
if ([string]::IsNullOrWhiteSpace($Python)) {
    $bundledPython = Join-Path $env:USERPROFILE ".cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe"
    if (Test-Path -LiteralPath $bundledPython) {
        $Python = $bundledPython
    }
    else {
        $Python = "python"
    }
}

$root = Split-Path -Parent $PSScriptRoot
$backendDir = Join-Path $root "backend"
$mobileDir = Join-Path $root "mobile"
$dataDir = Join-Path $root "data"
$fileDir = Join-Path $dataDir "files"
$webDir = Join-Path $mobileDir "build\web"
$backendUrl = "http://127.0.0.1:${BackendPort}"
$webUrl = "http://127.0.0.1:${WebPort}"

function Test-HttpOk {
    param([string]$Url)
    try {
        $response = Invoke-WebRequest -UseBasicParsing -Uri $Url -TimeoutSec 2
        return $response.StatusCode -ge 200 -and $response.StatusCode -lt 500
    }
    catch {
        return $false
    }
}

function Test-BackendAuth {
    try {
        $headers = @{ "X-App-Token" = $AppToken }
        $config = Invoke-RestMethod `
            -Uri "$backendUrl/api/devices/web-preview/config" `
            -Method Get `
            -Headers $headers `
            -TimeoutSec 5
        return $config.device_id -eq "web-preview"
    }
    catch {
        return $false
    }
}

function Test-BackendCors {
    try {
        $headers = @{
            "Origin" = $webUrl
            "Access-Control-Request-Method" = "GET"
            "Access-Control-Request-Headers" = "x-app-token"
        }
        $response = Invoke-WebRequest `
            -UseBasicParsing `
            -Uri "$backendUrl/api/templates" `
            -Method Options `
            -Headers $headers `
            -TimeoutSec 5
        $allowedOrigin = $response.Headers["Access-Control-Allow-Origin"]
        return $allowedOrigin -eq $webUrl -or $allowedOrigin -eq "*"
    }
    catch {
        return $false
    }
}

New-Item -ItemType Directory -Force -Path $dataDir | Out-Null
New-Item -ItemType Directory -Force -Path $fileDir | Out-Null

if (Test-HttpOk "$backendUrl/api/health") {
    if (-not (Test-BackendAuth)) {
        throw "Backend at $backendUrl is running but rejected the app token. Use another -BackendPort or stop that process."
    }
    if (-not (Test-BackendCors)) {
        throw "Backend at $backendUrl is running but does not allow CORS from $webUrl. Use another -BackendPort or restart it with CORS_ALLOW_ORIGINS including $webUrl."
    }
    Write-Host "Using existing backend at $backendUrl"
}
else {
    Write-Host "Starting backend at $backendUrl"
    $env:APP_TOKEN = $AppToken
    $env:DB_PATH = Join-Path $dataDir "web-preview.db"
    $env:FILE_BASE = $fileDir
    $env:CORS_ALLOW_ORIGINS = "$webUrl,http://localhost:${WebPort}"
    if ([string]::IsNullOrWhiteSpace($env:RELAY_BASE_URL)) {
        $env:RELAY_BASE_URL = ""
    }
    if ([string]::IsNullOrWhiteSpace($env:RELAY_API_KEY)) {
        $env:RELAY_API_KEY = ""
    }
    Start-Process `
        -FilePath $Python `
        -ArgumentList @("-m", "uvicorn", "app.main:app", "--host", "127.0.0.1", "--port", "$BackendPort") `
        -WorkingDirectory $backendDir `
        -WindowStyle Hidden | Out-Null

    for ($attempt = 0; $attempt -lt 60; $attempt++) {
        if (Test-HttpOk "$backendUrl/api/health") {
            break
        }
        Start-Sleep -Milliseconds 500
    }
    if (-not (Test-HttpOk "$backendUrl/api/health")) {
        throw "Backend did not become healthy at $backendUrl."
    }
    if (-not (Test-BackendAuth)) {
        throw "Backend started at $backendUrl but rejected the app token."
    }
    if (-not (Test-BackendCors)) {
        throw "Backend started at $backendUrl but CORS did not allow $webUrl."
    }
}

if (-not $SkipBuild) {
    Write-Host "Building Flutter Web preview"
    Push-Location $mobileDir
    try {
        flutter build web `
            --dart-define=API_BASE_URL=$backendUrl `
            --dart-define=APP_TOKEN=$AppToken
        if ($LASTEXITCODE -ne 0) {
            throw "flutter build web failed with exit code $LASTEXITCODE."
        }
    }
    finally {
        Pop-Location
    }
}
elseif (-not (Test-Path -LiteralPath (Join-Path $webDir "index.html"))) {
    throw "Web build output not found. Run without -SkipBuild first."
}

if (Test-HttpOk $webUrl) {
    Write-Host "Using existing Web preview at $webUrl"
}
else {
    Write-Host "Starting Web preview at $webUrl"
    Start-Process `
        -FilePath $Python `
        -ArgumentList @("-m", "http.server", "$WebPort", "--bind", "127.0.0.1") `
        -WorkingDirectory $webDir `
        -WindowStyle Hidden | Out-Null

    for ($attempt = 0; $attempt -lt 30; $attempt++) {
        if (Test-HttpOk $webUrl) {
            break
        }
        Start-Sleep -Milliseconds 500
    }
    if (-not (Test-HttpOk $webUrl)) {
        throw "Web preview did not become available at $webUrl."
    }
}

Write-Host "Web preview ready: $webUrl"
Write-Host "Backend ready: $backendUrl"
