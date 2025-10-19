@{
    # Script module or binary module file associated with this manifest.
    RootModule = 'logManager.dll'

    # Version number of this module.
    ModuleVersion = '0.1.0'

    # Supported PSEditions
    CompatiblePSEditions = @('Core')

    # ID used to uniquely identify this module
    GUID = 'a1b2c3d4-e5f6-7890-abcd-ef1234567890'

    # Author of this module
    Author = 'Adam Branham'

    # Company or vendor of this module
    CompanyName = 'Unknown'

    # Copyright statement for this module
    Copyright = '(c) 2024. All rights reserved.'

    # Description of the functionality provided by this module
    Description = 'A modular PowerShell log file management module'

    # Minimum version of the PowerShell engine required by this module
    PowerShellVersion = '7.0'

    # Minimum version of the .NET Framework required by this module
    DotNetFrameworkVersion = '9.0'

    # Modules that must be imported into the global environment prior to importing this module
    RequiredModules = @()

    # Assemblies that must be loaded prior to importing this module
    RequiredAssemblies = @()

    # Script files (.ps1) that are run in the caller's environment prior to importing this module.
    ScriptsToProcess = @()

    # Type files (.ps1xml) to be loaded when importing this module
    TypesToProcess = @()

    # Format files (.ps1xml) to be loaded when importing this module
    FormatsToProcess = @()

    # Help info URI for this module
    HelpInfoURI = 'https://github.com/your-repo/logManager'

    # Functions to export from this module
    FunctionsToExport = @()

    # Cmdlets to export from this module
    CmdletsToExport = @(
        'Convert-TokenPath',
        'Get-LogFiles',
        'Get-LogFolders',
        'Group-LogFilesByDate',
        'Compress-Logs',
        'Send-LogsToS3',
        'Test-S3Backup'
    )

    # Variables to export from this module
    VariablesToExport = @()

    # Aliases to export from this module
    AliasesToExport = @()

    # Private data to pass to the module specified in RootModule/ModuleToProcess
    PrivateData = @{
        PSData = @{
            # Tags applied to this module for online galleries
            Tags = @('Logging', 'LogManagement', 'PowerShell')

            # A URL to the license for this module.
            LicenseUri = ''

            # A URL to the main website for this project.
            ProjectUri = ''

            # ReleaseNotes of this module
            ReleaseNotes = 'Initial framework release'
        }
    }
}
