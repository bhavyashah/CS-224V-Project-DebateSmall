# Verification Test Script for All Four Debate Architectures (PARALLEL VERSION)
# This script runs 2 test debates IN PARALLEL (1-turn, 4o-mini vs 4o-mini) to verify all 4 architectures work
#
# Prerequisites:
#   - Python environment with required packages (dspy-ai, pandas, python-dotenv)
#   - .env file with OPENAI_API_KEY in the Main folder
#   - logic_store.json in the Main folder (required for schema_guided architecture)
#
# Usage: Run this script from the architecture_verification_test folder
#   .\run_verification_tests.ps1

# Get the script's directory and the Main folder (2 levels up: Tests -> Main)
$ScriptDir = $PSScriptRoot
$TestsDir = Split-Path -Parent $ScriptDir
$MainDir = Split-Path -Parent $TestsDir

Write-Host "=== Debate Architecture Verification Tests (PARALLEL) ===" -ForegroundColor Cyan
Write-Host "Running 2 test debates IN PARALLEL with 1 turn each using gpt-4o-mini" -ForegroundColor Cyan
Write-Host "Results will be saved to: $ScriptDir" -ForegroundColor Cyan
Write-Host ""

# Define the motion (shared across tests)
$Motion = "This House believes that developing countries should prioritize economic growth over environmental protection."

# Define jobs array to track all parallel jobs
$Jobs = @()

# Test 1: baseline (Prop) vs enhanced (Opp) - Start as background job
Write-Host "Starting Test 1: baseline vs enhanced..." -ForegroundColor Yellow
$Jobs += Start-Job -Name "Test1_baseline_vs_enhanced" -ScriptBlock {
    param($MainDir, $ScriptDir, $Motion)
    python "$MainDir\Bhavya_All_Four_Architectures.py" `
        -t 1 `
        -pm 4o-mini `
        -om 4o-mini `
        -pa baseline `
        -oa enhanced `
        -jm o3 `
        -m $Motion `
        -o "$ScriptDir\verification_test1_baseline_vs_enhanced.csv"
} -ArgumentList $MainDir, $ScriptDir, $Motion

# Test 2: detailed_prompts (Prop) vs schema_guided (Opp) - Start as background job
Write-Host "Starting Test 2: detailed_prompts vs schema_guided..." -ForegroundColor Yellow
$Jobs += Start-Job -Name "Test2_detailed_vs_schema" -ScriptBlock {
    param($MainDir, $ScriptDir, $Motion)
    python "$MainDir\Bhavya_All_Four_Architectures.py" `
        -t 1 `
        -pm 4o-mini `
        -om 4o-mini `
        -pa detailed_prompts `
        -oa schema_guided `
        -jm o3 `
        -m $Motion `
        -o "$ScriptDir\verification_test2_detailed_vs_schema.csv"
} -ArgumentList $MainDir, $ScriptDir, $Motion

Write-Host ""
Write-Host "All $($Jobs.Count) debates started in parallel. Waiting for completion..." -ForegroundColor Cyan
Write-Host ""

# Wait for all jobs to complete and show progress
$CompletedJobs = @()
while ($CompletedJobs.Count -lt $Jobs.Count) {
    foreach ($Job in $Jobs) {
        if ($Job.State -eq "Completed" -and $Job.Name -notin $CompletedJobs) {
            $CompletedJobs += $Job.Name
            Write-Host "✓ $($Job.Name) completed ($($CompletedJobs.Count)/$($Jobs.Count))" -ForegroundColor Green
        }
        elseif ($Job.State -eq "Failed" -and $Job.Name -notin $CompletedJobs) {
            $CompletedJobs += $Job.Name
            Write-Host "✗ $($Job.Name) FAILED ($($CompletedJobs.Count)/$($Jobs.Count))" -ForegroundColor Red
        }
    }
    if ($CompletedJobs.Count -lt $Jobs.Count) {
        Start-Sleep -Seconds 2
    }
}

Write-Host ""
Write-Host "=== All Debates Complete ===" -ForegroundColor Green
Write-Host ""

# Display output from each job
foreach ($Job in $Jobs) {
    Write-Host "--- Output from $($Job.Name) ---" -ForegroundColor Cyan
    Receive-Job -Job $Job
    Write-Host ""
}

# Clean up jobs
$Jobs | Remove-Job -Force

Write-Host "=== Verification Complete ===" -ForegroundColor Green
Write-Host "Check the CSV files in this folder for results:" -ForegroundColor Green
Write-Host "  - verification_test1_baseline_vs_enhanced.csv" -ForegroundColor White
Write-Host "  - verification_test2_detailed_vs_schema.csv" -ForegroundColor White
