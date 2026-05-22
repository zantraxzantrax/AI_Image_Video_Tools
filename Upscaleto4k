$ffmpeg          = "G:\ffmpeg\bin\ffmpeg.exe"
$realesrgan      = "G:\realergan_Vulkan_Standalone\realesrgan-ncnn-vulkan.exe"
$modelsDir       = "G:\realergan_Vulkan_Standalone\models"
$model           = "realesr-animevideov3"
$srcDir          = "Z:\ComfyUI\frames\2xRTXUPSCALED"
$outputPath      = "G:\comfyui\ComfyUI_windows_portable\ComfyUI\output\4k_Upscale\4k_output"
$tempBase        = "G:\comfyui\ComfyUI_windows_portable\ComfyUI\output\4k_Upscale\_temp"
$logFile         = "G:\comfyui\ComfyUI_windows_portable\ComfyUI\output\4k_Upscale\upscale_log.txt"
$maxParallelJobs = 2
$statusLines     = $maxParallelJobs + 1   # job bars + 1 main bar at bottom

if (-not (Test-Path $outputPath)) { New-Item -ItemType Directory -Path $outputPath | Out-Null }
if (Test-Path -LiteralPath $tempBase) {
    Write-Host "Flushing temp folder..." -ForegroundColor Yellow
    Remove-Item -Recurse -Force -LiteralPath $tempBase
}
New-Item -ItemType Directory -Path $tempBase | Out-Null

# ---------------------------------------------------------------------------
# Draw a single line at absolute console row Y using Console API directly.
# This bypasses PowerShell's output pipeline and never causes scrolling.
# ---------------------------------------------------------------------------
function Draw-Line {
    param([int]$y, [string]$text, [ConsoleColor]$color = [ConsoleColor]::White)
    $winW  = [Console]::WindowWidth
    $line  = $text.PadRight($winW).Substring(0, $winW)
    $saved = [Console]::CursorVisible
    [Console]::CursorVisible = $false
    [Console]::SetCursorPosition(0, $y)
    [Console]::ForegroundColor = $color
    [Console]::Write($line)
    [Console]::ResetColor()
    [Console]::CursorVisible = $saved
}

# ---------------------------------------------------------------------------
# Write-Log: prints to scrolling area ABOVE the status block only.
# Uses [Console]::SetCursorPosition to ensure we never write into status rows.
# ---------------------------------------------------------------------------
function Write-Log {
    param($message, [ConsoleColor]$color = [ConsoleColor]::White)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $entry     = "[$timestamp] $message"

    $winH  = [Console]::WindowHeight
    $safeY = $winH - $statusLines - 1   # last safe row for scrolling output

    # Clamp cursor above the status zone
    $curY = [Console]::CursorTop
    if ($curY -gt $safeY) { [Console]::SetCursorPosition(0, $safeY) }

    [Console]::ForegroundColor = $color
    [Console]::WriteLine($entry)
    [Console]::ResetColor()

    # Re-clamp after write in case it bumped into the status zone
    $curY = [Console]::CursorTop
    if ($curY -gt $safeY) { [Console]::SetCursorPosition(0, $safeY) }

    # Write to log file with retry on lock
    $retries = 10
    while ($retries -gt 0) {
        try   { Add-Content -Path $logFile -Value $entry -ErrorAction Stop; break }
        catch { $retries--; Start-Sleep -Milliseconds 50 }
    }
}

