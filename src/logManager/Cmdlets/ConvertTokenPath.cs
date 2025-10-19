using System;
using System.Globalization;
using System.Management.Automation;
using logManager.Common;

namespace logManager.Cmdlets
{
    /// <summary>
    /// Converts token placeholders in a path to their actual values.
    /// Supported tokens: {SERVER}, {YEAR}, {MONTH}, {DAY}
    /// </summary>
    [Cmdlet(VerbsData.Convert, "TokenPath")]
    [OutputType(typeof(string))]
    public class ConvertTokenPathCmdlet : PSCmdlet
    {
        /// <summary>
        /// The path containing tokens to be converted.
        /// </summary>
        [Parameter(
            Mandatory = true,
            Position = 0,
            ValueFromPipeline = true,
            ValueFromPipelineByPropertyName = true,
            HelpMessage = "The tokenized path to convert (e.g., '/{SERVER}/Logs/{YEAR}/')")]
        public string? Path { get; set; }

        /// <summary>
        /// Optional date in yyyyMMdd format for token conversion.
        /// If not supplied, today's date will be used.
        /// </summary>
        [Parameter(
            Mandatory = false,
            Position = 1,
            ValueFromPipelineByPropertyName = true,
            HelpMessage = "Date in yyyyMMdd format (e.g., 20251018). Defaults to today's date.")]
        public string? Date { get; set; }

        private DateTime _conversionDate;

        /// <summary>
        /// Initializes the cmdlet and validates the date parameter.
        /// </summary>
        protected override void BeginProcessing()
        {
            // Parse and validate the date parameter
            if (string.IsNullOrWhiteSpace(Date))
            {
                _conversionDate = DateTime.Today;
                WriteVerbose($"No date supplied. Using today's date: {_conversionDate:yyyyMMdd}");
            }
            else
            {
                if (!ValidateAndParseDate(Date, out DateTime parsedDate))
                {
                    ThrowTerminatingError(
                        new ErrorRecord(
                            new ArgumentException($"Date must be in yyyyMMdd format. Received: {Date}"),
                            "InvalidDateFormat",
                            ErrorCategory.InvalidArgument,
                            Date));
                    return;
                }

                _conversionDate = parsedDate;
                WriteVerbose($"Using provided date: {_conversionDate:yyyyMMdd}");
            }
        }

        /// <summary>
        /// Processes the input path and converts tokens.
        /// </summary>
        protected override void ProcessRecord()
        {
            if (string.IsNullOrEmpty(Path))
            {
                WriteError(new ErrorRecord(
                    new ArgumentException("Path cannot be null or empty."),
                    "EmptyPath",
                    ErrorCategory.InvalidArgument,
                    Path));
                return;
            }

            try
            {
                string convertedPath = TokenConverter.Convert(Path, _conversionDate);
                WriteObject(convertedPath);
            }
            catch (Exception ex)
            {
                WriteError(new ErrorRecord(
                    ex,
                    "TokenConversionError",
                    ErrorCategory.OperationStopped,
                    Path));
            }
        }

        /// <summary>
        /// Validates and parses a date string in yyyyMMdd format.
        /// </summary>
        private static bool ValidateAndParseDate(string dateString, out DateTime parsedDate)
        {
            return DateTime.TryParseExact(
                dateString,
                "yyyyMMdd",
                CultureInfo.InvariantCulture,
                DateTimeStyles.None,
                out parsedDate);
        }
    }
}
