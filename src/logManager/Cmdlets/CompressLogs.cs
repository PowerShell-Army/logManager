using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Management.Automation;
using System.Text;
using logManager.Common;

namespace logManager.Cmdlets
{
    /// <summary>
    /// Compresses files or folders from Get-LogFiles or Get-LogFolders to a ZIP archive.
    /// Optimized for performance with token path conversion support.
    /// </summary>
    [Cmdlet(VerbsData.Compress, "Logs")]
    [OutputType(typeof(FileInfo))]
    public class CompressLogsCmdlet : PSCmdlet
    {
        /// <summary>
        /// Input objects (FileInfo or DirectoryInfo) from pipeline.
        /// </summary>
        [Parameter(
            Mandatory = true,
            Position = 0,
            ValueFromPipeline = true,
            HelpMessage = "FileInfo or DirectoryInfo objects from Get-LogFiles or Get-LogFolders")]
        public PSObject[] InputObject { get; set; } = Array.Empty<PSObject>();

        /// <summary>
        /// Full path where the ZIP archive will be created (must end with .zip).
        /// Supports token conversion: {SERVER}, {YEAR}, {MONTH}, {DAY}
        /// When used with AppName, only directory path is required.
        /// </summary>
        [Parameter(
            Mandatory = true,
            Position = 1,
            HelpMessage = "Full path where the ZIP archive will be created (must end with .zip, supports token conversion)")]
        public string? ArchivePath { get; set; }

        /// <summary>
        /// Application name to use in archive filename format: APPNAME-yyyyMMdd.zip
        /// Only applies to grouped compression (Group-LogFilesByDate output).
        /// Overrides {DateGroup} token usage.
        /// </summary>
        [Parameter(
            Mandatory = false,
            HelpMessage = "Application name for grouped archives (format: APPNAME-yyyyMMdd.zip)")]
        [ValidateNotNullOrEmpty]
        public string? AppName { get; set; }

        private readonly List<PSObject> _groupedObjects = new();
        private bool? _isGroupedInput;
        private string? _convertedArchivePath;
        private string? _tempListFilePath;
        private StreamWriter? _tempListWriter;
        private int _singleArchiveItemCount;
        private string? _singleArchiveStagingDirectory;
        private string? _singleArchiveSourceRoot;

        /// <summary>
        /// Validates and converts archive path early (fail fast).
        /// </summary>
        protected override void BeginProcessing()
        {
            if (string.IsNullOrEmpty(ArchivePath))
            {
                ThrowTerminatingError(new ErrorRecord(
                    new ArgumentException("Archive path cannot be empty"),
                    "EmptyArchivePath",
                    ErrorCategory.InvalidArgument,
                    null));
                return;
            }

            _convertedArchivePath = TokenConverter.Convert(ArchivePath);

            // Validate archive path extension early (only if not using AppName)
            // When using AppName, ArchivePath is a directory, not a filename
            if (string.IsNullOrEmpty(AppName) && !_convertedArchivePath.EndsWith(".zip", StringComparison.OrdinalIgnoreCase))
            {
                ThrowTerminatingError(new ErrorRecord(
                    new ArgumentException("Archive path must end with .zip extension"),
                    "InvalidArchiveExtension",
                    ErrorCategory.InvalidArgument,
                    ArchivePath));
            }

            _groupedObjects.Clear();
            _isGroupedInput = null;
            _singleArchiveItemCount = 0;
            _tempListFilePath = null;
            _singleArchiveStagingDirectory = null;
            _singleArchiveSourceRoot = null;

            _tempListWriter?.Dispose();
            _tempListWriter = null;
        }

        /// <summary>
        /// Accumulates pipeline objects.
        /// </summary>
        protected override void ProcessRecord()
        {
            if (InputObject != null && InputObject.Length > 0)
            {
                foreach (var obj in InputObject)
                {
                    if (_isGroupedInput == null)
                    {
                        _isGroupedInput = IsGroupedInput(obj);
                    }

                    if (_isGroupedInput == true)
                    {
                        _groupedObjects.Add(obj);
                    }
                    else if (_isGroupedInput == false)
                    {
                        AppendToSingleArchiveList(obj);
                    }
                }
            }
        }

