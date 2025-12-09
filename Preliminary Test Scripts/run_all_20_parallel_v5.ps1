# Run all 20 debates in parallel using the new v5 architecture
# Output: all_20_debates_v5_results.csv

$motions = @(
    "This house would ban zoos",
    "This house believes that developing nations should prioritize economic growth over environmental protection",
    "This house would remove the right to privacy for politicians",
    "This house would make voting mandatory",
    "This house believes that the emphasis on hard work and hustle culture is harmful"
)

$models = @("4o", "4o-mini")
$pythonExe = "C:\Users\Bhavya Shah\OneDrive\Desktop\Kyle\.venv\Scripts\python.exe"
$script = "C:\Users\Bhavya Shah\OneDrive\Desktop\Kyle\crossover_debate.py"
$tempDir = "C:\Users\Bhavya Shah\OneDrive\Desktop\Kyle\temp_results_v5"
$finalOutput = "all_20_debates_v5_results.csv"

# Create temp directory
if (Test-Path $tempDir) {
    Remove-Item $tempDir -Recurse -Force
}
New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

$jobs = @()
$jobId = 0

Write-Host "=== Launching 20 Debates in Parallel (v5 Architecture) ===" -ForegroundColor Cyan
Write-Host "Temp results will be stored in: $tempDir"
Write-Host "Final output will be: $finalOutput`n"

foreach ($motion in $motions) {
    foreach ($model in $models) {
        # Orientation 1: Enhanced (Prop) vs Baseline (Opp)
        $jobId++
        $outFile1 = Join-Path $tempDir "debate_${jobId}.csv"
        $args1 = @(
            "-m", $motion,
            "-pm", $model, "-om", $model,
            "-pa", "enhanced", "-oa", "baseline",
            "-jm", "o3",
            "-o", $outFile1
        )
        
        Write-Host "Starting Job ${jobId}: $model (Enhanced vs Baseline) - $motion" -ForegroundColor Gray
        $jobs += Start-Job -ScriptBlock {
            param($exe, $scr, $a)
            & $exe $scr @a
        } -ArgumentList $pythonExe, $script, $args1

        # Orientation 2: Baseline (Prop) vs Enhanced (Opp)
        $jobId++
        $outFile2 = Join-Path $tempDir "debate_${jobId}.csv"
        $args2 = @(
            "-m", $motion,
            "-pm", $model, "-om", $model,
            "-pa", "baseline", "-oa", "enhanced",
            "-jm", "o3",
            "-o", $outFile2
        )
        
        Write-Host "Starting Job ${jobId}: $model (Baseline vs Enhanced) - $motion" -ForegroundColor Gray
        $jobs += Start-Job -ScriptBlock {
            param($exe, $scr, $a)
            & $exe $scr @a
        } -ArgumentList $pythonExe, $script, $args2
    }
}

Write-Host "`nAll $jobId jobs launched. Waiting for completion..." -ForegroundColor Yellow

# Wait for all jobs
$jobs | Wait-Job | Out-Null

# Check for errors
$failed = $jobs | Where-Object { $_.State -ne 'Completed' }
if ($failed) {
    Write-Host "`nWARNING: Some jobs failed or did not complete successfully." -ForegroundColor Red
    $failed | Receive-Job
}

# Merge results
Write-Host "`nMerging results..." -ForegroundColor Cyan
$results = Get-ChildItem $tempDir -Filter "*.csv"
if ($results) {
    $merged = $results | ForEach-Object { Import-Csv $_.FullName }
    $merged | Export-Csv $finalOutput -NoTypeInformation
    Write-Host "Success! All results merged into $finalOutput" -ForegroundColor Green
} else {
    Write-Host "No results found to merge." -ForegroundColor Red
}

# Cleanup
# Remove-Item $tempDir -Recurse -Force
