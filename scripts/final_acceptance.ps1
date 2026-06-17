param(
    [string]$Python = "",
    [switch]$RunPreflight,
    [switch]$AllowPending,
    [switch]$AllowLocalUrls
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
$OutputEncoding = [System.Text.UTF8Encoding]::new()
$env:PYTHONUTF8 = "1"
$env:PYTHONIOENCODING = "utf-8"

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

function Invoke-CheckedPowerShell {
    param([Parameter(Mandatory = $true)][string[]]$Arguments)

    powershell -NoProfile @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "PowerShell command failed with exit code ${LASTEXITCODE}: powershell $($Arguments -join ' ')"
    }
}

function Invoke-CheckedPython {
    param([Parameter(Mandatory = $true)][string[]]$Arguments)

    & $Python @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Python command failed with exit code ${LASTEXITCODE}: $Python $($Arguments -join ' ')"
    }
}

Push-Location $root
try {
    Write-Host "Using Python: $Python"

    if ($RunPreflight) {
        Write-Host "Running full project preflight"
        Invoke-CheckedPowerShell -Arguments @(
            "-ExecutionPolicy", "Bypass",
            "-File", "scripts/preflight.ps1",
            "-Python", $Python
        )
    }

    Write-Host "Running final MVP evidence check"
    $checkArgs = @("scripts/check_mvp_evidence.py")
    if ($AllowPending) {
        $checkArgs += "--allow-pending"
    }
    if ($AllowLocalUrls) {
        $checkArgs += "--allow-local-urls"
    }

    Invoke-CheckedPython -Arguments $checkArgs

    if ($AllowPending) {
        Write-Host "Final acceptance dry run completed. Pending evidence is still allowed in this mode."
    }
    else {
        Write-Host "Final acceptance passed: 0 failed, 0 pending."
    }
}
finally {
    Pop-Location
}
