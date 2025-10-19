using System;
using System.Management.Automation;
using logManager.Common;

namespace logManager.Cmdlets
{
    /// <summary>
    /// Tests if a backup exists in S3 and returns its details.
    /// Supports token-based key paths ({SERVER}, {YEAR}, {MONTH}, {DAY}).
    /// </summary>
    [Cmdlet(VerbsDiagnostic.Test, "S3Backup", DefaultParameterSetName = "ByKey")]
    [OutputType(typeof(S3BackupInfo))]
    public class TestS3BackupCmdlet : PSCmdlet
    {
        /// <summary>
        /// S3 bucket name.
        /// </summary>
        [Parameter(
            Mandatory = true,
            Position = 0,
            HelpMessage = "S3 bucket name")]
        [ValidateNotNullOrEmpty]
        public string? Bucket { get; set; }

        /// <summary>
        /// S3 object key (supports tokens: {SERVER}, {YEAR}, {MONTH}, {DAY}).
        /// </summary>
        [Parameter(
            Mandatory = true,
            Position = 1,
            HelpMessage = "S3 object key (supports tokens: {SERVER}, {YEAR}, {MONTH}, {DAY})")]
        [ValidateNotNullOrEmpty]
        public string? Key { get; set; }

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

        private string? _convertedKey;

        /// <summary>
        /// Validates parameters and converts token-based key.
        /// </summary>
        protected override void BeginProcessing()
        {
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

            // Convert tokens in key if specified
            if (!string.IsNullOrEmpty(Key))
            {
                _convertedKey = TokenConverter.Convert(Key);
                WriteVerbose($"Converted key: {Key} -> {_convertedKey}");
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
        /// Tests if backup exists and returns its metadata.
        /// </summary>
        protected override void ProcessRecord()
        {
            try
            {
                WriteVerbose($"Checking S3 backup: s3://{Bucket}/{_convertedKey}");

                var backupInfo = AwsS3Helper.GetBackupInfo(
                    bucket: Bucket!,
                    key: _convertedKey!,
                    profile: ProfileName,
                    region: Region,
                    accessKey: AccessKey,
                    secretKey: SecretKey,
                    writeVerbose: msg => WriteVerbose(msg));

                if (backupInfo != null)
                {
                    WriteVerbose($"Backup exists: {FormatBytes(backupInfo.ContentLength)}, LastModified: {backupInfo.LastModified:u}");
                    WriteObject(backupInfo);
                }
                else
                {
                    WriteVerbose($"Backup not found: s3://{Bucket}/{_convertedKey}");
                    // Write nothing if backup doesn't exist (null output)
                }
            }
            catch (Exception ex)
            {
                WriteError(new ErrorRecord(
                    ex,
                    "S3BackupCheckError",
                    ErrorCategory.OperationStopped,
                    Key));
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
    }
}
