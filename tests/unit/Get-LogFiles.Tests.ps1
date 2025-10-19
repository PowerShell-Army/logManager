BeforeAll {
    $modulePath = "$PSScriptRoot\..\..\src\logManager\bin\Debug\net9.0\logManager.dll"
    Import-Module $modulePath -Force

    $testDataPath = "$PSScriptRoot\..\data\LogFilesTest"

    # Setup test data directory
    if (Test-Path $testDataPath) {
        Remove-Item -Path $testDataPath -Recurse -Force
    }
    New-Item -ItemType Directory -Path $testDataPath -Force | Out-Null

    # Create subdirectories
    New-Item -ItemType Directory -Path "$testDataPath\subdir1" -Force | Out-Null
    New-Item -ItemType Directory -Path "$testDataPath\subdir2\nested" -Force | Out-Null

    # Create files with specific ages
    $now = Get-Date

    # 5 days old
    $file1 = New-Item -ItemType File -Path "$testDataPath\logfile_5days.txt" -Force
    $file1.CreationTime = $now.AddDays(-5)
    $file1.LastWriteTime = $now.AddDays(-5)

    # 10 days old
    $file2 = New-Item -ItemType File -Path "$testDataPath\logfile_10days.txt" -Force
    $file2.CreationTime = $now.AddDays(-10)
    $file2.LastWriteTime = $now.AddDays(-10)

    # 18 days old
    $file3 = New-Item -ItemType File -Path "$testDataPath\logfile_18days.txt" -Force
    $file3.CreationTime = $now.AddDays(-18)
    $file3.LastWriteTime = $now.AddDays(-18)

    # 30 days old
    $file4 = New-Item -ItemType File -Path "$testDataPath\logfile_30days.txt" -Force
    $file4.CreationTime = $now.AddDays(-30)
    $file4.LastWriteTime = $now.AddDays(-30)

    # Recent file (1 day old)
    $file5 = New-Item -ItemType File -Path "$testDataPath\logfile_1day.txt" -Force
    $file5.CreationTime = $now.AddDays(-1)
    $file5.LastWriteTime = $now.AddDays(-1)

    # Files in subdirectories
    $fileSubdir1 = New-Item -ItemType File -Path "$testDataPath\subdir1\log_3days.txt" -Force
    $fileSubdir1.CreationTime = $now.AddDays(-3)
    $fileSubdir1.LastWriteTime = $now.AddDays(-3)

    $fileNested = New-Item -ItemType File -Path "$testDataPath\subdir2\nested\log_25days.txt" -Force
    $fileNested.CreationTime = $now.AddDays(-25)
    $fileNested.LastWriteTime = $now.AddDays(-25)
}

AfterAll {
    # Cleanup test data
    $testDataPath = "$PSScriptRoot\..\data\LogFilesTest"
    if (Test-Path $testDataPath) {
        Remove-Item -Path $testDataPath -Recurse -Force
    }
}

