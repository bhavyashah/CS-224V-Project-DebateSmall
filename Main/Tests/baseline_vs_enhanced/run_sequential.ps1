# Run Final 13 Missing Debates - Sequential Version
# This version runs debates one at a time for maximum reliability

$ScriptDir = $PSScriptRoot
$TestsDir = Split-Path -Parent $ScriptDir
$MainDir = Split-Path -Parent $TestsDir
$ConsolidatedFile = "$ScriptDir\baseline_vs_enhanced_ALL_RESULTS.csv"

Write-Host "=== Running Final Missing Debates (Sequential) ===" -ForegroundColor Cyan
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

# Get existing debates from CSV
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
    Write-Host "Found $($csv.Count) existing debates"
}

# Build list of missing debates
$missingDebates = @()
$models = @("4o", "4o-mini")

foreach ($model in $models) {
    $motionIndex = 0
    foreach ($motion in $motions) {
        $motionIndex++
        $motionPrefix = $motion.Substring(0, 40)
        
        # Forward: enhanced prop vs baseline opp
        $key = "$model|enhanced|$motionPrefix"
        if (-not $existingDebates.ContainsKey($key)) {
            $missingDebates += @{
                Model = $model
                MotionIndex = $motionIndex
                Motion = $motion
                PropArch = "enhanced"
                OppArch = "baseline"
                Name = "${model}_M${motionIndex}_forward"
            }
        }
        
        # Reverse: baseline prop vs enhanced opp
        $key = "$model|baseline|$motionPrefix"
        if (-not $existingDebates.ContainsKey($key)) {
            $missingDebates += @{
                Model = $model
                MotionIndex = $motionIndex
                Motion = $motion
                PropArch = "baseline"
                OppArch = "enhanced"
                Name = "${model}_M${motionIndex}_reverse"
            }
        }
    }
}

Write-Host "Missing debates: $($missingDebates.Count)"
Write-Host ""

if ($missingDebates.Count -eq 0) {
    Write-Host "All 40 debates complete!" -ForegroundColor Green
    exit 0
}

# Run each debate sequentially
$completed = 0
$total = $missingDebates.Count

foreach ($debate in $missingDebates) {
    $completed++
    $tempFile = "$ScriptDir\temp_$($debate.Name).csv"
    
    Write-Host "[$completed/$total] Running: $($debate.Name) ($($debate.PropArch) vs $($debate.OppArch))" -ForegroundColor Yellow
    
    # Run the debate
    Push-Location $MainDir
    python Bhavya_All_Four_Architectures.py `
        -t 3 `
        -pm $debate.Model `
        -om $debate.Model `
        -pa $debate.PropArch `
        -oa $debate.OppArch `
        -jm o3 `
        -m $debate.Motion `
        -o $tempFile
    Pop-Location
    
    # Check if output was created and merge
    if (Test-Path $tempFile) {
        Write-Host "  [OK] Completed - merging to consolidated file" -ForegroundColor Green
        
        # Append to consolidated file
        $newRow = Import-Csv $tempFile
        if (Test-Path $ConsolidatedFile) {
            $existingRows = @(Import-Csv $ConsolidatedFile)
            $allRows = $existingRows + $newRow
        } else {
            $allRows = @($newRow)
        }
        $allRows | Export-Csv -Path $ConsolidatedFile -NoTypeInformation
        
        # Cleanup temp file
        Remove-Item $tempFile -Force
    } else {
        Write-Host "  [FAIL] No output file created" -ForegroundColor Red
    }
    
    Write-Host ""
}

# Final count
$finalCsv = Import-Csv $ConsolidatedFile
Write-Host "=== COMPLETE ===" -ForegroundColor Green
Write-Host "Total debates in consolidated file: $($finalCsv.Count)"
