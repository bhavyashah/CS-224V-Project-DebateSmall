# Run Missing Enhanced Debates - Batch size 10
# Fills in the 27 missing debates from the first run

$ScriptDir = $PSScriptRoot
$TestsDir = Split-Path -Parent $ScriptDir
$MainDir = Split-Path -Parent $TestsDir
$TempDir = "$ScriptDir\temp_missing"
$ConsolidatedFile = "$ScriptDir\baseline_vs_enhanced_ALL_RESULTS.csv"

Write-Host "=== Running Missing Enhanced Debates ===" -ForegroundColor Cyan
Write-Host "Using smaller batch size of 10 to avoid rate limits" -ForegroundColor Cyan
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

# All 40 debates - we'll skip ones that already exist
$allDebates = @()
$jobIndex = 0
$models = @("4o", "4o-mini")

foreach ($model in $models) {
    $motionIndex = 0
    foreach ($motion in $motions) {
        $motionIndex++
        
        # Forward
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
        
        # Reverse
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

# Load existing results to identify what's missing
$existingData = @()
if (Test-Path $ConsolidatedFile) {
    $existingData = @(Import-Csv $ConsolidatedFile)
}
Write-Host "Existing debates in consolidated file: $($existingData.Count)" -ForegroundColor Yellow

# Create a set of existing debate keys for quick lookup
$existingKeys = @{}
foreach ($row in $existingData) {
    $model = if ($row.prop_model -eq "gpt-4o") { "4o" } else { "4o-mini" }
    $motionShort = $row.motion.Substring(0, [Math]::Min(50, $row.motion.Length))
    $propArch = $row.prop_architecture
    $oppArch = $row.opp_architecture
    $key = "${model}_${propArch}_${oppArch}_${motionShort}"
    $existingKeys[$key] = $true
}

# Filter to only missing debates
$missingDebates = @()
foreach ($debate in $allDebates) {
    $motionShort = $debate.Motion.Substring(0, [Math]::Min(50, $debate.Motion.Length))
    $key = "$($debate.Model)_$($debate.PropArch)_$($debate.OppArch)_${motionShort}"
    if (-not $existingKeys.ContainsKey($key)) {
        $missingDebates += $debate
    }
}

Write-Host "Missing debates to run: $($missingDebates.Count)" -ForegroundColor Yellow
Write-Host ""

if ($missingDebates.Count -eq 0) {
    Write-Host "All debates already complete!" -ForegroundColor Green
    exit
}

# Run in batches of 10
$batchSize = 10
$totalBatches = [math]::Ceiling($missingDebates.Count / $batchSize)

for ($batchNum = 0; $batchNum -lt $totalBatches; $batchNum++) {
    $startIdx = $batchNum * $batchSize
    $endIdx = [math]::Min($startIdx + $batchSize - 1, $missingDebates.Count - 1)
    $batchDebates = $missingDebates[$startIdx..$endIdx]
    
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "=== BATCH $($batchNum + 1) of $totalBatches ===" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""
    
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
    Write-Host "Batch $($batchNum + 1): All $($batchDebates.Count) jobs started. Waiting..." -ForegroundColor Cyan
    Write-Host ""
    
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
    
    $jobs | Remove-Job
    
    Write-Host ""
    Write-Host "Batch $($batchNum + 1) complete: $successful succeeded, $failed failed" -ForegroundColor Cyan
    Write-Host ""
}

# Merge temp files with existing data
Write-Host "========================================" -ForegroundColor Green
Write-Host "=== MERGING RESULTS ===" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green

$tempFiles = Get-ChildItem $TempDir -Filter "*.csv" -ErrorAction SilentlyContinue
Write-Host "Found $($tempFiles.Count) new temp files" -ForegroundColor Yellow

if ($tempFiles.Count -gt 0) {
    $newData = @()
    foreach ($tempFile in $tempFiles) {
        $data = Import-Csv $tempFile.FullName -ErrorAction SilentlyContinue
        if ($data) {
            $newData += $data
            Write-Host "  Added: $($tempFile.Name)" -ForegroundColor Gray
        }
    }
    
    Write-Host "New rows: $($newData.Count)" -ForegroundColor Yellow
    Write-Host "Existing rows: $($existingData.Count)" -ForegroundColor Yellow
    
    $allData = $existingData + $newData
    $allData | Export-Csv $ConsolidatedFile -NoTypeInformation
    
    Write-Host ""
    Write-Host "=== COMPLETE ===" -ForegroundColor Green
    Write-Host "Total debates: $($allData.Count)" -ForegroundColor Green
    Write-Host "Results: $ConsolidatedFile" -ForegroundColor Green
    
    Remove-Item $TempDir -Recurse -Force
    Write-Host "Temp files cleaned up." -ForegroundColor Gray
} else {
    Write-Host "WARNING: No temp files found!" -ForegroundColor Red
}
