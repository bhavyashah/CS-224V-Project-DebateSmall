# Baseline vs Detailed Prompts Test Script (PARALLEL - BATCHED)
# Runs 40 debate matchups: 10 motions × 2 models (4o, 4o-mini) × 2 directions (forward + reverse)
# Executes in batches of 10 parallel debates to avoid API rate limits
#
# For each motion and model:
#   - Forward: detailed_prompts (Prop) vs baseline (Opp)
#   - Reverse: baseline (Prop) vs detailed_prompts (Opp)
#
# Prerequisites:
#   - Python environment with required packages (dspy-ai, pandas, python-dotenv)
#   - .env file with OPENAI_API_KEY in the Main folder
#   - motions.txt in the Main folder
#
# Usage: Run this script from the baseline_vs_detailed_prompts folder
#   .\run_baseline_vs_detailed_tests.ps1

# Get the script's directory and the Main folder (2 levels up: Tests -> Main)
$ScriptDir = $PSScriptRoot
$TestsDir = Split-Path -Parent $ScriptDir
$MainDir = Split-Path -Parent $TestsDir

Write-Host "=== Baseline vs Detailed Prompts Experiment (PARALLEL) ===" -ForegroundColor Cyan
Write-Host "Running 40 debate matchups (10 motions x 2 models x 2 directions)" -ForegroundColor Cyan
Write-Host "Executing in batches of 10 parallel debates" -ForegroundColor Cyan
Write-Host "Results will be saved to: $ScriptDir" -ForegroundColor Cyan
Write-Host ""

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
$batchSize = 10
$totalDebates = 40

# Build list of all debate configurations
$allDebates = @()
foreach ($model in $models) {
    $motionIndex = 0
    foreach ($motion in $motions) {
        $motionIndex++
        
        # Forward: detailed_prompts (Prop) vs baseline (Opp)
        $allDebates += @{
            Name = "${model}_M${motionIndex}_fwd"
            Model = $model
            MotionIndex = $motionIndex
            Motion = $motion
            PropArch = "detailed_prompts"
            OppArch = "baseline"
            OutputFile = "$ScriptDir\${model}_motion${motionIndex}_forward_detailed_vs_baseline.csv"
            Description = "$model - Motion $motionIndex - Forward (detailed_prompts vs baseline)"
        }
        
        # Reverse: baseline (Prop) vs detailed_prompts (Opp)
        $allDebates += @{
            Name = "${model}_M${motionIndex}_rev"
            Model = $model
            MotionIndex = $motionIndex
            Motion = $motion
            PropArch = "baseline"
            OppArch = "detailed_prompts"
            OutputFile = "$ScriptDir\${model}_motion${motionIndex}_reverse_baseline_vs_detailed.csv"
            Description = "$model - Motion $motionIndex - Reverse (baseline vs detailed_prompts)"
        }
    }
}

Write-Host "Total debates to run: $($allDebates.Count)" -ForegroundColor Cyan
Write-Host ""

# Process in batches
$batchNumber = 0
$completedTotal = 0

for ($i = 0; $i -lt $allDebates.Count; $i += $batchSize) {
    $batchNumber++
    $batchEnd = [Math]::Min($i + $batchSize, $allDebates.Count)
    $currentBatch = $allDebates[$i..($batchEnd - 1)]
    
    Write-Host "========================================" -ForegroundColor Magenta
    Write-Host "BATCH $batchNumber : Starting $($currentBatch.Count) debates in parallel..." -ForegroundColor Magenta
    Write-Host "========================================" -ForegroundColor Magenta
    
    # Start all jobs in this batch
    $jobs = @()
    foreach ($debate in $currentBatch) {
        Write-Host "  Starting: $($debate.Description)" -ForegroundColor Yellow
        
        $jobs += Start-Job -Name $debate.Name -ScriptBlock {
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
        } -ArgumentList $MainDir, $debate.Model, $debate.PropArch, $debate.OppArch, $debate.Motion, $debate.OutputFile
    }
    
    Write-Host ""
    Write-Host "Waiting for batch $batchNumber to complete..." -ForegroundColor Cyan
    
    # Wait for all jobs in this batch to complete
    $jobs | Wait-Job | Out-Null
    
    # Check results
    foreach ($job in $jobs) {
        $completedTotal++
        if ($job.State -eq "Completed") {
            Write-Host "  [OK] $($job.Name) completed ($completedTotal/$totalDebates total)" -ForegroundColor Green
        }
        else {
            Write-Host "  [FAIL] $($job.Name) FAILED ($completedTotal/$totalDebates total)" -ForegroundColor Red
            Receive-Job -Job $job
        }
    }
    
    # Clean up jobs from this batch
    $jobs | Remove-Job -Force
    
    Write-Host ""
    Write-Host "Batch $batchNumber complete! ($completedTotal/$totalDebates debates done)" -ForegroundColor Green
    Write-Host ""
    
    # Small delay between batches to let API rate limits reset
    if ($batchEnd -lt $allDebates.Count) {
        Write-Host "Pausing 10 seconds before next batch to respect API rate limits..." -ForegroundColor DarkYellow
        Start-Sleep -Seconds 10
    }
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "=== All Debates Complete ===" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host "Total debates run: $completedTotal" -ForegroundColor Green
Write-Host ""

# --- MERGE ALL CSV FILES INTO ONE CONSOLIDATED FILE ---
Write-Host "Merging all CSV files into consolidated results..." -ForegroundColor Cyan

$consolidatedFile = "$ScriptDir\baseline_vs_detailed_ALL_RESULTS.csv"
$csvFiles = Get-ChildItem -Path $ScriptDir -Filter "*.csv" | Where-Object { $_.Name -ne "baseline_vs_detailed_ALL_RESULTS.csv" }

if ($csvFiles.Count -gt 0) {
    $allData = @()
    $headerWritten = $false
    
    foreach ($csvFile in $csvFiles) {
        $content = Import-Csv -Path $csvFile.FullName
        if ($content) {
            $allData += $content
        }
    }
    
    if ($allData.Count -gt 0) {
        $allData | Export-Csv -Path $consolidatedFile -NoTypeInformation
        Write-Host "  [OK] Merged $($csvFiles.Count) CSV files into: baseline_vs_detailed_ALL_RESULTS.csv" -ForegroundColor Green
        Write-Host "  Total rows in consolidated file: $($allData.Count)" -ForegroundColor Green
    }
    else {
        Write-Host "  [WARN] No data found in CSV files to merge" -ForegroundColor Yellow
    }
}
else {
    Write-Host "  [WARN] No CSV files found to merge" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "=== Experiment Complete ===" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host "Individual results: $ScriptDir\*.csv" -ForegroundColor Green
Write-Host "Consolidated results: $consolidatedFile" -ForegroundColor Green
