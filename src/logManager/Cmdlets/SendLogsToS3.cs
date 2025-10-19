using System;
using System.Globalization;
using System.IO;
using System.Management.Automation;
using System.Text.RegularExpressions;
using logManager.Common;

namespace logManager.Cmdlets
{
    /// <summary>
    /// Sends log files to AWS S3 for long-term storage.
    /// Supports IAM role authentication, integrity verification, and token-based key generation.
    /// </summary>
    [Cmdlet(VerbsCommunications.Send, "LogsToS3", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Medium)]
    [OutputType(typeof(FileInfo))]
    public class SendLogsToS3Cmdlet : PSCmdlet
    {
        /// <summary>
        /// Input file to upload to S3 (typically from Compress-Logs).
        /// </summary>
        [Parameter(
            Mandatory = true,
            Position = 0,
            ValueFromPipeline = true,
            ValueFromPipelineByPropertyName = true,
            HelpMessage = "FileInfo object to upload (e.g., from Compress-Logs)")]
        [ValidateNotNull]
        public FileInfo? InputFile { get; set; }

        /// <summary>
        /// S3 bucket name.
        /// </summary>
        [Parameter(
            Mandatory = true,
            Position = 1,
            HelpMessage = "S3 bucket name")]
        [ValidateNotNullOrEmpty]
        public string? Bucket { get; set; }

        /// <summary>
        /// S3 key prefix (supports tokens: {SERVER}, {YEAR}, {MONTH}, {DAY}).
        /// </summary>
        [Parameter(
            Mandatory = false,
            Position = 2,
            HelpMessage = "S3 key prefix (supports tokens). Example: 'archive/{YEAR}/{MONTH}/'")]
        public string? KeyPrefix { get; set; }

        /// <summary>
        /// AWS profile name (optional, uses default if not specified).
        /// </summary>
        [Parameter(
            Mandatory = false,
            HelpMessage = "AWS profile name from ~/.aws/credentials")]
        public string? ProfileName { get; set; }

        /// <summary>
        /// AWS region (optional, uses default region if not specified).
        /// </summary>
        [Parameter(
            Mandatory = false,
            HelpMessage = "AWS region (e.g., us-east-1)")]
        public string? Region { get; set; }

        /// <summary>
        /// AWS access key ID (optional, primarily use IAM role or profile).
        /// </summary>
        [Parameter(
            Mandatory = false,
            HelpMessage = "AWS access key ID (use IAM role or profile when possible)")]
        public string? AccessKey { get; set; }

        /// <summary>
        /// AWS secret access key (optional, required if AccessKey is specified).
        /// </summary>
        [Parameter(
            Mandatory = false,
            HelpMessage = "AWS secret access key (required if AccessKey is specified)")]
        public string? SecretKey { get; set; }

        /// <summary>
        /// S3 storage class (default: STANDARD).
        /// </summary>
        [Parameter(
            Mandatory = false,
            HelpMessage = "S3 storage class (STANDARD, INTELLIGENT_TIERING, GLACIER, etc.)")]
        [ValidateSet("STANDARD", "REDUCED_REDUNDANCY", "STANDARD_IA", "ONEZONE_IA",
                     "INTELLIGENT_TIERING", "GLACIER", "DEEP_ARCHIVE", "GLACIER_IR")]
        public string? StorageClass { get; set; }

        /// <summary>
        /// Skip integrity verification (not recommended).
        /// </summary>
        [Parameter(
            Mandatory = false,
            HelpMessage = "Skip integrity verification (not recommended)")]
        public SwitchParameter SkipVerification { get; set; }

        /// <summary>
        /// Force overwrite if object already exists.
        /// </summary>
        [Parameter(
            Mandatory = false,
            HelpMessage = "Force overwrite if S3 object already exists")]
        public SwitchParameter Force { get; set; }

