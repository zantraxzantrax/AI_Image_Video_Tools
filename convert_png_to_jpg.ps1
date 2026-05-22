$ffmpeg     = "G:\ffmpeg\bin\ffmpeg.exe"
$src        = "G:\comfyui\ComfyUI_windows_portable\ComfyUI\output\10240x5760_Refined"
$dest       = "G:\comfyui\ComfyUI_windows_portable\ComfyUI\output\10240x5760jpegconverted"
$maxJobs    = 20   # 9800X3D + 5080 can handle more — bump to 20 if CPU stays below 90%

if (-not (Test-Path $dest)) { New-Item -ItemType Directory -Path $dest }

$pngs = Get-ChildItem -Path $src -Filter "*.png"
Write-Host "Found $($pngs.Count) PNG files. Converting with $maxJobs parallel jobs..." -ForegroundColor Cyan

foreach ($png in $pngs) {
    # Throttle: wait until a slot opens
    while (@(Get-Job -State Running).Count -ge $maxJobs) {
        Start-Sleep -Seconds 1
    }

    $outPath = Join-Path $dest ("$($png.BaseName).jpg")

    # Skip if already converted
    if (Test-Path $outPath) {
        Write-Host "Skipping (exists): $($png.Name)" -ForegroundColor DarkGray
        continue
    }

    Write-Host "Queuing: $($png.Name)" -ForegroundColor Green

    Start-Job -ArgumentList $ffmpeg, $png.FullName, $outPath -ScriptBlock {
        param($ffPath, $inFile, $outFile)
        & $ffPath -hide_banner -loglevel error -n -i $inFile -frames:v 1 -update 1 -vf "format=yuv444p" -q:v 2 $outFile
    } | Out-Null
}

# Wait for remaining jobs
Write-Host "All jobs queued. Waiting for final conversions..." -ForegroundColor Cyan
while (@(Get-Job -State Running).Count -gt 0) {
    $running = @(Get-Job -State Running).Count
    $done    = @(Get-Job -State Completed).Count
    Write-Host "  Running: $running | Done: $done" -ForegroundColor Yellow
    Start-Sleep -Seconds 3
}

Get-Job | Remove-Job
Write-Host "Done. JPEGs are in: $dest" -ForegroundColor Green