Describe "Get-LogFiles" {
    Context "Basic File Retrieval" {
        It "Should retrieve all files from directory" {
            $results = Get-LogFiles -Path $testDataPath
            $results | Should -HaveCount 5
        }

        It "Should return FileInfo objects" {
            $results = Get-LogFiles -Path $testDataPath
            $results[0] | Should -BeOfType System.IO.FileInfo
        }

        It "Should include file names" {
            $results = Get-LogFiles -Path $testDataPath
            $results.Name | Should -Contain "logfile_5days.txt"
            $results.Name | Should -Contain "logfile_10days.txt"
        }

        It "Should fail with non-existent path" {
            { Get-LogFiles -Path "C:\NonExistent\Path" -ErrorAction Stop } | Should -Throw
        }
    }

    Context "Age Filtering - OlderThan" {
        It "Should filter files older than 12 days" {
            $results = Get-LogFiles -Path $testDataPath -OlderThan 12
            $results | Should -HaveCount 2
            $results.Name | Should -Contain "logfile_18days.txt"
            $results.Name | Should -Contain "logfile_30days.txt"
        }

        It "Should filter files older than 5 days" {
            $results = Get-LogFiles -Path $testDataPath -OlderThan 5
            $results | Should -HaveCount 4
            $results.Name | Should -Not -Contain "logfile_1day.txt"
        }

        It "Should return no files when threshold exceeds oldest file" {
            $results = Get-LogFiles -Path $testDataPath -OlderThan 35
            $results | Should -BeNullOrEmpty
        }
    }

    Context "Age Filtering - YoungerThan" {
        It "Should filter files younger than 12 days" {
            $results = Get-LogFiles -Path $testDataPath -YoungerThan 12
            $results | Should -HaveCount 3
            $results.Name | Should -Contain "logfile_1day.txt"
            $results.Name | Should -Contain "logfile_5days.txt"
            $results.Name | Should -Contain "logfile_10days.txt"
        }

        It "Should filter files younger than 3 days" {
            $results = Get-LogFiles -Path $testDataPath -YoungerThan 3
            $results | Should -HaveCount 1
            $results.Name | Should -Be "logfile_1day.txt"
        }

        It "Should return all files when threshold exceeds newest file" {
            $results = Get-LogFiles -Path $testDataPath -YoungerThan 40
            $results | Should -HaveCount 5
        }
    }

    Context "Combined Age Filtering" {
        It "Should filter with both OlderThan and YoungerThan" {
            $results = Get-LogFiles -Path $testDataPath -OlderThan 8 -YoungerThan 20
            $results | Should -HaveCount 2
            $results.Name | Should -Contain "logfile_10days.txt"
            $results.Name | Should -Contain "logfile_18days.txt"
        }

        It "Should return no files when range is too narrow" {
            $results = Get-LogFiles -Path $testDataPath -OlderThan 20 -YoungerThan 8
            $results | Should -BeNullOrEmpty
        }

        It "Should handle exact boundaries" {
            $results = Get-LogFiles -Path $testDataPath -OlderThan 10 -YoungerThan 10
            $results.Name | Should -Be "logfile_10days.txt"
        }
    }

    Context "DateType Parameter" {
        It "Should use CreatedOn by default" {
            $results = Get-LogFiles -Path $testDataPath -OlderThan 15
            $results | Should -HaveCount 2
        }

        It "Should accept CreatedOn explicitly" {
            $results = Get-LogFiles -Path $testDataPath -OlderThan 15 -DateType CreatedOn
            $results | Should -HaveCount 2
        }

        It "Should accept LastModified" {
            $results = Get-LogFiles -Path $testDataPath -OlderThan 15 -DateType LastModified
            $results | Should -HaveCount 2
        }

        It "Should reject invalid DateType" {
            { Get-LogFiles -Path $testDataPath -DateType "InvalidType" -ErrorAction Stop } | Should -Throw
        }
    }

    Context "Recursion" {
        It "Should not recurse by default" {
            $results = Get-LogFiles -Path $testDataPath
            $results | Should -HaveCount 5
            $results.Name | Should -Not -Contain "log_3days.txt"
        }

        It "Should recurse with -Recurse flag" {
            $results = Get-LogFiles -Path $testDataPath -Recurse
            $results | Should -HaveCount 7
        }

        It "Should find nested files with -Recurse" {
            $results = Get-LogFiles -Path $testDataPath -Recurse
            $results.Name | Should -Contain "log_3days.txt"
            $results.Name | Should -Contain "log_25days.txt"
        }

        It "Should apply age filter with -Recurse" {
            $results = Get-LogFiles -Path $testDataPath -Recurse -OlderThan 10
            $results | Should -HaveCount 4
            $results.Name | Should -Contain "logfile_10days.txt"
            $results.Name | Should -Contain "logfile_18days.txt"
            $results.Name | Should -Contain "logfile_30days.txt"
            $results.Name | Should -Contain "log_25days.txt"
        }
    }

    Context "Token Conversion" {
        It "Should convert tokens in path parameter" {
            $serverName = [System.Environment]::MachineName
            $tokenPath = "/{SERVER}/data"

            # Create a test directory with the converted path
            $convertedPath = Convert-TokenPath -Path $tokenPath
            New-Item -ItemType Directory -Path $convertedPath -Force | Out-Null
            $testFile = New-Item -ItemType File -Path "$convertedPath\testfile.txt" -Force

            try {
                $results = Get-LogFiles -Path $tokenPath
                $results.Name | Should -Contain "testfile.txt"
            }
            finally {
                Remove-Item -Path (Split-Path $testFile.FullName) -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    Context "Pipeline Support" {
        It "Should accept path via pipeline" {
            $results = $testDataPath | Get-LogFiles
            $results | Should -HaveCount 5
        }

        It "Should accept path and parameters via pipeline" {
            $results = $testDataPath | Get-LogFiles -OlderThan 15
            $results | Should -HaveCount 2
        }
    }

    Context "Edge Cases" {
        It "Should handle empty directory" {
            $emptyDir = "$testDataPath\empty"
            New-Item -ItemType Directory -Path $emptyDir -Force | Out-Null

            try {
                $results = Get-LogFiles -Path $emptyDir
                $results | Should -BeNullOrEmpty
            }
            finally {
                Remove-Item -Path $emptyDir -Force
            }
        }

        It "Should handle zero OlderThan value" {
            $results = Get-LogFiles -Path $testDataPath -OlderThan 0
            $results | Should -HaveCount 5
        }
    }
}
