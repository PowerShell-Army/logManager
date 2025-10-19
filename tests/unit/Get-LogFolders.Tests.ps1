BeforeAll {
    $modulePath = "$PSScriptRoot\..\..\src\logManager\bin\Debug\net9.0\logManager.dll"
    Import-Module $modulePath -Force

    $testDataPath = "$PSScriptRoot\..\data\LogFoldersTest"

    # Setup test data directory
    if (Test-Path $testDataPath) {
        Remove-Item -Path $testDataPath -Recurse -Force
    }
    New-Item -ItemType Directory -Path $testDataPath -Force | Out-Null

    $now = Get-Date

    # Create folders in yyyyMMdd format
    $folder1 = New-Item -ItemType Directory -Path "$testDataPath\20251018" -Force
    $folder1.CreationTime = $now.AddDays(-3)
    $folder1.LastWriteTime = $now.AddDays(-3)

    $folder2 = New-Item -ItemType Directory -Path "$testDataPath\20251010" -Force
    $folder2.CreationTime = $now.AddDays(-8)
    $folder2.LastWriteTime = $now.AddDays(-8)

    $folder3 = New-Item -ItemType Directory -Path "$testDataPath\20250930" -Force
    $folder3.CreationTime = $now.AddDays(-18)
    $folder3.LastWriteTime = $now.AddDays(-18)

    $folder4 = New-Item -ItemType Directory -Path "$testDataPath\20250915" -Force
    $folder4.CreationTime = $now.AddDays(-33)
    $folder4.LastWriteTime = $now.AddDays(-33)

    # Create folders in yyyy-MM-dd format
    $folder5 = New-Item -ItemType Directory -Path "$testDataPath\2025-10-01" -Force
    $folder5.CreationTime = $now.AddDays(-17)
    $folder5.LastWriteTime = $now.AddDays(-17)

    $folder6 = New-Item -ItemType Directory -Path "$testDataPath\2025-09-20" -Force
    $folder6.CreationTime = $now.AddDays(-28)
    $folder6.LastWriteTime = $now.AddDays(-28)

    # Create folders with invalid format (should be filtered out)
    $invalidFolder1 = New-Item -ItemType Directory -Path "$testDataPath\InvalidFolder" -Force
    $invalidFolder2 = New-Item -ItemType Directory -Path "$testDataPath\2025-10" -Force  # Partial format
    $invalidFolder3 = New-Item -ItemType Directory -Path "$testDataPath\20251" -Force  # Incomplete format
}

AfterAll {
    # Cleanup test data
    $testDataPath = "$PSScriptRoot\..\data\LogFoldersTest"
    if (Test-Path $testDataPath) {
        Remove-Item -Path $testDataPath -Recurse -Force
    }
}

