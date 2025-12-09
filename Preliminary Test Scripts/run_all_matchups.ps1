# PowerShell script to run all crossover debate matchups
# This will run 3v3 debates for gpt-4o-mini, gpt-4o, and o1 models
# Both structured vs baseline and baseline vs structured configurations

# Activate virtual environment
.\.venv\Scripts\Activate.ps1

Write-Host "==================================================================" -ForegroundColor Cyan
Write-Host "Running All Crossover Debate Matchups (3v3)" -ForegroundColor Cyan
Write-Host "==================================================================" -ForegroundColor Cyan
Write-Host ""

# Delete old results file if exists
if (Test-Path "finalresults.csv") {
    Remove-Item "finalresults.csv"
    Write-Host "Removed old finalresults.csv" -ForegroundColor Yellow
}

Write-Host "Starting matchups..." -ForegroundColor Green
Write-Host ""

# GPT-4o-mini matchups
Write-Host "[1/6] Running: GPT-4o-mini (enhanced) vs GPT-4o-mini (baseline)" -ForegroundColor Cyan
python crossover_debate.py -t 3 -pm 4o-mini -om 4o-mini -pa enhanced -oa baseline -o finalresults.csv
Write-Host ""

Write-Host "[2/6] Running: GPT-4o-mini (baseline) vs GPT-4o-mini (enhanced)" -ForegroundColor Cyan
python crossover_debate.py -t 3 -pm 4o-mini -om 4o-mini -pa baseline -oa enhanced -o finalresults.csv
Write-Host ""

# GPT-4o matchups
Write-Host "[3/6] Running: GPT-4o (enhanced) vs GPT-4o (baseline)" -ForegroundColor Cyan
python crossover_debate.py -t 3 -pm 4o -om 4o -pa enhanced -oa baseline -o finalresults.csv
Write-Host ""

Write-Host "[4/6] Running: GPT-4o (baseline) vs GPT-4o (enhanced)" -ForegroundColor Cyan
python crossover_debate.py -t 3 -pm 4o -om 4o -pa baseline -oa enhanced -o finalresults.csv
Write-Host ""

# O1 matchups
Write-Host "[5/6] Running: O1 (enhanced) vs O1 (baseline)" -ForegroundColor Cyan
python crossover_debate.py -t 3 -pm o1 -om o1 -pa enhanced -oa baseline -o finalresults.csv
Write-Host ""

Write-Host "[6/6] Running: O1 (baseline) vs O1 (enhanced)" -ForegroundColor Cyan
python crossover_debate.py -t 3 -pm o1 -om o1 -pa baseline -oa enhanced -o finalresults.csv
Write-Host ""

Write-Host "==================================================================" -ForegroundColor Green
Write-Host "All matchups complete! Results saved to finalresults.csv" -ForegroundColor Green
Write-Host "==================================================================" -ForegroundColor Green