        /// <summary>
        /// Processes accumulated objects and performs compression.
        /// Handles both individual files and grouped objects from Group-LogFilesByDate.
        /// </summary>
        protected override void EndProcessing()
        {
            try
            {
                if (_isGroupedInput == null)
                {
                    WriteError(new ErrorRecord(
                        new ArgumentException("No input objects provided"),
                        "NoInputObjects",
                        ErrorCategory.InvalidArgument,
                        null));
                    return;
                }

                if (_isGroupedInput == true)
                {
                    if (_groupedObjects.Count == 0)
                    {
                        WriteError(new ErrorRecord(
                            new ArgumentException("No valid files or folders found in input"),
                            "NoValidPaths",
                            ErrorCategory.InvalidArgument,
                            null));
                        return;
                    }

                    CompressGroupedFiles(_groupedObjects);
                }
                else
                {
                    if (_singleArchiveItemCount == 0 || string.IsNullOrEmpty(_tempListFilePath))
                    {
                        WriteError(new ErrorRecord(
                            new ArgumentException("No valid files or folders found in input"),
                            "NoValidPaths",
                            ErrorCategory.InvalidArgument,
                            null));
                        return;
                    }

                    _tempListWriter?.Flush();
                    _tempListWriter?.Dispose();
                    _tempListWriter = null;

                    CompressSingleArchive(_tempListFilePath, _singleArchiveItemCount);
                }
            }
            catch (Exception ex)
            {
                WriteError(new ErrorRecord(
                    ex,
                    "CompressLogsError",
                    ErrorCategory.OperationStopped,
                    ArchivePath));
            }
            finally
            {
                _tempListWriter?.Dispose();
                _tempListWriter = null;

                if (!string.IsNullOrEmpty(_tempListFilePath) && File.Exists(_tempListFilePath))
                {
                    try
                    {
                        File.Delete(_tempListFilePath);
                    }
                    catch (Exception cleanupEx)
                    {
                        WriteVerbose($"Unable to delete temporary list file '{_tempListFilePath}': {cleanupEx.Message}");
                    }
                }
            }
        }

        /// <summary>
        /// Compresses individual files/folders into a single archive.
        /// </summary>
        private void CompressSingleArchive(string fileListPath, int itemCount)
        {
            if (itemCount == 0)
            {
                WriteError(new ErrorRecord(
                    new ArgumentException("No valid files or folders found in input"),
                    "NoValidPaths",
                    ErrorCategory.InvalidArgument,
                    null));
                return;
            }

            WriteVerbose($"Compressing {itemCount} items to {_convertedArchivePath}");

            try
            {
                // Perform compression
                bool success = SevenZipHelper.Compress(_convertedArchivePath!, fileListPath);

                if (!success)
                {
                    throw new InvalidOperationException("ZIP compression failed");
                }

                // Return archive info
                var archiveInfo = new FileInfo(_convertedArchivePath!);
                if (archiveInfo.Exists)
                {
                    WriteObject(archiveInfo);
                }
                else
                {
                    throw new FileNotFoundException($"Archive was not created: {_convertedArchivePath!}");
                }
            }
            finally
            {
                if (File.Exists(fileListPath))
                {
                    try
                    {
                        File.Delete(fileListPath);
                    }
                    catch (Exception cleanupEx)
                    {
                        WriteVerbose($"Unable to delete temporary list file '{fileListPath}': {cleanupEx.Message}");
                    }
                }
            }
        }

        /// <summary>
        /// Ensures the temporary list writer exists for single-archive mode.
        /// </summary>
        private void EnsureSingleArchiveWriter(string sourcePath)
        {
            if (_tempListWriter != null && !string.IsNullOrEmpty(_tempListFilePath))
            {
                return;
            }

            _singleArchiveStagingDirectory = SevenZipHelper.DetermineCompressionStagingDirectory(sourcePath);
            _tempListFilePath = Path.Combine(_singleArchiveStagingDirectory, $"7z_list_{Guid.NewGuid():N}.txt");
            _tempListWriter = new StreamWriter(
                new FileStream(_tempListFilePath, FileMode.Create, FileAccess.Write, FileShare.Read),
                new UTF8Encoding(encoderShouldEmitUTF8Identifier: false));
        }

        /// <summary>
        /// Appends a resolved path to the temporary list file for single-archive mode.
        /// </summary>
        private void AppendToSingleArchiveList(PSObject obj)
        {
            if (!TryExtractPath(obj, out var path) || string.IsNullOrEmpty(path))
            {
                return;
            }

            string fullPath;
            try
            {
                fullPath = Path.GetFullPath(path);
            }
            catch (Exception ex)
            {
                throw new InvalidOperationException($"Unable to resolve path '{path}' for compression.", ex);
            }

            string? pathRoot = Path.GetPathRoot(fullPath);
            if (string.IsNullOrEmpty(pathRoot))
            {
                throw new InvalidOperationException($"Unable to determine drive for compression source '{fullPath}'.");
            }

            if (_singleArchiveSourceRoot == null)
            {
                _singleArchiveSourceRoot = pathRoot;
            }
            else if (!string.Equals(_singleArchiveSourceRoot, pathRoot, StringComparison.OrdinalIgnoreCase))
            {
                throw new InvalidOperationException("Compression inputs span multiple drives. Split inputs by drive to ensure local staging.");
            }

            EnsureSingleArchiveWriter(fullPath);
            _tempListWriter!.WriteLine(path);
            _singleArchiveItemCount++;
        }

        /// <summary>
        /// Attempts to extract a supported filesystem path from the pipeline object.
        /// </summary>
        private static bool TryExtractPath(PSObject obj, out string? path)
        {
            switch (obj.BaseObject)
            {
                case FileInfo fileInfo:
                    path = fileInfo.FullName;
                    return true;
                case DirectoryInfo dirInfo:
                    path = dirInfo.FullName;
                    return true;
                default:
                    path = null;
                    return false;
            }
        }


