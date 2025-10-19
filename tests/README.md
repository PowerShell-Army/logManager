# logManager Test Suite

Comprehensive Pester tests for all logManager cmdlets.

## Test Structure

```
tests/
├── unit/                                 # Individual test files
│   ├── Convert-TokenPath.Tests.ps1      # Token conversion tests
│   ├── Get-LogFiles.Tests.ps1           # Log file retrieval tests
│   ├── Get-LogFolders.Tests.ps1         # Log folder retrieval tests
│   └── Compress-Logs.Tests.ps1          # Log compression tests
├── data/                                 # Test data (auto-created and cleaned)
├── Run-Tests.ps1                        # Main test runner
└── README.md                            # This file
```

## Running Tests

### Run All Tests

```powershell
cd tests
.\Run-Tests.ps1
```

### Run with Detailed Output

```powershell
.\Run-Tests.ps1 -Show
```

### Run Specific Test Suite

```powershell
Invoke-Pester -Path ".\unit\Convert-TokenPath.Tests.ps1"
Invoke-Pester -Path ".\unit\Get-LogFiles.Tests.ps1"
Invoke-Pester -Path ".\unit\Get-LogFolders.Tests.ps1"
Invoke-Pester -Path ".\unit\Compress-Logs.Tests.ps1"
```

## Test Coverage

### Convert-TokenPath Tests
- ✅ Token conversion ({SERVER}, {YEAR}, {MONTH}, {DAY})
- ✅ Case-insensitive token matching
- ✅ Whitespace tolerance in tokens
- ✅ Date parameter handling
- ✅ Path handling (UNC, forward/backward slashes)
- ✅ Error handling (invalid date formats)
- ✅ Pipeline support

### Get-LogFiles Tests
- ✅ Basic file retrieval
- ✅ Age filtering (OlderThan, YoungerThan)
- ✅ Combined age filtering
- ✅ DateType parameter (CreatedOn, LastModified)
- ✅ Recursion (-Recurse flag)
- ✅ Token conversion in path
- ✅ Pipeline support
- ✅ Edge cases (empty directory, zero values)

### Get-LogFolders Tests
- ✅ Folder retrieval with date format validation
- ✅ Support for yyyyMMdd and yyyy-MM-dd formats
- ✅ Filtering of invalid format folders
- ✅ Age filtering (OlderThan, YoungerThan)
- ✅ Combined age filtering
- ✅ DateType parameter (CreatedOn, LastModified)
- ✅ Token conversion in path
- ✅ Pipeline support
- ✅ Edge cases (empty directory, no valid folders)

### Compress-Logs Tests
- ✅ Basic compression (files and folders)
- ✅ ZIP extension requirement and validation
- ✅ Case-insensitive extension handling
- ✅ Token path conversion ({SERVER}, {YEAR}, {MONTH}, {DAY})
- ✅ Input validation
- ✅ Filtering with compression
- ✅ Archive naming and paths
- ✅ Pipeline support
- ✅ Performance with multiple files
- ✅ Error handling

## Test Data Handling

- All test data is created in `tests/data/` directory
- Each test suite creates its own subdirectory for isolation
- Test data is **automatically cleaned up** after test execution
- No test data is persisted between test runs

### Test Data Directories

- `tests/data/LogFilesTest/` - Get-LogFiles test data
- `tests/data/LogFoldersTest/` - Get-LogFolders test data
- `tests/data/CompressTest/` - Compress-Logs test data
- `tests/data/Archives/` - Archive output for compression tests

## Requirements

- PowerShell 7.0+
- Pester module (included with PowerShell 7+)
- 7-Zip (for Compress-Logs tests)
- logManager module built and available at `src/logManager/bin/Debug/net9.0/logManager.dll`

## Test Results

Tests output a comprehensive summary including:
- Total number of tests executed
- Number of passed tests
- Number of failed tests
- Number of skipped tests

Example output:
```
==================================================
Test Summary
==================================================
Total Tests:    156
Passed:         156
Failed:         0
Skipped:        0

All tests passed!
```

## Troubleshooting

### Tests Fail with "Module not found"
- Ensure logManager is built: `dotnet build src/logManager`
- Verify the DLL exists at `src/logManager/bin/Debug/net9.0/logManager.dll`

### Compress-Logs Tests Fail
- Ensure 7-Zip is installed on your system
- Common 7-Zip installation paths:
  - `C:\Program Files\7-Zip\7z.exe`
  - `C:\Program Files (x86)\7-Zip\7z.exe`

### Test Data Not Cleaned Up
- Manually remove `tests/data/` directory
- Restart PowerShell session to release file locks

## Continuous Integration

The test suite can be integrated into CI/CD pipelines:

```powershell
# Run tests and exit with appropriate code
.\tests\Run-Tests.ps1

# Capture exit code
if ($LASTEXITCODE -ne 0) {
    Write-Host "Tests failed!"
    exit 1
}
```

## Contributing Tests

When adding new tests:

1. Create a new `.Tests.ps1` file in `tests/unit/`
2. Use `BeforeAll` for setup and module import
3. Use `AfterAll` for cleanup
4. Place test data in `tests/data/{Feature}Test/`
5. Clean up all test data in `AfterAll` block
6. Follow Pester naming conventions (Describe, Context, It)

Example template:

```powershell
BeforeAll {
    $modulePath = "$PSScriptRoot\..\..\src\logManager\bin\Debug\net9.0\logManager.dll"
    Import-Module $modulePath -Force

    $testDataPath = "$PSScriptRoot\..\data\MyFeatureTest"
    if (Test-Path $testDataPath) {
        Remove-Item -Path $testDataPath -Recurse -Force
    }
    New-Item -ItemType Directory -Path $testDataPath -Force | Out-Null
}

AfterAll {
    $testDataPath = "$PSScriptRoot\..\data\MyFeatureTest"
    if (Test-Path $testDataPath) {
        Remove-Item -Path $testDataPath -Recurse -Force
    }
}

Describe "My-Feature" {
    Context "Scenario" {
        It "Should do something" {
            # Arrange
            # Act
            # Assert
        }
    }
}
```
