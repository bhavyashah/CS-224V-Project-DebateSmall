# Baseline vs Schema Guided Test Script - Sequential with Smart Resume
# Runs 40 debate matchups: 10 motions × 2 models (4o, 4o-mini) × 2 directions (forward + reverse)
#
# For each motion and model:
#   - Forward: schema_guided (Prop) vs baseline (Opp)
#   - Reverse: baseline (Prop) vs schema_guided (Opp)
#
# Features:
#   - Skips debates that already exist in the consolidated file
#   - Merges results into a single consolidated CSV after each debate
#   - Can be safely re-run to complete any missing debates
#
# Prerequisites:
#   - Python environment with required packages (dspy-ai, pandas, python-dotenv)
#   - .env file with OPENAI_API_KEY in the Main folder
#   - logic_store.json in the Main folder (required for schema_guided architecture)
#
# Usage: Run this script from the baseline_vs_schema_guided folder
#   .\run_baseline_vs_schema_guided_tests.ps1

# Get the script's directory and the Main folder (2 levels up: Tests -> Main)
$ScriptDir = $PSScriptRoot
$TestsDir = Split-Path -Parent $ScriptDir
$MainDir = Split-Path -Parent $TestsDir
$ConsolidatedFile = "$ScriptDir\baseline_vs_schema_ALL_RESULTS.csv"

Write-Host "=== Baseline vs Schema Guided Experiment ===" -ForegroundColor Cyan
Write-Host "Running 40 debate matchups (10 motions x 2 models x 2 directions)" -ForegroundColor Cyan
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

# Load existing debates from consolidated file
$existingDebates = @{}
if (Test-Path $ConsolidatedFile) {
    $csv = Import-Csv $ConsolidatedFile
    foreach ($row in $csv) {
        $model = if ($row.prop_model -eq "gpt-4o") { "4o" } else { "4o-mini" }
        $propArch = $row.prop_architecture
        $motionPrefix = $row.motion.Substring(0, 40)
        $key = "$model|$propArch|$motionPrefix"
        $existingDebates[$key] = $true
    }
    Write-Host "Found $($csv.Count) existing debates in consolidated file" -ForegroundColor Green
    Write-Host ""
}

$models = @("4o", "4o-mini")
$debateCount = 0
$skippedCount = 0
$completedCount = 0
$totalDebates = 40

foreach ($model in $models) {
    $motionIndex = 0
    foreach ($motion in $motions) {
        $motionIndex++
        $motionPrefix = $motion.Substring(0, 40)
        
        # Forward: schema_guided (Prop) vs baseline (Opp)
        $debateCount++
        $key = "$model|schema_guided|$motionPrefix"
        if ($existingDebates.ContainsKey($key)) {
            Write-Host "[$debateCount/$totalDebates] SKIP: $model M$motionIndex forward (already exists)" -ForegroundColor Gray
            $skippedCount++
        } else {
            Write-Host "[$debateCount/$totalDebates] Running: $model M$motionIndex forward (schema_guided vs baseline)" -ForegroundColor Yellow
            $tempFile = "$ScriptDir\temp_${model}_M${motionIndex}_forward.csv"
            
            Push-Location $MainDir
            python Bhavya_All_Four_Architectures.py `
                -t 3 `
                -pm $model `
                -om $model `
                -pa schema_guided `
                -oa baseline `
                -jm o3 `
                -m $motion `
                -o $tempFile
            Pop-Location
            
            # Merge to consolidated file
            if (Test-Path $tempFile) {
                $newRow = Import-Csv $tempFile
                if (Test-Path $ConsolidatedFile) {
                    $allRows = @(Import-Csv $ConsolidatedFile) + $newRow
                } else {
                    $allRows = @($newRow)
                }
                $allRows | Export-Csv -Path $ConsolidatedFile -NoTypeInformation
                Remove-Item $tempFile -Force
                Write-Host "  [OK] Merged to consolidated file" -ForegroundColor Green
                $completedCount++
            } else {
                Write-Host "  [FAIL] No output file created" -ForegroundColor Red
            }
        }
        
        # Reverse: baseline (Prop) vs schema_guided (Opp)
        $debateCount++
        $key = "$model|baseline|$motionPrefix"
        if ($existingDebates.ContainsKey($key)) {
            Write-Host "[$debateCount/$totalDebates] SKIP: $model M$motionIndex reverse (already exists)" -ForegroundColor Gray
            $skippedCount++
        } else {
            Write-Host "[$debateCount/$totalDebates] Running: $model M$motionIndex reverse (baseline vs schema_guided)" -ForegroundColor Yellow
            $tempFile = "$ScriptDir\temp_${model}_M${motionIndex}_reverse.csv"
            
            Push-Location $MainDir
            python Bhavya_All_Four_Architectures.py `
                -t 3 `
                -pm $model `
                -om $model `
                -pa baseline `
                -oa schema_guided `
                -jm o3 `
                -m $motion `
                -o $tempFile
            Pop-Location
            
            # Merge to consolidated file
            if (Test-Path $tempFile) {
                $newRow = Import-Csv $tempFile
                if (Test-Path $ConsolidatedFile) {
                    $allRows = @(Import-Csv $ConsolidatedFile) + $newRow
                } else {
                    $allRows = @($newRow)
                }
                $allRows | Export-Csv -Path $ConsolidatedFile -NoTypeInformation
                Remove-Item $tempFile -Force
                Write-Host "  [OK] Merged to consolidated file" -ForegroundColor Green
                $completedCount++
            } else {
                Write-Host "  [FAIL] No output file created" -ForegroundColor Red
            }
        }
    }
}

Write-Host ""
Write-Host "=== Experiment Complete ===" -ForegroundColor Green
Write-Host "Completed: $completedCount new debates" -ForegroundColor Green
Write-Host "Skipped: $skippedCount existing debates" -ForegroundColor Green

# Final count
if (Test-Path $ConsolidatedFile) {
    $finalCsv = Import-Csv $ConsolidatedFile
    Write-Host "Total in consolidated file: $($finalCsv.Count)" -ForegroundColor Cyan
}
Write-Host "Results: $ConsolidatedFile" -ForegroundColor Cyan
