using System;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Threading.Tasks;

namespace logManager.Common
{
    /// <summary>
    /// Helper class for AWS S3 operations using AWS CLI.
    /// Optimized for performance with lazy path caching and tiered verification.
    /// </summary>
    public static class AwsS3Helper
    {
        // Cached AWS CLI path for performance (eliminates repeated PATH searches)
        private static readonly Lazy<string?> CachedAwsCliPath = new Lazy<string?>(() =>
        {
            // Check common installation paths first
            var commonPaths = new[]
            {
                Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), "Amazon", "AWSCLIV2", "aws.exe"),
                "aws.exe", // From PATH
                "aws"      // Linux/Mac (for cross-platform support)
            };

            foreach (var path in commonPaths)
            {
                try
                {
                    var testInfo = new ProcessStartInfo
                    {
                        FileName = path,
                        Arguments = "--version",
                        UseShellExecute = false,
                        RedirectStandardOutput = true,
                        RedirectStandardError = true,
                        CreateNoWindow = true
                    };

                    using (var process = Process.Start(testInfo))
                    {
                        if (process != null)
                        {
                            bool exited = process.WaitForExit(5000); // 5 second timeout

                            if (!exited)
                            {
                                try
                                {
                                    process.Kill(entireProcessTree: true);
                                }
                                catch
                                {
                                    // Ignore kill failures; process might have exited between checks
                                }
                            }

                            if (exited && process.ExitCode == 0)
                            {
                                return path;
                            }
                        }
                    }
                }
                catch
                {
                    // Path not valid, try next
                    continue;
                }
            }

