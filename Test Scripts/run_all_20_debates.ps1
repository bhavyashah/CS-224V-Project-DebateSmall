# Run all 20 debates: 5 motions x 2 models x 2 orientations
# Output: detailed_prompts_only_against_baseline_v2.csv

$motions = @(
    "This house would ban zoos",
    "This house believes that developing nations should prioritize economic growth over environmental protection",
    "This house would remove the right to privacy for politicians",
    "This house would make voting mandatory",
    "This house believes that the emphasis on hard work and hustle culture is harmful"
)

$models = @("4o", "4o-mini")
$outputFile = "detailed_prompts_only_against_baseline_v2.csv"
$pythonExe = "C:\Users\Bhavya Shah\OneDrive\Desktop\Kyle\.venv\Scripts\python.exe"
$script = "C:\Users\Bhavya Shah\OneDrive\Desktop\Kyle\crossover_debate.py"

$total = $motions.Count * $models.Count * 2  # 2 orientations per model
$current = 0

Write-Host "=== Running All 20 Debates ===" -ForegroundColor Cyan
Write-Host "Output file: $outputFile`n"

foreach ($motion in $motions) {
    foreach ($model in $models) {
        # Orientation 1: Enhanced (Prop) vs Baseline (Opp)
        $current++
        Write-Host "[$current/$total] $motion" -ForegroundColor Yellow
        Write-Host "  $model: Enhanced (Prop) vs Baseline (Opp)" -ForegroundColor Gray
        & $pythonExe $script -m $motion -pm $model -om $model -pa enhanced -oa baseline -jm o3 -o $outputFile
        
        # Orientation 2: Baseline (Prop) vs Enhanced (Opp)
        $current++
        Write-Host "[$current/$total] $motion" -ForegroundColor Yellow
        Write-Host "  $model: Baseline (Prop) vs Enhanced (Opp)" -ForegroundColor Gray
        & $pythonExe $script -m $motion -pm $model -om $model -pa baseline -oa enhanced -jm o3 -o $outputFile
    }
}

Write-Host "`n=== All 20 Debates Complete ===" -ForegroundColor Green
Write-Host "Results saved to: $outputFile"

# Quick summary
$csv = Import-Csv $outputFile
$enhancedWins = ($csv | Where-Object { 
    ($_.prop_architecture -eq 'enhanced' -and $_.winner -eq 'Proposition') -or 
    ($_.opp_architecture -eq 'enhanced' -and $_.winner -eq 'Opposition') 
}).Count
$baselineWins = $csv.Count - $enhancedWins

Write-Host "`n=== Summary ===" -ForegroundColor Cyan
Write-Host "Total debates: $($csv.Count)"
Write-Host "Enhanced wins: $enhancedWins"
Write-Host "Baseline wins: $baselineWins"
