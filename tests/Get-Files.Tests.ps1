BeforeAll {
    # Import the module
    $ModulePath = Join-Path $PSScriptRoot ".." "src" "logManager.psd1"
    Import-Module $ModulePath -Force

    # Test data paths
    $script:TestDataPath = Join-Path $PSScriptRoot "data"
    $script:TestFilesCreated = @()

    # Date configuration - 5 different dates
    $script:Today = Get-Date -Hour 0 -Minute 0 -Second 0 -Millisecond 0
    $script:TestDates = @{
        Date1 = $script:Today.AddDays(-1)   # 1 day old
        Date2 = $script:Today.AddDays(-5)   # 5 days old
        Date3 = $script:Today.AddDays(-10)  # 10 days old
        Date4 = $script:Today.AddDays(-20)  # 20 days old
        Date5 = $script:Today.AddDays(-30)  # 30 days old
    }

    # Files per date (10000 total files)
    $script:FilesPerDate = 2000  # 2000 * 5 = 10000 files

    function New-TestDataFiles {
        param(
            [string]$BasePath,
            [hashtable]$Dates,
            [int]$FilesPerDate
        )

        Write-Host "Creating test data in: $BasePath" -ForegroundColor Cyan

        # Ensure the directory exists
        if (-not (Test-Path $BasePath)) {
            New-Item -Path $BasePath -ItemType Directory -Force | Out-Null
        }

        $totalFiles = 0
        $createdFiles = @()

        foreach ($dateKey in $Dates.Keys) {
            $date = $Dates[$dateKey]
            Write-Host "  Creating $FilesPerDate files for $dateKey ($($date.ToString('yyyy-MM-dd')))..." -ForegroundColor Gray

            for ($i = 1; $i -le $FilesPerDate; $i++) {
                # Create different file types for variety
                $extension = switch ($i % 4) {
                    0 { ".log" }
                    1 { ".txt" }
                    2 { ".xml" }
                    3 { ".json" }
                }

                $fileName = "testfile_$($dateKey)_$($i.ToString('0000'))$extension"
                $filePath = Join-Path $BasePath $fileName

                # Create empty file
                $null = New-Item -Path $filePath -ItemType File -Force

                # Set both creation time and last write time to the same date
                $fileInfo = Get-Item $filePath
                $fileInfo.CreationTime = $date
                $fileInfo.LastWriteTime = $date

                $createdFiles += $filePath
                $totalFiles++
            }
        }

        Write-Host "Created $totalFiles test files" -ForegroundColor Green
        return $createdFiles
    }

    function Remove-TestDataFiles {
        param([string[]]$Files)

        if ($Files.Count -gt 0) {
            Write-Host "Cleaning up $($Files.Count) test files..." -ForegroundColor Yellow
            foreach ($file in $Files) {
                if (Test-Path $file) {
                    Remove-Item $file -Force -ErrorAction SilentlyContinue
                }
            }
        }

        # Remove the test data directory if it exists and is empty
        if (Test-Path $script:TestDataPath) {
            $remainingFiles = Get-ChildItem $script:TestDataPath -File
            if ($remainingFiles.Count -eq 0) {
                Remove-Item $script:TestDataPath -Force -ErrorAction SilentlyContinue
                Write-Host "Removed test data directory" -ForegroundColor Green
            }
        }
    }

    # Create test files
    Write-Host "`nSetting up test environment..." -ForegroundColor Cyan
    $script:TestFilesCreated = New-TestDataFiles -BasePath $script:TestDataPath -Dates $script:TestDates -FilesPerDate $script:FilesPerDate
    Write-Host "Test environment ready!`n" -ForegroundColor Green
}

AfterAll {
    # Cleanup all test files
    Write-Host "`nCleaning up test environment..." -ForegroundColor Cyan
    Remove-TestDataFiles -Files $script:TestFilesCreated
    Write-Host "Cleanup complete!`n" -ForegroundColor Green
}

