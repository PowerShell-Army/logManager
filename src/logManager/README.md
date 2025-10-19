# logManager PowerShell Module

A modular PowerShell log management module built with C# 12 and .NET 9.0. The module targets PowerShell 7+ and provides an opinionated pipeline for finding, grouping, compressing, and archiving log files.

## Features

- Token-aware path handling (`{SERVER}`, `{YEAR}`, `{MONTH}`, `{DAY}`, `{DateGroup}`)
- Drive-local compression staging (no temp files on the OS drive)
- Date-aware grouping, ZIP creation, and S3 distribution
- Rich external help for every cmdlet (`en-US\logManager.dll-Help.xml`)
- Minimal build output (module DLL, manifest, docs, en-US help only)

## Project Layout

```
src/logManager/
├── logManager.csproj        # .NET project
├── logManager.psd1          # PowerShell module manifest
├── Cmdlets/                 # Public cmdlet implementations
├── Common/                  # Shared helpers (AWS, 7-zip, tokens, etc.)
├── Models/                  # Data contracts returned by cmdlets
└── en-US/                   # External help (source + binary copies)
```

## Prerequisites

- .NET 9 SDK (9.0.306 or newer)
- PowerShell 7.0 or newer
- 7-Zip installed and resolvable on the target machine (for `Compress-Logs`)
- AWS CLI v2 available in `PATH` for the S3 cmdlets

## Building

```powershell
cd src/logManager
# Debug build (default)
dotnet build

# Clean + rebuild
dotnet clean
dotnet build

# Release build
dotnet build -c Release
```

> After every build the output folder `bin/<Configuration>/net9.0` contains only the module artifacts (`logManager.dll`, `logManager.psd1`, `logManager.xml`, `logManager.deps.json`, and `en-US/`). Satellite language folders and RID-specific runtime assets are automatically trimmed.

## Loading the Module

```powershell
# Debug bits
dotnet build              # ensure current
Import-Module ./src/logManager/bin/Debug/net9.0/logManager.psd1 -Force

# Release bits (if built)
Import-Module ./src/logManager/bin/Release/net9.0/logManager.psd1 -Force

# Inspect surface area
Get-Command -Module logManager
Get-Help Test-S3Backup -Full
```

## Cmdlet Summary

| Cmdlet | Purpose | Highlights |
| --- | --- | --- |
| `Convert-TokenPath` | Replace tokens in filesystem paths. | Case-insensitive tokens; optional explicit date.
| `Get-LogFiles` | Enumerate log files with age filtering. | Older/Younger filters; CreatedOn vs LastModified; recursive search.
| `Get-LogFolders` | Enumerate dated folders (`yyyyMMdd`). | Age filtering and recursion support.
| `Group-LogFilesByDate` | Bundle files into `yyyyMMdd` buckets. | Pipeline friendly; output feeds `Compress-Logs`.
| `Compress-Logs` | Produce ZIP archives from files or groups. | Creates per-date archives, `{DateGroup}`/`AppName` support, staging on source drive.
| `Send-LogsToS3` | Upload archives to Amazon S3. | Token-aware keys, IAM/profile/explicit creds, checksum metadata/verification.
| `Test-S3Backup` | Inspect existing backups in S3. | Resolves tokens; returns `S3BackupInfo` metadata (Exists, size, ETag, LastModified).

## Example Pipelines

```powershell
# Single archive of all files older than 30 days
Get-LogFiles -Path 'C:\logs' -OlderThan 30 |
  Compress-Logs -ArchivePath 'C:\archive\logs.zip'

# Per-day archives with grouping and upload
Get-LogFiles -Path 'C:\logs' -Recurse -OlderThan 7 |
  Group-LogFilesByDate |
  Compress-Logs -ArchivePath 'C:\backup\{YEAR}\{MONTH}' -AppName 'weblogs' |
  Send-LogsToS3 -Bucket 'my-logs' -KeyPrefix 'archive/{YEAR}/{MONTH}/' -Region 'us-east-1'

# Skip uploads when the backup already exists
if (Test-S3Backup -Bucket 'my-logs' -Key 'archive/{YEAR}/{MONTH}/{DAY}/weblogs.zip') {
    Write-Host 'Archive already present in S3.'
} else {
    # perform compression + upload
}
```

## Packaging & Distribution

1. `dotnet build -c Release`
2. Copy `src/logManager/bin/Release/net9.0` to a clean distribution folder.
3. (Optional) Zip the folder or publish to an internal PowerShell repository.
4. Ensure the `en-US` directory travels with the module so `Get-Help` remains rich.

Every release should update the following:
- `logManager.psd1` – bump `ModuleVersion`, refresh metadata.
- `en-US/logManager-help.xml` & `en-US/logManager.dll-Help.xml` – keep cmdlet help in sync.
- `README.md` / `CLAUDE.md` – document new cmdlets or behaviors.

## Authoring New Cmdlets

1. Add a new class in `Cmdlets/` inheriting from `PSCmdlet`.
2. Follow PowerShell verb-noun guidelines (`Get-Verb`).
3. Use `[Parameter]` attributes to document pipeline/position metadata.
4. Update external help in both `en-US` files.
5. Build and run `Get-Help <Cmdlet> -Full` to verify documentation.

### Minimal Cmdlet Template

```csharp
using System.Management.Automation;

namespace logManager.Cmdlets;

[Cmdlet(VerbsCommon.Get, "Example")]
[OutputType(typeof(string))]
public class GetExampleCmdlet : PSCmdlet
{
    [Parameter(Position = 0, Mandatory = true, ValueFromPipeline = true)]
    public string? Name { get; set; }

    protected override void ProcessRecord()
    {
        WriteObject($"Example: {Name}");
    }
}
```

## Help Authoring

- Edit `src/logManager/en-US/logManager-help.xml` (source of truth).
- Mirror changes to `src/logManager/en-US/logManager.dll-Help.xml` (binary copy).
- After building, confirm `Get-Help <Cmdlet> -Full` shows the new content.

## Testing

- Unit tests live under `tests/` (Pester). Run via `Invoke-Pester` from repo root.
- Manual smoke tests: exercise key pipelines and verify S3 connectivity when credentials are available.

## Support

Please open an issue or sync with the module maintainers for questions, defects, or feature requests.