        /// <summary>
        /// Return S3UploadResult object with upload details.
        /// </summary>
        [Parameter(
            Mandatory = false,
            HelpMessage = "Return S3UploadResult object with upload details")]
        public SwitchParameter PassThru { get; set; }

        private string? _keyPrefixTemplate;

        /// <summary>
        /// Validates parameters and converts token-based key prefix.
        /// </summary>
        protected override void BeginProcessing()
        {
            _keyPrefixTemplate = null;

            // Validate AccessKey/SecretKey pair
            if (!string.IsNullOrEmpty(AccessKey) && string.IsNullOrEmpty(SecretKey))
            {
                ThrowTerminatingError(new ErrorRecord(
                    new ArgumentException("SecretKey is required when AccessKey is specified"),
                    "MissingSecretKey",
                    ErrorCategory.InvalidArgument,
                    AccessKey));
            }

            if (!string.IsNullOrEmpty(SecretKey) && string.IsNullOrEmpty(AccessKey))
            {
                ThrowTerminatingError(new ErrorRecord(
                    new ArgumentException("AccessKey is required when SecretKey is specified"),
                    "MissingAccessKey",
                    ErrorCategory.InvalidArgument,
                    SecretKey));
            }

            // Convert tokens in KeyPrefix if specified
            if (!string.IsNullOrEmpty(KeyPrefix))
            {
                string normalizedTemplate = NormalizeKeyPrefix(KeyPrefix);
                _keyPrefixTemplate = string.IsNullOrEmpty(normalizedTemplate) ? null : normalizedTemplate;
                WriteVerbose($"Normalized key prefix template: {KeyPrefix} -> {_keyPrefixTemplate ?? "<root>"}");
            }

            // Verify AWS CLI is available
            string? awsCli = AwsS3Helper.FindAwsCli();
            if (string.IsNullOrEmpty(awsCli))
            {
                ThrowTerminatingError(new ErrorRecord(
                    new FileNotFoundException(
                        "AWS CLI not found. Install AWS CLI v2 from https://aws.amazon.com/cli/ " +
                        "or ensure it's in your PATH."),
                    "AwsCliNotFound",
                    ErrorCategory.ObjectNotFound,
                    null));
            }

            WriteVerbose($"Using AWS CLI: {awsCli}");
        }

        /// <summary>
        /// Processes each input file and uploads to S3.
        /// </summary>
        protected override void ProcessRecord()
        {
            if (InputFile == null || !InputFile.Exists)
            {
                WriteError(new ErrorRecord(
                    new FileNotFoundException($"Input file not found: {InputFile?.FullName}"),
                    "FileNotFound",
                    ErrorCategory.ObjectNotFound,
                    InputFile));
                return;
            }

            try
            {
                // Build S3 key from prefix + filename
                string fileName = InputFile.Name;
                string? resolvedPrefix = null;

                if (!string.IsNullOrEmpty(_keyPrefixTemplate))
                {
                    DateTime tokenDate = DetermineTokenDate(InputFile, out string dateGroupToken);
                    string convertedPrefix = TokenConverter.Convert(_keyPrefixTemplate!, tokenDate, dateGroupToken);
                    string normalizedPrefix = NormalizeKeyPrefix(convertedPrefix);
                    resolvedPrefix = string.IsNullOrEmpty(normalizedPrefix) ? null : normalizedPrefix;
                }

                string s3Key = string.IsNullOrEmpty(resolvedPrefix)
                    ? fileName
                    : $"{resolvedPrefix}/{fileName}";

                // Check if object exists (for -Force validation)
                if (!Force.IsPresent && !SkipVerification.IsPresent)
                {
                    // Note: We rely on WhatIf/ShouldProcess for confirmation
                    // Checking object existence would add latency, so we let S3 overwrite
                }

                // WhatIf/Confirm support
                string target = $"s3://{Bucket}/{s3Key}";
                string action = $"Upload {InputFile.FullName} ({FormatBytes(InputFile.Length)})";

                if (!ShouldProcess(target, action))
                {
                    return;
                }

                // Perform upload with verification
                WriteVerbose($"Uploading {InputFile.Name} to {target}");

                var result = AwsS3Helper.Upload(
                    filePath: InputFile.FullName,
                    bucket: Bucket!,
                    key: s3Key,
                    profile: ProfileName,
                    region: Region,
                    accessKey: AccessKey,
                    secretKey: SecretKey,
                    storageClass: StorageClass,
                    skipVerification: SkipVerification.IsPresent,
                    writeVerbose: msg => WriteVerbose(msg),
                    writeWarning: msg => WriteWarning(msg)
                );

                // Write success message
                WriteVerbose($"Successfully uploaded to {result.S3Uri} in {result.UploadDurationSeconds:F2}s");

                // Return FileInfo for pipeline chaining
                WriteObject(InputFile);

                // Optionally return detailed result
                if (PassThru.IsPresent)
                {
                    WriteObject(result);
                }
            }
            catch (Exception ex)
            {
                WriteError(new ErrorRecord(
                    ex,
                    "S3UploadError",
                    ErrorCategory.OperationStopped,
                    InputFile));
            }
        }

