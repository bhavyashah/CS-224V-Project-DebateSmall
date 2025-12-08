# Run failed debates (missing CSVs) with batching to avoid rate limits
# Output: all_20_debates_v5_results.csv (updated)

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

$jobId = 0
$batchSize = 4
$runningJobs = @()

Write-Host "=== Retrying Failed Debates (Batch Size: $batchSize) ===" -ForegroundColor Cyan

foreach ($motion in $motions) {
    foreach ($model in $models) {
        # Orientation 1
        $jobId++
        $outFile = Join-Path $tempDir "debate_${jobId}.csv"
        
        if (-not (Test-Path $outFile)) {
            $argsList = @(
                "-m", $motion,
                "-pm", $model, "-om", $model,
                "-pa", "enhanced", "-oa", "baseline",
                "-jm", "o3",
                "-o", $outFile
            )
            
            Write-Host "Queuing Job ${jobId}: $model (Enhanced vs Baseline) - $motion" -ForegroundColor Yellow
            $runningJobs += [PSCustomObject]@{
                Id = $jobId
                Args = $argsList
                OutFile = $outFile
            }
        }

        # Orientation 2
        $jobId++
        $outFile = Join-Path $tempDir "debate_${jobId}.csv"
        
        if (-not (Test-Path $outFile)) {
            $argsList = @(
                "-m", $motion,
                "-pm", $model, "-om", $model,
                "-pa", "baseline", "-oa", "enhanced",
                "-jm", "o3",
                "-o", $outFile
            )
            
            Write-Host "Queuing Job ${jobId}: $model (Baseline vs Enhanced) - $motion" -ForegroundColor Yellow
            $runningJobs += [PSCustomObject]@{
                Id = $jobId
                Args = $argsList
                OutFile = $outFile
            }
        }
    }
}

Write-Host "`nTotal missing jobs: $($runningJobs.Count)" -ForegroundColor Cyan

# Process in batches
for ($i = 0; $i -lt $runningJobs.Count; $i += $batchSize) {
    $batch = $runningJobs[$i..[Math]::Min($i + $batchSize - 1, $runningJobs.Count - 1)]
    $currentBatchJobs = @()
    
    Write-Host "`nStarting Batch $([Math]::Floor($i/$batchSize) + 1)..." -ForegroundColor Green
    
    foreach ($item in $batch) {
        Write-Host "  Running Job $($item.Id)..." -ForegroundColor Gray
        $currentBatchJobs += Start-Job -ScriptBlock {
            param($exe, $scr, $a)
            & $exe $scr @a
        } -ArgumentList $pythonExe, $script, $item.Args
    }
    
    # Wait for this batch to finish
    $currentBatchJobs | Wait-Job | Out-Null
    
    # Check for failures in this batch
    $failed = $currentBatchJobs | Where-Object { $_.State -ne 'Completed' }
    if ($failed) {
        Write-Host "  WARNING: Some jobs in this batch failed." -ForegroundColor Red
    } else {
        Write-Host "  Batch complete." -ForegroundColor Green
    }
    
    # Small delay to be nice to API
    Start-Sleep -Seconds 2
}

# Merge results again
Write-Host "`nMerging all results..." -ForegroundColor Cyan
$results = Get-ChildItem $tempDir -Filter "*.csv"
if ($results) {
    $merged = $results | ForEach-Object { Import-Csv $_.FullName }
    $merged | Export-Csv $finalOutput -NoTypeInformation
    Write-Host "Success! All results merged into $finalOutput" -ForegroundColor Green
    Write-Host "Total rows: $($merged.Count)"
} else {
    Write-Host "No results found to merge." -ForegroundColor Red
}