Describe "Get-Files Cmdlet Tests" {

    Context "Parameter Validation" {
        It "Should require -Path parameter" {
            { Get-Files } | Should -Throw
        }

        It "Should fail with non-existent path" {
            { Get-Files -Path "C:\NonExistentPath\Fake" -OlderThan 5 -ErrorAction Stop } | Should -Throw
        }

        It "Should validate DateType values" {
            { Get-Files -Path $script:TestDataPath -DateType "InvalidType" -OlderThan 5 } | Should -Throw
        }

        It "Should accept CreatedOn as DateType" {
            { Get-Files -Path $script:TestDataPath -DateType "CreatedOn" -OlderThan 1 } | Should -Not -Throw
        }

        It "Should accept LastModified as DateType" {
            { Get-Files -Path $script:TestDataPath -DateType "LastModified" -OlderThan 1 } | Should -Not -Throw
        }

        It "Should default DateType to CreatedOn when not specified" {
            # This should work without specifying DateType
            { Get-Files -Path $script:TestDataPath -OlderThan 1 } | Should -Not -Throw
        }

        It "Should fail when OlderThan >= YoungerThan" {
            { Get-Files -Path $script:TestDataPath -OlderThan 10 -YoungerThan 5 -ErrorAction Stop } | Should -Throw
        }

        It "Should fail when OlderThan equals YoungerThan" {
            { Get-Files -Path $script:TestDataPath -OlderThan 10 -YoungerThan 10 -ErrorAction Stop } | Should -Throw
        }
    }

    Context "Date Filtering - OlderThan" {
        It "Should find files older than 2 days" {
            $results = Get-Files -Path $script:TestDataPath -DateType CreatedOn -OlderThan 2
            $results.Count | Should -BeGreaterThan 0
            # Should get files from Date2, Date3, Date4, Date5 (4 * 2000 = 8000 files)
            $results.Count | Should -Be 8000
        }

        It "Should find files older than 7 days" {
            $results = Get-Files -Path $script:TestDataPath -DateType CreatedOn -OlderThan 7
            $results.Count | Should -BeGreaterThan 0
            # Should get files from Date3, Date4, Date5 (3 * 2000 = 6000 files)
            $results.Count | Should -Be 6000
        }

        It "Should find files older than 15 days" {
            $results = Get-Files -Path $script:TestDataPath -DateType CreatedOn -OlderThan 15
            $results.Count | Should -BeGreaterThan 0
            # Should get files from Date4, Date5 (2 * 2000 = 4000 files)
            $results.Count | Should -Be 4000
        }

        It "Should find files older than 25 days" {
            $results = Get-Files -Path $script:TestDataPath -DateType CreatedOn -OlderThan 25
            $results.Count | Should -BeGreaterThan 0
            # Should get files from Date5 (1 * 2000 = 2000 files)
            $results.Count | Should -Be 2000
        }

        It "Should return no files when OlderThan is greater than oldest file" {
            $results = Get-Files -Path $script:TestDataPath -DateType CreatedOn -OlderThan 35
            $results.Count | Should -Be 0
        }
    }

    Context "Date Filtering - YoungerThan" {
        It "Should find files younger than 35 days" {
            $results = Get-Files -Path $script:TestDataPath -DateType CreatedOn -YoungerThan 35
            # Should get all files (5 * 2000 = 10000 files)
            $results.Count | Should -Be 10000
        }

        It "Should find files younger than 25 days" {
            $results = Get-Files -Path $script:TestDataPath -DateType CreatedOn -YoungerThan 25
            # Should get files from Date1, Date2, Date3, Date4 (4 * 2000 = 8000 files)
            $results.Count | Should -Be 8000
        }

        It "Should find files younger than 15 days" {
            $results = Get-Files -Path $script:TestDataPath -DateType CreatedOn -YoungerThan 15
            # Should get files from Date1, Date2, Date3 (3 * 2000 = 6000 files)
            $results.Count | Should -Be 6000
        }

        It "Should find files younger than 7 days" {
            $results = Get-Files -Path $script:TestDataPath -DateType CreatedOn -YoungerThan 7
            # Should get files from Date1, Date2 (2 * 2000 = 4000 files)
            $results.Count | Should -Be 4000
        }

        It "Should find files younger than 2 days" {
            $results = Get-Files -Path $script:TestDataPath -DateType CreatedOn -YoungerThan 2
            # Should get files from Date1 (1 * 2000 = 2000 files)
            $results.Count | Should -Be 2000
        }

        It "Should return no files when YoungerThan is 0" {
            $results = Get-Files -Path $script:TestDataPath -DateType CreatedOn -YoungerThan 0
            $results.Count | Should -Be 0
        }
    }

    Context "Date Filtering - Combined OlderThan and YoungerThan" {
        It "Should find files between 7 and 15 days old" {
            $results = Get-Files -Path $script:TestDataPath -DateType CreatedOn -OlderThan 7 -YoungerThan 15
            # Should get files from Date3 (1 * 2000 = 2000 files)
            $results.Count | Should -Be 2000
        }

        It "Should find files between 3 and 25 days old" {
            $results = Get-Files -Path $script:TestDataPath -DateType CreatedOn -OlderThan 3 -YoungerThan 25
            # Should get files from Date2, Date3, Date4 (3 * 2000 = 6000 files)
            $results.Count | Should -Be 6000
        }

        It "Should find files between 15 and 25 days old" {
            $results = Get-Files -Path $script:TestDataPath -DateType CreatedOn -OlderThan 15 -YoungerThan 25
            # Should get files from Date4 (1 * 2000 = 2000 files)
            $results.Count | Should -Be 2000
        }

        It "Should return no files for impossible date range" {
            $results = Get-Files -Path $script:TestDataPath -DateType CreatedOn -OlderThan 8 -YoungerThan 9
            $results.Count | Should -Be 0
        }
    }

    Context "DateType: CreatedOn vs LastModified" {
        It "Should return same results for CreatedOn and LastModified when dates match" {
            $resultsCreated = Get-Files -Path $script:TestDataPath -DateType CreatedOn -OlderThan 7
            $resultsModified = Get-Files -Path $script:TestDataPath -DateType LastModified -OlderThan 7

            $resultsCreated.Count | Should -Be $resultsModified.Count
        }

        It "Should use CreatedOn by default" {
            $resultsDefault = Get-Files -Path $script:TestDataPath -OlderThan 7
            $resultsCreated = Get-Files -Path $script:TestDataPath -DateType CreatedOn -OlderThan 7

            $resultsDefault.Count | Should -Be $resultsCreated.Count
        }
    }

    Context "Pattern Filtering" {
        It "Should filter by .log extension" {
            $results = Get-Files -Path $script:TestDataPath -Pattern "*.log" -OlderThan 0
            $results.Count | Should -BeGreaterThan 0
            $results | ForEach-Object { $_.Extension | Should -Be ".log" }
        }

        It "Should filter by .txt extension" {
            $results = Get-Files -Path $script:TestDataPath -Pattern "*.txt" -OlderThan 0
            $results.Count | Should -BeGreaterThan 0
            $results | ForEach-Object { $_.Extension | Should -Be ".txt" }
        }

        It "Should filter by .xml extension" {
            $results = Get-Files -Path $script:TestDataPath -Pattern "*.xml" -OlderThan 0
            $results.Count | Should -BeGreaterThan 0
            $results | ForEach-Object { $_.Extension | Should -Be ".xml" }
        }

        It "Should filter by .json extension" {
            $results = Get-Files -Path $script:TestDataPath -Pattern "*.json" -OlderThan 0
            $results.Count | Should -BeGreaterThan 0
            $results | ForEach-Object { $_.Extension | Should -Be ".json" }
        }

        It "Should combine pattern and date filters" {
            $results = Get-Files -Path $script:TestDataPath -Pattern "*.log" -DateType CreatedOn -OlderThan 7
            $results.Count | Should -BeGreaterThan 0
            # Should be 1/4 of the 6000 files = 1500 files
            $results.Count | Should -Be 1500
            $results | ForEach-Object { $_.Extension | Should -Be ".log" }
        }
    }

    Context "Output Validation" {
        It "Should return FileInfo objects" {
            $results = Get-Files -Path $script:TestDataPath -OlderThan 1
            $results[0] | Should -BeOfType [System.IO.FileInfo]
        }

        It "Should have valid file properties" {
            $results = Get-Files -Path $script:TestDataPath -OlderThan 1
            $file = $results[0]

            $file.Name | Should -Not -BeNullOrEmpty
            $file.FullName | Should -Not -BeNullOrEmpty
            $file.CreationTime | Should -BeOfType [DateTime]
            $file.LastWriteTime | Should -BeOfType [DateTime]
        }

        It "Should return files in the correct directory" {
            $results = Get-Files -Path $script:TestDataPath -OlderThan 1
            $results | ForEach-Object {
                $_.DirectoryName | Should -Be $script:TestDataPath
            }
        }
    }

    Context "Performance Tests" {
        It "Should process 10000 files in reasonable time" {
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            $results = Get-Files -Path $script:TestDataPath -OlderThan 0
            $stopwatch.Stop()

            $results.Count | Should -Be 10000
            $stopwatch.ElapsedMilliseconds | Should -BeLessThan 15000  # Should complete within 15 seconds
        }

        It "Should handle multiple filter combinations efficiently" {
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            $results = Get-Files -Path $script:TestDataPath -Pattern "*.log" -DateType CreatedOn -OlderThan 7 -YoungerThan 25
            $stopwatch.Stop()

            $stopwatch.ElapsedMilliseconds | Should -BeLessThan 3000  # Should complete within 3 seconds
        }
    }

    Context "Edge Cases" {
        It "Should handle empty directory gracefully" {
            $emptyDir = Join-Path $script:TestDataPath "empty_test_dir"
            New-Item -Path $emptyDir -ItemType Directory -Force | Out-Null

            $results = Get-Files -Path $emptyDir -OlderThan 1
            $results.Count | Should -Be 0

            Remove-Item $emptyDir -Force
        }

        It "Should work with absolute paths" {
            $results = Get-Files -Path $script:TestDataPath -OlderThan 1
            $results.Count | Should -BeGreaterThan 0
        }

        It "Should handle very large OlderThan values" {
            $results = Get-Files -Path $script:TestDataPath -OlderThan 10000
            $results.Count | Should -Be 0
        }

        It "Should handle very large YoungerThan values" {
            $results = Get-Files -Path $script:TestDataPath -YoungerThan 10000
            $results.Count | Should -Be 10000
        }
    }

    Context "Real-world Scenarios" {
        It "Scenario: Find log files older than 14 days for cleanup" {
            $results = Get-Files -Path $script:TestDataPath -Pattern "*.log" -DateType CreatedOn -OlderThan 14
            $results.Count | Should -Be 1000  # Date4 and Date5 log files (500 each)
        }

        It "Scenario: Find files modified in the last week" {
            $results = Get-Files -Path $script:TestDataPath -DateType LastModified -YoungerThan 7
            $results.Count | Should -Be 4000  # Date1 and Date2
        }

        It "Scenario: Find XML files between 5 and 20 days old" {
            $results = Get-Files -Path $script:TestDataPath -Pattern "*.xml" -DateType CreatedOn -OlderThan 5 -YoungerThan 20
            # Should get Date3 XML files only (Date4 is exactly 20 days, excluded)
            $results.Count | Should -Be 500
        }

        It "Scenario: Archive files older than 30 days" {
            $results = Get-Files -Path $script:TestDataPath -DateType CreatedOn -OlderThan 30
            $results.Count | Should -Be 0
        }

        It "Scenario: Find recent JSON files (last 10 days)" {
            $results = Get-Files -Path $script:TestDataPath -Pattern "*.json" -DateType CreatedOn -YoungerThan 10
            # Should get Date1 and Date2 JSON files (2 * 500 = 1000 files)
            $results.Count | Should -Be 1000
        }
    }
}
