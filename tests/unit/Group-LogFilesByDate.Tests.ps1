BeforeAll {
    # Import module
    $modulePath = "$PSScriptRoot/../../src/logManager/bin/Debug/net9.0/logManager.dll"
    Import-Module $modulePath -Force

    # Create test data directory
    $script:TestDataPath = "$PSScriptRoot/../data/GroupByDateTest"
    if (Test-Path $script:TestDataPath) {
        Remove-Item $script:TestDataPath -Recurse -Force
    }
    New-Item -ItemType Directory -Path $script:TestDataPath -Force | Out-Null

    # Helper function to create test files with specific dates
    function New-TestFile {
        param(
            [string]$Name,
            [DateTime]$CreatedTime,
            [DateTime]$ModifiedTime
        )

        $filePath = Join-Path $script:TestDataPath $Name
        "Test content for $Name" | Set-Content -Path $filePath

        # Set file timestamps
        $file = Get-Item -Path $filePath
        $file.CreationTime = $CreatedTime
        $file.LastWriteTime = $ModifiedTime

        return $file
    }

    # Create test files with various dates
    $today = Get-Date
    $script:TestFiles = @()

    # Files from today
    $script:TestFiles += New-TestFile -Name "today-1.log" -CreatedTime $today -ModifiedTime $today
    $script:TestFiles += New-TestFile -Name "today-2.log" -CreatedTime $today -ModifiedTime $today

    # Files from 5 days ago
    $fiveDaysAgo = $today.AddDays(-5)
    $script:TestFiles += New-TestFile -Name "5days-ago-1.log" -CreatedTime $fiveDaysAgo -ModifiedTime $fiveDaysAgo

    # Files from 10 days ago
    $tenDaysAgo = $today.AddDays(-10)
    $script:TestFiles += New-TestFile -Name "10days-ago-1.log" -CreatedTime $tenDaysAgo -ModifiedTime $tenDaysAgo
    $script:TestFiles += New-TestFile -Name "10days-ago-2.log" -CreatedTime $tenDaysAgo -ModifiedTime $tenDaysAgo
}

Describe "Group-LogFilesByDate" {

    Context "Basic Grouping by CreatedOn" {
        It "Should group files by yyyyMMdd date" {
            $result = Get-ChildItem -Path $script:TestDataPath -File | Group-LogFilesByDate

            $result | Should -Not -BeNullOrEmpty
            $result | Should -HaveCount 3 # Three different date groups
        }

        It "Should have DateGroup property in yyyyMMdd format" {
            $result = Get-ChildItem -Path $script:TestDataPath -File | Group-LogFilesByDate

            $result | ForEach-Object {
                $_.DateGroup | Should -Match '^\d{8}$'
            }
        }

        It "Should have Files array property" {
            $result = Get-ChildItem -Path $script:TestDataPath -File | Group-LogFilesByDate

            $result | ForEach-Object {
                $_.Files | Should -Not -BeNullOrEmpty
                $_.Files | Should -BeOfType [System.IO.FileInfo]
            }
        }

        It "Should have Count property" {
            $result = Get-ChildItem -Path $script:TestDataPath -File | Group-LogFilesByDate

            $result | ForEach-Object {
                $_.Count | Should -BeGreaterThan 0
                $_.Count | Should -Be $_.Files.Count
            }
        }

        It "Should group correct number of files per date" {
            $result = Get-ChildItem -Path $script:TestDataPath -File | Group-LogFilesByDate

            # Today should have 2 files
            $todayGroup = $result | Where-Object { $_.DateGroup -eq (Get-Date).ToString('yyyyMMdd') }
            $todayGroup.Count | Should -Be 2

            # 10 days ago should have 2 files
            $tenDaysAgoDate = (Get-Date).AddDays(-10).ToString('yyyyMMdd')
            $tenDaysAgoGroup = $result | Where-Object { $_.DateGroup -eq $tenDaysAgoDate }
            $tenDaysAgoGroup.Count | Should -Be 2
        }
    }

    Context "Grouping by LastModified" {
        It "Should group by LastModified when DateType=LastModified" {
            # Create files with different creation and modification times
            $createdDate = (Get-Date).AddDays(-20)
            $modifiedDate = (Get-Date).AddDays(-5)

            $testFile = Join-Path $script:TestDataPath "modified-test.log"
            "Test" | Set-Content -Path $testFile
            $file = Get-Item -Path $testFile
            $file.CreationTime = $createdDate
            $file.LastWriteTime = $modifiedDate

            $result = Get-Item -Path $testFile | Group-LogFilesByDate -DateType "LastModified"

            # Should group by modified date, not creation date
            $result.DateGroup | Should -Be $modifiedDate.ToString('yyyyMMdd')
        }
    }

    Context "Pipeline Input" {
        It "Should accept FileInfo from pipeline" {
            $result = Get-ChildItem -Path $script:TestDataPath -File | Group-LogFilesByDate
            $result | Should -Not -BeNullOrEmpty
        }

        It "Should accept multiple FileInfo objects from pipeline" {
            $files = Get-ChildItem -Path $script:TestDataPath -File
            $result = $files | Group-LogFilesByDate

            $result | Should -Not -BeNullOrEmpty
        }
    }

    Context "Path Parameter Input" {
        It "Should accept Path parameter" {
            $result = Group-LogFilesByDate -Path $script:TestDataPath
            $result | Should -Not -BeNullOrEmpty
        }

        It "Should support Recurse parameter" {
            # Create subdirectory with files
            $subDir = Join-Path $script:TestDataPath "subdir"
            New-Item -ItemType Directory -Path $subDir -Force | Out-Null
            "Sub file content" | Set-Content -Path (Join-Path $subDir "subfile.log")

            $result = Group-LogFilesByDate -Path $script:TestDataPath -Recurse

            # Should find files in subdirectory
            $totalFiles = $result | Measure-Object -Property Count -Sum
            $totalFiles.Sum | Should -BeGreaterThan 3
        }
    }

    Context "Edge Cases" {
        It "Should handle empty directory gracefully" {
            $emptyDir = Join-Path $script:TestDataPath "empty"
            New-Item -ItemType Directory -Path $emptyDir -Force | Out-Null

            $result = Group-LogFilesByDate -Path $emptyDir

            # Should return null or empty collection
            $result | Should -BeNullOrEmpty
        }

        It "Should handle single file" {
            $singleFile = Join-Path $script:TestDataPath "single.log"
            "Single file" | Set-Content -Path $singleFile

            $result = Get-Item -Path $singleFile | Group-LogFilesByDate

            $result | Should -Not -BeNullOrEmpty
            $result.Count | Should -Be 1
        }
    }
}

AfterAll {
    # Clean up test data
    if (Test-Path $script:TestDataPath) {
        Remove-Item $script:TestDataPath -Recurse -Force -ErrorAction SilentlyContinue
    }

    Write-Host "Group-LogFilesByDate tests complete"
}
