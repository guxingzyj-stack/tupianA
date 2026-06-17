param(
    [Parameter(Mandatory = $true)]
    [string]$BaseUrl,
    [string]$AppToken = $env:APP_TOKEN,
    [string]$Python = "",
    [string]$CheckPersistenceFrom = "",
    [string]$EvidencePath = "deployment_evidence.json"
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
$OutputEncoding = [System.Text.UTF8Encoding]::new()
$env:PYTHONUTF8 = "1"
$env:PYTHONIOENCODING = "utf-8"

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

$BaseUrl = $BaseUrl.TrimEnd("/")
$startedAt = Get-Date
$headers = @{ "X-App-Token" = $AppToken }
$volumePersistence = [ordered]@{
    checked = $false
    db_marker_checked = $false
    file_marker_checked = $false
    source_evidence = $null
    notes = "Run again after a Zeabur restart with -CheckPersistenceFrom <previous deployment_evidence.json>."
}

function Get-JsonFile {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) {
        return $null
    }
    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Persistence evidence was not found: $Path"
    }
    return Get-Content -LiteralPath $Path -Encoding UTF8 | ConvertFrom-Json
}

function Test-HttpOk {
    param([string]$Url)
    if ([string]::IsNullOrWhiteSpace($Url)) {
        return $false
    }
    try {
        $response = Invoke-WebRequest -Uri $Url -Method Get -TimeoutSec 20 -UseBasicParsing
        return [int]$response.StatusCode -ge 200 -and [int]$response.StatusCode -lt 300
    }
    catch {
        return $false
    }
}

Write-Host "Checking deployment health: $BaseUrl"
$health = Invoke-RestMethod -Uri "$BaseUrl/api/health" -Method Get -TimeoutSec 15
if ($health.status -ne "ok") {
    throw "Health check did not return ok."
}

Write-Host "Checking app token with device config API"
$deviceId = "deployment-check"
$config = Invoke-RestMethod `
    -Uri "$BaseUrl/api/devices/$deviceId/config" `
    -Method Get `
    -Headers $headers `
    -TimeoutSec 20
if ($config.device_id -ne $deviceId) {
    throw "Device config check returned an unexpected device_id."
}

if (-not [string]::IsNullOrWhiteSpace($CheckPersistenceFrom)) {
    Write-Host "Checking Zeabur Volume persistence from previous evidence"
    $previousEvidence = Get-JsonFile $CheckPersistenceFrom
    $previousMarker = $previousEvidence.volume_persistence_marker
    if ($null -eq $previousMarker) {
        throw "Previous evidence does not contain volume_persistence_marker."
    }

    $markerDeviceId = [string]$previousMarker.device_id
    $expectedShareTarget = [string]$previousMarker.share_target
    $fileUrl = [string]$previousMarker.file_url
    $markerConfig = Invoke-RestMethod `
        -Uri "$BaseUrl/api/devices/$markerDeviceId/config" `
        -Method Get `
        -Headers $headers `
        -TimeoutSec 20
    $dbMarkerOk = [string]$markerConfig.share_target -eq $expectedShareTarget
    $fileMarkerOk = Test-HttpOk $fileUrl
    if (-not $dbMarkerOk) {
        throw "Volume persistence DB marker mismatch. Expected share_target '$expectedShareTarget', got '$($markerConfig.share_target)'."
    }
    if (-not $fileMarkerOk) {
        throw "Volume persistence file marker is not reachable: $fileUrl"
    }
    $volumePersistence = [ordered]@{
        checked = $true
        db_marker_checked = $true
        file_marker_checked = $true
        source_evidence = (Resolve-Path -LiteralPath $CheckPersistenceFrom).Path
        marker_device_id = $markerDeviceId
        file_url = $fileUrl
        notes = "DB marker and file marker survived a service restart."
    }
}

Write-Host "Running remote smoke"
powershell -ExecutionPolicy Bypass -File scripts/smoke_test.ps1 `
    -BaseUrl $BaseUrl `
    -AppToken $AppToken `
    -Python $Python

$smokeAnalyzePath = "smoke_output/analyze.json"
if (-not (Test-Path -LiteralPath $smokeAnalyzePath)) {
    throw "Smoke analyze output was not found: $smokeAnalyzePath"
}
$smokeAnalyze = Get-Content -LiteralPath $smokeAnalyzePath -Encoding UTF8 | ConvertFrom-Json
$persistenceMarkerId = "deployment-volume-" + [Guid]::NewGuid().ToString("N")
$persistenceShareTarget = "volume-marker-" + [Guid]::NewGuid().ToString("N")
$markerPayload = @{
    share_target = $persistenceShareTarget
} | ConvertTo-Json -Compress
Invoke-RestMethod `
    -Uri "$BaseUrl/api/devices/$persistenceMarkerId/config" `
    -Method Put `
    -Headers $headers `
    -ContentType "application/json" `
    -Body $markerPayload `
    -TimeoutSec 20 | Out-Null
$markerConfigCheck = Invoke-RestMethod `
    -Uri "$BaseUrl/api/devices/$persistenceMarkerId/config" `
    -Method Get `
    -Headers $headers `
    -TimeoutSec 20
if ([string]$markerConfigCheck.share_target -ne $persistenceShareTarget) {
    throw "Failed to write deployment persistence marker."
}
$volumePersistenceMarker = [ordered]@{
    device_id = $persistenceMarkerId
    share_target = $persistenceShareTarget
    file_url = [string]$smokeAnalyze.base_image_url
    created_at = (Get-Date).ToUniversalTime().ToString("o")
    instructions = "Restart the Zeabur service, then run verify_deployment.ps1 with -CheckPersistenceFrom this evidence file."
}

$endedAt = Get-Date
$evidence = [ordered]@{
    base_url = $BaseUrl
    checked_at = $endedAt.ToUniversalTime().ToString("o")
    elapsed_seconds = [Math]::Round(($endedAt - $startedAt).TotalSeconds, 2)
    health = $health
    device_config_checked = $true
    smoke_passed = $true
    volume_persistence_marker = $volumePersistenceMarker
    volume_persistence = $volumePersistence
    volume_persistence_checked = [bool]$volumePersistence.checked
    notes = "Remote deployment verification passed."
}

$evidenceJson = $evidence | ConvertTo-Json -Depth 8
[System.IO.File]::WriteAllText(
    $EvidencePath,
    $evidenceJson,
    [System.Text.UTF8Encoding]::new($false)
)

Write-Host "Deployment verification passed"
Write-Host "Evidence:"
Write-Host "  $EvidencePath"
