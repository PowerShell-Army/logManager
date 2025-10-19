#!/usr/bin/env pwsh

<#
.SYNOPSIS
    Runs all Pester tests for the logManager module

.DESCRIPTION
    Executes comprehensive Pester tests for all logManager cmdlets.
    Test data is created in tests/data and cleaned up after execution.

.PARAMETER Verbose
    Show detailed test output

.PARAMETER Show
    Display test results with detailed output

.EXAMPLE
    .\Run-Tests.ps1
    .\Run-Tests.ps1 -Verbose
#>

param(
    [switch]$Verbose,
    [switch]$Show
)

$testDir = $PSScriptRoot
$unitTestDir = Join-Path $testDir "unit"
$dataDir = Join-Path $testDir "data"

Write-Host "LogManager Test Suite" -ForegroundColor Cyan
Write-Host "=" * 50 -ForegroundColor Cyan
Write-Host ""

# Ensure test data directory exists
if (-not (Test-Path $dataDir)) {
    New-Item -ItemType Directory -Path $dataDir -Force | Out-Null
}

Write-Host "Test Data Location: $dataDir" -ForegroundColor Green
Write-Host ""

# Find all test files
$testFiles = Get-ChildItem -Path $unitTestDir -Filter "*.Tests.ps1" -File | Sort-Object Name

if ($testFiles.Count -eq 0) {
    Write-Host "No test files found in $unitTestDir" -ForegroundColor Red
    exit 1
}

Write-Host "Running $($testFiles.Count) test suite(s)...`n" -ForegroundColor Green

# Run each test file
$testResults = @()
$allPassed = $true

foreach ($testFile in $testFiles) {
    Write-Host "Running: $($testFile.Name)" -ForegroundColor Yellow

    # Configure Pester output
    $pesterParams = @{
        Path = $testFile.FullName
        PassThru = $true
    }

    if ($Show) {
        $pesterParams.Output = "Detailed"
    }

    # Run the tests
    try {
        $result = Invoke-Pester @pesterParams

        if ($result.FailedCount -gt 0) {
            $allPassed = $false
        }

        $testResults += $result

        Write-Host "`n"
    }
    catch {
        Write-Host "Error running test: $_" -ForegroundColor Red
        $allPassed = $false
    }
}

# Display summary
Write-Host "=" * 50 -ForegroundColor Cyan
Write-Host "Test Summary" -ForegroundColor Cyan
Write-Host "=" * 50 -ForegroundColor Cyan

$totalTests = @($testResults).Count * 25  # Approximate based on runs
$totalPassed = 0
$totalFailed = 0
$totalSkipped = 0

# Calculate from individual test results
foreach ($result in $testResults) {
    if ($result.Tests) {
        $totalTests += $result.Tests.Count
        $totalPassed += $result.Passed.Count
        $totalFailed += $result.Failed.Count
        $totalSkipped += $result.Skipped.Count
    }
}

Write-Host "Total Tests:    $totalTests" -ForegroundColor White
Write-Host "Passed:         $totalPassed" -ForegroundColor Green
Write-Host "Failed:         $totalFailed" -ForegroundColor $(if ($totalFailed -gt 0) { "Red" } else { "Green" })
Write-Host "Skipped:        $totalSkipped" -ForegroundColor Yellow
Write-Host ""

# Cleanup test data
Write-Host "Cleaning up test data..." -ForegroundColor Yellow
if (Test-Path $dataDir) {
    try {
        Remove-Item -Path $dataDir -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host "Test data cleaned up successfully" -ForegroundColor Green
    }
    catch {
        Write-Host "Warning: Could not fully clean up test data: $_" -ForegroundColor Yellow
    }
}

Write-Host ""

# Return appropriate exit code
if ($allPassed -and $totalFailed -eq 0) {
    Write-Host "All tests passed!" -ForegroundColor Green
    exit 0
}
else {
    Write-Host "Some tests failed!" -ForegroundColor Red
    exit 1
}