        /// <summary>
        /// Formats bytes into human-readable format.
        /// </summary>
        private static string FormatBytes(long bytes)
        {
            string[] sizes = { "B", "KB", "MB", "GB", "TB" };
            double len = bytes;
            int order = 0;

            while (len >= 1024 && order < sizes.Length - 1)
            {
                order++;
                len /= 1024;
            }

            return $"{len:0.##} {sizes[order]}";
        }

        private static string NormalizeKeyPrefix(string? prefix)
        {
            if (string.IsNullOrWhiteSpace(prefix))
            {
                return string.Empty;
            }

            string normalized = prefix.Replace('\\', '/');
            normalized = normalized.Trim('/');

            return normalized;
        }

        private static DateTime DetermineTokenDate(FileInfo file, out string dateGroup)
        {
            DateTime candidate = file.LastWriteTime;

            DateTime? fromName = ExtractDateFromString(Path.GetFileNameWithoutExtension(file.Name));
            if (fromName.HasValue)
            {
                candidate = fromName.Value;
            }
            else
            {
                string? directoryName = file.Directory?.Name;
                DateTime? fromDirectory = ExtractDateFromString(directoryName);
                if (fromDirectory.HasValue)
                {
                    candidate = fromDirectory.Value;
                }
                else
                {
                    string? fullDirectory = file.Directory?.FullName;
                    DateTime? fromFullPath = ExtractDateFromString(fullDirectory);
                    if (fromFullPath.HasValue)
                    {
                        candidate = fromFullPath.Value;
                    }
                }
            }

            dateGroup = candidate.ToString("yyyyMMdd", CultureInfo.InvariantCulture);
            return candidate;
        }

        private static DateTime? ExtractDateFromString(string? value)
        {
            if (string.IsNullOrWhiteSpace(value))
            {
                return null;
            }

            foreach (Match match in Regex.Matches(value, @"(?<!\d)(\d{8})(?!\d)"))
            {
                if (DateTime.TryParseExact(match.Value, "yyyyMMdd", CultureInfo.InvariantCulture, DateTimeStyles.None, out var parsed))
                {
                    return parsed;
                }
            }

            foreach (Match match in Regex.Matches(value, @"(?<!\d)(\d{4})[-_.](\d{2})[-_.](\d{2})(?!\d)"))
            {
                string candidate = $"{match.Groups[1].Value}{match.Groups[2].Value}{match.Groups[3].Value}";
                if (DateTime.TryParseExact(candidate, "yyyyMMdd", CultureInfo.InvariantCulture, DateTimeStyles.None, out var parsed))
                {
                    return parsed;
                }
            }

            return null;
        }
    }
}
