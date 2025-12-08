# Run all 20 debates in parallel with race-condition-safe CSV handling
# Each job writes to its own temp file, then we merge at the end

$motions = @(
    "This house would ban zoos",
    "This house believes that developing nations should prioritize economic growth over environmental protection",
    "This house would remove the right to privacy for politicians",
    "This house would make voting mandatory",
    "This house believes that the emphasis on hard work and hustle culture is harmful"
)

$models = @("4o", "4o-mini")
$outputFile = "detailed_prompts_only_against_baseline_v2.csv"
$tempDir = "C:\Users\Bhavya Shah\OneDrive\Desktop\Kyle\temp_debates"
$pythonExe = "C:\Users\Bhavya Shah\OneDrive\Desktop\Kyle\.venv\Scripts\python.exe"
$scriptPath = "C:\Users\Bhavya Shah\OneDrive\Desktop\Kyle\crossover_debate.py"
$workDir = "C:\Users\Bhavya Shah\OneDrive\Desktop\Kyle"

# Clean up and create temp directory
Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
Remove-Item $outputFile -ErrorAction SilentlyContinue

Write-Host "=== Running All 20 Debates in Parallel ===" -ForegroundColor Cyan
Write-Host "Temp directory: $tempDir"
Write-Host "Final output: $outputFile`n"

$jobs = @()
$jobId = 0

foreach ($motion in $motions) {
    foreach ($model in $models) {
        foreach ($orientation in @("enhanced_vs_baseline", "baseline_vs_enhanced")) {
            $jobId++
            $tempFile = "$tempDir\debate_$jobId.csv"
            
            if ($orientation -eq "enhanced_vs_baseline") {
                $propArch = "enhanced"
                $oppArch = "baseline"
            } else {
                $propArch = "baseline"
                $oppArch = "enhanced"
            }
            
            $shortMotion = $motion.Substring(0, [Math]::Min(30, $motion.Length))
            Write-Host "Starting Job $jobId : $shortMotion... | $model | $propArch vs $oppArch" -ForegroundColor Gray
            
            $job = Start-Job -ScriptBlock {
                param($python, $script, $motion, $model, $propArch, $oppArch, $output, $wd)
                Set-Location $wd
                & $python $script -m $motion -pm $model -om $model -pa $propArch -oa $oppArch -jm o3 -o $output 2>&1
            } -ArgumentList $pythonExe, $scriptPath, $motion, $model, $propArch, $oppArch, $tempFile, $workDir
            
            $jobs += @{
                Job = $job
                Id = $jobId
                Motion = $shortMotion
                Model = $model
                Orientation = "$propArch vs $oppArch"
                TempFile = $tempFile
            }
        }
    }
}

Write-Host "`n=== $($jobs.Count) Jobs Started - Waiting for Completion ===" -ForegroundColor Yellow

# Monitor progress
$completed = @()
while ($completed.Count -lt $jobs.Count) {
    Start-Sleep -Seconds 5
    
    foreach ($j in $jobs) {
        if ($j.Id -notin $completed -and $j.Job.State -ne 'Running') {
            $completed += $j.Id
            $status = if ($j.Job.State -eq 'Completed') { "OK" } else { "FAILED" }
            $color = if ($status -eq "OK") { "Green" } else { "Red" }
            Write-Host "[$($completed.Count)/$($jobs.Count)] Job $($j.Id) $status : $($j.Motion) | $($j.Model) | $($j.Orientation)" -ForegroundColor $color
        }
    }
}

Write-Host "`n=== All Jobs Complete - Merging Results ===" -ForegroundColor Cyan

# Merge all temp CSV files into final output
$allData = @()
$successCount = 0

foreach ($j in $jobs) {
    if (Test-Path $j.TempFile) {
        try {
            $data = Import-Csv $j.TempFile
            $allData += $data
            $successCount++
        } catch {
            Write-Host "Warning: Could not read $($j.TempFile)" -ForegroundColor Yellow
        }
    } else {
        Write-Host "Warning: Missing temp file for Job $($j.Id)" -ForegroundColor Yellow
    }
}

if ($allData.Count -gt 0) {
    $allData | Export-Csv -Path $outputFile -NoTypeInformation
    Write-Host "`nMerged $($allData.Count) debates into $outputFile" -ForegroundColor Green
}

# Cleanup temp files
Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue

# Summary
Write-Host "`n=== Summary ===" -ForegroundColor Cyan
Write-Host "Total debates: $($allData.Count)"

if ($allData.Count -gt 0) {
    $csv = Import-Csv $outputFile
    $enhancedWins = ($csv | Where-Object { 
        ($_.prop_architecture -eq 'enhanced' -and $_.winner -eq 'Proposition') -or 
        ($_.opp_architecture -eq 'enhanced' -and $_.winner -eq 'Opposition') 
    }).Count
    $baselineWins = $csv.Count - $enhancedWins
    
    Write-Host "Enhanced wins: $enhancedWins ($([math]::Round($enhancedWins/$csv.Count*100, 1))%)"
    Write-Host "Baseline wins: $baselineWins ($([math]::Round($baselineWins/$csv.Count*100, 1))%)"
}

# Show any job errors
Write-Host "`n=== Job Details ===" -ForegroundColor Gray
foreach ($j in $jobs) {
    if ($j.Job.State -ne 'Completed') {
        Write-Host "Job $($j.Id) failed:" -ForegroundColor Red
        Receive-Job $j.Job | Write-Host
    }
}

# Cleanup jobs
$jobs | ForEach-Object { Remove-Job $_.Job -Force -ErrorAction SilentlyContinue }
