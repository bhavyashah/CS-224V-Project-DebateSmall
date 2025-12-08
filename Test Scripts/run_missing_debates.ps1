# Script to run 8 missing debates in parallel
# Each debate tests enhanced vs baseline prompts

# Get absolute paths BEFORE starting jobs
$scriptDir = $PSScriptRoot
if (-not $scriptDir) { $scriptDir = (Get-Location).Path }
$venvPython = Join-Path $scriptDir ".venv\Scripts\python.exe"
$debateScript = Join-Path $scriptDir "crossover_debate.py"
$outputFile = Join-Path $scriptDir "detailed_prompts_only_against_baseline.csv"

Write-Host "=== Configuration ===" -ForegroundColor Cyan
Write-Host "Script dir: $scriptDir"
Write-Host "Python: $venvPython"
Write-Host "Debate script: $debateScript"
Write-Host "Output file: $outputFile"
Write-Host ""

# Verify paths exist
if (-not (Test-Path $venvPython)) {
    Write-Host "ERROR: Virtual environment Python not found at $venvPython" -ForegroundColor Red
    exit 1
}
if (-not (Test-Path $debateScript)) {
    Write-Host "ERROR: crossover_debate.py not found at $debateScript" -ForegroundColor Red
    exit 1
}

# Note: Model names should be '4o' and '4o-mini' (not 'gpt-4o')
$motions = @(
    @{
        motion = "This house would ban zoos"
        model = "4o"
        prop_arch = "baseline"
        opp_arch = "enhanced"
    },
    @{
        motion = "This house believes that developing nations should prioritize economic growth over environmental protection"
        model = "4o"
        prop_arch = "enhanced"
        opp_arch = "baseline"
    },
    @{
        motion = "This house believes that developing nations should prioritize economic growth over environmental protection"
        model = "4o"
        prop_arch = "baseline"
        opp_arch = "enhanced"
    },
    @{
        motion = "This house believes that politicians have no right to a private life"
        model = "4o"
        prop_arch = "enhanced"
        opp_arch = "baseline"
    },
    @{
        motion = "This house would make voting mandatory"
        model = "4o"
        prop_arch = "enhanced"
        opp_arch = "baseline"
    },
    @{
        motion = "This house regrets the narrative that hard work leads to success"
        model = "4o-mini"
        prop_arch = "baseline"
        opp_arch = "enhanced"
    },
    @{
        motion = "This house regrets the narrative that hard work leads to success"
        model = "4o"
        prop_arch = "enhanced"
        opp_arch = "baseline"
    },
    @{
        motion = "This house regrets the narrative that hard work leads to success"
        model = "4o"
        prop_arch = "baseline"
        opp_arch = "enhanced"
    }
)

Write-Host "Starting 8 missing debates in parallel..." -ForegroundColor Cyan
Write-Host "All results will append to: $outputFile" -ForegroundColor Yellow
Write-Host ""

# Start all jobs with absolute paths passed as arguments
$jobs = @()
for ($i = 0; $i -lt $motions.Count; $i++) {
    $config = $motions[$i]
    $jobName = "Debate_$($i+1)_$($config.model)_$($config.prop_arch)_vs_$($config.opp_arch)"
    
    $scriptBlock = {
        param($pythonExe, $scriptPath, $workDir, $motion, $propModel, $oppModel, $judgeModel, $propArch, $oppArch, $output)
        
        # Change to the working directory
        Set-Location $workDir
        
        # Run the debate and capture output
        $result = & $pythonExe $scriptPath `
            -m $motion `
            -t 3 `
            -pm $propModel `
            -om $oppModel `
            -jm $judgeModel `
            -pa $propArch `
            -oa $oppArch `
            -o $output 2>&1
        
        # Return both the output and exit code
        @{
            Output = $result
            ExitCode = $LASTEXITCODE
        }
    }
    
    $job = Start-Job -Name $jobName -ScriptBlock $scriptBlock -ArgumentList @(
        $venvPython,
        $debateScript,
        $scriptDir,
        $config.motion,
        $config.model,
        $config.model,
        "o3",
        $config.prop_arch,
        $config.opp_arch,
        $outputFile
    )
    
    $jobs += $job
    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Started: $jobName" -ForegroundColor Green
}

Write-Host ""
Write-Host "All 8 jobs started. Monitoring progress..." -ForegroundColor Cyan
Write-Host "(Each debate takes 5-15 minutes)" -ForegroundColor Gray
Write-Host ""

# Monitor progress
$startTime = Get-Date

while ($jobs | Where-Object { $_.State -eq 'Running' }) {
    $running = ($jobs | Where-Object { $_.State -eq 'Running' }).Count
    $done = ($jobs | Where-Object { $_.State -ne 'Running' }).Count
    
    $elapsed = (Get-Date) - $startTime
    Write-Host "`r[$(Get-Date -Format 'HH:mm:ss')] Running: $running | Done: $done | Elapsed: $($elapsed.ToString('hh\:mm\:ss'))     " -NoNewline
    
    Start-Sleep -Seconds 10
}

Write-Host ""
Write-Host ""

# Collect results and check for actual success
Write-Host "=== FINAL RESULTS ===" -ForegroundColor Cyan
$successCount = 0
$failCount = 0

foreach ($job in $jobs) {
    $result = Receive-Job -Job $job
    
    # Check if the job actually succeeded (exit code 0 and no errors)
    $actualSuccess = $false
    if ($result -is [hashtable] -and $result.ExitCode -eq 0) {
        $actualSuccess = $true
        $successCount++
    } else {
        $failCount++
    }
    
    $status = if ($actualSuccess) { "[SUCCESS]" } else { "[FAILED]" }
    $color = if ($actualSuccess) { "Green" } else { "Red" }
    Write-Host "  $status - $($job.Name)" -ForegroundColor $color
    
    if (-not $actualSuccess -and $result) {
        Write-Host "    Error: $($result.Output | Select-Object -First 5)" -ForegroundColor Yellow
    }
}

Write-Host ""
Write-Host "Summary:" -ForegroundColor Yellow
Write-Host "  Total debates: $($jobs.Count)"
Write-Host "  Succeeded: $successCount"
Write-Host "  Failed: $failCount"
Write-Host ""

# Clean up jobs
$jobs | Remove-Job -Force

# Verify CSV was updated
$csvCount = (Import-Csv $outputFile).Count
Write-Host "CSV now contains $csvCount debates" -ForegroundColor Cyan
