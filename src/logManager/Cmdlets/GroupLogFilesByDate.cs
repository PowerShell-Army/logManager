using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Management.Automation;

namespace logManager.Cmdlets
{
    /// <summary>
    /// Groups log files by date into yyyyMMdd date groups.
    /// Accepts pipeline input from Get-LogFiles or directory path.
    /// Returns PSCustomObject with DateGroup, Files, and Count properties.
    /// </summary>
    [Cmdlet(VerbsData.Group, "LogFilesByDate")]
    [OutputType(typeof(PSObject))]
    public class GroupLogFilesByDateCmdlet : PSCmdlet
    {
        /// <summary>
        /// Files from pipeline (Get-LogFiles output).
        /// </summary>
        [Parameter(
            Mandatory = false,
            ValueFromPipeline = true,
            HelpMessage = "FileInfo objects from Get-LogFiles")]
        public FileInfo[]? InputObject { get; set; }

        /// <summary>
        /// Directory path for file retrieval.
        /// </summary>
        [Parameter(
            Mandatory = false,
            Position = 0,
            HelpMessage = "Directory path to search for files")]
        [ValidateNotNullOrEmpty]
        public string? Path { get; set; }

        /// <summary>
        /// Search recursively through subdirectories.
        /// </summary>
        [Parameter(
            ParameterSetName = "ByPath",
            Mandatory = false,
            HelpMessage = "Search recursively through subdirectories")]
        public SwitchParameter Recurse { get; set; }

        /// <summary>
        /// Date type to use for grouping (CreatedOn or LastModified).
        /// </summary>
        [Parameter(
            Mandatory = false,
            HelpMessage = "Date type for grouping: CreatedOn (default) or LastModified")]
        [ValidateSet("CreatedOn", "LastModified")]
        public string DateType { get; set; } = "CreatedOn";


        private Dictionary<string, List<FileInfo>> _dateGroups = new();
        private bool _useCreationTime;
        private DateTime _now = DateTime.Now;
        private bool _usingPipeline = false;

        /// <summary>
        /// Validates parameters and caches computations.
        /// </summary>
        protected override void BeginProcessing()
        {
            // Cache date type comparison result
            _useCreationTime = DateType == "CreatedOn";

            // If using pipeline, flag it
            _usingPipeline = MyInvocation.BoundParameters.ContainsKey("InputObject");
        }

        /// <summary>
        /// Processes piped FileInfo objects.
        /// </summary>
        protected override void ProcessRecord()
        {
            if (InputObject != null)
            {
                _usingPipeline = true;
                foreach (var file in InputObject)
                {
                    ProcessFile(file);
                }
            }
        }

        /// <summary>
        /// Outputs grouped results after pipeline completes.
        /// </summary>
        protected override void EndProcessing()
        {
            // If using Path parameter, retrieve files first
            if (!_usingPipeline && !string.IsNullOrEmpty(Path))
            {
                var dirInfo = new DirectoryInfo(Path);
                if (!dirInfo.Exists)
                {
                    WriteError(new ErrorRecord(
                        new DirectoryNotFoundException($"Directory not found: {Path}"),
                        "DirectoryNotFound",
                        ErrorCategory.ObjectNotFound,
                        Path));
                    return;
                }

                var searchOption = Recurse ? SearchOption.AllDirectories : SearchOption.TopDirectoryOnly;
                var files = dirInfo.EnumerateFiles("*", searchOption);

                foreach (var file in files)
                {
                    ProcessFile(file);
                }
            }

            // Output grouped results sorted by date descending
            foreach (var dateGroup in _dateGroups.OrderByDescending(x => x.Key))
            {
                var groupObject = new PSObject();
                groupObject.Properties.Add(new PSNoteProperty("DateGroup", dateGroup.Key));
                groupObject.Properties.Add(new PSNoteProperty("Files", dateGroup.Value.ToArray()));
                groupObject.Properties.Add(new PSNoteProperty("Count", dateGroup.Value.Count));

                WriteObject(groupObject);
            }
        }

        /// <summary>
        /// Processes a single file and adds to appropriate date group.
        /// </summary>
        private void ProcessFile(FileInfo file)
        {
            // Get file date
            DateTime fileDate = _useCreationTime ? file.CreationTime : file.LastWriteTime;

            // Get date group key (yyyyMMdd)
            string dateKey = fileDate.ToString("yyyyMMdd");

            // Add to dictionary
            if (!_dateGroups.TryGetValue(dateKey, out var list))
            {
                list = new List<FileInfo>();
                _dateGroups[dateKey] = list;
            }

            list.Add(file);
        }
    }
}
