param(
    [Parameter(Mandatory = $true)]
    [string]$BaseUrl,
    [string]$AppToken = $env:APP_TOKEN,
    [string]$Python = "",
    [switch]$SkipBackendVerify,
    [switch]$AllowPlaceholder,
    [switch]$AllowDebugSigning,
    [switch]$SkipApkSigner
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
$OutputEncoding = [System.Text.UTF8Encoding]::new()
$env:PYTHONUTF8 = "1"
$env:PYTHONIOENCODING = "utf-8"

function Invoke-CheckedPowerShell {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments,
        [string[]]$SecretValues = @()
    )

    powershell -NoProfile @Arguments
    if ($LASTEXITCODE -ne 0) {
        $displayArgs = $Arguments | ForEach-Object {
            if ($SecretValues -contains $_) {
                "<redacted>"
            }
            else {
                $_
            }
        }
        throw "Command failed with exit code ${LASTEXITCODE}: powershell $($displayArgs -join ' ')"
    }
}

if ([string]::IsNullOrWhiteSpace($AppToken)) {
    throw "AppToken is required. Set APP_TOKEN or pass -AppToken."
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
$BaseUrl = $BaseUrl.TrimEnd("/")

if (-not $SkipBackendVerify) {
    Write-Host "Verifying backend deployment"
    Push-Location $backendDir
    try {
        $verifyDeployArgs = @(
            "-ExecutionPolicy", "Bypass",
            "-File", "scripts/verify_deployment.ps1",
            "-BaseUrl", $BaseUrl,
            "-AppToken", $AppToken,
            "-Python", $Python
        )
        Invoke-CheckedPowerShell -Arguments $verifyDeployArgs -SecretValues @($AppToken)
    }
    finally {
        Pop-Location
    }
}
else {
    Write-Host "Skipping backend deployment verification"
}

Write-Host "Building Android release APK"
Push-Location $mobileDir
try {
    $buildArgs = @(
        "-ExecutionPolicy", "Bypass",
        "-File", "scripts/build_android_release.ps1",
        "-ApiBaseUrl", $BaseUrl,
        "-AppToken", $AppToken
    )
    if ($AllowPlaceholder) {
        $buildArgs += "-AllowPlaceholder"
    }
    Invoke-CheckedPowerShell -Arguments $buildArgs -SecretValues @($AppToken)

    Write-Host "Verifying Android release artifact"
    $verifyArgs = @(
        "-ExecutionPolicy", "Bypass",
        "-File", "scripts/verify_android_artifact.ps1"
    )
    if ($AllowPlaceholder) {
        $verifyArgs += "-AllowPlaceholder"
    }
    if ($AllowDebugSigning) {
        $verifyArgs += "-AllowDebugSigning"
    }
    if ($SkipApkSigner) {
        $verifyArgs += "-SkipApkSigner"
    }
    Invoke-CheckedPowerShell -Arguments $verifyArgs
}
finally {
    Pop-Location
}

Write-Host "Android release package is ready."
Write-Host "Next step: connect an Android phone and run:"
Write-Host "  cd mobile"
Write-Host "  powershell -ExecutionPolicy Bypass -File scripts/install_android_apk.ps1 -LaunchAfterInstall"
