# Run Final 13 Missing Debates
# Uses batch size of 5 for extra reliability

$ScriptDir = $PSScriptRoot
$TestsDir = Split-Path -Parent $ScriptDir
$MainDir = Split-Path -Parent $TestsDir
$TempDir = "$ScriptDir\temp_final13"
$ConsolidatedFile = "$ScriptDir\baseline_vs_enhanced_ALL_RESULTS.csv"

Write-Host "=== Running Final 13 Missing Debates ===" -ForegroundColor Cyan
Write-Host "Using batch size of 5 for reliability" -ForegroundColor Cyan
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
    Write-Host "Found $($csv.Count) existing debates in consolidated file"
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
                Direction = "forward"
                PropArch = "enhanced"
                OppArch = "baseline"
                JobName = "${model}_M${motionIndex}_forward"
            }
        }
        
        # Reverse: baseline prop vs enhanced opp
        $key = "$model|baseline|$motionPrefix"
        if (-not $existingDebates.ContainsKey($key)) {
            $missingDebates += @{
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
}

Write-Host "Missing debates to run: $($missingDebates.Count)"
Write-Host ""

if ($missingDebates.Count -eq 0) {
    Write-Host "All 40 debates complete!" -ForegroundColor Green
    exit 0
}

# Run in batches of 5
$batchSize = 5
$totalBatches = [math]::Ceiling($missingDebates.Count / $batchSize)
$globalJobIndex = 0

for ($batch = 0; $batch -lt $totalBatches; $batch++) {
    Write-Host "========================================"
    Write-Host "=== BATCH $($batch + 1) of $totalBatches ===" -ForegroundColor Yellow
    Write-Host "========================================"
    Write-Host ""
    
    $start = $batch * $batchSize
    $end = [math]::Min($start + $batchSize, $missingDebates.Count)
    $batchDebates = $missingDebates[$start..($end-1)]
    
    $jobs = @()
    
    foreach ($debate in $batchDebates) {
        $globalJobIndex++
        $tempFile = "$TempDir\temp_${globalJobIndex}_$($debate.JobName).csv"
        $modelShort = $debate.Model  # Use 4o or 4o-mini directly
        $modelFull = if ($debate.Model -eq "4o") { "gpt-4o" } else { "gpt-4o-mini" }  # For display
        $direction = if ($debate.Direction -eq "forward") { "enhanced vs baseline" } else { "baseline vs enhanced" }
        
        Write-Host "  Starting: $($debate.JobName) ($direction)" -ForegroundColor Gray
        
        $job = Start-Job -ScriptBlock {
            param($MainDir, $Motion, $PropArch, $OppArch, $ModelShort, $TempFile)
            Set-Location $MainDir
            conda activate base 2>$null
            python Bhavya_All_Four_Architectures.py `
                --motion $Motion `
                --prop-architecture $PropArch `
                --opp-architecture $OppArch `
                --prop-model $ModelShort `
                --opp-model $ModelShort `
                --num-turns 3 `
                --output $TempFile 2>&1
        } -ArgumentList $MainDir, $debate.Motion, $debate.PropArch, $debate.OppArch, $modelShort, $tempFile
        
        $jobs += @{
            Job = $job
            Name = $debate.JobName
            TempFile = $tempFile
        }
    }
    
    Write-Host ""
    Write-Host "Batch $($batch + 1): All $($jobs.Count) jobs started. Waiting..." -ForegroundColor Cyan
    Write-Host ""
    
    # Wait for all jobs in batch
    $succeeded = 0
    $failed = 0
    
    foreach ($jobInfo in $jobs) {
        $result = Wait-Job -Job $jobInfo.Job
        Remove-Job -Job $jobInfo.Job
        
        if (Test-Path $jobInfo.TempFile) {
            Write-Host "  [OK] $($jobInfo.Name) completed" -ForegroundColor Green
            $succeeded++
        } else {
            Write-Host "  [FAIL] $($jobInfo.Name) - no output file" -ForegroundColor Red
            $failed++
        }
    }
    
    Write-Host ""
    Write-Host "Batch $($batch + 1) complete: $succeeded succeeded, $failed failed" -ForegroundColor Cyan
    Write-Host ""
    
    # Small delay between batches
    if ($batch -lt $totalBatches - 1) {
        Start-Sleep -Seconds 5
    }
}

# Merge results
Write-Host "========================================"
Write-Host "=== MERGING RESULTS ===" -ForegroundColor Yellow
Write-Host "========================================"

$tempFiles = Get-ChildItem "$TempDir\*.csv" -ErrorAction SilentlyContinue
Write-Host "Found $($tempFiles.Count) new temp files"

$newRows = @()
foreach ($file in $tempFiles) {
    $content = Import-Csv $file.FullName
    if ($content) {
        $newRows += $content
        Write-Host "  Added: $($file.Name)"
    }
}

# Load existing and merge
$existingRows = @()
if (Test-Path $ConsolidatedFile) {
    $existingRows = @(Import-Csv $ConsolidatedFile)
}

Write-Host "New rows: $($newRows.Count)"
Write-Host "Existing rows: $($existingRows.Count)"

# Combine and save
$allRows = $existingRows + $newRows
$allRows | Export-Csv -Path $ConsolidatedFile -NoTypeInformation

Write-Host ""
Write-Host "=== COMPLETE ===" -ForegroundColor Green
Write-Host "Total debates: $($allRows.Count)"
Write-Host "Results: $ConsolidatedFile"

# Cleanup temp files
if ($tempFiles.Count -gt 0) {
    Remove-Item "$TempDir\*.csv" -Force
    Remove-Item $TempDir -Force
    Write-Host "Temp files cleaned up."
}
