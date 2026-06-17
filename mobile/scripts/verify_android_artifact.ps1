param(
    [string]$ApkPath = "dist/lao-zhao-0.1.0-release.apk",
    [switch]$AllowPlaceholder,
    [switch]$AllowDebugSigning,
    [switch]$SkipApkSigner,
    [string]$EvidencePath = ""
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
$OutputEncoding = [System.Text.UTF8Encoding]::new()

$blockedReleaseHosts = @(
    "your-backend.example.com",
    "localhost",
    "127.0.0.1",
    "10.0.2.2"
)

function Find-ApkSigner {
    $candidates = @()
    foreach ($root in @($env:ANDROID_HOME, $env:ANDROID_SDK_ROOT, "C:\Android\android-sdk")) {
        if (-not [string]::IsNullOrWhiteSpace($root)) {
            $buildTools = Join-Path $root "build-tools"
            if (Test-Path -LiteralPath $buildTools) {
                $candidates += Get-ChildItem -Path $buildTools -Recurse -Filter "apksigner.bat" -ErrorAction SilentlyContinue
            }
        }
    }
    $pathCommand = Get-Command apksigner.bat -ErrorAction SilentlyContinue
    if ($pathCommand) {
        $candidates += Get-Item -LiteralPath $pathCommand.Source
    }
    $selected = $candidates | Sort-Object FullName -Descending | Select-Object -First 1
    if ($selected) {
        return $selected.FullName
    }
    return $null
}

function Test-ApkSignature {
    param([string]$ResolvedApkPath)

    $apksigner = Find-ApkSigner
    if ([string]::IsNullOrWhiteSpace($apksigner)) {
        throw "apksigner was not found. Install Android SDK build-tools or pass -SkipApkSigner only for non-final checks."
    }

    $output = & $apksigner verify --verbose --print-certs $ResolvedApkPath 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "apksigner verify failed with exit code $LASTEXITCODE. $($output -join ' ')"
    }

    $text = $output -join "`n"
    $v1 = $text -match "Verified using v1 scheme .*:\s*true"
    $v2 = $text -match "Verified using v2 scheme .*:\s*true"
    $v3 = $text -match "Verified using v3 scheme .*:\s*true"
    $v31 = $text -match "Verified using v3\.1 scheme .*:\s*true"
    $v4 = $text -match "Verified using v4 scheme .*:\s*true"
    $dn = $null
    if ($text -match "Signer #1 certificate DN:\s*(.+)") {
        $dn = $matches[1].Trim()
    }
    $certSha256 = $null
    if ($text -match "Signer #1 certificate SHA-256 digest:\s*([0-9a-fA-F]+)") {
        $certSha256 = $matches[1].Trim().ToLowerInvariant()
    }
    $keyAlgorithm = $null
    if ($text -match "Signer #1 key algorithm:\s*(.+)") {
        $keyAlgorithm = $matches[1].Trim()
    }
    $keySize = $null
    if ($text -match "Signer #1 key size \(bits\):\s*(\d+)") {
        $keySize = [int]$matches[1]
    }

    if (-not ($v2 -or $v3 -or $v31)) {
        throw "APK signature must verify with APK Signature Scheme v2 or newer."
    }

    return [ordered]@{
        checked = $true
        apksigner = $apksigner
        v1 = [bool]$v1
        v2 = [bool]$v2
        v3 = [bool]$v3
        v31 = [bool]$v31
        v4 = [bool]$v4
        signer_dn = $dn
        signer_cert_sha256 = $certSha256
        key_algorithm = $keyAlgorithm
        key_size_bits = $keySize
    }
}

if (-not (Test-Path -LiteralPath $ApkPath)) {
    throw "APK was not found: $ApkPath. Build it first with scripts/build_android_release.ps1."
}

$resolvedApk = Resolve-Path -LiteralPath $ApkPath
$apk = Get-Item -LiteralPath $resolvedApk.Path
$shaPath = "$($apk.FullName).sha256"
$manifestPath = [System.IO.Path]::ChangeExtension($apk.FullName, ".json")

