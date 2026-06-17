param(
    [string]$BaseUrl = "http://localhost:8000",
    [string]$AppToken = $env:APP_TOKEN,
    [string]$ImagePath = "test_images/cheetah.jpg",
    [string]$OutputDir = "smoke_output",
    [string]$Python = "python"
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
$OutputEncoding = [System.Text.UTF8Encoding]::new()
$env:PYTHONUTF8 = "1"
$env:PYTHONIOENCODING = "utf-8"

if ([string]::IsNullOrWhiteSpace($AppToken)) {
    $AppToken = "dev-token-change-me"
}

if (-not (Test-Path -LiteralPath $ImagePath)) {
    & $Python scripts/make_test_image.py $ImagePath
}

New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
$startedAt = Get-Date

Invoke-RestMethod -Uri "$BaseUrl/api/health" -Method Get | Out-Null

$headers = @{ "X-App-Token" = $AppToken }
$configPayload = @{
    daily_budget_cny = 500
    daily_video_limit = 100
    enable_video = $true
    enable_animate_old = $true
} | ConvertTo-Json -Compress
Invoke-RestMethod `
    -Uri "$BaseUrl/api/devices/smoke-device/config" `
    -Method Put `
    -Headers $headers `
    -ContentType "application/json" `
    -Body $configPayload | Out-Null

$bytes = [System.IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $ImagePath))
$payload = @{
    device_id = "smoke-device"
    image = [Convert]::ToBase64String($bytes)
} | ConvertTo-Json -Compress

$payloadPath = Join-Path $OutputDir "payload.json"
$analyzePath = Join-Path $OutputDir "analyze.json"
[System.IO.File]::WriteAllText($payloadPath, $payload, [System.Text.UTF8Encoding]::new($false))
& curl.exe -fsS `
    -H "Content-Type: application/json" `
    -H "X-App-Token: $AppToken" `
    -d "@$payloadPath" `
    "$BaseUrl/api/analyze" `
    -o $analyzePath

$basePath = Join-Path $OutputDir "base.jpg"
$analysisLines = & $Python scripts/smoke_json.py analyze $analyzePath

$jobId = $analysisLines[0]
$baseImageUrl = $analysisLines[1]
$namesText = $analysisLines[2]
& curl.exe -fsS $baseImageUrl -o $basePath

$budgetConfigPayload = @{
    daily_budget_cny = 0
    daily_video_limit = 100
    enable_video = $true
} | ConvertTo-Json -Compress
Invoke-RestMethod `
    -Uri "$BaseUrl/api/devices/smoke-budget-device/config" `
    -Method Put `
    -Headers $headers `
    -ContentType "application/json" `
    -Body $budgetConfigPayload | Out-Null
$budgetVideoPayload = @{
    device_id = "smoke-budget-device"
    image_url = $baseImageUrl
    motion = "slow_zoom"
} | ConvertTo-Json -Compress
$budgetPayloadPath = Join-Path $OutputDir "budget_video_payload.json"
$budgetResponsePath = Join-Path $OutputDir "budget_video_error.json"
[System.IO.File]::WriteAllText($budgetPayloadPath, $budgetVideoPayload, [System.Text.UTF8Encoding]::new($false))
$budgetStatus = & curl.exe -sS `
    -H "Content-Type: application/json" `
    -H "X-App-Token: $AppToken" `
    -d "@$budgetPayloadPath" `
    "$BaseUrl/api/video" `
    -o $budgetResponsePath `
    -w "%{http_code}"
if ($budgetStatus -ne "429") {
    throw "Expected budget check to return 429, got $budgetStatus"
}
& $Python scripts/smoke_json.py budget-error $budgetResponsePath | Out-Null

for ($index = 0; $index -lt 3; $index++) {
    $enhancePayload = @{
        job_id = $jobId
        option_index = $index
    } | ConvertTo-Json -Compress

    $enhancePayloadPath = Join-Path $OutputDir ("enhance_{0}_payload.json" -f $index)
    $enhanceResponsePath = Join-Path $OutputDir ("enhance_{0}.json" -f $index)
    [System.IO.File]::WriteAllText($enhancePayloadPath, $enhancePayload, [System.Text.UTF8Encoding]::new($false))
    & curl.exe -fsS `
        -H "Content-Type: application/json" `
        -H "X-App-Token: $AppToken" `
        -d "@$enhancePayloadPath" `
        "$BaseUrl/api/enhance" `
        -o $enhanceResponsePath

    $target = Join-Path $OutputDir ("option_{0}.jpg" -f ($index + 1))
    $resultUrl = & $Python scripts/smoke_json.py enhance $enhanceResponsePath
    & curl.exe -fsS $resultUrl -o $target
}

