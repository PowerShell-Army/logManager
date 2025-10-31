BeforeAll {
    # Import the module
    $ModulePath = Join-Path $PSScriptRoot ".." "src" "logManager.psd1"
    Import-Module $ModulePath -Force

    # Test data paths
    $script:TestDataPath = Join-Path $PSScriptRoot "data" "folders_test"
    $script:TestFoldersCreated = @()

    # Date configuration - 5 different dates
    $script:Today = Get-Date -Hour 0 -Minute 0 -Second 0 -Millisecond 0
    $script:TestDates = @{
        Date1 = $script:Today.AddDays(-1)   # 1 day old
        Date2 = $script:Today.AddDays(-5)   # 5 days old
        Date3 = $script:Today.AddDays(-10)  # 10 days old
        Date4 = $script:Today.AddDays(-20)  # 20 days old
        Date5 = $script:Today.AddDays(-30)  # 30 days old
    }

    # Folders per date and format (10000 total folders)
    $script:FoldersPerDatePerFormat = 1000  # 1000 * 2 formats * 5 dates = 10000 folders

    function New-TestDataFolders {
        param(
            [string]$BasePath,
            [hashtable]$Dates,
            [int]$FoldersPerDatePerFormat
        )

        Write-Host "Creating test folder structure in: $BasePath" -ForegroundColor Cyan

        # Ensure the directory exists
        if (-not (Test-Path $BasePath)) {
            New-Item -Path $BasePath -ItemType Directory -Force | Out-Null
        }

        $totalFolders = 0
        $createdFolders = @()

        foreach ($dateKey in $Dates.Keys) {
            $date = $Dates[$dateKey]

            # Create folders in yyyyMMdd format
            Write-Host "  Creating $FoldersPerDatePerFormat folders for $dateKey ($($date.ToString('yyyy-MM-dd'))) in yyyyMMdd format..." -ForegroundColor Gray
            for ($i = 1; $i -le $FoldersPerDatePerFormat; $i++) {
                $folderName = $date.ToString('yyyyMMdd')
                if ($i -gt 1) {
                    $folderName += "_$($i.ToString('000'))"
                }
                $folderPath = Join-Path $BasePath $folderName
                $null = New-Item -Path $folderPath -ItemType Directory -Force
                $createdFolders += $folderPath
                $totalFolders++
            }

            # Create folders in yyyy-MM-dd format
            Write-Host "  Creating $FoldersPerDatePerFormat folders for $dateKey ($($date.ToString('yyyy-MM-dd'))) in yyyy-MM-dd format..." -ForegroundColor Gray
            for ($i = 1; $i -le $FoldersPerDatePerFormat; $i++) {
                $folderName = $date.ToString('yyyy-MM-dd')
                if ($i -gt 1) {
                    $folderName += "_$($i.ToString('000'))"
                }
                $folderPath = Join-Path $BasePath $folderName
                $null = New-Item -Path $folderPath -ItemType Directory -Force
                $createdFolders += $folderPath
                $totalFolders++
            }
        }

        # Create some invalid folders (should be ignored)
        Write-Host "  Creating invalid format folders for testing..." -ForegroundColor Gray
        $invalidFolders = @(
            "InvalidFolder",
            "2024-13-01",  # Invalid month
            "2024-02-30",  # Invalid day
            "20241301",    # Invalid month
            "20240230",    # Invalid day
            "NotADate",
            "2024_01_01",  # Wrong separator
            "01-01-2024"   # Wrong order
        )
        foreach ($invalidFolder in $invalidFolders) {
            $folderPath = Join-Path $BasePath $invalidFolder
            $null = New-Item -Path $folderPath -ItemType Directory -Force
            $createdFolders += $folderPath
            $totalFolders++
        }

        Write-Host "Created $totalFolders test folders (including invalid ones)" -ForegroundColor Green
        return $createdFolders
    }

    function Remove-TestDataFolders {
        param([string]$BasePath)

        if (Test-Path $BasePath) {
            Write-Host "Cleaning up test folders..." -ForegroundColor Yellow
            Remove-Item $BasePath -Recurse -Force -ErrorAction SilentlyContinue
            Write-Host "Removed test folder structure" -ForegroundColor Green
        }
    }

    # Create test folders
    Write-Host "`nSetting up test environment..." -ForegroundColor Cyan
    $script:TestFoldersCreated = New-TestDataFolders -BasePath $script:TestDataPath -Dates $script:TestDates -FoldersPerDatePerFormat $script:FoldersPerDatePerFormat
    Write-Host "Test environment ready!`n" -ForegroundColor Green
}

