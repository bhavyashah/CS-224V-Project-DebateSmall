# Run all 4 zoo debate matchups in parallel
# Each debate is independent and can run simultaneously

$motion = "This house would ban zoos"
$output = "zoo_debates.csv"
$turns = 3
$arch = "enhanced"
$judge = "o3"

# Delete existing output file to start fresh
if (Test-Path $output) {
    Remove-Item $output
}

Write-Host "=== Starting 4 parallel zoo debates ===" -ForegroundColor Green
Write-Host ""

# Start all 4 debates as background jobs
$job1 = Start-Job -ScriptBlock {
    Set-Location $using:PWD
    & .venv\Scripts\Activate.ps1
    python crossover_debate.py -t $using:turns -pm 4o-mini -om 4o-mini -pa $using:arch -oa $using:arch -jm $using:judge -m $using:motion -o $using:output
}

$job2 = Start-Job -ScriptBlock {
    Set-Location $using:PWD
    & .venv\Scripts\Activate.ps1
    python crossover_debate.py -t $using:turns -pm 4o-mini -om 4o -pa $using:arch -oa $using:arch -jm $using:judge -m $using:motion -o $using:output
}

$job3 = Start-Job -ScriptBlock {
    Set-Location $using:PWD
    & .venv\Scripts\Activate.ps1
    python crossover_debate.py -t $using:turns -pm 4o -om 4o-mini -pa $using:arch -oa $using:arch -jm $using:judge -m $using:motion -o $using:output
}

$job4 = Start-Job -ScriptBlock {
    Set-Location $using:PWD
    & .venv\Scripts\Activate.ps1
    python crossover_debate.py -t $using:turns -pm 4o -om 4o -pa $using:arch -oa $using:arch -jm $using:judge -m $using:motion -o $using:output
}

Write-Host "Job 1: 4o-mini vs 4o-mini (ID: $($job1.Id))" -ForegroundColor Cyan
Write-Host "Job 2: 4o-mini vs 4o (ID: $($job2.Id))" -ForegroundColor Cyan
Write-Host "Job 3: 4o vs 4o-mini (ID: $($job3.Id))" -ForegroundColor Cyan
Write-Host "Job 4: 4o vs 4o (ID: $($job4.Id))" -ForegroundColor Cyan
Write-Host ""

# Wait for all jobs to complete and show progress
$jobs = @($job1, $job2, $job3, $job4)
while ($jobs | Where-Object { $_.State -eq 'Running' }) {
    $completed = ($jobs | Where-Object { $_.State -ne 'Running' }).Count
    $total = $jobs.Count
    Write-Host "`rProgress: $completed/$total debates completed" -NoNewline -ForegroundColor Yellow
    Start-Sleep -Seconds 5
}

Write-Host "`n"
Write-Host "=== All debates complete! ===" -ForegroundColor Green
Write-Host ""

# Display results from each job
Write-Host "=== Job 1 Output (4o-mini vs 4o-mini) ===" -ForegroundColor Magenta
Receive-Job -Job $job1
Write-Host ""

Write-Host "=== Job 2 Output (4o-mini vs 4o) ===" -ForegroundColor Magenta
Receive-Job -Job $job2
Write-Host ""

Write-Host "=== Job 3 Output (4o vs 4o-mini) ===" -ForegroundColor Magenta
Receive-Job -Job $job3
Write-Host ""

Write-Host "=== Job 4 Output (4o vs 4o) ===" -ForegroundColor Magenta
Receive-Job -Job $job4
Write-Host ""

# Clean up jobs
Remove-Job -Job $jobs

Write-Host "All results saved to $output" -ForegroundColor Green
