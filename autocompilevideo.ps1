$ffmpeg = "G:\ffmpeg\bin\ffmpeg.exe"
$galleryPath = Join-Path -Path $PSScriptRoot -ChildPath "Master_Gallery"
$maxParallelJobs = 8

if (-not (Test-Path $galleryPath)) { New-Item -ItemType Directory -Path $galleryPath }

# Get folders excluding the Master Gallery
$folders = Get-ChildItem -Directory -Recurse | Where-Object { $_.FullName -notlike "*Master_Gallery*" }

Write-Host "Science mode engaged. Processing $($folders.Count) folders with 8 parallel streams..." -ForegroundColor Cyan

foreach ($folder in $folders) {
    # Wait if 8 jobs are already running
    while (@(Get-Job -State Running).Count -ge $maxParallelJobs) {
        Start-Sleep -Seconds 2
    }

    $pngs = Get-ChildItem -Path $folder.FullName -Filter "*.png"
    $outputName = "$($folder.Name)_960x544.mp4"
    $outputPath = Join-Path -Path $folder.FullName -ChildPath $outputName

    if ($pngs.Count -gt 0 -and -not (Test-Path $outputPath)) {
        
        # Pre-create the list file
        $listPath = Join-Path -Path $folder.FullName -ChildPath "mylist.txt"
        $pngs | Sort-Object Name | ForEach-Object { "file '$($_.Name)'" } | Out-File -FilePath $listPath -Encoding ascii

        Write-Host "Launching: $($folder.Name)" -ForegroundColor Green

        # Standard Start-Job for 2026 compatibility
        Start-Job -Name "Encode_$($folder.Name)" -ArgumentList $ffmpeg, $folder.FullName, $listPath, $outputName, $galleryPath -ScriptBlock {
            param($ffPath, $fFull, $lPath, $oName, $gPath)
            
            # Navigate to the specific chunk folder
            Set-Location -LiteralPath $fFull
            
            # Execute FFmpeg with CQ 10 for high-quality RTX preservation
            & $ffPath -f concat -safe 0 -r 60 -i "mylist.txt" `
            -vf "pad=ceil(iw/2)*2:ceil(ih/2)*2" `
            -c:v hevc_nvenc -preset p7 -tune hq -pix_fmt yuv420p10le `
            -rc vbr -cq 10 -spatial-aq 1 -temporal-aq 1 -b:v 0 -maxrate 150M -bufsize 300M `
            -y $oName
            
            # Cleanup and Copy to Master Gallery
            if (Test-Path "mylist.txt") { Remove-Item "mylist.txt" }
            if (Test-Path $oName) { Copy-Item $oName -Destination $gPath }
        }
    }
}

# Wait for all jobs to finish
Write-Host "All folders queued. Finalizing background renders..." -ForegroundColor Cyan
while (@(Get-Job -State Running).Count -gt 0) {
    Start-Sleep -Seconds 5
}

# Clean up job history
Get-Job | Remove-Job
Write-Host "Science Complete. Check Master_Gallery for all 8-stream results." -ForegroundColor Green