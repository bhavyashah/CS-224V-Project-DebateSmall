# Run enhanced vs baseline architecture experiments
# 5 motions × 3 models × 2 orientations = 30 debates

$motions = @(
    "This house would ban zoos",
    "This house would make voting mandatory",
    "This house believes that politicians have no right to a private life",
    "This house regrets the narrative that hard work leads to success",
    "This house believes that developing nations should prioritize economic growth over environmental protection"
)

$models = @("4o-mini", "4o", "o1-mini")
$output = "detailed_prompts_only_against_baseline.csv"
$turns = 3
$judge = "o3"

# Delete existing output file to start fresh
if (Test-Path $output) {
    Remove-Item $output
}

Write-Host "=== Starting 30 parallel debates ===" -ForegroundColor Green
Write-Host "5 motions × 3 models × 2 orientations (enhanced vs baseline)" -ForegroundColor Cyan
Write-Host ""

$jobs = @()
$jobCounter = 1

foreach ($motion in $motions) {
    foreach ($model in $models) {
        # Debate 1: Enhanced Prop vs Baseline Opp
        $job = Start-Job -ScriptBlock {
            Set-Location $using:PWD
            & .venv\Scripts\Activate.ps1
            python crossover_debate.py -t $using:turns -pm $using:model -om $using:model -pa enhanced -oa baseline -jm $using:judge -m $using:motion -o $using:output
        }
        $jobs += $job
        Write-Host "Job $jobCounter : $model enhanced(P) vs $model baseline(O) - '$($motion.Substring(0, [Math]::Min(40, $motion.Length)))...' (ID: $($job.Id))" -ForegroundColor Yellow
        $jobCounter++

        # Debate 2: Baseline Prop vs Enhanced Opp
        $job = Start-Job -ScriptBlock {
            Set-Location $using:PWD
            & .venv\Scripts\Activate.ps1
            python crossover_debate.py -t $using:turns -pm $using:model -om $using:model -pa baseline -oa enhanced -jm $using:judge -m $using:motion -o $using:output
        }
        $jobs += $job
        Write-Host "Job $jobCounter : $model baseline(P) vs $model enhanced(O) - '$($motion.Substring(0, [Math]::Min(40, $motion.Length)))...' (ID: $($job.Id))" -ForegroundColor Yellow
        $jobCounter++
    }
}

Write-Host ""
Write-Host "Total jobs started: $($jobs.Count)" -ForegroundColor Green
Write-Host ""

# Wait for all jobs to complete and show progress
$startTime = Get-Date
while ($jobs | Where-Object { $_.State -eq 'Running' }) {
    $completed = ($jobs | Where-Object { $_.State -ne 'Running' }).Count
    $running = ($jobs | Where-Object { $_.State -eq 'Running' }).Count
    $elapsed = (Get-Date) - $startTime
    Write-Host "`r[$(Get-Date -Format 'HH:mm:ss')] Progress: $completed/$($jobs.Count) completed, $running running (Elapsed: $($elapsed.ToString('hh\:mm\:ss')))" -NoNewline -ForegroundColor Cyan
    Start-Sleep -Seconds 3
}

$totalTime = (Get-Date) - $startTime
Write-Host "`n"
Write-Host "=== All debates complete! ===" -ForegroundColor Green
Write-Host "Total time: $($totalTime.ToString('hh\:mm\:ss'))" -ForegroundColor Magenta
Write-Host ""

# Check for failed jobs
$failed = $jobs | Where-Object { $_.State -eq 'Failed' }
if ($failed.Count -gt 0) {
    Write-Host "WARNING: $($failed.Count) jobs failed!" -ForegroundColor Red
    foreach ($job in $failed) {
        Write-Host "Failed Job ID: $($job.Id)" -ForegroundColor Red
        Receive-Job -Job $job
    }
}

# Clean up jobs
Remove-Job -Job $jobs

Write-Host "All results saved to $output" -ForegroundColor Green
Write-Host ""

# Show summary
if (Test-Path $output) {
    $results = Import-Csv $output
    Write-Host "=== Results Summary ===" -ForegroundColor Magenta
    Write-Host "Total debates recorded: $($results.Count)" -ForegroundColor Cyan
    
    # Count by motion
    Write-Host "`nDebates per motion:" -ForegroundColor Yellow
    $results | Group-Object motion | ForEach-Object {
        Write-Host "  $($_.Name): $($_.Count) debates"
    }
    
    # Count by model
    Write-Host "`nDebates per model:" -ForegroundColor Yellow
    $results | Group-Object prop_model | ForEach-Object {
        Write-Host "  $($_.Name): $($_.Count) debates"
    }
    
    # Architecture wins
    Write-Host "`nArchitecture performance:" -ForegroundColor Yellow
    $enhancedWins = 0
    $baselineWins = 0
    foreach ($row in $results) {
        if (($row.prop_architecture -eq 'enhanced' -and $row.winner -eq 'Proposition') -or
            ($row.opp_architecture -eq 'enhanced' -and $row.winner -eq 'Opposition')) {
            $enhancedWins++
        } else {
            $baselineWins++
        }
    }
    Write-Host "  Enhanced wins: $enhancedWins" -ForegroundColor Green
    Write-Host "  Baseline wins: $baselineWins" -ForegroundColor Red
}