            return null;
        });

        /// <summary>
        /// File size thresholds for verification tiers (in bytes).
        /// </summary>
        private const long SmallFileThreshold = 1L * 1024 * 1024 * 1024;  // 1 GB
        private const long LargeFileThreshold = 10L * 1024 * 1024 * 1024; // 10 GB
        private const int AwsCliTimeoutHours = 12;
        private const int AwsCliTimeoutMilliseconds = AwsCliTimeoutHours * 60 * 60 * 1000;

        /// <summary>
        /// Finds the AWS CLI executable.
        /// </summary>
        public static string? FindAwsCli()
        {
            return CachedAwsCliPath.Value;
        }

        /// <summary>
        /// Uploads a file to S3 with integrity verification.
        /// </summary>
        public static S3UploadResult Upload(
            string filePath,
            string bucket,
            string key,
            string? profile = null,
            string? region = null,
            string? accessKey = null,
            string? secretKey = null,
            string? storageClass = null,
            bool skipVerification = false,
            Action<string>? writeVerbose = null,
            Action<string>? writeWarning = null)
        {
            string? awsCliPath = FindAwsCli();
            if (string.IsNullOrEmpty(awsCliPath))
            {
                throw new FileNotFoundException("AWS CLI not found. Install AWS CLI v2 from https://aws.amazon.com/cli/");
            }

            var fileInfo = new FileInfo(filePath);
            if (!fileInfo.Exists)
            {
                throw new FileNotFoundException($"File not found: {filePath}");
            }

            writeVerbose?.Invoke($"Uploading {fileInfo.Name} ({FormatBytes(fileInfo.Length)}) to s3://{bucket}/{key}");

            var startTime = DateTime.UtcNow;

            // Build upload arguments
            var args = new StringBuilder();
            args.Append($"s3 cp \"{filePath}\" s3://{bucket}/{key}");
            args.Append(" --no-progress"); // Clean output for parsing

            if (!string.IsNullOrEmpty(region))
            {
                args.Append($" --region {region}");
            }

            if (!string.IsNullOrEmpty(storageClass))
            {
                args.Append($" --storage-class {storageClass}");
            }

            // Compute checksum once so metadata and verification share the value
            string localMd5 = ComputeFileMd5(fileInfo.FullName);

            // Add metadata (includes source-md5 for verification/audit)
            var metadata = BuildMetadata(fileInfo, localMd5);
            args.Append($" --metadata {metadata}");

            // Execute upload
            var (exitCode, stdout, stderr) = RunAwsCli(awsCliPath, args.ToString(), profile, accessKey, secretKey);

            if (exitCode != 0)
            {
                string errorDetails = string.IsNullOrEmpty(stderr) ? stdout : stderr;
                throw new InvalidOperationException($"S3 upload failed with exit code {exitCode}. Details: {errorDetails}");
            }

            var uploadDuration = (DateTime.UtcNow - startTime).TotalSeconds;

            // Determine verification strategy based on file size
            var verificationResult = new VerificationResult { Success = true };

            if (!skipVerification)
            {
                if (fileInfo.Length < SmallFileThreshold)
                {
                    // Small files: Full verification (size + MD5)
                    writeVerbose?.Invoke("Verifying upload integrity (size + MD5)...");
                    verificationResult = VerifyUploadFull(filePath, bucket, key, awsCliPath, profile, accessKey, secretKey, region, localMd5);
                }
                else if (fileInfo.Length < LargeFileThreshold)
                {
                    // Medium files: Size check + MD5 (warn about time)
                    writeVerbose?.Invoke("Verifying upload integrity (size + MD5). This may take a moment for large files...");
                    verificationResult = VerifyUploadFull(filePath, bucket, key, awsCliPath, profile, accessKey, secretKey, region, localMd5);
                }
                else
                {
                    // Large files: Size check only (warn user)
                    writeWarning?.Invoke($"Large file detected ({FormatBytes(fileInfo.Length)}). Performing size-only verification. Use -SkipVerification if unneeded.");
                    verificationResult = VerifyUploadSizeOnly(filePath, bucket, key, awsCliPath, profile, accessKey, secretKey, region);
                }

                if (!verificationResult.Success)
                {
                    throw new InvalidOperationException($"Upload verification failed: {verificationResult.Error}");
                }

                writeVerbose?.Invoke($"Upload verified successfully. {verificationResult.Details}");
            }

            return new S3UploadResult
            {
                Success = true,
                S3Uri = $"s3://{bucket}/{key}",
                ETag = verificationResult.ETag,
                SourceMd5 = localMd5,
                ContentLength = fileInfo.Length,
                UploadDurationSeconds = uploadDuration,
                LocalFilePath = filePath
            };
        }

        /// <summary>
        /// Checks if a backup exists in S3 and returns its metadata.
        /// </summary>
        public static S3BackupInfo? GetBackupInfo(
            string bucket,
            string key,
            string? profile = null,
            string? region = null,
            string? accessKey = null,
            string? secretKey = null,
            Action<string>? writeVerbose = null)
        {
            string? awsCliPath = FindAwsCli();
            if (string.IsNullOrEmpty(awsCliPath))
            {
                throw new FileNotFoundException("AWS CLI not found. Install AWS CLI v2 from https://aws.amazon.com/cli/");
            }

            try
            {
                writeVerbose?.Invoke($"Checking if s3://{bucket}/{key} exists...");
                var metadata = GetObjectMetadata(bucket, key, awsCliPath, profile, accessKey, secretKey, region);

                string checksumInfo = string.IsNullOrEmpty(metadata.SourceMd5)
                    ? "(no metadata checksum)"
                    : $"MD5: {metadata.SourceMd5}";
                writeVerbose?.Invoke($"Backup found: {FormatBytes(metadata.ContentLength)}, ETag: {metadata.ETag} {checksumInfo}");

                return new S3BackupInfo
                {
                    Exists = true,
                    S3Uri = $"s3://{bucket}/{key}",
                    ContentLength = metadata.ContentLength,
                    ETag = metadata.ETag,
                    SourceMd5 = metadata.SourceMd5,
                    LastModified = metadata.LastModified
                };
            }
            catch (InvalidOperationException ex) when (ex.Message.Contains("NoSuchKey"))
            {
                writeVerbose?.Invoke($"Backup not found: s3://{bucket}/{key}");
                return null;
            }
            catch (Exception ex)
            {
                writeVerbose?.Invoke($"Error checking backup: {ex.Message}");
                throw;
            }
        }

        /// <summary>
        /// Full verification: size + metadata checksum comparison.
        /// </summary>
        private static VerificationResult VerifyUploadFull(
            string filePath,
            string bucket,
            string key,
            string awsCliPath,
            string? profile,
            string? accessKey,
            string? secretKey,
            string? region,
            string localMd5)
        {
            // Get S3 object metadata
            var metadata = GetObjectMetadata(bucket, key, awsCliPath, profile, accessKey, secretKey, region);

            var fileInfo = new FileInfo(filePath);

            // Check size
            if (metadata.ContentLength != fileInfo.Length)
            {
                return new VerificationResult
                {
                    Success = false,
                    Error = $"Size mismatch: local {fileInfo.Length} bytes, S3 {metadata.ContentLength} bytes"
                };
            }

            // Compare with S3 metadata checksum (stored during upload)
            string? remoteMd5 = metadata.SourceMd5;

            if (string.IsNullOrEmpty(remoteMd5))
            {
                return new VerificationResult
                {
                    Success = false,
                    Error = "S3 object is missing source-md5 metadata. Re-run upload with metadata enabled."
                };
            }

            if (!remoteMd5.Equals(localMd5, StringComparison.OrdinalIgnoreCase))
            {
                return new VerificationResult
                {
                    Success = false,
                    Error = $"MD5 mismatch: local {localMd5}, S3 metadata {remoteMd5}"
                };
            }

            return new VerificationResult
            {
                Success = true,
                ETag = metadata.ETag.Trim('"'),
                RemoteSourceMd5 = remoteMd5,
                Details = $"MD5 (metadata): {remoteMd5}, Size: {FormatBytes(fileInfo.Length)}"
            };
        }

        /// <summary>
        /// Size-only verification for large files.
        /// </summary>
        private static VerificationResult VerifyUploadSizeOnly(
            string filePath,
            string bucket,
            string key,
            string awsCliPath,
            string? profile,
            string? accessKey,
            string? secretKey,
            string? region)
        {
            var metadata = GetObjectMetadata(bucket, key, awsCliPath, profile, accessKey, secretKey, region);
            var fileInfo = new FileInfo(filePath);

            if (metadata.ContentLength != fileInfo.Length)
            {
                return new VerificationResult
                {
                    Success = false,
                    Error = $"Size mismatch: local {fileInfo.Length} bytes, S3 {metadata.ContentLength} bytes"
                };
            }

            return new VerificationResult
            {
                Success = true,
                ETag = metadata.ETag.Trim('"'),
                RemoteSourceMd5 = metadata.SourceMd5,
                Details = $"Size: {FormatBytes(fileInfo.Length)} (checksum verification skipped)"
            };
        }

        /// <summary>
        /// Gets S3 object metadata using aws s3api head-object.
        /// </summary>
        private static S3ObjectMetadata GetObjectMetadata(
            string bucket,
            string key,
            string awsCliPath,
            string? profile,
            string? accessKey,
            string? secretKey,
            string? region)
        {
            var args = new StringBuilder();
            args.Append($"s3api head-object --bucket {bucket} --key \"{key}\"");

            if (!string.IsNullOrEmpty(region))
            {
                args.Append($" --region {region}");
            }

            var (exitCode, stdout, stderr) = RunAwsCli(awsCliPath, args.ToString(), profile, accessKey, secretKey);

            if (exitCode != 0)
            {
                throw new InvalidOperationException($"Failed to retrieve S3 object metadata: {stderr}");
            }

            // Parse JSON response
            try
            {
                var doc = JsonDocument.Parse(stdout);
                var root = doc.RootElement;

                if (!root.TryGetProperty("ETag", out var etagElement))
                {
                    throw new InvalidOperationException("S3 metadata response is missing ETag");
                }

                if (!root.TryGetProperty("ContentLength", out var contentLengthElement))
                {
                    throw new InvalidOperationException("S3 metadata response is missing ContentLength");
                }

                if (!root.TryGetProperty("LastModified", out var lastModifiedElement))
                {
                    throw new InvalidOperationException("S3 metadata response is missing LastModified");
                }

                string? lastModifiedStr = lastModifiedElement.GetString();
                if (string.IsNullOrWhiteSpace(lastModifiedStr))
                {
                    throw new InvalidOperationException("S3 metadata LastModified value is empty");
                }

                if (!DateTimeOffset.TryParse(lastModifiedStr, CultureInfo.InvariantCulture, DateTimeStyles.AssumeUniversal | DateTimeStyles.AdjustToUniversal, out var lastModifiedOffset))
                {
                    throw new InvalidOperationException($"Unable to parse S3 LastModified value: {lastModifiedStr}");
                }

                long contentLength = contentLengthElement.GetInt64();
                DateTime lastModified = lastModifiedOffset.UtcDateTime;

                string? sourceMd5 = null;
                if (root.TryGetProperty("Metadata", out var metadataElement) && metadataElement.ValueKind == JsonValueKind.Object)
                {
                    if (metadataElement.TryGetProperty("source-md5", out var md5Element))
                    {
                        sourceMd5 = md5Element.GetString();
                    }
                }

                return new S3ObjectMetadata
                {
                    ETag = etagElement.GetString() ?? string.Empty,
                    ContentLength = contentLength,
                    LastModified = lastModified,
                    SourceMd5 = sourceMd5
                };
            }
            catch (Exception ex)
            {
                throw new InvalidOperationException($"Failed to parse S3 metadata response: {ex.Message}");
            }
        }

        /// <summary>
        /// Computes MD5 hash of a file.
        /// </summary>
        private static string ComputeFileMd5(string filePath)
        {
            using var md5 = MD5.Create();
            using var stream = File.OpenRead(filePath);
            byte[] hash = md5.ComputeHash(stream);
            return BitConverter.ToString(hash).Replace("-", "").ToLowerInvariant();
        }

        /// <summary>
        /// Builds metadata string for S3 upload.
        /// </summary>
        private static string BuildMetadata(FileInfo fileInfo, string sourceMd5)
        {
            var metadata = new StringBuilder();
            metadata.Append($"uploaded-by=logManager");
            metadata.Append($",source-host={Environment.MachineName}");
            metadata.Append($",uploaded-at={DateTime.UtcNow:o}");
            metadata.Append($",original-size={fileInfo.Length}");
            metadata.Append($",source-md5={sourceMd5}");

            return metadata.ToString();
        }

        /// <summary>
        /// Runs AWS CLI command with authentication and captures output.
        /// </summary>
        private static (int exitCode, string stdout, string stderr) RunAwsCli(
            string awsCliPath,
            string arguments,
            string? profile,
            string? accessKey,
            string? secretKey)
        {
            var processInfo = new ProcessStartInfo
            {
                FileName = awsCliPath,
                Arguments = arguments,
                UseShellExecute = false,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                CreateNoWindow = true
            };

            // Configure AWS authentication environment variables (prefer explicit keys over profile)
            if (!string.IsNullOrEmpty(accessKey) && !string.IsNullOrEmpty(secretKey))
            {
                processInfo.Environment["AWS_ACCESS_KEY_ID"] = accessKey;
                processInfo.Environment["AWS_SECRET_ACCESS_KEY"] = secretKey;

                if (processInfo.Environment.ContainsKey("AWS_PROFILE"))
                {
                    processInfo.Environment.Remove("AWS_PROFILE");
                }
            }
            else if (!string.IsNullOrEmpty(profile))
            {
                processInfo.Environment["AWS_PROFILE"] = profile;
                processInfo.Environment.Remove("AWS_ACCESS_KEY_ID");
                processInfo.Environment.Remove("AWS_SECRET_ACCESS_KEY");
            }

            using (var process = Process.Start(processInfo))
            {
                if (process == null)
                {
                    throw new InvalidOperationException("Failed to start AWS CLI process");
                }

                Task<string> stdoutTask = process.StandardOutput.ReadToEndAsync();
                Task<string> stderrTask = process.StandardError.ReadToEndAsync();

                if (!process.WaitForExit(AwsCliTimeoutMilliseconds))
                {
                    try
                    {
                        process.Kill(entireProcessTree: true);
                    }
                    catch
                    {
                        // Ignore kill failures; process might have exited between checks
                    }

                    throw new TimeoutException($"AWS CLI command timed out after {AwsCliTimeoutHours} hours. Command: {awsCliPath} {arguments}");
                }

                Task.WaitAll(stdoutTask, stderrTask);

                return (process.ExitCode, stdoutTask.Result, stderrTask.Result);
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

    /// <summary>
    /// Result of S3 upload operation.
    /// </summary>
    public class S3UploadResult
    {
        /// <summary>
        /// Whether the upload succeeded.
        /// </summary>
        public bool Success { get; set; }

        /// <summary>
        /// S3 URI of the uploaded object (s3://bucket/key).
        /// </summary>
        public string S3Uri { get; set; } = string.Empty;

        /// <summary>
        /// ETag reported by S3 for the uploaded object.
        /// </summary>
        public string? ETag { get; set; }

        /// <summary>
        /// MD5 checksum of the local file (stored in object metadata as source-md5).
        /// </summary>
        public string? SourceMd5 { get; set; }

        /// <summary>
        /// Size of the uploaded file in bytes.
        /// </summary>
        public long ContentLength { get; set; }

        /// <summary>
        /// Duration of the upload operation in seconds.
        /// </summary>
        public double UploadDurationSeconds { get; set; }

        /// <summary>
        /// Local file path that was uploaded.
        /// </summary>
        public string LocalFilePath { get; set; } = string.Empty;
    }

    /// <summary>
    /// S3 object metadata from head-object.
    /// </summary>
    internal class S3ObjectMetadata
    {
        public string ETag { get; set; } = string.Empty;
        public long ContentLength { get; set; }
        public DateTime LastModified { get; set; }
        public string? SourceMd5 { get; set; }
    }

    /// <summary>
    /// Result of verification check.
    /// </summary>
    internal class VerificationResult
    {
        public bool Success { get; set; }
        public string? Error { get; set; }
        public string? ETag { get; set; }
        public string? RemoteSourceMd5 { get; set; }
        public string? Details { get; set; }
    }

    /// <summary>
    /// Information about an S3 backup object.
    /// </summary>
    public class S3BackupInfo
    {
        /// <summary>
        /// Whether the backup exists in S3.
        /// </summary>
        public bool Exists { get; set; }

        /// <summary>
        /// S3 URI of the backup object (s3://bucket/key).
        /// </summary>
        public string S3Uri { get; set; } = string.Empty;

        /// <summary>
        /// Size of the backup file in bytes.
        /// </summary>
        public long ContentLength { get; set; }

        /// <summary>
        /// ETag/MD5 hash of the backup object.
        /// </summary>
        public string? ETag { get; set; }

        /// <summary>
        /// MD5 checksum stored in object metadata (source-md5).
        /// </summary>
        public string? SourceMd5 { get; set; }

        /// <summary>
        /// Last modification time of the backup object.
        /// </summary>
        public DateTime LastModified { get; set; }
    }
}
