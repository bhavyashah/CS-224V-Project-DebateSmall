# Baseline vs Enhanced (Multistep) Test Script - PARALLEL VERSION
# Runs 40 debate matchups: 10 motions × 2 models (4o, 4o-mini) × 2 directions (forward + reverse)
# Uses parallel execution with unique temp files to avoid race conditions
#
# For each motion and model:
#   - Forward: enhanced (Prop) vs baseline (Opp)
#   - Reverse: baseline (Prop) vs enhanced (Opp)
#
# Prerequisites:
#   - Python environment with required packages (dspy-ai, pandas, python-dotenv)
#   - .env file with OPENAI_API_KEY in the Main folder
#   - motions.txt in the Main folder
#
# Usage: Run this script from the baseline_vs_enhanced folder
#   .\run_baseline_vs_enhanced_tests.ps1

# Get the script's directory and the Main folder (2 levels up: Tests -> Main)
$ScriptDir = $PSScriptRoot
$TestsDir = Split-Path -Parent $ScriptDir
$MainDir = Split-Path -Parent $TestsDir
$TempDir = "$ScriptDir\temp_parallel"
$ConsolidatedFile = "$ScriptDir\baseline_vs_enhanced_ALL_RESULTS.csv"

Write-Host "=== Baseline vs Enhanced (Multistep) Experiment ===" -ForegroundColor Cyan
Write-Host "Running 40 debate matchups (10 motions x 2 models x 2 directions)" -ForegroundColor Cyan
Write-Host "Using PARALLEL execution with batch size 20" -ForegroundColor Cyan
Write-Host "Results will be saved to: $ConsolidatedFile" -ForegroundColor Cyan
Write-Host ""

# Create temp directory
if (-not (Test-Path $TempDir)) {
    New-Item -ItemType Directory -Path $TempDir | Out-Null
}

# Define motions
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

$models = @("4o", "4o-mini")

# Build list of all 40 debates
$allDebates = @()
$jobIndex = 0

foreach ($model in $models) {
    $motionIndex = 0
    foreach ($motion in $motions) {
        $motionIndex++
        
        # Forward: enhanced (Prop) vs baseline (Opp)
        $jobIndex++
        $allDebates += @{
            Index = $jobIndex
            Model = $model
            MotionIndex = $motionIndex
            Motion = $motion
            Direction = "forward"
            PropArch = "enhanced"
            OppArch = "baseline"
            JobName = "${model}_M${motionIndex}_forward"
        }
        
        # Reverse: baseline (Prop) vs enhanced (Opp)
        $jobIndex++
        $allDebates += @{
            Index = $jobIndex
            Model = $model
            MotionIndex = $motionIndex
            Motion = $motion
            Direction = "reverse"
            PropArch = "baseline"
            OppArch = "enhanced"
            JobName = "${model}_M${motionIndex}_reverse"
        }
    }
}

Write-Host "Total debates to run: $($allDebates.Count)" -ForegroundColor Yellow
Write-Host ""

# Run in batches of 20
$batchSize = 20
$totalBatches = [math]::Ceiling($allDebates.Count / $batchSize)

for ($batchNum = 0; $batchNum -lt $totalBatches; $batchNum++) {
    $startIdx = $batchNum * $batchSize
    $endIdx = [math]::Min($startIdx + $batchSize - 1, $allDebates.Count - 1)
    $batchDebates = $allDebates[$startIdx..$endIdx]
    
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "=== BATCH $($batchNum + 1) of $totalBatches (debates $($startIdx + 1)-$($endIdx + 1)) ===" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""
    
    # Start all jobs in this batch
    $jobs = @()
    
    foreach ($debate in $batchDebates) {
        $tempOutputFile = "$TempDir\temp_$($debate.Index)_$($debate.JobName).csv"
        
        Write-Host "  Starting: $($debate.JobName) ($($debate.PropArch) vs $($debate.OppArch))" -ForegroundColor Yellow
        
        $jobs += Start-Job -Name $debate.JobName -ScriptBlock {
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
        } -ArgumentList $MainDir, $debate.Model, $debate.PropArch, $debate.OppArch, $debate.Motion, $tempOutputFile
    }
    
    Write-Host ""
    Write-Host "Batch $($batchNum + 1): All $($batchDebates.Count) jobs started. Waiting for completion..." -ForegroundColor Cyan
    Write-Host ""
    
    # Wait for all jobs in this batch
    $successful = 0
    $failed = 0
    
    foreach ($job in $jobs) {
        Wait-Job -Job $job | Out-Null
        if ($job.State -eq "Completed") {
            Write-Host "  [OK] $($job.Name) completed" -ForegroundColor Green
            $successful++
        } else {
            Write-Host "  [FAIL] $($job.Name) failed: $($job.State)" -ForegroundColor Red
            $failed++
        }
    }
    
    # Clean up jobs from this batch
    $jobs | Remove-Job
    
    Write-Host ""
    Write-Host "Batch $($batchNum + 1) complete: $successful succeeded, $failed failed" -ForegroundColor Cyan
    Write-Host ""
}

# Merge all temp files into consolidated file
Write-Host "========================================" -ForegroundColor Green
Write-Host "=== MERGING ALL RESULTS ===" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green

$tempFiles = Get-ChildItem $TempDir -Filter "*.csv" -ErrorAction SilentlyContinue
Write-Host "Found $($tempFiles.Count) temp files to merge" -ForegroundColor Yellow

if ($tempFiles.Count -gt 0) {
    $allData = @()
    foreach ($tempFile in $tempFiles) {
        $data = Import-Csv $tempFile.FullName -ErrorAction SilentlyContinue
        if ($data) {
            $allData += $data
            Write-Host "  Added: $($tempFile.Name)" -ForegroundColor Gray
        }
    }
    
    Write-Host ""
    Write-Host "Total rows collected: $($allData.Count)" -ForegroundColor Yellow
    
    # Save consolidated file
    $allData | Export-Csv $ConsolidatedFile -NoTypeInformation
    
    Write-Host ""
    Write-Host "=== EXPERIMENT COMPLETE ===" -ForegroundColor Green
    Write-Host "Total debates: $($allData.Count)" -ForegroundColor Green
    Write-Host "Results saved to: $ConsolidatedFile" -ForegroundColor Green
    
    # Clean up temp directory
    Write-Host ""
    Write-Host "Cleaning up temp files..." -ForegroundColor Gray
    Remove-Item $TempDir -Recurse -Force
    Write-Host "Temp directory removed." -ForegroundColor Gray
} else {
    Write-Host "WARNING: No temp files found! Jobs may have failed." -ForegroundColor Red
}
