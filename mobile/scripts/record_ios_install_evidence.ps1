param(
    [Parameter(Mandatory = $true)]
    [string]$DeviceModel,
    [Parameter(Mandatory = $true)]
    [string]$IosVersion,
    [Parameter(Mandatory = $true)]
    [string]$AppVersion,
    [string]$DeviceName = "",
    [string]$DeviceUdid = "",
    [string]$BundleId = "com.family.photorescue.laoZhao",
    [string]$BuildMethod = "Xcode physical device install",
    [string]$SigningTeam = "",
    [string]$ScreenshotPath = "",
    [string]$Notes = "",
    [string]$EvidencePath = "dist/ios_install_evidence.json"
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
$OutputEncoding = [System.Text.UTF8Encoding]::new()

if ([string]::IsNullOrWhiteSpace($DeviceModel)) {
    throw "DeviceModel is required."
}
if ([string]::IsNullOrWhiteSpace($IosVersion)) {
    throw "IosVersion is required."
}
if ([string]::IsNullOrWhiteSpace($AppVersion)) {
    throw "AppVersion is required."
}

$resolvedScreenshot = $null
if (-not [string]::IsNullOrWhiteSpace($ScreenshotPath)) {
    if (-not (Test-Path -LiteralPath $ScreenshotPath)) {
        throw "ScreenshotPath was not found: $ScreenshotPath"
    }
    $screenshotFile = Get-Item -LiteralPath $ScreenshotPath
    if ($screenshotFile.Length -le 0) {
        throw "ScreenshotPath is empty: $ScreenshotPath"
    }
    $resolvedScreenshot = (Resolve-Path -LiteralPath $ScreenshotPath).Path
}

$evidence = [ordered]@{
    installed_at = (Get-Date).ToUniversalTime().ToString("o")
    platform = "ios"
    device_model = $DeviceModel.Trim()
    device_name = $DeviceName.Trim()
    device_udid = $DeviceUdid.Trim()
    ios_version = $IosVersion.Trim()
    bundle_id = $BundleId.Trim()
    app_version = $AppVersion.Trim()
    build_method = $BuildMethod.Trim()
    signing_team = $SigningTeam.Trim()
    screenshot_path = $resolvedScreenshot
    notes = $Notes.Trim()
}

$evidenceDir = Split-Path -Parent $EvidencePath
if (-not [string]::IsNullOrWhiteSpace($evidenceDir)) {
    New-Item -ItemType Directory -Force -Path $evidenceDir | Out-Null
}
[System.IO.File]::WriteAllText(
    $EvidencePath,
    ($evidence | ConvertTo-Json -Depth 6),
    [System.Text.UTF8Encoding]::new($false)
)

Write-Host "iOS install evidence written:"
Write-Host ("  {0}" -f $EvidencePath)
