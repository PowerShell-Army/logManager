# Test script to verify help is available for all logManager cmdlets

param(
    [string]$ModulePath = "C:\Users\abranham\Desktop\logManager\src\logManager\bin\Debug\net9.0\logManager.dll",
    [switch]$ShowFull
)

Write-Host "========================================" -ForegroundColor Green
Write-Host "logManager Help Verification" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""

# Import module
Write-Host "Importing module from: $ModulePath" -ForegroundColor Cyan
Import-Module $ModulePath -Force
Write-Host "✓ Module imported successfully" -ForegroundColor Green
Write-Host ""

# List all cmdlets
$cmdlets = @('Convert-TokenPath', 'Get-LogFiles', 'Get-LogFolders', 'Group-LogFilesByDate', 'Compress-Logs', 'Send-LogsToS3')

Write-Host "========================================" -ForegroundColor Green
Write-Host "Available Cmdlets and Help Summary" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""

foreach ($cmdlet in $cmdlets) {
    $help = Get-Help $cmdlet -ErrorAction SilentlyContinue
    if ($help) {
        Write-Host "✓ $cmdlet" -ForegroundColor Green

        # Show basic info
        $synopsis = $help.Synopsis
        if ($synopsis) {
            Write-Host "  Synopsis: $($synopsis.Substring(0, [Math]::Min(70, $synopsis.Length)))..."
        }

        # Show parameter count
        $params = @($help.Parameters.Parameter | Where-Object { $_.Name -ne 'CommonParameters' })
        Write-Host "  Parameters: $($params.Count)"

        if ($ShowFull) {
            Write-Host ""
            Get-Help $cmdlet -Full
            Write-Host ""
        }
    }
    else {
        Write-Host "✗ $cmdlet - Help not found" -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "Help File Status" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""

$helpFile = Join-Path (Split-Path $ModulePath) "en-US\logManager-help.xml"
if (Test-Path $helpFile) {
    $fileInfo = Get-Item $helpFile
    Write-Host "✓ External help file found" -ForegroundColor Green
    Write-Host "  Path: $helpFile"
    Write-Host "  Size: $($fileInfo.Length) bytes"
    Write-Host "  Modified: $($fileInfo.LastWriteTime)"

    # Parse and show command count in XML
    [xml]$xml = Get-Content $helpFile
    $cmdCount = @($xml.helpItems.command.command).Count
    Write-Host "  Commands documented: $cmdCount"
}
else {
    Write-Host "⚠ External help file not found" -ForegroundColor Yellow
    Write-Host "  Expected path: $helpFile"
    Write-Host "  Note: Basic parameter help is still available"
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "Sample: Full Help for Convert-TokenPath" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""

Get-Help Convert-TokenPath -Full

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "Sample: Examples for Get-LogFiles" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""

Get-Help Get-LogFiles -Examples

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "Help Verification Complete" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
