# Run Missing Debates Script v2
# Fixed version: Each job writes to unique file, merge after all complete
# This avoids race conditions from parallel writes

$ScriptDir = $PSScriptRoot
$TestsDir = Split-Path -Parent $ScriptDir
$MainDir = Split-Path -Parent $TestsDir
$ConsolidatedFile = "$ScriptDir\baseline_vs_detailed_ALL_RESULTS.csv"
$TempDir = "$ScriptDir\temp_missing_v2"

Write-Host "=== Running 18 Missing Debates (v2 - Fixed) ===" -ForegroundColor Cyan
Write-Host "Each job writes to unique temp file to avoid race conditions" -ForegroundColor Cyan
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

# Missing debates - each with unique temp file
$missingDebates = @(
    # 4o missing debates (12)
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
    
    # 4o-mini missing debates (6)
    @{ Model = "4o-mini"; MotionIndex = 2; Direction = "forward"; PropArch = "detailed_prompts"; OppArch = "baseline" },
    @{ Model = "4o-mini"; MotionIndex = 4; Direction = "forward"; PropArch = "detailed_prompts"; OppArch = "baseline" },
    @{ Model = "4o-mini"; MotionIndex = 5; Direction = "reverse"; PropArch = "baseline"; OppArch = "detailed_prompts" },
    @{ Model = "4o-mini"; MotionIndex = 7; Direction = "reverse"; PropArch = "baseline"; OppArch = "detailed_prompts" },
    @{ Model = "4o-mini"; MotionIndex = 9; Direction = "forward"; PropArch = "detailed_prompts"; OppArch = "baseline" },
    @{ Model = "4o-mini"; MotionIndex = 10; Direction = "forward"; PropArch = "detailed_prompts"; OppArch = "baseline" }
)

Write-Host "Total missing debates to run: $($missingDebates.Count)" -ForegroundColor Yellow
Write-Host "Temp files will be created in: $TempDir" -ForegroundColor Yellow
Write-Host ""

# Start all jobs - each writes to UNIQUE temp file
$jobs = @()
$jobIndex = 0

foreach ($debate in $missingDebates) {
    $jobIndex++
    $motionIndex = $debate.MotionIndex
    $motion = $motions[$motionIndex - 1]
    $model = $debate.Model
    $direction = $debate.Direction
    $propArch = $debate.PropArch
    $oppArch = $debate.OppArch
    
    $jobName = "${model}_M${motionIndex}_${direction}"
    # UNIQUE output file per job - no race conditions!
    $tempOutputFile = "$TempDir\temp_${jobIndex}_${jobName}.csv"
    
    Write-Host "  Starting: $jobName -> temp file #$jobIndex" -ForegroundColor Yellow
    
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
    } -ArgumentList $MainDir, $model, $propArch, $oppArch, $motion, $tempOutputFile
}

Write-Host ""
Write-Host "All 18 jobs started. Waiting for completion..." -ForegroundColor Cyan
Write-Host ""

# Wait and report status
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

# Clean up jobs
$jobs | Remove-Job

Write-Host ""
Write-Host "========================================"
Write-Host "=== All Jobs Finished ===" -ForegroundColor Cyan
Write-Host "========================================"
Write-Host "Successful: $successful / $($missingDebates.Count)"
Write-Host "Failed: $failed / $($missingDebates.Count)"
Write-Host ""

# Now merge all temp files into consolidated file
Write-Host "=== Merging Results ===" -ForegroundColor Cyan

$tempFiles = Get-ChildItem $TempDir -Filter "*.csv" -ErrorAction SilentlyContinue
Write-Host "Found $($tempFiles.Count) temp files to merge" -ForegroundColor Yellow

if ($tempFiles.Count -gt 0) {
    # Collect all data from temp files
    $newData = @()
    foreach ($tempFile in $tempFiles) {
        $data = Import-Csv $tempFile.FullName -ErrorAction SilentlyContinue
        if ($data) {
            $newData += $data
            Write-Host "  Added data from: $($tempFile.Name)" -ForegroundColor Gray
        }
    }
    
    Write-Host "Total new rows from temp files: $($newData.Count)" -ForegroundColor Yellow
    
    # Load existing consolidated file if it exists
    $existingData = @()
    if (Test-Path $ConsolidatedFile) {
        $existingData = @(Import-Csv $ConsolidatedFile)
        Write-Host "Existing rows in consolidated file: $($existingData.Count)" -ForegroundColor Yellow
    }
    
    # Combine and save
    $allData = $existingData + $newData
    $allData | Export-Csv $ConsolidatedFile -NoTypeInformation
    
    Write-Host ""
    Write-Host "=== FINAL RESULTS ===" -ForegroundColor Green
    Write-Host "Total rows in consolidated file: $($allData.Count)" -ForegroundColor Green
    Write-Host "Results saved to: $ConsolidatedFile" -ForegroundColor Green
    
    # Clean up temp files
    Write-Host ""
    Write-Host "Cleaning up temp files..." -ForegroundColor Gray
    Remove-Item $TempDir -Recurse -Force
    Write-Host "Temp directory removed." -ForegroundColor Gray
} else {
    Write-Host "WARNING: No temp files found! Jobs may have failed." -ForegroundColor Red
}
