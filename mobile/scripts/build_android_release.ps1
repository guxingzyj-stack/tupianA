param(
    [string]$ApiBaseUrl,
    [string]$AppToken = $env:APP_TOKEN,
    [string]$OutputDir = "dist",
    [string]$StagingDir = (Join-Path $env:TEMP "lao_zhao_android_release_build"),
    [switch]$KeepStaging,
    [switch]$AllowPlaceholder
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
$OutputEncoding = [System.Text.UTF8Encoding]::new()

if ([string]::IsNullOrWhiteSpace($ApiBaseUrl)) {
    throw "ApiBaseUrl is required. Example: -ApiBaseUrl https://your-backend.example.com"
}
if ([string]::IsNullOrWhiteSpace($AppToken)) {
    throw "AppToken is required. Set APP_TOKEN or pass -AppToken."
}

$blockedReleaseHosts = @(
    "your-backend.example.com",
    "localhost",
    "127.0.0.1",
    "10.0.2.2"
)
$apiUri = [System.Uri]$ApiBaseUrl
if (-not $AllowPlaceholder) {
    if ($apiUri.Scheme -ne "https") {
        throw "Release APK should use an HTTPS backend URL. Pass -AllowPlaceholder only for build-mechanics checks."
    }
    if ($blockedReleaseHosts -contains $apiUri.Host.ToLowerInvariant()) {
        throw "Release APK backend URL is not install-ready: $ApiBaseUrl. Pass the deployed Zeabur HTTPS URL, or use -AllowPlaceholder only for build-mechanics checks."
    }
}

$sourceRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$resolvedSource = $sourceRoot.Path
$resolvedStagingParent = (Resolve-Path (Split-Path -Parent $StagingDir)).Path
$usesDedicatedReleaseSigning = Test-Path -LiteralPath (Join-Path $resolvedSource "android\key.properties")
if (-not $AllowPlaceholder -and -not $usesDedicatedReleaseSigning) {
    throw "Install-ready release builds require a dedicated release keystore. Run scripts/create_android_keystore.ps1 first."
}

if (-not $StagingDir.StartsWith($resolvedStagingParent, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Invalid staging directory: $StagingDir"
}

if (Test-Path -LiteralPath $StagingDir) {
    $resolvedStaging = (Resolve-Path -LiteralPath $StagingDir).Path
    if (-not $resolvedStaging.StartsWith($resolvedStagingParent, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to remove unexpected staging directory: $resolvedStaging"
    }
    Remove-Item -LiteralPath $resolvedStaging -Recurse -Force
}

New-Item -ItemType Directory -Force -Path $StagingDir | Out-Null

$robocopyArgs = @(
    $resolvedSource,
    $StagingDir,
    "/MIR",
    "/XD", ".dart_tool", "build", "dist",
    "/XF", ".flutter-plugins-dependencies",
    "/NFL", "/NDL", "/NJH", "/NJS", "/NP"
)
& robocopy @robocopyArgs | Out-Null
if ($LASTEXITCODE -gt 7) {
    throw "Failed to copy project to staging directory. Robocopy exit code: $LASTEXITCODE"
}

Push-Location $StagingDir
try {
    flutter pub get
    flutter build apk --release `
        --dart-define=API_BASE_URL=$ApiBaseUrl `
        --dart-define=APP_TOKEN=$AppToken
}
finally {
    Pop-Location
}

$sourceApk = Join-Path $StagingDir "build\app\outputs\flutter-apk\app-release.apk"
if (-not (Test-Path -LiteralPath $sourceApk)) {
    throw "Release APK was not produced: $sourceApk"
}

$targetDir = Join-Path $resolvedSource $OutputDir
New-Item -ItemType Directory -Force -Path $targetDir | Out-Null
$targetApk = Join-Path $targetDir "lao-zhao-0.1.0-release.apk"
Copy-Item -LiteralPath $sourceApk -Destination $targetApk -Force

$apk = Get-Item -LiteralPath $targetApk
$hash = (Get-FileHash -LiteralPath $apk.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
$shaPath = "$targetApk.sha256"
[System.IO.File]::WriteAllText(
    $shaPath,
    "$hash  $($apk.Name)`n",
    [System.Text.UTF8Encoding]::new($false)
)

$pubspec = Get-Content -LiteralPath (Join-Path $resolvedSource "pubspec.yaml") -Encoding UTF8
$versionLine = $pubspec | Where-Object { $_ -match "^version:\s*(.+)$" } | Select-Object -First 1
$appVersion = if ($versionLine -match "^version:\s*(.+)$") { $matches[1].Trim() } else { "unknown" }
$manifestPath = Join-Path $targetDir "lao-zhao-0.1.0-release.json"
$manifest = [ordered]@{
    app = "Lao Zhao"
    package = "com.family.photorescue.lao_zhao"
    version = $appVersion
    build_mode = "release"
    backend_url = $ApiBaseUrl
    app_token_configured = $true
    placeholder_allowed = [bool]$AllowPlaceholder
    signing = if ($usesDedicatedReleaseSigning) { "dedicated release keystore" } else { "debug signing config for self-use sideloading" }
    apk = $apk.Name
    apk_bytes = $apk.Length
    sha256 = $hash
    built_at = (Get-Date).ToUniversalTime().ToString("o")
}
[System.IO.File]::WriteAllText(
    $manifestPath,
    ($manifest | ConvertTo-Json -Depth 4),
    [System.Text.UTF8Encoding]::new($false)
)

if (-not $KeepStaging) {
    Remove-Item -LiteralPath $StagingDir -Recurse -Force
}

Write-Host "Release APK built:"
Write-Host ("  {0}" -f $apk.FullName)
Write-Host ("  {0} bytes" -f $apk.Length)
Write-Host ("  sha256: {0}" -f $hash)
Write-Host ("  manifest: {0}" -f $manifestPath)
if ($usesDedicatedReleaseSigning) {
    Write-Host "Note: Android release build used the dedicated release keystore."
}
else {
    Write-Host "Note: current Android release build uses the debug signing config for self-use sideloading."
}
