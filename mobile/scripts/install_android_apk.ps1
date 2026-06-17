param(
    [string]$ApkPath = "dist/lao-zhao-0.1.0-release.apk",
    [string]$Serial = "",
    [switch]$SkipHashCheck,
    [switch]$SkipVerifyEvidence,
    [switch]$LaunchAfterInstall,
    [string]$ScreenshotPath = "",
    [string]$EvidencePath = "dist/install_evidence.json"
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
$OutputEncoding = [System.Text.UTF8Encoding]::new()

if (-not (Get-Command adb -ErrorAction SilentlyContinue)) {
    throw "adb was not found. Install Android platform-tools or add adb to PATH."
}

$resolvedApk = Resolve-Path -LiteralPath $ApkPath
$apkFile = Get-Item -LiteralPath $resolvedApk.Path
$manifestPath = [System.IO.Path]::ChangeExtension($apkFile.FullName, ".json")
$manifest = $null
if (Test-Path -LiteralPath $manifestPath) {
    $manifest = Get-Content -LiteralPath $manifestPath -Encoding UTF8 | ConvertFrom-Json
    Write-Host ("APK backend URL: {0}" -f $manifest.backend_url)
}
$verifyPath = [System.IO.Path]::ChangeExtension($apkFile.FullName, ".verify.json")
$verifyEvidence = $null

if (-not $SkipHashCheck) {
    $shaPath = "$($apkFile.FullName).sha256"
    if (-not (Test-Path -LiteralPath $shaPath)) {
        throw "SHA256 file was not found: $shaPath"
    }
    $expected = (Get-Content -LiteralPath $shaPath -Encoding UTF8 | Select-Object -First 1).Split(" ")[0].Trim()
    $actual = (Get-FileHash -LiteralPath $apkFile.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actual -ne $expected.ToLowerInvariant()) {
        throw "APK SHA256 mismatch. Expected $expected, got $actual."
    }
}
$actualSha256 = (Get-FileHash -LiteralPath $apkFile.FullName -Algorithm SHA256).Hash.ToLowerInvariant()

if (-not $SkipVerifyEvidence) {
    if (-not (Test-Path -LiteralPath $verifyPath)) {
        throw "APK verification evidence was not found: $verifyPath. Run scripts/verify_android_artifact.ps1 before installing."
    }
    $verifyEvidence = Get-Content -LiteralPath $verifyPath -Encoding UTF8 | ConvertFrom-Json
    if (($verifyEvidence.sha256).ToLowerInvariant() -ne $actualSha256) {
        throw "APK verification evidence SHA256 does not match APK. Expected $($verifyEvidence.sha256), got $actualSha256."
    }
    if ($verifyEvidence.signature.checked -ne $true) {
        throw "APK verification evidence does not include an apksigner check."
    }
    if (-not ($verifyEvidence.signature.v2 -or $verifyEvidence.signature.v3 -or $verifyEvidence.signature.v31)) {
        throw "APK verification evidence does not show a v2 or newer APK signature."
    }
}

$devices = & adb devices
$readyDevices = @()
foreach ($line in $devices) {
    if ($line -match "^(\S+)\s+device$") {
        $readyDevices += $matches[1]
    }
}

if ($readyDevices.Count -eq 0) {
    throw "No Android device is ready. Connect a phone, enable USB debugging, then approve the computer on the phone."
}

if ([string]::IsNullOrWhiteSpace($Serial)) {
    if ($readyDevices.Count -gt 1) {
        throw "Multiple Android devices are connected. Pass -Serial with one of: $($readyDevices -join ', ')"
    }
    $Serial = $readyDevices[0]
}

if ($readyDevices -notcontains $Serial) {
    throw "Device $Serial is not ready. Ready devices: $($readyDevices -join ', ')"
}

Write-Host "Installing APK to $Serial"
& adb -s $Serial install -r $apkFile.FullName
if ($LASTEXITCODE -ne 0) {
    throw "adb install failed with exit code $LASTEXITCODE"
}

$packageName = "com.family.photorescue.lao_zhao"
if ($null -ne $manifest -and -not [string]::IsNullOrWhiteSpace([string]$manifest.package)) {
    $packageName = [string]$manifest.package
}

function Get-AdbValue {
    param([string[]]$Arguments)
    $value = & adb -s $Serial @Arguments
    if ($LASTEXITCODE -ne 0) {
        return ""
    }
    return (($value -join "`n").Trim())
}

$packageDump = Get-AdbValue @("shell", "dumpsys", "package", $packageName)
$installedVersionName = $null
if ($packageDump -match "versionName=([^\s]+)") {
    $installedVersionName = $matches[1]
}

$deviceInfo = [ordered]@{
    serial = $Serial
    manufacturer = Get-AdbValue @("shell", "getprop", "ro.product.manufacturer")
    model = Get-AdbValue @("shell", "getprop", "ro.product.model")
    android_release = Get-AdbValue @("shell", "getprop", "ro.build.version.release")
    android_sdk = Get-AdbValue @("shell", "getprop", "ro.build.version.sdk")
}

$launchChecked = $false
$resolvedScreenshot = $null
if ($LaunchAfterInstall) {
    Write-Host "Launching $packageName on $Serial"
    & adb -s $Serial shell monkey -p $packageName -c android.intent.category.LAUNCHER 1 | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "adb launch failed with exit code $LASTEXITCODE"
    }
    Start-Sleep -Seconds 3
    $launchChecked = $true

    if ([string]::IsNullOrWhiteSpace($ScreenshotPath)) {
        $ScreenshotPath = "dist/android_launch.png"
    }
    $screenshotDir = Split-Path -Parent $ScreenshotPath
    if (-not [string]::IsNullOrWhiteSpace($screenshotDir)) {
        New-Item -ItemType Directory -Force -Path $screenshotDir | Out-Null
    }
    & adb -s $Serial exec-out screencap -p > $ScreenshotPath
    if ($LASTEXITCODE -ne 0) {
        throw "adb screencap failed with exit code $LASTEXITCODE"
    }
    if (-not (Test-Path -LiteralPath $ScreenshotPath)) {
        throw "Screenshot was not written: $ScreenshotPath"
    }
    $screenshotFile = Get-Item -LiteralPath $ScreenshotPath
    if ($screenshotFile.Length -le 0) {
        throw "Screenshot is empty: $ScreenshotPath"
    }
    $resolvedScreenshot = (Resolve-Path -LiteralPath $ScreenshotPath).Path
}

$evidence = [ordered]@{
    installed_at = (Get-Date).ToUniversalTime().ToString("o")
    device_serial = $Serial
    device = $deviceInfo
    package = $packageName
    installed_version_name = $installedVersionName
    apk = $apkFile.Name
    apk_bytes = $apkFile.Length
    sha256 = if ($SkipHashCheck) { $null } else { $actualSha256 }
    manifest = $manifest
    verification = $verifyEvidence
    launch_checked = $launchChecked
    screenshot_path = $resolvedScreenshot
}
$evidenceDir = Split-Path -Parent $EvidencePath
if (-not [string]::IsNullOrWhiteSpace($evidenceDir)) {
    New-Item -ItemType Directory -Force -Path $evidenceDir | Out-Null
}
[System.IO.File]::WriteAllText(
    $EvidencePath,
    ($evidence | ConvertTo-Json -Depth 8),
    [System.Text.UTF8Encoding]::new($false)
)

Write-Host "APK installed successfully"
Write-Host ("Install evidence: {0}" -f $EvidencePath)
if ($launchChecked) {
    Write-Host ("Launch screenshot: {0}" -f $resolvedScreenshot)
}