AfterAll {
    # Cleanup all test folders
    Write-Host "`nCleaning up test environment..." -ForegroundColor Cyan
    Remove-TestDataFolders -BasePath $script:TestDataPath
    Write-Host "Cleanup complete!`n" -ForegroundColor Green
}

Describe "Get-Folders Cmdlet Tests" {

    Context "Parameter Validation" {
        It "Should require -Path parameter" {
            { Get-Folders } | Should -Throw
        }

        It "Should fail with non-existent path" {
            { Get-Folders -Path "C:\NonExistentPath\Fake" -OlderThan 5 -ErrorAction Stop } | Should -Throw
        }

        It "Should work without date filters" {
            { Get-Folders -Path $script:TestDataPath } | Should -Not -Throw
        }

        It "Should fail when OlderThan >= YoungerThan" {
            { Get-Folders -Path $script:TestDataPath -OlderThan 10 -YoungerThan 5 -ErrorAction Stop } | Should -Throw
        }

        It "Should fail when OlderThan equals YoungerThan" {
            { Get-Folders -Path $script:TestDataPath -OlderThan 10 -YoungerThan 10 -ErrorAction Stop } | Should -Throw
        }
    }

    Context "Date Format Parsing" {
        It "Should parse yyyyMMdd format" {
            $results = Get-Folders -Path $script:TestDataPath -OlderThan 0
            $yyyyMMddFolders = $results | Where-Object { $_.Name -match '^\d{8}' }
            $yyyyMMddFolders.Count | Should -BeGreaterThan 0
        }

        It "Should parse yyyy-MM-dd format" {
            $results = Get-Folders -Path $script:TestDataPath -OlderThan 0
            $dashedFolders = $results | Where-Object { $_.Name -match '^\d{4}-\d{2}-\d{2}' }
            $dashedFolders.Count | Should -BeGreaterThan 0
        }

        It "Should ignore folders with invalid date formats" {
            $results = Get-Folders -Path $script:TestDataPath -OlderThan 0
            # Should not include InvalidFolder, NotADate, etc.
            $results.Name | Should -Not -Contain "InvalidFolder"
            $results.Name | Should -Not -Contain "NotADate"
            $results.Name | Should -Not -Contain "2024_01_01"
            $results.Name | Should -Not -Contain "01-01-2024"
        }

        It "Should ignore folders with invalid dates (like Feb 30)" {
            $results = Get-Folders -Path $script:TestDataPath -OlderThan 0
            $results.Name | Should -Not -Contain "2024-02-30"
            $results.Name | Should -Not -Contain "20240230"
        }

        It "Should ignore folders with invalid months" {
            $results = Get-Folders -Path $script:TestDataPath -OlderThan 0
            $results.Name | Should -Not -Contain "2024-13-01"
            $results.Name | Should -Not -Contain "20241301"
        }
    }

    Context "Date Filtering - OlderThan" {
        It "Should find folders older than 2 days" {
            $results = Get-Folders -Path $script:TestDataPath -OlderThan 2
            $results.Count | Should -BeGreaterThan 0
            # Should get folders from Date2, Date3, Date4, Date5 (4 * 1000 * 2 formats = 8000 folders)
            $results.Count | Should -Be 8000
        }

        It "Should find folders older than 7 days" {
            $results = Get-Folders -Path $script:TestDataPath -OlderThan 7
            $results.Count | Should -BeGreaterThan 0
            # Should get folders from Date3, Date4, Date5 (3 * 1000 * 2 formats = 6000 folders)
            $results.Count | Should -Be 6000
        }

        It "Should find folders older than 15 days" {
            $results = Get-Folders -Path $script:TestDataPath -OlderThan 15
            $results.Count | Should -BeGreaterThan 0
            # Should get folders from Date4, Date5 (2 * 1000 * 2 formats = 4000 folders)
            $results.Count | Should -Be 4000
        }

        It "Should find folders older than 25 days" {
            $results = Get-Folders -Path $script:TestDataPath -OlderThan 25
            $results.Count | Should -BeGreaterThan 0
            # Should get folders from Date5 (1 * 1000 * 2 formats = 2000 folders)
            $results.Count | Should -Be 2000
        }

        It "Should return no folders when OlderThan is greater than oldest folder" {
            $results = Get-Folders -Path $script:TestDataPath -OlderThan 35
            $results.Count | Should -Be 0
        }
    }

    Context "Date Filtering - YoungerThan" {
        It "Should find folders younger than 35 days" {
            $results = Get-Folders -Path $script:TestDataPath -YoungerThan 35
            # Should get all valid folders (5 * 1000 * 2 formats = 10000 folders)
            $results.Count | Should -Be 10000
        }

        It "Should find folders younger than 25 days" {
            $results = Get-Folders -Path $script:TestDataPath -YoungerThan 25
            # Should get folders from Date1, Date2, Date3, Date4 (4 * 1000 * 2 formats = 8000 folders)
            $results.Count | Should -Be 8000
        }

        It "Should find folders younger than 15 days" {
            $results = Get-Folders -Path $script:TestDataPath -YoungerThan 15
            # Should get folders from Date1, Date2, Date3 (3 * 1000 * 2 formats = 6000 folders)
            $results.Count | Should -Be 6000
        }

        It "Should find folders younger than 7 days" {
            $results = Get-Folders -Path $script:TestDataPath -YoungerThan 7
            # Should get folders from Date1, Date2 (2 * 1000 * 2 formats = 4000 folders)
            $results.Count | Should -Be 4000
        }

        It "Should find folders younger than 2 days" {
            $results = Get-Folders -Path $script:TestDataPath -YoungerThan 2
            # Should get folders from Date1 (1 * 1000 * 2 formats = 2000 folders)
            $results.Count | Should -Be 2000
        }

        It "Should return no folders when YoungerThan is 0" {
            $results = Get-Folders -Path $script:TestDataPath -YoungerThan 0
            $results.Count | Should -Be 0
        }
    }

    Context "Date Filtering - Combined OlderThan and YoungerThan" {
        It "Should find folders between 7 and 15 days old" {
            $results = Get-Folders -Path $script:TestDataPath -OlderThan 7 -YoungerThan 15
            # Should get folders from Date3 (1 * 1000 * 2 formats = 2000 folders)
            $results.Count | Should -Be 2000
        }

        It "Should find folders between 3 and 25 days old" {
            $results = Get-Folders -Path $script:TestDataPath -OlderThan 3 -YoungerThan 25
            # Should get folders from Date2, Date3, Date4 (3 * 1000 * 2 formats = 6000 folders)
            $results.Count | Should -Be 6000
        }

        It "Should find folders between 15 and 25 days old" {
            $results = Get-Folders -Path $script:TestDataPath -OlderThan 15 -YoungerThan 25
            # Should get folders from Date4 (1 * 1000 * 2 formats = 2000 folders)
            $results.Count | Should -Be 2000
        }

        It "Should return no folders for impossible date range" {
            $results = Get-Folders -Path $script:TestDataPath -OlderThan 8 -YoungerThan 9
            $results.Count | Should -Be 0
        }
    }

    Context "Pattern Filtering" {
        It "Should filter by pattern (2025*)" {
            $results = Get-Folders -Path $script:TestDataPath -Pattern "2025*" -OlderThan 0
            $results.Count | Should -BeGreaterThan 0
            $results | ForEach-Object { $_.Name | Should -Match "^2025" }
        }

        It "Should filter by specific date pattern" {
            $testDate = $script:TestDates['Date1'].ToString('yyyyMMdd')
            $results = Get-Folders -Path $script:TestDataPath -Pattern "$testDate*" -OlderThan 0
            $results.Count | Should -Be 1000  # All folders starting with that date
        }

        It "Should combine pattern and date filters" {
            $results = Get-Folders -Path $script:TestDataPath -Pattern "2025*" -OlderThan 7
            $results.Count | Should -BeGreaterThan 0
        }
    }

    Context "Output Validation" {
        It "Should return DirectoryInfo objects" {
            $results = Get-Folders -Path $script:TestDataPath -OlderThan 1
            $results[0] | Should -BeOfType [System.IO.DirectoryInfo]
        }

        It "Should have valid folder properties" {
            $results = Get-Folders -Path $script:TestDataPath -OlderThan 1
            $folder = $results[0]

            $folder.Name | Should -Not -BeNullOrEmpty
            $folder.FullName | Should -Not -BeNullOrEmpty
            $folder.Exists | Should -Be $true
        }

        It "Should return folders in the correct directory" {
            $results = Get-Folders -Path $script:TestDataPath -OlderThan 1
            $results | ForEach-Object {
                $_.Parent.FullName | Should -Be $script:TestDataPath
            }
        }
    }

    Context "Performance Tests" {
        It "Should process 10000 folders in reasonable time" {
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            $results = Get-Folders -Path $script:TestDataPath -OlderThan 0
            $stopwatch.Stop()

            $results.Count | Should -Be 10000
            $stopwatch.ElapsedMilliseconds | Should -BeLessThan 15000  # Should complete within 15 seconds
        }

        It "Should handle multiple filter combinations efficiently" {
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            $results = Get-Folders -Path $script:TestDataPath -Pattern "2025*" -OlderThan 7 -YoungerThan 25
            $stopwatch.Stop()

            $stopwatch.ElapsedMilliseconds | Should -BeLessThan 3000  # Should complete within 3 seconds
        }
    }

    Context "Edge Cases" {
        It "Should handle empty directory gracefully" {
            $emptyDir = Join-Path $script:TestDataPath "empty_test_dir"
            New-Item -Path $emptyDir -ItemType Directory -Force | Out-Null

            $results = Get-Folders -Path $emptyDir -OlderThan 1
            $results.Count | Should -Be 0

            Remove-Item $emptyDir -Force
        }

        It "Should work with absolute paths" {
            $results = Get-Folders -Path $script:TestDataPath -OlderThan 1
            $results.Count | Should -BeGreaterThan 0
        }

        It "Should handle very large OlderThan values" {
            $results = Get-Folders -Path $script:TestDataPath -OlderThan 10000
            $results.Count | Should -Be 0
        }

        It "Should handle very large YoungerThan values" {
            $results = Get-Folders -Path $script:TestDataPath -YoungerThan 10000
            $results.Count | Should -Be 10000
        }

        It "Should handle directory with only invalid folders" {
            $invalidDir = Join-Path $script:TestDataPath "invalid_only"
            New-Item -Path $invalidDir -ItemType Directory -Force | Out-Null
            New-Item -Path (Join-Path $invalidDir "NotADate") -ItemType Directory -Force | Out-Null
            New-Item -Path (Join-Path $invalidDir "InvalidFolder") -ItemType Directory -Force | Out-Null

            $results = Get-Folders -Path $invalidDir -OlderThan 0
            $results.Count | Should -Be 0

            Remove-Item $invalidDir -Recurse -Force
        }
    }

    Context "Real-world Scenarios" {
        It "Scenario: Find backup folders older than 14 days for cleanup" {
            $results = Get-Folders -Path $script:TestDataPath -OlderThan 14
            $results.Count | Should -Be 4000  # Date4 and Date5 folders
        }

        It "Scenario: Find recent folders (last week)" {
            $results = Get-Folders -Path $script:TestDataPath -YoungerThan 7
            $results.Count | Should -Be 4000  # Date1 and Date2
        }

        It "Scenario: Find folders from specific date range for archival" {
            $results = Get-Folders -Path $script:TestDataPath -OlderThan 5 -YoungerThan 20
            # Should get Date3 folders only (Date4 is exactly 20 days, excluded)
            $results.Count | Should -Be 2000
        }

        It "Scenario: Count all valid date-formatted folders" {
            $results = Get-Folders -Path $script:TestDataPath -OlderThan 0
            $results.Count | Should -Be 10000
        }

        It "Scenario: Find folders from 2025" {
            $results = Get-Folders -Path $script:TestDataPath -Pattern "2025*" -OlderThan 0
            $results.Count | Should -BeGreaterThan 0
            $results | ForEach-Object {
                $_.Name | Should -Match "^2025"
            }
        }
    }

    Context "Mixed Formats Handling" {
        It "Should handle both yyyyMMdd and yyyy-MM-dd in same query" {
            $results = Get-Folders -Path $script:TestDataPath -OlderThan 7 -YoungerThan 15

            # Should have both format types
            $yyyyMMdd = $results | Where-Object { $_.Name -match '^\d{8}' }
            $dashed = $results | Where-Object { $_.Name -match '^\d{4}-\d{2}-\d{2}' }

            $yyyyMMdd.Count | Should -BeGreaterThan 0
            $dashed.Count | Should -BeGreaterThan 0
        }

        It "Should return same date folders in both formats" {
            $date3_yyyyMMdd = $script:TestDates['Date3'].ToString('yyyyMMdd')
            $date3_dashed = $script:TestDates['Date3'].ToString('yyyy-MM-dd')

            $results = Get-Folders -Path $script:TestDataPath -OlderThan 7 -YoungerThan 15

            $format1 = $results | Where-Object { $_.Name -match "^$date3_yyyyMMdd" }
            $format2 = $results | Where-Object { $_.Name -match "^$date3_dashed" }

            $format1.Count | Should -Be 1000
            $format2.Count | Should -Be 1000
        }
    }
}
