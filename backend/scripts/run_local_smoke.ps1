param(
    [string]$HostName = "127.0.0.1",
    [int]$Port = 8000,
    [string]$AppToken = $env:APP_TOKEN,
    [string]$Python = "python",
    [string]$ImagePath = "test_images/cheetah.jpg",
    [string]$OutputDir = "smoke_output"
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
$OutputEncoding = [System.Text.UTF8Encoding]::new()
$env:PYTHONUTF8 = "1"
$env:PYTHONIOENCODING = "utf-8"

if ([string]::IsNullOrWhiteSpace($AppToken)) {
    $AppToken = "dev-token-change-me"
}

$baseUrl = "http://${HostName}:${Port}"
$startedProcess = $null

function Test-Health {
    try {
        $response = Invoke-RestMethod -Uri "$baseUrl/api/health" -Method Get -TimeoutSec 2
        return $response.status -eq "ok"
    }
    catch {
        return $false
    }
}

try {
    if (-not (Test-Health)) {
        $env:APP_TOKEN = $AppToken
        if ([string]::IsNullOrWhiteSpace($env:DB_PATH)) {
            $env:DB_PATH = "./data/app.db"
        }
        if ([string]::IsNullOrWhiteSpace($env:FILE_BASE)) {
            $env:FILE_BASE = "./data/files"
        }
        if ([string]::IsNullOrWhiteSpace($env:RELAY_BASE_URL)) {
            $env:RELAY_BASE_URL = ""
        }
        if ([string]::IsNullOrWhiteSpace($env:RELAY_API_KEY)) {
            $env:RELAY_API_KEY = ""
        }

        $startedProcess = Start-Process `
            -FilePath $Python `
            -ArgumentList @("-m", "uvicorn", "app.main:app", "--host", $HostName, "--port", "$Port") `
            -WorkingDirectory (Get-Location) `
            -PassThru `
            -WindowStyle Hidden

        for ($attempt = 0; $attempt -lt 60; $attempt++) {
            if (Test-Health) {
                break
            }
            if ($startedProcess.HasExited) {
                throw "Local backend exited before health check passed."
            }
            Start-Sleep -Milliseconds 500
        }
    }

    if (-not (Test-Health)) {
        throw "Local backend did not become healthy at $baseUrl."
    }

    powershell -ExecutionPolicy Bypass -File scripts/smoke_test.ps1 `
        -BaseUrl $baseUrl `
        -AppToken $AppToken `
        -ImagePath $ImagePath `
        -OutputDir $OutputDir `
        -Python $Python
}
finally {
    if ($null -ne $startedProcess -and -not $startedProcess.HasExited) {
        Stop-Process -Id $startedProcess.Id -Force
    }
}
