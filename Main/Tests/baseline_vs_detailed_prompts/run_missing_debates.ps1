# Run Missing Debates Script
# Runs only the 18 debates that failed in the previous run
# Results append to baseline_vs_detailed_ALL_RESULTS.csv

$ScriptDir = $PSScriptRoot
$TestsDir = Split-Path -Parent $ScriptDir
$MainDir = Split-Path -Parent $TestsDir
$ConsolidatedFile = "$ScriptDir\baseline_vs_detailed_ALL_RESULTS.csv"

Write-Host "=== Running 18 Missing Debates ===" -ForegroundColor Cyan
Write-Host "Results will append to: $ConsolidatedFile" -ForegroundColor Cyan
Write-Host ""

# Define motions (same as original script)
$motions = @(
    "This House Believes that developing countries should prioritise service led economic growth over manufacturing led economic growth.",
    "This House regrets the norm of association between sex and romantic love.",
    "This House believes that China should pursue aggressive economic stimulus policies (e.g., injecting central bank funds directly into the economy at large scale, providing stimulus checks).",
    "This House Opposes the narrative that power tends to corrupt.",
    "This House opposes the expectation that romantic partners should be significant support systems of each other's mental health.",
    "This House would heavily ease labour regulations in times of economic crisis (e.g., heavily reducing/removing the minimum wage, relaxing safety laws, etc.).",
    "This House regrets the glorification of the career longevity of dominant sportspersons (e.g., Lebron James, Tom Brady, Cristiano Ronaldo).",
    "This House believes that works of modern fictional media should not portray members of an oppressed minority group (such as LGBTQ+ or minority ethnicity groups) as villains.",
    "This House opposes the norm to prefer the natural to the artificial.",
    "This House believes that education systems should over-inflate children's academic self-perception (e.g., providing overwhelmingly positive feedback, avoiding fail grades, etc.)"
)

# Missing debates identified from file analysis:
# 4o model missing (12 debates):
#   - motion1 fwd & rev
#   - motion2 fwd (rev exists)
#   - motion3 fwd (rev exists)
#   - motion4 fwd & rev
#   - motion6 fwd & rev
#   - motion7 rev (fwd exists)
#   - motion8 rev (fwd exists)
#   - motion10 fwd & rev
#
# 4o-mini model missing (6 debates):
#   - motion2 fwd (rev exists)
#   - motion4 fwd (rev exists)
#   - motion5 rev (fwd exists)
#   - motion7 rev (fwd exists)
#   - motion9 fwd (rev exists)
#   - motion10 fwd (rev exists)

$missingDebates = @(
    # 4o missing debates
    @{ Model = "4o"; MotionIndex = 1; Direction = "forward"; PropArch = "detailed_prompts"; OppArch = "baseline" },
    @{ Model = "4o"; MotionIndex = 1; Direction = "reverse"; PropArch = "baseline"; OppArch = "detailed_prompts" },
    @{ Model = "4o"; MotionIndex = 2; Direction = "forward"; PropArch = "detailed_prompts"; OppArch = "baseline" },
    @{ Model = "4o"; MotionIndex = 3; Direction = "forward"; PropArch = "detailed_prompts"; OppArch = "baseline" },
    @{ Model = "4o"; MotionIndex = 4; Direction = "forward"; PropArch = "detailed_prompts"; OppArch = "baseline" },
    @{ Model = "4o"; MotionIndex = 4; Direction = "reverse"; PropArch = "baseline"; OppArch = "detailed_prompts" },
    @{ Model = "4o"; MotionIndex = 6; Direction = "forward"; PropArch = "detailed_prompts"; OppArch = "baseline" },
    @{ Model = "4o"; MotionIndex = 6; Direction = "reverse"; PropArch = "baseline"; OppArch = "detailed_prompts" },
    @{ Model = "4o"; MotionIndex = 7; Direction = "reverse"; PropArch = "baseline"; OppArch = "detailed_prompts" },
    @{ Model = "4o"; MotionIndex = 8; Direction = "reverse"; PropArch = "baseline"; OppArch = "detailed_prompts" },
    @{ Model = "4o"; MotionIndex = 10; Direction = "forward"; PropArch = "detailed_prompts"; OppArch = "baseline" },
    @{ Model = "4o"; MotionIndex = 10; Direction = "reverse"; PropArch = "baseline"; OppArch = "detailed_prompts" },
    
    # 4o-mini missing debates
    @{ Model = "4o-mini"; MotionIndex = 2; Direction = "forward"; PropArch = "detailed_prompts"; OppArch = "baseline" },
    @{ Model = "4o-mini"; MotionIndex = 4; Direction = "forward"; PropArch = "detailed_prompts"; OppArch = "baseline" },
    @{ Model = "4o-mini"; MotionIndex = 5; Direction = "reverse"; PropArch = "baseline"; OppArch = "detailed_prompts" },
    @{ Model = "4o-mini"; MotionIndex = 7; Direction = "reverse"; PropArch = "baseline"; OppArch = "detailed_prompts" },
    @{ Model = "4o-mini"; MotionIndex = 9; Direction = "forward"; PropArch = "detailed_prompts"; OppArch = "baseline" },
    @{ Model = "4o-mini"; MotionIndex = 10; Direction = "forward"; PropArch = "detailed_prompts"; OppArch = "baseline" }
)

