param(
    [Parameter(Mandatory = $true)]
    [string]$BaseUrl,
    [string]$AppToken = $env:APP_TOKEN,
    [double]$DurationMinutes = 10080,
    [double]$IntervalSeconds = 300,
    [string]$DeviceId = "uptime-check",
    [double]$MaxFailureRatePercent = 1.0,
    [string]$EvidencePath = "uptime_evidence.json"
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
$OutputEncoding = [System.Text.UTF8Encoding]::new()

if ([string]::IsNullOrWhiteSpace($AppToken)) {
    throw "AppToken is required. Set APP_TOKEN or pass -AppToken."
}
if ($DurationMinutes -le 0) {
    throw "DurationMinutes must be greater than 0."
}
if ($IntervalSeconds -le 0) {
    throw "IntervalSeconds must be greater than 0."
}

$BaseUrl = $BaseUrl.TrimEnd("/")
$headers = @{ "X-App-Token" = $AppToken }
$startedAt = Get-Date
$endAt = $startedAt.AddMinutes($DurationMinutes)
$samples = New-Object System.Collections.Generic.List[object]

Write-Host "Monitoring deployment: $BaseUrl"
Write-Host ("Duration: {0:n2} minutes, interval: {1:n2} seconds" -f $DurationMinutes, $IntervalSeconds)

function Invoke-MonitorSample {
    $sampleStarted = Get-Date
    $result = [ordered]@{
        checked_at = $sampleStarted.ToUniversalTime().ToString("o")
        ok = $false
        elapsed_ms = $null
        health_status = $null
        health_version = $null
        device_config_checked = $false
        error = $null
    }

    try {
        $health = Invoke-RestMethod -Uri "$BaseUrl/api/health" -Method Get -TimeoutSec 20
        $result.health_status = [string]$health.status
        $result.health_version = [string]$health.version
        if ($health.status -ne "ok") {
            throw "Health status was '$($health.status)'."
        }

        $config = Invoke-RestMethod `
            -Uri "$BaseUrl/api/devices/$DeviceId/config" `
            -Method Get `
            -Headers $headers `
            -TimeoutSec 20
        if ($config.device_id -ne $DeviceId) {
            throw "Device config returned unexpected device_id '$($config.device_id)'."
        }
        $result.device_config_checked = $true
        $result.ok = $true
    }
    catch {
        $result.error = $_.Exception.Message
    }
    finally {
        $result.elapsed_ms = [Math]::Round(((Get-Date) - $sampleStarted).TotalMilliseconds, 0)
    }

    return $result
}

do {
    $sample = Invoke-MonitorSample
    $samples.Add([pscustomobject]$sample)
    if ($sample.ok) {
        Write-Host ("[{0}] ok in {1}ms" -f $sample.checked_at, $sample.elapsed_ms)
    }
    else {
        Write-Host ("[{0}] failed: {1}" -f $sample.checked_at, $sample.error)
    }

    $remainingMs = ($endAt - (Get-Date)).TotalMilliseconds
    if ($remainingMs -gt 0) {
        $sleepMs = [Math]::Min($remainingMs, $IntervalSeconds * 1000)
        Start-Sleep -Milliseconds ([int][Math]::Max(1, $sleepMs))
    }
} while ((Get-Date) -lt $endAt)

$endedAt = Get-Date
$total = $samples.Count
$failures = @($samples | Where-Object { -not $_.ok }).Count
$failureRate = if ($total -eq 0) { 100.0 } else { [Math]::Round(($failures / $total) * 100, 3) }
$durationSeconds = [Math]::Round(($endedAt - $startedAt).TotalSeconds, 2)
$monitorPassed = $total -gt 0 -and $failureRate -le $MaxFailureRatePercent

$evidence = [ordered]@{
    base_url = $BaseUrl
    started_at = $startedAt.ToUniversalTime().ToString("o")
    ended_at = $endedAt.ToUniversalTime().ToString("o")
    duration_seconds = $durationSeconds
    interval_seconds = $IntervalSeconds
    sample_count = $total
    failure_count = $failures
    failure_rate_percent = $failureRate
    max_failure_rate_percent = $MaxFailureRatePercent
    monitor_passed = $monitorPassed
    samples = $samples
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

Write-Host "Deployment monitor finished"
Write-Host ("  samples: {0}" -f $total)
Write-Host ("  failures: {0}" -f $failures)
Write-Host ("  failure rate: {0}%" -f $failureRate)
Write-Host ("  evidence: {0}" -f $EvidencePath)

if (-not $monitorPassed) {
    throw "Deployment monitor failed. Failure rate $failureRate% is above $MaxFailureRatePercent%."
}