Describe "Get-LogFolders" {
    Context "Basic Folder Retrieval" {
        It "Should retrieve all valid date-format folders" {
            $results = Get-LogFolders -Path $testDataPath
            $results | Should -HaveCount 6
        }

        It "Should return DirectoryInfo objects" {
            $results = Get-LogFolders -Path $testDataPath
            $results[0] | Should -BeOfType System.IO.DirectoryInfo
        }

        It "Should exclude folders with invalid format" {
            $results = Get-LogFolders -Path $testDataPath
            $results.Name | Should -Not -Contain "InvalidFolder"
            $results.Name | Should -Not -Contain "2025-10"
            $results.Name | Should -Not -Contain "20251"
        }

        It "Should include yyyyMMdd format folders" {
            $results = Get-LogFolders -Path $testDataPath
            $results.Name | Should -Contain "20251018"
            $results.Name | Should -Contain "20251010"
        }

        It "Should include yyyy-MM-dd format folders" {
            $results = Get-LogFolders -Path $testDataPath
            $results.Name | Should -Contain "2025-10-01"
            $results.Name | Should -Contain "2025-09-20"
        }

        It "Should fail with non-existent path" {
            { Get-LogFolders -Path "C:\NonExistent\Path" -ErrorAction Stop } | Should -Throw
        }
    }

    Context "Age Filtering - OlderThan" {
        It "Should filter folders older than 15 days" {
            $results = Get-LogFolders -Path $testDataPath -OlderThan 15
            $results | Should -HaveCount 4
            $results.Name | Should -Contain "20250930"
            $results.Name | Should -Contain "20250915"
            $results.Name | Should -Contain "2025-10-01"
            $results.Name | Should -Contain "2025-09-20"
        }

        It "Should filter folders older than 20 days" {
            $results = Get-LogFolders -Path $testDataPath -OlderThan 20
            $results | Should -HaveCount 2
            $results.Name | Should -Contain "20250915"
            $results.Name | Should -Contain "2025-09-20"
        }

        It "Should return no folders when threshold exceeds oldest" {
            $results = Get-LogFolders -Path $testDataPath -OlderThan 40
            $results | Should -BeNullOrEmpty
        }
    }

    Context "Age Filtering - YoungerThan" {
        It "Should filter folders younger than 10 days" {
            $results = Get-LogFolders -Path $testDataPath -YoungerThan 10
            $results | Should -HaveCount 2
            $results.Name | Should -Contain "20251018"
            $results.Name | Should -Contain "20251010"
        }

        It "Should filter folders younger than 5 days" {
            $results = Get-LogFolders -Path $testDataPath -YoungerThan 5
            $results | Should -HaveCount 1
            $results.Name | Should -Be "20251018"
        }

        It "Should return all folders when threshold exceeds newest" {
            $results = Get-LogFolders -Path $testDataPath -YoungerThan 40
            $results | Should -HaveCount 6
        }
    }

    Context "Combined Age Filtering" {
        It "Should filter with both OlderThan and YoungerThan" {
            $results = Get-LogFolders -Path $testDataPath -OlderThan 5 -YoungerThan 20
            $results | Should -HaveCount 3
            $results.Name | Should -Contain "20251010"
            $results.Name | Should -Contain "20250930"
            $results.Name | Should -Contain "2025-10-01"
        }

        It "Should return no folders when range is too narrow" {
            $results = Get-LogFolders -Path $testDataPath -OlderThan 20 -YoungerThan 5
            $results | Should -BeNullOrEmpty
        }

        It "Should handle exact boundaries" {
            $results = Get-LogFolders -Path $testDataPath -OlderThan 8 -YoungerThan 8
            $results.Name | Should -Be "20251010"
        }
    }

    Context "DateType Parameter" {
        It "Should use CreatedOn by default" {
            $results = Get-LogFolders -Path $testDataPath -OlderThan 15
            $results | Should -HaveCount 4
        }

        It "Should accept CreatedOn explicitly" {
            $results = Get-LogFolders -Path $testDataPath -OlderThan 15 -DateType CreatedOn
            $results | Should -HaveCount 4
        }

        It "Should accept LastModified" {
            $results = Get-LogFolders -Path $testDataPath -OlderThan 15 -DateType LastModified
            $results | Should -HaveCount 4
        }

        It "Should reject invalid DateType" {
            { Get-LogFolders -Path $testDataPath -DateType "InvalidType" -ErrorAction Stop } | Should -Throw
        }
    }

    Context "Name Format Validation" {
        It "Should correctly identify yyyyMMdd format" {
            $result = Get-LogFolders -Path $testDataPath | Where-Object { $_.Name -match '^\d{8}$' }
            $result | Should -HaveCount 4
        }

        It "Should correctly identify yyyy-MM-dd format" {
            $result = Get-LogFolders -Path $testDataPath | Where-Object { $_.Name -match '^\d{4}-\d{2}-\d{2}$' }
            $result | Should -HaveCount 2
        }

        It "Should reject folders without date format" {
            $invalidFolders = Get-ChildItem -Path $testDataPath -Directory -Filter "Invalid*"
            $results = Get-LogFolders -Path $testDataPath
            $results.Name | Should -Not -Contain "InvalidFolder"
        }
    }

    Context "Token Conversion" {
        It "Should convert tokens in path parameter" {
            $tokenPath = "/{SERVER}/data"

            # Create a test directory with the converted path
            $convertedPath = Convert-TokenPath -Path $tokenPath
            New-Item -ItemType Directory -Path $convertedPath -Force | Out-Null

            # Create a valid date-format folder
            $testFolder = New-Item -ItemType Directory -Path "$convertedPath\20251018" -Force

            try {
                $results = Get-LogFolders -Path $tokenPath
                $results.Name | Should -Contain "20251018"
            }
            finally {
                Remove-Item -Path (Split-Path $testFolder.FullName) -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    Context "Pipeline Support" {
        It "Should accept path via pipeline" {
            $results = $testDataPath | Get-LogFolders
            $results | Should -HaveCount 6
        }

        It "Should accept path and parameters via pipeline" {
            $results = $testDataPath | Get-LogFolders -OlderThan 20
            $results | Should -HaveCount 2
        }
    }

    Context "Edge Cases" {
        It "Should handle empty directory" {
            $emptyDir = "$testDataPath\empty"
            New-Item -ItemType Directory -Path $emptyDir -Force | Out-Null

            try {
                $results = Get-LogFolders -Path $emptyDir
                $results | Should -BeNullOrEmpty
            }
            finally {
                Remove-Item -Path $emptyDir -Force
            }
        }

        It "Should handle directory with no valid date folders" {
            $noDateDir = "$testDataPath\nodate"
            New-Item -ItemType Directory -Path $noDateDir -Force | Out-Null
            New-Item -ItemType Directory -Path "$noDateDir\folder1" -Force | Out-Null
            New-Item -ItemType Directory -Path "$noDateDir\folder2" -Force | Out-Null

            try {
                $results = Get-LogFolders -Path $noDateDir
                $results | Should -BeNullOrEmpty
            }
            finally {
                Remove-Item -Path $noDateDir -Recurse -Force
            }
        }

        It "Should handle zero OlderThan value" {
            $results = Get-LogFolders -Path $testDataPath -OlderThan 0
            $results | Should -HaveCount 6
        }
    }
}
