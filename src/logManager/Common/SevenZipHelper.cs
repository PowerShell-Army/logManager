using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace logManager.Common
{
    /// <summary>
    /// Helper class for finding and executing 7z compression to ZIP archives.
    /// Optimized for performance with minimal overhead.
    /// </summary>
    public static class SevenZipHelper
    {
        private const int CompressionTimeoutMinutes = 30;
        private const int CompressionTimeoutMilliseconds = CompressionTimeoutMinutes * 60 * 1000;

        // Cached 7z executable path for performance (eliminates 2-3 disk I/O ops per compression)
        private static readonly Lazy<string?> CachedSevenZipPath = new Lazy<string?>(() =>
        {
            var commonPaths = new[]
            {
                Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), "7-Zip", "7z.exe"),
                Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86), "7-Zip", "7z.exe"),
                "7z.exe"
            };

            foreach (var path in commonPaths)
            {
                if (!string.IsNullOrEmpty(path) && File.Exists(path))
                {
                    return path;
                }
            }

            return null;
        });

        /// <summary>
        /// Finds the 7z executable in common Windows installation paths.
        /// </summary>
        /// <returns>Full path to 7z.exe, or null if not found.</returns>
        public static string? Find7zExecutable()
        {
            return CachedSevenZipPath.Value;
        }

        /// <summary>
        /// Compresses files/folders to a ZIP archive using a file list.
        /// Optimized for performance with minimal memory overhead.
        /// </summary>
        /// <param name="archivePath">Full path where the ZIP archive will be created (must end with .zip).</param>
        /// <param name="fileListPath">Path to temporary file containing list of items to compress (one per line).</param>
        /// <returns>True if successful, false otherwise.</returns>
        public static bool Compress(string archivePath, string fileListPath)
        {
            if (!File.Exists(fileListPath))
            {
                throw new FileNotFoundException($"File list not found: {fileListPath}");
            }

            if (!archivePath.EndsWith(".zip", StringComparison.OrdinalIgnoreCase))
            {
                throw new ArgumentException("Archive path must have .zip extension", nameof(archivePath));
            }

            string? sevenZipPath = Find7zExecutable();
            if (string.IsNullOrEmpty(sevenZipPath))
            {
                throw new FileNotFoundException("7z.exe not found in common installation paths");
            }

            try
            {
                string? stagingDirectory = Path.GetDirectoryName(fileListPath);
                if (string.IsNullOrEmpty(stagingDirectory) || !Directory.Exists(stagingDirectory))
                {
                    throw new DirectoryNotFoundException($"Staging directory not found for file list: {fileListPath}");
                }

                // Use -tzip for ZIP format, -mm=Deflate for speed, -mmt=on for multi-threading
                // Suppress verbose stdout (-bso0) while keeping stderr (-bse1) for diagnostics
                var processInfo = new ProcessStartInfo
                {
                    FileName = sevenZipPath,
                    Arguments = $"a -tzip -mm=Deflate -mmt=on -bso0 -bse1 -scsUTF-8 -w\"{stagingDirectory}\" \"{archivePath}\" @\"{fileListPath}\"",
                    UseShellExecute = false,
                    CreateNoWindow = true,
                    RedirectStandardOutput = true,
                    RedirectStandardError = true,
                    WorkingDirectory = stagingDirectory
                };

                using (var process = Process.Start(processInfo))
                {
                    if (process == null)
                    {
                        throw new InvalidOperationException("Failed to start 7z process");
                    }

                    // Capture output for diagnostics without risk of deadlock
                    Task<string> stdoutTask = process.StandardOutput.ReadToEndAsync();
                    Task<string> stderrTask = process.StandardError.ReadToEndAsync();

                    if (!process.WaitForExit(CompressionTimeoutMilliseconds))
                    {
                        try
                        {
                            process.Kill(entireProcessTree: true);
                        }
                        catch
                        {
                            // Ignore kill failures; process might have exited between checks
                        }

                        throw new InvalidOperationException($"7z compression timed out after {CompressionTimeoutMinutes} minutes.");
                    }

                    Task.WaitAll(stdoutTask, stderrTask);

                    string stdout = stdoutTask.Result;
                    string stderr = stderrTask.Result;

                    if (process.ExitCode != 0)
                    {
                        string errorDetails = string.IsNullOrEmpty(stderr) ? stdout : stderr;
                        throw new InvalidOperationException($"7z compression failed with exit code {process.ExitCode}. Details: {errorDetails}");
                    }

                    return true;
                }
            }
            catch (Exception ex)
            {
                throw new InvalidOperationException($"ZIP compression failed: {ex.Message}", ex);
            }
        }

        /// <summary>
        /// Creates a temporary file list for 7z compression.
        /// </summary>
        /// <param name="paths">Collection of full paths to compress.</param>
        /// <returns>Path to temporary file containing the list.</returns>
        public static string CreateFileList(IEnumerable<string> paths)
        {
            var normalizedPaths = paths.Select(path => path ?? string.Empty).ToList();

            string stagingDirectory = DetermineCompressionStagingDirectory(normalizedPaths);
            string tempFile = Path.Combine(stagingDirectory, $"7z_list_{Guid.NewGuid():N}.txt");
            var encoding = new UTF8Encoding(encoderShouldEmitUTF8Identifier: false);
            File.WriteAllLines(tempFile, normalizedPaths, encoding);
            return tempFile;
        }

        internal static string DetermineCompressionStagingDirectory(IEnumerable<string> sourcePaths)
        {
            if (sourcePaths == null)
            {
                throw new ArgumentNullException(nameof(sourcePaths));
            }

            string? resolvedRoot = null;
            foreach (var path in sourcePaths)
            {
                if (string.IsNullOrWhiteSpace(path))
                {
                    continue;
                }

                string fullPath;
                try
                {
                    fullPath = Path.GetFullPath(path);
                }
                catch (Exception ex)
                {
                    throw new ArgumentException($"Unable to resolve full path for '{path}'.", nameof(sourcePaths), ex);
                }

                string? currentRoot = Path.GetPathRoot(fullPath);
                if (string.IsNullOrEmpty(currentRoot))
                {
                    throw new InvalidOperationException($"Unable to determine drive for compression source '{path}'.");
                }

                if (resolvedRoot == null)
                {
                    resolvedRoot = currentRoot;
                }
                else if (!string.Equals(resolvedRoot, currentRoot, StringComparison.OrdinalIgnoreCase))
                {
                    throw new InvalidOperationException("Compression sources span multiple drives. Split inputs by drive to ensure local staging.");
                }
            }

            if (resolvedRoot == null)
            {
                throw new ArgumentException("No valid source paths were provided to determine the compression staging location.", nameof(sourcePaths));
            }

            string stagingDirectory = Path.Combine(resolvedRoot, "logManagerTemp");
            Directory.CreateDirectory(stagingDirectory);
            return stagingDirectory;
        }

        internal static string DetermineCompressionStagingDirectory(string sourcePath)
        {
            if (string.IsNullOrWhiteSpace(sourcePath))
            {
                throw new ArgumentException("Source path cannot be null or empty.", nameof(sourcePath));
            }

            return DetermineCompressionStagingDirectory(new[] { sourcePath });
        }
    }
}
