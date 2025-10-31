using System.Management.Automation;

namespace LogManager.Cmdlets;

/// <summary>
/// Get-Files cmdlet for retrieving files based on date criteria
/// </summary>
[Cmdlet(VerbsCommon.Get, "Files")]
[OutputType(typeof(FileInfo))]
public class GetFilesCmdlet : PSCmdlet
{
    /// <summary>
    /// Path to the directory to search
    /// </summary>
    [Parameter(
        Mandatory = true,
        Position = 0,
        ValueFromPipeline = true,
        ValueFromPipelineByPropertyName = true,
        HelpMessage = "Path to the directory to search for files")]
    [ValidateNotNullOrEmpty]
    public string Path { get; set; } = string.Empty;

    /// <summary>
    /// Date type to filter by (CreatedOn or LastModified)
    /// </summary>
    [Parameter(
        Mandatory = false,
        HelpMessage = "Date type to filter by: CreatedOn or LastModified")]
    [ValidateSet("CreatedOn", "LastModified")]
    public string DateType { get; set; } = "CreatedOn";

    /// <summary>
    /// Files older than this many days (exclusive)
    /// </summary>
    [Parameter(
        Mandatory = false,
        HelpMessage = "Get files older than this many days")]
    [ValidateRange(0, int.MaxValue)]
    public int? OlderThan { get; set; }

    /// <summary>
    /// Files younger than this many days (exclusive)
    /// </summary>
    [Parameter(
        Mandatory = false,
        HelpMessage = "Get files younger than this many days")]
    [ValidateRange(0, int.MaxValue)]
    public int? YoungerThan { get; set; }

    /// <summary>
    /// Include subdirectories in the search
    /// </summary>
    [Parameter(
        Mandatory = false,
        HelpMessage = "Include subdirectories in the search")]
    public SwitchParameter Recurse { get; set; }

    /// <summary>
    /// File pattern to match (e.g., *.log)
    /// </summary>
    [Parameter(
        Mandatory = false,
        HelpMessage = "File pattern to match (e.g., *.log)")]
    public string Pattern { get; set; } = "*";

    protected override void BeginProcessing()
    {
        // Validate the path exists
        if (!Directory.Exists(Path))
        {
            ThrowTerminatingError(new ErrorRecord(
                new DirectoryNotFoundException($"Directory not found: {Path}"),
                "DirectoryNotFound",
                ErrorCategory.ObjectNotFound,
                Path));
        }

        // Validate logical date range
        if (OlderThan.HasValue && YoungerThan.HasValue && OlderThan.Value >= YoungerThan.Value)
        {
            ThrowTerminatingError(new ErrorRecord(
                new ArgumentException("OlderThan must be less than YoungerThan"),
                "InvalidDateRange",
                ErrorCategory.InvalidArgument,
                null));
        }

        // Calculate date boundaries once (performance optimization)
        var today = DateTime.Today;

        if (YoungerThan.HasValue)
        {
            // Files must be newer than (today - YoungerThan days)
            _minDate = today.AddDays(-YoungerThan.Value);
        }

        if (OlderThan.HasValue)
        {
            // Files must be older than (today - OlderThan days)
            _maxDate = today.AddDays(-OlderThan.Value);
        }
    }

    // Cached date boundaries calculated in BeginProcessing
    private DateTime? _minDate;
    private DateTime? _maxDate;

    protected override void ProcessRecord()
    {
        try
        {
            WriteVerbose($"Searching in: {Path}");
            WriteVerbose($"Date type: {DateType}");
            WriteVerbose($"Min date: {_minDate?.ToString("yyyy-MM-dd") ?? "None"}");
            WriteVerbose($"Max date: {_maxDate?.ToString("yyyy-MM-dd") ?? "None"}");

            // Simplified EnumerationOptions - only essential settings
            var enumerationOptions = new EnumerationOptions
            {
                RecurseSubdirectories = Recurse,
                IgnoreInaccessible = true
            };

            // Use Directory.EnumerateFiles for best performance
            foreach (var filePath in Directory.EnumerateFiles(Path, Pattern, enumerationOptions))
            {
                // Check for stop signal
                if (Stopping)
                {
                    break;
                }

                try
                {
                    // Get date without creating FileInfo object first (performance optimization)
                    var fileDate = DateType == "CreatedOn"
                        ? File.GetCreationTime(filePath).Date
                        : File.GetLastWriteTime(filePath).Date;

                    // Apply date filters
                    bool matchesFilter = true;

                    if (_minDate.HasValue && fileDate <= _minDate.Value)
                    {
                        matchesFilter = false;
                    }

                    if (_maxDate.HasValue && fileDate >= _maxDate.Value)
                    {
                        matchesFilter = false;
                    }

                    // Only create FileInfo object for files that pass the filter
                    if (matchesFilter)
                    {
                        WriteObject(new FileInfo(filePath));
                    }
                }
                catch (UnauthorizedAccessException ex)
                {
                    WriteWarning($"Access denied: {filePath} - {ex.Message}");
                }
                catch (Exception ex)
                {
                    WriteError(new ErrorRecord(
                        ex,
                        "FileAccessError",
                        ErrorCategory.ReadError,
                        filePath));
                }
            }
        }
        catch (UnauthorizedAccessException ex)
        {
            WriteError(new ErrorRecord(
                ex,
                "DirectoryAccessDenied",
                ErrorCategory.PermissionDenied,
                Path));
        }
        catch (Exception ex)
        {
            WriteError(new ErrorRecord(
                ex,
                "EnumerationError",
                ErrorCategory.NotSpecified,
                Path));
        }
    }
}