# ---------------------------------------------------------------------------
# Get per-job progress by counting PNGs in temp folders
# ---------------------------------------------------------------------------
function Get-JobProgress {
    param($jobName)
    $name       = $jobName -replace '^Upscale_', ''
    $framesDir  = Join-Path $tempBase "${name}_frames"
    $upscaleDir = Join-Path $tempBase "${name}_upscaled"
    $countFile  = Join-Path $tempBase "${name}_framecount.txt"
    $extracted  = if (Test-Path $framesDir)  { try { (Get-ChildItem $framesDir  -Filter *.png -ErrorAction Stop).Count } catch { 0 } } else { 0 }
    $upscaled   = if (Test-Path $upscaleDir) { try { (Get-ChildItem $upscaleDir -Filter *.png -ErrorAction Stop).Count } catch { 0 } } else { 0 }
    # Read actual frame count if available, fall back to 961
    $total = if (Test-Path $countFile) { [int](Get-Content $countFile -ErrorAction SilentlyContinue) } else { 961 }
    if ($total -le 0) { $total = 961 }
    if ($upscaled -gt 0)       { $stage = "Upscaling "; $count = $upscaled }
    elseif ($extracted -gt 0)  { $stage = "Extracting"; $count = $extracted }
    else                        { $stage = "Starting  "; $count = 0 }
    $rawPct = if ($total -gt 0) { [math]::Round(($count / $total) * 100) } else { 0 }
    $pct    = [math]::Min(100, $rawPct)
    $filled = [math]::Floor($pct / 4)
    $bar    = "[" + ("#" * $filled) + ("-" * (25 - $filled)) + "]"
    return " $stage $bar $pct% ($count/$total) | $name"
}

# ---------------------------------------------------------------------------
# Redraw the entire status block in-place using Draw-Line (no scroll)
# ---------------------------------------------------------------------------
function Show-Status {
    param($current, $total, $isPaused)
    $winH    = [Console]::WindowHeight
    $status  = if ($isPaused) { "!! PAUSED !!  Press P to resume" } else { "Running  |  Press P to pause after current job finishes" }
    $pct     = if ($total -gt 0) { [math]::Round(($current / $total) * 100, 1) } else { 0 }
    $filled  = [math]::Floor($pct / 2)
    $mainBar = " [" + ("#" * $filled) + ("-" * (50 - $filled)) + "] $pct% ($current/$total)  |  $status"

    $runningJobs = @(Get-Job -State Running)

    # Draw one job progress line per slot
    for ($i = 0; $i -lt $maxParallelJobs; $i++) {
        $y = $winH - $statusLines + $i
        if ($i -lt $runningJobs.Count) {
            Draw-Line $y (Get-JobProgress $runningJobs[$i].Name) Magenta
        } else {
            Draw-Line $y "" White
        }
    }

    # Draw main bar at very bottom row
    $mainColor = if ($isPaused) { [ConsoleColor]::Yellow } else { [ConsoleColor]::Cyan }
    Draw-Line ($winH - 1) $mainBar $mainColor
}

# ---------------------------------------------------------------------------
function Check-Keypress {
    if ([Console]::KeyAvailable) {
        $key = [Console]::ReadKey($true)
        if ($key.KeyChar -eq 'p' -or $key.KeyChar -eq 'P') { return $true }
    }
    return $false
}

# ---------------------------------------------------------------------------
$paused      = $false
$doneCount   = 0
$videos      = Get-ChildItem -Path $srcDir -Filter "*.mp4" -File | Sort-Object Name
$totalVideos = $videos.Count

# Reserve bottom N lines by printing blank lines to push content up
1..$statusLines | ForEach-Object { Write-Host "" }

Write-Log "Science mode engaged. Processing $totalVideos videos..." Cyan
Write-Log "Press P at any time to pause/resume between jobs." Cyan

