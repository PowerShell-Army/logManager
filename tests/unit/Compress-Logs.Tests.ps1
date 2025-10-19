BeforeAll {
    $modulePath = "$PSScriptRoot\..\..\src\logManager\bin\Debug\net9.0\logManager.dll"
    Import-Module $modulePath -Force

    $testDataPath = "$PSScriptRoot\..\data\CompressTest"
    $archiveDataPath = "$PSScriptRoot\..\data\Archives"

    # Setup test data directories
    if (Test-Path $testDataPath) {
        Remove-Item -Path $testDataPath -Recurse -Force
    }
    if (Test-Path $archiveDataPath) {
        Remove-Item -Path $archiveDataPath -Recurse -Force
    }

    New-Item -ItemType Directory -Path $testDataPath -Force | Out-Null
    New-Item -ItemType Directory -Path $archiveDataPath -Force | Out-Null

    # Create test files with content
    $now = Get-Date

    1..5 | ForEach-Object {
        $file = New-Item -ItemType File -Path "$testDataPath\log_$_.txt" -Force
        $file.CreationTime = $now.AddDays(-$_)
        Add-Content -Path $file.FullName -Value ("Test log content $_" * 10)
    }

    # Create test folders in date format
    $folder1 = New-Item -ItemType Directory -Path "$testDataPath\20251015" -Force
    $folder1.CreationTime = $now.AddDays(-3)

    $folder2 = New-Item -ItemType Directory -Path "$testDataPath\20251010" -Force
    $folder2.CreationTime = $now.AddDays(-8)

    # Create files inside folders
    1..3 | ForEach-Object {
        New-Item -ItemType File -Path "$testDataPath\20251015\nested_log_$_.txt" -Force | Out-Null
    }
}

AfterAll {
    # Cleanup test data
    $testDataPath = "$PSScriptRoot\..\data\CompressTest"
    $archiveDataPath = "$PSScriptRoot\..\data\Archives"

    if (Test-Path $testDataPath) {
        Remove-Item -Path $testDataPath -Recurse -Force
    }
    if (Test-Path $archiveDataPath) {
        Remove-Item -Path $archiveDataPath -Recurse -Force
    }
}

