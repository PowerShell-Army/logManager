# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**logManager** is a PowerShell binary module written in C#/.NET 8.0 that provides high-performance cmdlets for file and folder management, particularly focused on date-based filtering and log management tasks.

## Build and Development Commands

### Building the Module
```bash
cd src
dotnet build
```

The compiled DLL is output to `src/bin/Debug/net8.0/logManager.dll`.

### Testing
```bash
# Run all tests from project root
pwsh -Command "Invoke-Pester -Path ./tests/*.Tests.ps1 -Output Detailed"

# Run specific test file
pwsh -Command "Invoke-Pester -Path ./tests/Get-Files.Tests.ps1 -Output Detailed"
pwsh -Command "Invoke-Pester -Path ./tests/Get-Folders.Tests.ps1 -Output Detailed"

# Run with normal output (less verbose)
pwsh -Command "Invoke-Pester -Path ./tests/*.Tests.ps1 -Output Normal"
```

### Loading the Module for Manual Testing
```powershell
# From project root
Import-Module ./src/logManager.psd1 -Force

# List available cmdlets
Get-Command -Module logManager

# Get help for a cmdlet
Get-Help Get-Files -Full
```

## Architecture

### Module Structure

This is a **binary PowerShell module** - PowerShell cmdlets are implemented in C# and compiled to a DLL, then loaded via a `.psd1` module manifest. This architecture provides:
- Superior performance compared to script modules
- Type safety and compile-time checking
- Access to full .NET ecosystem

**Key Files:**
- `src/logManager.psd1` - Module manifest that defines exported cmdlets and points to the compiled DLL
- `src/logManager.csproj` - .NET project file targeting net8.0 with PowerShellStandard.Library dependency
- `src/Cmdlets/*.cs` - Individual cmdlet implementations
- `src/Helpers/*.cs` - Shared helper classes

### Cmdlet Implementation Pattern

All cmdlets follow the PowerShell cmdlet pattern by inheriting from `PSCmdlet`:

1. **Parameters** - Decorated with `[Parameter]` attributes defining:
   - `Mandatory` - Whether parameter is required
   - `Position` - Positional parameter order (omit for named-only parameters)
   - `ValueFromPipeline` - Accept pipeline input
   - `HelpMessage` - Parameter description

2. **Lifecycle Methods**:
   - `BeginProcessing()` - Called once at start, used for validation
   - `ProcessRecord()` - Called for each pipeline input
   - `EndProcessing()` - Called once at end

3. **Output** - Use `WriteObject()` to send objects to pipeline, `WriteVerbose()` for verbose messages

### Performance Optimization Strategy

The cmdlets are optimized for processing large datasets (10,000+ objects):

1. **Lazy Enumeration** - Use `Directory.EnumerateFiles()` and `Directory.EnumerateDirectories()` instead of `GetFiles()`/`GetDirectories()` for memory efficiency

2. **Date Comparison** - Use `.Date` property to strip time component for accurate day-based comparisons

3. **Compiled Regex** - Date parsing uses `RegexOptions.Compiled` for performance when processing many folder names

4. **Early Filtering** - Apply date filters during enumeration rather than loading all objects first

5. **Cancellation Support** - Check `Stopping` property to respect pipeline cancellation

## Cmdlet-Specific Details

### Get-Files
Filters files by date (CreationTime or LastWriteTime) based on their file system metadata.

**Key Behaviors:**
- `-DateType` defaults to "CreatedOn" (optional parameter, no Position)
- Date comparisons use entire days (time stripped via `.Date`)
- `-OlderThan X` means file date < (today - X days)
- `-YoungerThan X` means file date > (today - X days)
- Both parameters are optional and can be combined

### Get-Folders
Filters folders by parsing dates from folder names (not file system dates).

**Key Behaviors:**
- Supports two date formats: `yyyyMMdd` (e.g., `20241030`) and `yyyy-MM-dd` (e.g., `2024-10-30`)
- Allows optional suffixes (e.g., `20241030_backup`, `2024-10-30_001`)
- Validates dates (rejects invalid dates like Feb 30, month 13, etc.)
- Regex patterns match from start of folder name only
- No `-DateType` parameter - always uses folder name

### Get-7ZipPath
Locates 7-Zip executable on Windows and Linux systems.

**Search Order:**
- Windows: Common Program Files locations, then PATH
- Linux: Common bin directories (`/usr/bin`, `/usr/local/bin`, etc.), then PATH via `which` command

## Test Architecture

Tests use Pester v5 with comprehensive setup/teardown:

- **Test Scale**: Each test suite creates 10,000 objects (files or folders) across 5 dates
- **Automatic Cleanup**: `BeforeAll` creates test data, `AfterAll` removes it - no persistent test artifacts
- **Date-Based Testing**: Uses relative dates (`Today.AddDays(-X)`) so tests remain valid over time
- **Performance Thresholds**: Tests verify cmdlets process 10,000 objects in < 15 seconds

**Test Data Locations:**
- Get-Files: `tests/data/` (temporary)
- Get-Folders: `tests/data/folders_test/` (temporary)

## Adding New Cmdlets

1. Create cmdlet class in `src/Cmdlets/` inheriting from `PSCmdlet`
2. Use `[Cmdlet(Verb, Noun)]` attribute with approved PowerShell verbs
3. Add to `CmdletsToExport` array in `src/logManager.psd1`
4. Build with `dotnet build`
5. Create corresponding Pester test in `tests/`

## Module Manifest Notes

The module manifest (`logManager.psd1`) uses a **relative path** to the compiled DLL:
```powershell
RootModule = './bin/Debug/net8.0/logManager.dll'
```

This means the manifest must be imported from the `src/` directory or the build output must be copied to the manifest's location.
- ALWAYS adhere to KISS, YAGNI, and DRY coding practices.