if (-not (Test-Path -LiteralPath $shaPath)) {
    throw "Missing SHA256 file: $shaPath"
}
if (-not (Test-Path -LiteralPath $manifestPath)) {
    throw "Missing release manifest: $manifestPath"
}

$expectedHash = (Get-Content -LiteralPath $shaPath -Encoding UTF8 | Select-Object -First 1).Split(" ")[0].Trim().ToLowerInvariant()
$actualHash = (Get-FileHash -LiteralPath $apk.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
if ($actualHash -ne $expectedHash) {
    throw "APK SHA256 mismatch. Expected $expectedHash, got $actualHash."
}

$manifest = Get-Content -LiteralPath $manifestPath -Encoding UTF8 | ConvertFrom-Json
if ($manifest.apk -ne $apk.Name) {
    throw "Manifest APK name does not match: $($manifest.apk) vs $($apk.Name)."
}
if ([int64]$manifest.apk_bytes -ne [int64]$apk.Length) {
    throw "Manifest APK size does not match: $($manifest.apk_bytes) vs $($apk.Length)."
}
if (($manifest.sha256).ToLowerInvariant() -ne $actualHash) {
    throw "Manifest SHA256 does not match APK hash."
}
if ($manifest.signing -ne "dedicated release keystore" -and -not $AllowDebugSigning) {
    throw "Release artifact should use the dedicated release keystore. Pass -AllowDebugSigning only for build-mechanics checks."
}

$backendUrl = [string]$manifest.backend_url
if ([string]::IsNullOrWhiteSpace($backendUrl)) {
    throw "Manifest backend_url is empty."
}
$backendUri = [System.Uri]$backendUrl
if (-not $AllowPlaceholder) {
    if ($backendUri.Scheme -ne "https") {
        throw "Install-ready APK must use an HTTPS backend URL."
    }
    if ($blockedReleaseHosts -contains $backendUri.Host.ToLowerInvariant()) {
        throw "Install-ready APK uses a placeholder/local backend URL: $backendUrl"
    }
    if ([bool]$manifest.placeholder_allowed) {
        throw "Install-ready APK was built with placeholder_allowed=true."
    }
}

$signature = [ordered]@{ checked = $false; skipped = [bool]$SkipApkSigner }
if (-not $SkipApkSigner) {
    $signature = Test-ApkSignature $apk.FullName
}

if ([string]::IsNullOrWhiteSpace($EvidencePath)) {
    $EvidencePath = [System.IO.Path]::ChangeExtension($apk.FullName, ".verify.json")
}
$evidence = [ordered]@{
    verified_at = (Get-Date).ToUniversalTime().ToString("o")
    apk = $apk.Name
    apk_path = $apk.FullName
    apk_bytes = $apk.Length
    sha256 = $actualHash
    backend_url = $backendUrl
    placeholder_allowed = [bool]$manifest.placeholder_allowed
    signing = [string]$manifest.signing
    signature = $signature
}
[System.IO.File]::WriteAllText(
    $EvidencePath,
    ($evidence | ConvertTo-Json -Depth 8),
    [System.Text.UTF8Encoding]::new($false)
)

Write-Host "Android release artifact verified"
Write-Host ("  APK: {0}" -f $apk.FullName)
Write-Host ("  bytes: {0}" -f $apk.Length)
Write-Host ("  sha256: {0}" -f $actualHash)
Write-Host ("  backend: {0}" -f $backendUrl)
if (-not $SkipApkSigner) {
    Write-Host ("  signer: {0}" -f $signature.signer_dn)
    Write-Host ("  signature schemes: v1={0}, v2={1}, v3={2}, v3.1={3}" -f $signature.v1, $signature.v2, $signature.v3, $signature.v31)
}
Write-Host ("  evidence: {0}" -f $EvidencePath)