        /// <summary>
        /// Compresses grouped files (from Group-LogFilesByDate) into multiple archives.
        /// One archive is created per date group using {DateGroup} token in ArchivePath.
        /// </summary>
        private void CompressGroupedFiles(List<PSObject> groupedObjects)
        {
            foreach (var groupObj in groupedObjects)
            {
                try
                {
                    // Extract group info
                    string? dateGroup = groupObj.Properties["DateGroup"]?.Value as string;
                    var filesArray = groupObj.Properties["Files"]?.Value as FileInfo[];

                    if (string.IsNullOrEmpty(dateGroup) || filesArray == null || filesArray.Length == 0)
                    {
                        continue;
                    }

                    // Build archive path for this date group
                    string archivePathForGroup;
                    DateTime? dateFromGroup = null;
                    if (DateTime.TryParseExact(dateGroup, "yyyyMMdd", CultureInfo.InvariantCulture, DateTimeStyles.None, out var parsedGroupDate))
                    {
                        dateFromGroup = parsedGroupDate;
                    }

                    if (!string.IsNullOrEmpty(AppName))
                    {
                        // If AppName provided, use format: APPNAME-yyyyMMdd.zip
                        string directory = TokenConverter.Convert(ArchivePath!, dateFromGroup, dateGroup);

                        // Ensure directory format (convert tokens first)
                        if (directory.EndsWith(".zip", StringComparison.OrdinalIgnoreCase))
                        {
                            directory = Path.GetDirectoryName(directory) ?? ".";
                        }

                        archivePathForGroup = Path.Combine(directory, $"{AppName}-{dateGroup}.zip");
                    }
                    else
                    {
                        archivePathForGroup = TokenConverter.Convert(ArchivePath!, dateFromGroup, dateGroup);
                    }

                    string convertedPath = archivePathForGroup;

                    // Validate archive extension (should always have .zip at this point)
                    if (!convertedPath.EndsWith(".zip", StringComparison.OrdinalIgnoreCase))
                    {
                        WriteError(new ErrorRecord(
                            new ArgumentException("Archive path must end with .zip extension"),
                            "InvalidArchiveExtension",
                            ErrorCategory.InvalidArgument,
                            ArchivePath));
                        continue;
                    }

                    // Ensure directory exists
                    string archiveDirectory = Path.GetDirectoryName(convertedPath) ?? ".";
                    if (!Directory.Exists(archiveDirectory))
                    {
                        Directory.CreateDirectory(archiveDirectory);
                    }

                    WriteVerbose($"Compressing {filesArray.Length} items ({dateGroup}) to {convertedPath}");

                    // Create temporary file list
                    var filePaths = filesArray.Select(f => f.FullName).ToList();
                    string fileListPath = SevenZipHelper.CreateFileList(filePaths);

                    try
                    {
                        // Perform compression
                        bool success = SevenZipHelper.Compress(convertedPath, fileListPath);

                        if (!success)
                        {
                            throw new InvalidOperationException($"ZIP compression failed for {dateGroup}");
                        }

                        // Return archive info
                        var archiveInfo = new FileInfo(convertedPath);
                        if (archiveInfo.Exists)
                        {
                            WriteObject(archiveInfo);
                        }
                        else
                        {
                            throw new FileNotFoundException($"Archive was not created: {convertedPath}");
                        }
                    }
                    finally
                    {
                        // Cleanup temporary file
                        if (File.Exists(fileListPath))
                        {
                            try
                            {
                                File.Delete(fileListPath);
                            }
                            catch (Exception cleanupEx)
                            {
                                WriteVerbose($"Unable to delete temporary list file '{fileListPath}': {cleanupEx.Message}");
                            }
                        }
                    }
                }
                catch (Exception ex)
                {
                    WriteError(new ErrorRecord(
                        ex,
                        "CompressGroupError",
                        ErrorCategory.OperationStopped,
                        ArchivePath));
                }
            }
        }

        /// <summary>
        /// Ensures temporary resources are cleaned up if processing stops prematurely.
        /// </summary>
        protected override void StopProcessing()
        {
            _tempListWriter?.Dispose();
            _tempListWriter = null;

            if (!string.IsNullOrEmpty(_tempListFilePath) && File.Exists(_tempListFilePath))
            {
                try
                {
                    File.Delete(_tempListFilePath);
                }
                catch (Exception cleanupEx)
                {
                    WriteVerbose($"Unable to delete temporary list file '{_tempListFilePath}': {cleanupEx.Message}");
                }
            }

            _singleArchiveStagingDirectory = null;
            _singleArchiveSourceRoot = null;

            base.StopProcessing();
        }

        /// <summary>
        /// Determines if input is from Group-LogFilesByDate (has DateGroup property).
        /// </summary>
        private bool IsGroupedInput(PSObject obj)
        {
            return obj.Properties["DateGroup"] != null && obj.Properties["Files"] != null;
        }



    }
}
