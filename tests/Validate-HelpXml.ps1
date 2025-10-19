$helpFile = 'C:\Users\abranham\Desktop\logManager\src\logManager\en-US\logManager-help.xml'

Write-Host "Validating XML: $helpFile" -ForegroundColor Cyan

try {
    [xml]$xml = Get-Content $helpFile
    Write-Host "✓ XML is valid!" -ForegroundColor Green

    $cmdCount = @($xml.helpItems.command.command).Count
    Write-Host "  Commands documented: $cmdCount"

    foreach ($cmd in $xml.helpItems.command.command) {
        $name = $cmd.details.name
        $desc = $cmd.maml.description.maml.para | Select-Object -First 1
        Write-Host "  - $name`: $desc"
    }
}
catch {
    Write-Host "✗ XML Error:" -ForegroundColor Red
    Write-Host $_.Exception.Message
    Write-Host ""

    # Try to show the problematic line
    $content = Get-Content $helpFile
    $lines = $content -split "`n"
    Write-Host "Checking for namespace mismatches..." -ForegroundColor Yellow

    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '</(matml|maml|dev|command):' -and $lines[$i] -match '<(maml|matml|dev|command):') {
            Write-Host "Line $($i+1): $($lines[$i])"
        }
    }
}