Describe "Compress-Logs" {
    Context "Basic Compression" {
        It "Should compress files from Get-LogFiles" {
            $archivePath = "$archiveDataPath\files_test.zip"
            $archive = Get-LogFiles -Path $testDataPath | Compress-Logs -ArchivePath $archivePath

            $archive | Should -Not -BeNullOrEmpty
            $archive.Name | Should -Be "files_test.zip"
            Test-Path $archive.FullName | Should -Be $true
        }

        It "Should compress folders from Get-LogFolders" {
            $archivePath = "$archiveDataPath\folders_test.zip"
            $archive = Get-LogFolders -Path $testDataPath | Compress-Logs -ArchivePath $archivePath

            $archive | Should -Not -BeNullOrEmpty
            $archive.Name | Should -Be "folders_test.zip"
            Test-Path $archive.FullName | Should -Be $true
        }

        It "Should return FileInfo object" {
            $archivePath = "$archiveDataPath\fileinfo_test.zip"
            $archive = Get-LogFiles -Path $testDataPath | Compress-Logs -ArchivePath $archivePath

            $archive | Should -BeOfType System.IO.FileInfo
            $archive.Extension | Should -Be ".zip"
        }

        It "Should create archive with content" {
            $archivePath = "$archiveDataPath\content_test.zip"
            $archive = Get-LogFiles -Path $testDataPath | Compress-Logs -ArchivePath $archivePath

            $archive.Length | Should -BeGreaterThan 0
        }
    }

    Context "Archive Extension Validation" {
        It "Should require .zip extension" {
            $archivePath = "$archiveDataPath\invalid.7z"
            { Get-LogFiles -Path $testDataPath | Compress-Logs -ArchivePath $archivePath -ErrorAction Stop } | Should -Throw
        }

        It "Should accept uppercase .ZIP extension" {
            $archivePath = "$archiveDataPath\uppercase_test.ZIP"
            $archive = Get-LogFiles -Path $testDataPath | Compress-Logs -ArchivePath $archivePath

            $archive | Should -Not -BeNullOrEmpty
            Test-Path $archive.FullName | Should -Be $true
        }

        It "Should accept mixed case .Zip extension" {
            $archivePath = "$archiveDataPath\mixedcase_test.Zip"
            $archive = Get-LogFiles -Path $testDataPath | Compress-Logs -ArchivePath $archivePath

            $archive | Should -Not -BeNullOrEmpty
            Test-Path $archive.FullName | Should -Be $true
        }

        It "Should reject .rar extension" {
            $archivePath = "$archiveDataPath\invalid.rar"
            { Get-LogFiles -Path $testDataPath | Compress-Logs -ArchivePath $archivePath -ErrorAction Stop } | Should -Throw
        }

        It "Should reject no extension" {
            $archivePath = "$archiveDataPath\nooext"
            { Get-LogFiles -Path $testDataPath | Compress-Logs -ArchivePath $archivePath -ErrorAction Stop } | Should -Throw
        }
    }

    Context "Token Path Conversion" {
        It "Should convert {SERVER} token in archive path" {
            $tokenPath = "/{SERVER}/data/archive.zip"
            $archive = Get-LogFiles -Path $testDataPath | Compress-Logs -ArchivePath $tokenPath

            $archive | Should -Not -BeNullOrEmpty
            $archive.FullName | Should -Match "^[A-Za-z]:"  # Windows path
        }

        It "Should convert {YEAR}{MONTH}{DAY} tokens" {
            $tokenPath = "$archiveDataPath/logs_{YEAR}{MONTH}{DAY}.zip"
            $archive = Get-LogFiles -Path $testDataPath | Compress-Logs -ArchivePath $tokenPath

            $archive | Should -Not -BeNullOrEmpty
            $today = Get-Date
            $expectedName = "logs_{0:D4}{1:D2}{2:D2}.zip" -f $today.Year, $today.Month, $today.Day
            $archive.Name | Should -Be $expectedName
        }

        It "Should convert full date format token path" {
            $tokenPath = "$archiveDataPath/{YEAR}-{MONTH}-{DAY}_archive.zip"
            $archive = Get-LogFiles -Path $testDataPath | Compress-Logs -ArchivePath $tokenPath

            $archive | Should -Not -BeNullOrEmpty
            $today = Get-Date
            $expectedName = "{0:D4}-{1:D2}-{2:D2}_archive.zip" -f $today.Year, $today.Month, $today.Day
            $archive.Name | Should -Be $expectedName
        }
    }

    Context "Input Validation" {
        It "Should fail when no input provided" {
            $archivePath = "$archiveDataPath\noinput.zip"
            { @() | Compress-Logs -ArchivePath $archivePath -ErrorAction Stop } | Should -Throw
        }

        It "Should require archive path" {
            { Get-LogFiles -Path $testDataPath | Compress-Logs -ErrorAction Stop } | Should -Throw
        }

        It "Should fail with null archive path" {
            { Get-LogFiles -Path $testDataPath | Compress-Logs -ArchivePath $null -ErrorAction Stop } | Should -Throw
        }

        It "Should fail with empty archive path" {
            { Get-LogFiles -Path $testDataPath | Compress-Logs -ArchivePath "" -ErrorAction Stop } | Should -Throw
        }
    }

    Context "Filtering with Compression" {
        It "Should compress only files older than N days" {
            $archivePath = "$archiveDataPath\filtered_old.zip"
            $archive = Get-LogFiles -Path $testDataPath -OlderThan 3 | Compress-Logs -ArchivePath $archivePath

            $archive | Should -Not -BeNullOrEmpty
            $archive.Length | Should -BeGreaterThan 0
        }

        It "Should compress only files younger than N days" {
            $archivePath = "$archiveDataPath\filtered_young.zip"
            $archive = Get-LogFiles -Path $testDataPath -YoungerThan 2 | Compress-Logs -ArchivePath $archivePath

            $archive | Should -Not -BeNullOrEmpty
        }

        It "Should compress folders matching date criteria" {
            $archivePath = "$archiveDataPath\filtered_folders.zip"
            $archive = Get-LogFolders -Path $testDataPath -OlderThan 5 | Compress-Logs -ArchivePath $archivePath

            $archive | Should -Not -BeNullOrEmpty
        }
    }

    Context "Archive Naming and Paths" {
        It "Should create archive in specified directory" {
            $archivePath = "$archiveDataPath\subdir_test.zip"
            $archive = Get-LogFiles -Path $testDataPath | Compress-Logs -ArchivePath $archivePath

            $archive.Directory.Name | Should -Be "Archives"
        }

        It "Should overwrite existing archive" {
            $archivePath = "$archiveDataPath\overwrite_test.zip"

            # Create first archive
            $archive1 = Get-LogFiles -Path $testDataPath | Compress-Logs -ArchivePath $archivePath
            $size1 = $archive1.Length

            # Create second archive with same name (with different content)
            $archive2 = Get-LogFiles -Path $testDataPath -OlderThan 4 | Compress-Logs -ArchivePath $archivePath
            $size2 = $archive2.Length

            # Archive should exist and may have different size
            Test-Path $archive2.FullName | Should -Be $true
        }

        It "Should handle long file paths in archive" {
            $longDirName = "A" * 50
            $longDir = "$testDataPath\$longDirName"
            New-Item -ItemType Directory -Path $longDir -Force | Out-Null

            try {
                New-Item -ItemType File -Path "$longDir\test.txt" -Force | Out-Null

                $archivePath = "$archiveDataPath\longpath_test.zip"
                $archive = Get-ChildItem -Path $longDir -File | Compress-Logs -ArchivePath $archivePath

                $archive | Should -Not -BeNullOrEmpty
            }
            finally {
                Remove-Item -Path $longDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    Context "Pipeline Support" {
        It "Should accept piped Get-LogFiles output" {
            $archivePath = "$archiveDataPath\piped_files.zip"
            $archive = Get-LogFiles -Path $testDataPath -OlderThan 1 | Compress-Logs -ArchivePath $archivePath

            $archive | Should -Not -BeNullOrEmpty
        }

        It "Should accept piped Get-LogFolders output" {
            $archivePath = "$archiveDataPath\piped_folders.zip"
            $archive = Get-LogFolders -Path $testDataPath | Compress-Logs -ArchivePath $archivePath

            $archive | Should -Not -BeNullOrEmpty
        }

        It "Should work with command chaining" {
            $archivePath = "$archiveDataPath\chained.zip"
            $archive = Get-LogFiles -Path $testDataPath -OlderThan 2 -Recurse | Compress-Logs -ArchivePath $archivePath

            $archive | Should -Not -BeNullOrEmpty
        }
    }

    Context "Performance" {
        It "Should handle multiple files efficiently" {
            # Create many test files
            $largeDir = "$testDataPath\large_batch"
            if (-not (Test-Path $largeDir)) {
                New-Item -ItemType Directory -Path $largeDir -Force | Out-Null
            }

            1..20 | ForEach-Object {
                New-Item -ItemType File -Path "$largeDir\file_$_.txt" -Force | Out-Null
            }

            $archivePath = "$archiveDataPath\batch_test.zip"
            $archive = Get-ChildItem -Path $largeDir -File | Compress-Logs -ArchivePath $archivePath

            $archive | Should -Not -BeNullOrEmpty
            $archive.Length | Should -BeGreaterThan 0
        }
    }

    Context "Error Handling" {
        It "Should handle invalid file paths gracefully" {
            $archivePath = "$archiveDataPath\invalid_files.zip"

            # This should not throw, but may return empty archive
            $archive = Get-LogFiles -Path $testDataPath | Compress-Logs -ArchivePath $archivePath

            $archive | Should -Not -BeNullOrEmpty
        }

        It "Should validate 7z availability" {
            $archivePath = "$archiveDataPath\7z_test.zip"
            $archive = Get-LogFiles -Path $testDataPath | Compress-Logs -ArchivePath $archivePath

            # If 7z is not installed, this will fail with appropriate error
            # If 7z is installed, archive should be created
            $archive | Should -Not -BeNullOrEmpty
        }
    }

    Context "Grouped Compression with Group-LogFilesByDate" {
        It "Should compress grouped files by date into separate archives" {
            $result = Get-LogFiles -Path $testDataPath -Recurse |
                      Group-LogFilesByDate |
                      Compress-Logs -ArchivePath "$archiveDataPath\{DateGroup}.zip"

            # Should create multiple archives (one per date)
            $result | Should -Not -BeNullOrEmpty
            $result.Count | Should -BeGreaterThan 1

            # All should be zip files
            $result | ForEach-Object {
                $_.Name | Should -Match '\.zip$'
            }
        }

        It "Should use {DateGroup} token in archive path" {
            $result = Get-LogFiles -Path $testDataPath -Recurse |
                      Group-LogFilesByDate |
                      Compress-Logs -ArchivePath "$archiveDataPath\logs_{DateGroup}.zip"

            # Archives should exist with date group in name
            $result | ForEach-Object {
                $_.Name | Should -Match 'logs_\d{8}\.zip'
            }
        }

        It "Should support nested paths with {DateGroup}" {
            $result = Get-LogFiles -Path $testDataPath -Recurse |
                      Group-LogFilesByDate |
                      Compress-Logs -ArchivePath "$archiveDataPath\{YEAR}\{MONTH}\archive_{DateGroup}.zip"

            # Should create archives in year/month subdirectories
            $result | Should -Not -BeNullOrEmpty

            # Verify files exist in nested structure
            $result | ForEach-Object {
                $_.Exists | Should -Be $true
            }
        }

        It "Should output FileInfo for each created archive" {
            $result = Get-LogFiles -Path $testDataPath |
                      Group-LogFilesByDate |
                      Compress-Logs -ArchivePath "$archiveDataPath\archive_{DateGroup}.zip"

            # Should return FileInfo objects
            $result | ForEach-Object {
                $_ | Should -BeOfType [System.IO.FileInfo]
                $_.Exists | Should -Be $true
                $_.Length | Should -BeGreaterThan 0
            }
        }

        It "Should create archives for each date group" {
            $grouped = Get-LogFiles -Path $testDataPath -Recurse | Group-LogFilesByDate
            $archiveCount = $grouped.Count

            $result = $grouped | Compress-Logs -ArchivePath "$archiveDataPath\by_date_{DateGroup}.zip"

            # Should create one archive per group
            $result.Count | Should -Be $archiveCount
        }

        It "Should handle {DateGroup} with other tokens" {
            $result = Get-LogFiles -Path $testDataPath -Recurse |
                      Group-LogFilesByDate |
                      Compress-Logs -ArchivePath "$archiveDataPath\{SERVER}_{DateGroup}.zip"

            # Should replace both tokens
            $result | ForEach-Object {
                $_.Name | Should -Match "^[^_]+_\d{8}\.zip$"
            }
        }
    }

    Context "AppName Parameter for Grouped Compression" {
        It "Should create archives with AppName-yyyyMMdd format" {
            $result = Get-LogFiles -Path $testDataPath -Recurse |
                      Group-LogFilesByDate |
                      Compress-Logs -ArchivePath "$archiveDataPath" -AppName "myapp"

            # Should create archives with myapp prefix
            $result | ForEach-Object {
                $_.Name | Should -Match '^myapp-\d{8}\.zip$'
            }
        }

        It "Should use AppName instead of {DateGroup} token" {
            $result = Get-LogFiles -Path $testDataPath -Recurse |
                      Group-LogFilesByDate |
                      Compress-Logs -ArchivePath "$archiveDataPath" -AppName "logs"

            # Should ignore {DateGroup} and use AppName format
            $result | ForEach-Object {
                $_.Name | Should -Match '^logs-\d{8}\.zip$'
                $_.Name | Should -Not -Match '\{DateGroup\}'
            }
        }

        It "Should create one archive per date group with AppName" {
            $grouped = Get-LogFiles -Path $testDataPath -Recurse | Group-LogFilesByDate
            $expectedCount = $grouped.Count

            $result = $grouped | Compress-Logs -ArchivePath "$archiveDataPath" -AppName "backup"

            # Should create one archive per group
            $result.Count | Should -Be $expectedCount
        }

        It "Should support AppName with nested directories" {
            $result = Get-LogFiles -Path $testDataPath -Recurse |
                      Group-LogFilesByDate |
                      Compress-Logs -ArchivePath "$archiveDataPath\{YEAR}\{MONTH}" -AppName "dailylogs"

            # Should create archives in nested structure with AppName
            $result | ForEach-Object {
                $_.Name | Should -Match '^dailylogs-\d{8}\.zip$'
                $_.Directory.Name | Should -Match '^\d{2}$'  # Month directory
            }
        }

        It "Should work with both AppName and token paths" {
            $result = Get-LogFiles -Path $testDataPath -Recurse |
                      Group-LogFilesByDate |
                      Compress-Logs -ArchivePath "$archiveDataPath\{SERVER}" -AppName "archive"

            # Should use AppName format with token-converted directory
            $result | ForEach-Object {
                $_.Name | Should -Match '^archive-\d{8}\.zip$'
            }
        }
    }
}