function Wait-SmokeJob {
    param(
        [string]$JobId,
        [string]$TargetPath
    )

    for ($attempt = 0; $attempt -lt 100; $attempt++) {
        $statusPath = Join-Path $OutputDir ("job_{0}_{1}.json" -f $JobId, $attempt)
        & curl.exe -fsS `
            -H "X-App-Token: $AppToken" `
            "$BaseUrl/api/jobs/$JobId" `
            -o $statusPath
        $resultUrl = & $Python scripts/smoke_json.py job-result $statusPath
        if (-not [string]::IsNullOrWhiteSpace($resultUrl)) {
            & curl.exe -fsS $resultUrl -o $TargetPath
            return
        }
        Start-Sleep -Milliseconds 250
    }

    throw "Async job did not finish: $JobId"
}

$videoPayload = @{
    device_id = "smoke-device"
    image_url = $baseImageUrl
    motion = "slow_zoom"
} | ConvertTo-Json -Compress
$videoPayloadPath = Join-Path $OutputDir "video_payload.json"
$videoCreatePath = Join-Path $OutputDir "video_create.json"
[System.IO.File]::WriteAllText($videoPayloadPath, $videoPayload, [System.Text.UTF8Encoding]::new($false))
& curl.exe -fsS `
    -H "Content-Type: application/json" `
    -H "X-App-Token: $AppToken" `
    -d "@$videoPayloadPath" `
    "$BaseUrl/api/video" `
    -o $videoCreatePath
$videoJobId = & $Python scripts/smoke_json.py create-job $videoCreatePath
Wait-SmokeJob -JobId $videoJobId -TargetPath (Join-Path $OutputDir "video.mp4")

$catalogPath = Join-Path $OutputDir "templates.json"
& curl.exe -fsS `
    -H "X-App-Token: $AppToken" `
    "$BaseUrl/api/templates" `
    -o $catalogPath
$templateId = & $Python scripts/smoke_json.py templates $catalogPath
$templatePayload = @{
    device_id = "smoke-device"
    template_id = $templateId
    text_index = 0
    image = [Convert]::ToBase64String($bytes)
} | ConvertTo-Json -Compress
$templatePayloadPath = Join-Path $OutputDir "template_payload.json"
$templateCreatePath = Join-Path $OutputDir "template_create.json"
[System.IO.File]::WriteAllText($templatePayloadPath, $templatePayload, [System.Text.UTF8Encoding]::new($false))
& curl.exe -fsS `
    -H "Content-Type: application/json" `
    -H "X-App-Token: $AppToken" `
    -d "@$templatePayloadPath" `
    "$BaseUrl/api/template/apply" `
    -o $templateCreatePath
$templateJobId = & $Python scripts/smoke_json.py create-job $templateCreatePath
Wait-SmokeJob -JobId $templateJobId -TargetPath (Join-Path $OutputDir "template.mp4")

$elapsed = (Get-Date) - $startedAt
Write-Host ("Smoke test passed in {0:n2}s" -f $elapsed.TotalSeconds)
Write-Host ("Options: {0}" -f ($namesText -replace "\|", ", "))
Write-Host "Outputs:"
Write-Host "  $basePath"
Write-Host "  $(Join-Path $OutputDir 'option_1.jpg')"
Write-Host "  $(Join-Path $OutputDir 'option_2.jpg')"
Write-Host "  $(Join-Path $OutputDir 'option_3.jpg')"
Write-Host "  $(Join-Path $OutputDir 'video.mp4')"
Write-Host "  $(Join-Path $OutputDir 'template.mp4')"
