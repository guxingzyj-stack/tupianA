param(
    [string]$ApiBaseUrl = "http://127.0.0.1:8000",
    [string]$AppToken = $env:APP_TOKEN,
    [string]$Python = "",
    [switch]$UseExistingBackend,
    [switch]$StrictBackendEnv,
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
if ([string]::IsNullOrWhiteSpace($Python)) {
    $bundledPython = Join-Path $env:USERPROFILE ".cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe"
    if (Test-Path -LiteralPath $bundledPython) {
        $Python = $bundledPython
    }
    else {
        $Python = "python"
    }
}
Write-Host "Using Python: $Python"

$root = Split-Path -Parent $PSScriptRoot
$backendDir = Join-Path $root "backend"
$mobileDir = Join-Path $root "mobile"
$ApiBaseUrl = $ApiBaseUrl.TrimEnd("/")
$backendProcess = $null

function Invoke-CheckedPowerShell {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments
    )

    powershell -NoProfile @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "PowerShell command failed with exit code ${LASTEXITCODE}: powershell $($Arguments -join ' ')"
    }
}

function Invoke-CheckedPython {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments
    )

    & $Python @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Python command failed with exit code ${LASTEXITCODE}: $Python $($Arguments -join ' ')"
    }
}

function Test-BackendHealth {
    try {
        $health = Invoke-RestMethod -Uri "$ApiBaseUrl/api/health" -Method Get -TimeoutSec 2
        return $health.status -eq "ok"
    }
    catch {
        return $false
    }
}

function Test-BackendAuth {
    try {
        $headers = @{ "X-App-Token" = $AppToken }
        $config = Invoke-RestMethod `
            -Uri "$ApiBaseUrl/api/devices/project-preflight/config" `
            -Method Get `
            -Headers $headers `
            -TimeoutSec 5
        return $config.device_id -eq "project-preflight"
    }
    catch {
        return $false
    }
}

function Test-PortAvailable {
    param(
        [string]$HostName,
        [int]$Port
    )

    $listener = $null
    try {
        $address = [System.Net.IPAddress]::Parse($HostName)
        $listener = [System.Net.Sockets.TcpListener]::new($address, $Port)
        $listener.Start()
        return $true
    }
    catch {
        return $false
    }
    finally {
        if ($null -ne $listener) {
            $listener.Stop()
        }
    }
}

function Switch-To-FreeLocalBackendUrl {
    $uri = [System.Uri]$ApiBaseUrl
    if ($uri.Host -notin @("127.0.0.1", "localhost")) {
        throw "Backend at $ApiBaseUrl is healthy but rejected the app token. Pass the correct -AppToken or use a local URL."
    }

    $hostName = if ($uri.Host -eq "localhost") { "127.0.0.1" } else { $uri.Host }
    for ($port = 8001; $port -le 8020; $port++) {
        if (Test-PortAvailable -HostName $hostName -Port $port) {
            $script:ApiBaseUrl = "http://${hostName}:${port}"
            Write-Host "Existing backend token did not match; using temporary backend at $script:ApiBaseUrl"
            return
        }
    }
    throw "No free local port found for temporary backend."
}

function Start-LocalBackend {
    $uri = [System.Uri]$ApiBaseUrl
    $hostName = $uri.Host
    $port = $uri.Port

    $env:APP_TOKEN = $AppToken
    $env:DB_PATH = "./data/app.db"
    $env:FILE_BASE = "./data/files"
    if ([string]::IsNullOrWhiteSpace($env:RELAY_BASE_URL)) {
        $env:RELAY_BASE_URL = ""
    }
    if ([string]::IsNullOrWhiteSpace($env:RELAY_API_KEY)) {
        $env:RELAY_API_KEY = ""
    }

    return Start-Process `
        -FilePath $Python `
        -ArgumentList @("-m", "uvicorn", "app.main:app", "--host", $hostName, "--port", "$port") `
        -WorkingDirectory $backendDir `
        -PassThru `
        -WindowStyle Hidden
}

try {
    if (-not $SkipBackendCheck) {
        Write-Host "Checking backend environment"
        Push-Location $backendDir
        try {
            if ($StrictBackendEnv) {
                Invoke-CheckedPython -Arguments @("scripts/check_env.py")
            }
            else {
                Invoke-CheckedPython -Arguments @("scripts/check_env.py", "--allow-local-dev")
            }
        }
        finally {
            Pop-Location
        }

        Write-Host "Checking Docker context"
        Push-Location $backendDir
        try {
            Invoke-CheckedPython -Arguments @("scripts/check_docker_context.py")
        }
        finally {
            Pop-Location
        }

        Write-Host "Running backend tests"
        Push-Location $backendDir
        try {
            Invoke-CheckedPowerShell -Arguments @(
                "-ExecutionPolicy", "Bypass",
                "-File", "scripts/run_tests.ps1",
                "-Python", $Python
            )
        }
        finally {
            Pop-Location
        }

        if (-not $UseExistingBackend) {
            if (Test-BackendHealth) {
                if (Test-BackendAuth) {
                    Write-Host "Using already healthy backend at $ApiBaseUrl"
                }
                else {
                    Switch-To-FreeLocalBackendUrl
                    Write-Host "Starting local backend at $ApiBaseUrl"
                    $backendProcess = Start-LocalBackend
                    for ($attempt = 0; $attempt -lt 60; $attempt++) {
                        if (Test-BackendHealth) {
                            break
                        }
                        if ($backendProcess.HasExited) {
                            throw "Local backend exited before health check passed."
                        }
                        Start-Sleep -Milliseconds 500
                    }
                }
            }
            else {
                Write-Host "Starting local backend at $ApiBaseUrl"
                $backendProcess = Start-LocalBackend
                for ($attempt = 0; $attempt -lt 60; $attempt++) {
                    if (Test-BackendHealth) {
                        break
                    }
                    if ($backendProcess.HasExited) {
                        throw "Local backend exited before health check passed."
                    }
                    Start-Sleep -Milliseconds 500
                }
            }
        }

        if (-not (Test-BackendHealth)) {
            throw "Backend is not healthy at $ApiBaseUrl."
        }
        if (-not (Test-BackendAuth)) {
            throw "Backend is healthy at $ApiBaseUrl but rejected the configured app token."
        }

        Write-Host "Running backend smoke"
        Push-Location $backendDir
        try {
            Invoke-CheckedPowerShell -Arguments @(
                "-ExecutionPolicy", "Bypass",
                "-File", "scripts/smoke_test.ps1",
                "-BaseUrl", $ApiBaseUrl,
                "-AppToken", $AppToken,
                "-Python", $Python
            )
        }
        finally {
            Pop-Location
        }
    }
    else {
        Write-Host "Skipping backend checks"
    }

    Write-Host "Running mobile preflight"
    Push-Location $mobileDir
    try {
        $mobileArguments = @(
            "-ExecutionPolicy", "Bypass",
            "-File", "scripts/preflight.ps1",
            "-ApiBaseUrl", $ApiBaseUrl,
            "-AppToken", $AppToken,
            "-Python", $Python
        )
        if ($SkipBackendCheck) {
            $mobileArguments += "-SkipBackendCheck"
        }
        Invoke-CheckedPowerShell -Arguments $mobileArguments
    }
    finally {
        Pop-Location
    }

    Write-Host "Project preflight passed"
}
finally {
    if ($null -ne $backendProcess -and -not $backendProcess.HasExited) {
        Stop-Process -Id $backendProcess.Id -Force
    }
}
