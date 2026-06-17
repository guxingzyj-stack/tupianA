param(
    [string]$Alias = "lao-zhao",
    [string]$KeystorePath = "android/keystore/lao-zhao-release.jks",
    [string]$KeyPropertiesPath = "android/key.properties",
    [string]$StorePassword = $env:LAO_ZHAO_STORE_PASSWORD,
    [string]$KeyPassword = $env:LAO_ZHAO_KEY_PASSWORD,
    [string]$DName = "CN=Lao Zhao, OU=Family, O=Family, L=Home, ST=Home, C=CN",
    [int]$ValidityDays = 10000,
    [ValidateSet("PKCS12", "JKS")]
    [string]$StoreType = "PKCS12"
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
$OutputEncoding = [System.Text.UTF8Encoding]::new()

function ConvertFrom-SecureStringAsPlainText {
    param([securestring]$SecureString)
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecureString)
    try {
        [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    }
    finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    }
}

if (-not (Get-Command keytool -ErrorAction SilentlyContinue)) {
    throw "keytool was not found. Install JDK or add keytool to PATH."
}

if ([string]::IsNullOrWhiteSpace($StorePassword)) {
    $secure = Read-Host "Keystore password" -AsSecureString
    $StorePassword = ConvertFrom-SecureStringAsPlainText $secure
}
if ([string]::IsNullOrWhiteSpace($KeyPassword)) {
    $secure = Read-Host "Key password" -AsSecureString
    $KeyPassword = ConvertFrom-SecureStringAsPlainText $secure
}
if ($StorePassword.Length -lt 6 -or $KeyPassword.Length -lt 6) {
    throw "Keystore and key passwords must be at least 6 characters."
}
if ($StoreType -eq "PKCS12" -and $KeyPassword -ne $StorePassword) {
    Write-Host "PKCS12 keystores use the store password for key entries; using the store password as keyPassword."
    $KeyPassword = $StorePassword
}

$projectRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$resolvedProjectRoot = $projectRoot.Path
$keystoreFullPath = Join-Path $resolvedProjectRoot $KeystorePath
$propertiesFullPath = Join-Path $resolvedProjectRoot $KeyPropertiesPath

foreach ($path in @($keystoreFullPath, $propertiesFullPath)) {
    $parent = Split-Path -Parent $path
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
    $resolvedParent = (Resolve-Path -LiteralPath $parent).Path
    if (-not $resolvedParent.StartsWith($resolvedProjectRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to write outside project: $path"
    }
}

if (Test-Path -LiteralPath $keystoreFullPath) {
    throw "Keystore already exists: $keystoreFullPath"
}
if (Test-Path -LiteralPath $propertiesFullPath) {
    throw "key.properties already exists: $propertiesFullPath"
}

& keytool `
    -genkeypair `
    -v `
    -keystore $keystoreFullPath `
    -storepass $StorePassword `
    -keypass $KeyPassword `
    -keyalg RSA `
    -keysize 2048 `
    -validity $ValidityDays `
    -alias $Alias `
    -storetype $StoreType `
    -dname $DName

if ($LASTEXITCODE -ne 0) {
    throw "keytool failed with exit code $LASTEXITCODE"
}

$storeFileForGradle = "../keystore/$([System.IO.Path]::GetFileName($keystoreFullPath))"
$properties = @"
storePassword=$StorePassword
keyPassword=$KeyPassword
keyAlias=$Alias
storeFile=$storeFileForGradle
"@

[System.IO.File]::WriteAllText(
    $propertiesFullPath,
    $properties,
    [System.Text.UTF8Encoding]::new($false)
)

Write-Host "Android release keystore created."
Write-Host ("  Keystore: {0}" -f $keystoreFullPath)
Write-Host ("  Properties: {0}" -f $propertiesFullPath)
Write-Host "Do not commit these files."