Write-Host "Total missing debates to run: $($missingDebates.Count)" -ForegroundColor Yellow
Write-Host ""

# Run all 18 in parallel (since it's fewer than before, should be safe)
$jobs = @()

foreach ($debate in $missingDebates) {
    $motionIndex = $debate.MotionIndex
    $motion = $motions[$motionIndex - 1]
    $model = $debate.Model
    $direction = $debate.Direction
    $propArch = $debate.PropArch
    $oppArch = $debate.OppArch
    
    $jobName = "${model}_M${motionIndex}_${direction}"
    Write-Host "  Starting: $jobName ($propArch vs $oppArch)" -ForegroundColor Yellow
    
    $jobs += Start-Job -Name $jobName -ScriptBlock {
        param($MainDir, $Model, $PropArch, $OppArch, $Motion, $OutputFile)
        python "$MainDir\Bhavya_All_Four_Architectures.py" `
            -t 3 `
            -pm $Model `
            -om $Model `
            -pa $PropArch `
            -oa $OppArch `
            -jm o3 `
            -m $Motion `
            -o $OutputFile
    } -ArgumentList $MainDir, $model, $propArch, $oppArch, $motion, $ConsolidatedFile
}

Write-Host ""
Write-Host "All $($jobs.Count) jobs started. Waiting for completion..." -ForegroundColor Cyan
Write-Host ""

# Wait for all jobs
$jobs | Wait-Job | Out-Null

# Check results
$successCount = 0
$failCount = 0

foreach ($job in $jobs) {
    if ($job.State -eq "Completed") {
        $successCount++
        Write-Host "  [OK] $($job.Name) completed" -ForegroundColor Green
    }
    else {
        $failCount++
        Write-Host "  [FAIL] $($job.Name) FAILED" -ForegroundColor Red
        Write-Host "  Error output:" -ForegroundColor Red
        Receive-Job -Job $job | Write-Host -ForegroundColor Red
    }
}

# Clean up jobs
$jobs | Remove-Job -Force

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "=== Missing Debates Complete ===" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host "Successful: $successCount / $($missingDebates.Count)" -ForegroundColor Green
Write-Host "Failed: $failCount / $($missingDebates.Count)" -ForegroundColor $(if ($failCount -gt 0) { "Red" } else { "Green" })
Write-Host ""
Write-Host "Results appended to: $ConsolidatedFile" -ForegroundColor Cyan

# Show final row count
if (Test-Path $ConsolidatedFile) {
    $rowCount = (Import-Csv $ConsolidatedFile).Count
    Write-Host "Total rows in consolidated file: $rowCount" -ForegroundColor Cyan
}
