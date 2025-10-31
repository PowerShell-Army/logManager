using System.Management.Automation;
using System.Globalization;
using System.Text.RegularExpressions;

namespace LogManager.Cmdlets;

/// <summary>
/// Get-Folders cmdlet for retrieving folders based on date criteria parsed from folder names
/// </summary>
[Cmdlet(VerbsCommon.Get, "Folders")]
[OutputType(typeof(DirectoryInfo))]
public class GetFoldersCmdlet : PSCmdlet
{
    /// <summary>
    /// Path to the directory to search
    /// </summary>
    [Parameter(
        Mandatory = true,
        Position = 0,
        ValueFromPipeline = true,
        ValueFromPipelineByPropertyName = true,
        HelpMessage = "Path to the directory to search for folders")]
    [ValidateNotNullOrEmpty]
    public string Path { get; set; } = string.Empty;

    /// <summary>
    /// Folders older than this many days (exclusive)
    /// </summary>
    [Parameter(
        Mandatory = false,
        HelpMessage = "Get folders older than this many days")]
    [ValidateRange(0, int.MaxValue)]
    public int? OlderThan { get; set; }

    /// <summary>
    /// Folders younger than this many days (exclusive)
    /// </summary>
    [Parameter(
        Mandatory = false,
        HelpMessage = "Get folders younger than this many days")]
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
    /// Folder pattern to match (e.g., 2024*)
    /// </summary>
    [Parameter(
        Mandatory = false,
        HelpMessage = "Folder pattern to match (e.g., 2024*)")]
    public string Pattern { get; set; } = "*";

    // Regex patterns for date formats (compiled for performance)
    // Allow optional suffixes after the date (e.g., 20240101_001, 2024-01-01_backup)
    private static readonly Regex YyyyMmDdPattern = new Regex(
        @"^(\d{4})(\d{2})(\d{2})",
        RegexOptions.Compiled);

    private static readonly Regex YyyyDashMmDashDdPattern = new Regex(
        @"^(\d{4})-(\d{2})-(\d{2})",
        RegexOptions.Compiled);

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
            // Folders must be newer than (today - YoungerThan days)
            _minDate = today.AddDays(-YoungerThan.Value);
        }

        if (OlderThan.HasValue)
        {
            // Folders must be older than (today - OlderThan days)
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
            WriteVerbose($"Min date: {_minDate?.ToString("yyyy-MM-dd") ?? "None"}");
            WriteVerbose($"Max date: {_maxDate?.ToString("yyyy-MM-dd") ?? "None"}");

            // Simplified EnumerationOptions - only essential settings
            var enumerationOptions = new EnumerationOptions
            {
                RecurseSubdirectories = Recurse,
                IgnoreInaccessible = true
            };

            // Use Directory.EnumerateDirectories for best performance
            foreach (var folderPath in Directory.EnumerateDirectories(Path, Pattern, enumerationOptions))
            {
                // Check for stop signal
                if (Stopping)
                {
                    break;
                }

                try
                {
                    // Extract folder name without creating DirectoryInfo first (performance optimization)
                    var folderName = System.IO.Path.GetFileName(folderPath);

                    // Try to parse the date from the folder name
                    var folderDate = TryParseDateFromFolderName(folderName);

                    if (!folderDate.HasValue)
                    {
                        // Folder name doesn't match date format, skip it
                        WriteVerbose($"Skipping folder (invalid date format): {folderName}");
                        continue;
                    }

                    // Apply date filters
                    bool matchesFilter = true;

                    if (_minDate.HasValue && folderDate.Value <= _minDate.Value)
                    {
                        matchesFilter = false;
                    }

                    if (_maxDate.HasValue && folderDate.Value >= _maxDate.Value)
                    {
                        matchesFilter = false;
                    }

                    // Only create DirectoryInfo object for folders that pass the filter
                    if (matchesFilter)
                    {
                        WriteObject(new DirectoryInfo(folderPath));
                    }
                }
                catch (UnauthorizedAccessException ex)
                {
                    WriteWarning($"Access denied: {folderPath} - {ex.Message}");
                }
                catch (Exception ex)
                {
                    WriteError(new ErrorRecord(
                        ex,
                        "FolderAccessError",
                        ErrorCategory.ReadError,
                        folderPath));
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

    /// <summary>
    /// Attempts to parse a date from a folder name in formats: yyyyMMdd or yyyy-MM-dd
    /// </summary>
    /// <param name="folderName">The folder name to parse</param>
    /// <returns>DateTime if parsing succeeds, null otherwise</returns>
    private DateTime? TryParseDateFromFolderName(string folderName)
    {
        if (string.IsNullOrEmpty(folderName))
        {
            return null;
        }

        // Try yyyyMMdd format
        var match = YyyyMmDdPattern.Match(folderName);
        if (match.Success)
        {
            return TryCreateDate(
                int.Parse(match.Groups[1].Value),  // year
                int.Parse(match.Groups[2].Value),  // month
                int.Parse(match.Groups[3].Value)); // day
        }

        // Try yyyy-MM-dd format
        match = YyyyDashMmDashDdPattern.Match(folderName);
        if (match.Success)
        {
            return TryCreateDate(
                int.Parse(match.Groups[1].Value),  // year
                int.Parse(match.Groups[2].Value),  // month
                int.Parse(match.Groups[3].Value)); // day
        }

        return null;
    }

    /// <summary>
    /// Attempts to create a valid DateTime from year, month, day components
    /// </summary>
    /// <param name="year">Year</param>
    /// <param name="month">Month (1-12)</param>
    /// <param name="day">Day (1-31)</param>
    /// <returns>DateTime if valid, null otherwise</returns>
    private DateTime? TryCreateDate(int year, int month, int day)
    {
        try
        {
            // Validate ranges
            if (year < 1 || year > 9999 || month < 1 || month > 12 || day < 1 || day > 31)
            {
                return null;
            }

            // Try to create the date (will throw if invalid like Feb 30)
            return new DateTime(year, month, day);
        }
        catch (ArgumentOutOfRangeException)
        {
            // Invalid date (e.g., Feb 30, Apr 31, etc.)
            return null;
        }
    }
}