foreach ($video in $videos) {

    $name    = $video.BaseName
    $outFile = Join-Path $outputPath "$($name)_4k.mp4"

    if (Test-Path -LiteralPath $outFile) {
        Write-Log "Skipping (exists): $($video.Name)" DarkGray
        $doneCount++
        Show-Status $doneCount $totalVideos $paused
        continue
    }

    # Throttle + pause loop
    while ($true) {
        if (Check-Keypress) {
            $paused = -not $paused
            if ($paused) { Write-Log "PAUSED - current job(s) will finish before holding..." Yellow }
            else          { Write-Log "RESUMED - continuing..." Green }
        }
        $runningCount = @(Get-Job -State Running).Count
        if ($paused) {
            Show-Status $doneCount $totalVideos $true
            Start-Sleep -Milliseconds 300
            continue
        }
        if ($runningCount -lt $maxParallelJobs) { break }
        Show-Status $doneCount $totalVideos $false
        Start-Sleep -Milliseconds 500
    }

    Show-Status $doneCount $totalVideos $false
    Write-Log "Launching: $($video.Name)" Green

    Start-Job -Name "Upscale_$name" -ArgumentList $ffmpeg, $realesrgan, $model, $modelsDir, $video.FullName, $outFile, $tempBase, $name, $logFile -ScriptBlock {
        param($ffPath, $esrPath, $mdl, $mdlDir, $inFile, $outFile, $tmpBase, $name, $log)

        function Write-Log {
            param($message)
            $entry   = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $message"
            $retries = 10
            while ($retries -gt 0) {
                try   { Add-Content -Path $log -Value $entry -ErrorAction Stop; break }
                catch { $retries--; Start-Sleep -Milliseconds 50 }
            }
        }

        $framesDir  = Join-Path $tmpBase "$($name)_frames"
        $upscaleDir = Join-Path $tmpBase "$($name)_upscaled"
        New-Item -ItemType Directory -Path $framesDir  -Force | Out-Null
        New-Item -ItemType Directory -Path $upscaleDir -Force | Out-Null

        Write-Log "[$name] Extracting frames..."
        & $ffPath -hide_banner -loglevel error -i $inFile "$framesDir\%06d.png"
        $frameCount = (Get-ChildItem -Path $framesDir -Filter "*.png").Count
        Write-Log "[$name] Extracted $frameCount frames"
        # Write actual frame count so progress bar uses the real total
        Set-Content -Path (Join-Path $tmpBase "${name}_framecount.txt") -Value $frameCount

        Write-Log "[$name] Upscaling with Real-ESRGAN..."
        & $esrPath -i $framesDir -o $upscaleDir -n $mdl -m $mdlDir -s 2 -t 1920 -g 0 -j 1:1:1

        $upscaledCount = (Get-ChildItem -Path $upscaleDir -Filter "*.png").Count
        if ($upscaledCount -eq 0) {
            Write-Log "[$name] ERROR - no upscaled frames produced, skipping reassembly"
            Remove-Item -Recurse -Force $framesDir, $upscaleDir
            return
        }

        Write-Log "[$name] Reassembling $upscaledCount frames into 4K video..."
        & $ffPath -hide_banner -loglevel error -framerate 60 -i "$upscaleDir\%06d.png" -c:v hevc_nvenc -preset p7 -tune hq -pix_fmt p010le -rc vbr -cq 10 -spatial-aq 1 -temporal-aq 1 -b:v 0 -maxrate 150M -bufsize 300M -y $outFile

        if (Test-Path -LiteralPath $outFile) { Write-Log "[$name] DONE - $outFile" }
        else                                  { Write-Log "[$name] ERROR - output file not created" }

        Remove-Item -Recurse -Force $framesDir, $upscaleDir
    } | Out-Null    # <-- suppresses the job table printout

    $doneCount++
    Show-Status $doneCount $totalVideos $paused
}

Write-Log "All videos queued. Finalizing remaining upscales..." Cyan
while (@(Get-Job -State Running).Count -gt 0) {
    if (Check-Keypress) {
        $paused = -not $paused
        Write-Log (if ($paused) { "PAUSED" } else { "RESUMED" }) Yellow
    }
    Show-Status ($totalVideos - @(Get-Job -State Running).Count) $totalVideos $paused
    Start-Sleep -Milliseconds 500
}

if (-not (Get-ChildItem -Path $tempBase -ErrorAction SilentlyContinue)) {
    Remove-Item -Force $tempBase
}
Get-Job | Remove-Job
Write-Log "Science Complete. Check 4k_output for results." Green
