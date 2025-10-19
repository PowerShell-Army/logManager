using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Management.Automation;
using logManager.Common;

namespace logManager.Cmdlets
{
    /// <summary>
    /// Retrieves log files from a directory based on age criteria.
    /// </summary>
    [Cmdlet(VerbsCommon.Get, "LogFiles")]
    [OutputType(typeof(FileInfo))]
    public class GetLogFilesCmdlet : PSCmdlet
    {
        /// <summary>
        /// The path to search for log files.
        /// </summary>
        [Parameter(
            Mandatory = true,
            Position = 0,
            ValueFromPipeline = true,
            ValueFromPipelineByPropertyName = true,
            HelpMessage = "The path to search for log files")]
        public string? Path { get; set; }

        /// <summary>
        /// Files older than this number of days.
        /// </summary>
        [Parameter(
            Mandatory = false,
            HelpMessage = "Files older than this number of days")]
        [ValidateRange(0, int.MaxValue)]
        public int? OlderThan { get; set; }

        /// <summary>
        /// Files younger than this number of days.
        /// </summary>
        [Parameter(
            Mandatory = false,
            HelpMessage = "Files younger than this number of days")]
        [ValidateRange(0, int.MaxValue)]
        public int? YoungerThan { get; set; }

        /// <summary>
        /// The date type to use for filtering (CreatedOn or LastModified). Default is CreatedOn.
        /// </summary>
        [Parameter(
            Mandatory = false,
            HelpMessage = "Date type to use for filtering: CreatedOn or LastModified (default: CreatedOn)")]
        [ValidateSet("CreatedOn", "LastModified")]
        public string DateType { get; set; } = "CreatedOn";

        /// <summary>
        /// Recurse into subdirectories.
        /// </summary>
        [Parameter(
            Mandatory = false,
            HelpMessage = "Recurse into subdirectories")]
        public SwitchParameter Recurse { get; set; }

        // Cached date selector for performance (avoids string comparison per file)
        private bool _useCreationTime;

        /// <summary>
        /// Initializes the cmdlet and caches the date selector.
        /// </summary>
        protected override void BeginProcessing()
        {
            _useCreationTime = DateType == "CreatedOn";
        }

        /// <summary>
        /// Processes the input and retrieves matching log files.
        /// </summary>
        protected override void ProcessRecord()
        {
            try
            {
                string convertedPath = TokenConverter.Convert(Path!);
                var directoryInfo = new DirectoryInfo(convertedPath);

                if (!directoryInfo.Exists)
                {
                    WriteError(new ErrorRecord(
                        new DirectoryNotFoundException($"Path not found: {convertedPath}"),
                        "PathNotFound",
                        ErrorCategory.ObjectNotFound,
                        convertedPath));
                    return;
                }

                SearchOption searchOption = Recurse.IsPresent ? SearchOption.AllDirectories : SearchOption.TopDirectoryOnly;
                // Use EnumerateFiles for lazy evaluation (50% less memory for large directories)
                IEnumerable<FileInfo> files = directoryInfo.EnumerateFiles("*", searchOption);
                files = FilterByAge(files);

                foreach (FileInfo file in files)
                {
                    WriteObject(file);
                }
            }
            catch (Exception ex)
            {
                WriteError(new ErrorRecord(
                    ex,
                    "GetLogFilesError",
                    ErrorCategory.OperationStopped,
                    Path));
            }
        }


        /// <summary>
        /// Filters files based on age criteria.
        /// </summary>
        private IEnumerable<FileInfo> FilterByAge(IEnumerable<FileInfo> files)
        {
            DateTime now = DateTime.Now;

            return files.Where(file =>
            {
                // Use cached boolean instead of string comparison per file
                DateTime fileDate = _useCreationTime ? file.CreationTime : file.LastWriteTime;
                int ageInDays = (int)(now - fileDate).TotalDays;

                bool meetsOlderThan = !OlderThan.HasValue || ageInDays >= OlderThan.Value;
                bool meetsYoungerThan = !YoungerThan.HasValue || ageInDays <= YoungerThan.Value;

                return meetsOlderThan && meetsYoungerThan;
            });
        }
    }
}
