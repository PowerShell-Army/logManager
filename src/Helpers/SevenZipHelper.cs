using System.Runtime.InteropServices;

namespace LogManager.Helpers;

/// <summary>
/// Helper class to locate 7-Zip executable on Windows and Linux systems
/// </summary>
public static class SevenZipHelper
{
    /// <summary>
    /// Locates the 7-Zip executable on the system
    /// </summary>
    /// <returns>Full path to 7z executable, or null if not found</returns>
    public static string? Find7ZipExecutable()
    {
        if (RuntimeInformation.IsOSPlatform(OSPlatform.Windows))
        {
            return FindWindowsExecutable();
        }
        else if (RuntimeInformation.IsOSPlatform(OSPlatform.Linux) ||
                 RuntimeInformation.IsOSPlatform(OSPlatform.OSX))
        {
            return FindUnixExecutable();
        }

        return null;
    }

    /// <summary>
    /// Locates 7-Zip executable on Windows systems
    /// </summary>
    private static string? FindWindowsExecutable()
    {
        // Common installation paths on Windows
        var commonPaths = new[]
        {
            @"C:\Program Files\7-Zip\7z.exe",
            @"C:\Program Files (x86)\7-Zip\7z.exe",
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), "7-Zip", "7z.exe"),
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86), "7-Zip", "7z.exe")
        };

        // Check common installation paths
        foreach (var path in commonPaths)
        {
            if (File.Exists(path))
            {
                return path;
            }
        }

        // Check PATH environment variable
        var pathExecutable = FindInPath("7z.exe");
        if (pathExecutable != null)
        {
            return pathExecutable;
        }

        return null;
    }

    /// <summary>
    /// Locates 7-Zip executable on Unix-like systems (Linux/macOS)
    /// </summary>
    private static string? FindUnixExecutable()
    {
        // Common installation paths on Unix-like systems
        var commonPaths = new[]
        {
            "/usr/bin/7z",
            "/usr/bin/7za",
            "/usr/bin/7zr",
            "/usr/local/bin/7z",
            "/usr/local/bin/7za",
            "/usr/local/bin/7zr",
            "/opt/7-zip/7z",
            "/opt/7-zip/7za"
        };

        // Check common installation paths
        foreach (var path in commonPaths)
        {
            if (File.Exists(path) && IsExecutable(path))
            {
                return path;
            }
        }

        // Try using 'which' command to find in PATH
        var whichResult = TryWhichCommand("7z");
        if (whichResult != null)
        {
            return whichResult;
        }

        whichResult = TryWhichCommand("7za");
        if (whichResult != null)
        {
            return whichResult;
        }

        whichResult = TryWhichCommand("7zr");
        if (whichResult != null)
        {
            return whichResult;
        }

        return null;
    }

    /// <summary>
    /// Searches for an executable in the PATH environment variable
    /// </summary>
    /// <param name="fileName">Name of the executable to find</param>
    /// <returns>Full path to executable, or null if not found</returns>
    private static string? FindInPath(string fileName)
    {
        var pathVar = Environment.GetEnvironmentVariable("PATH");
        if (string.IsNullOrEmpty(pathVar))
        {
            return null;
        }

        var pathSeparator = RuntimeInformation.IsOSPlatform(OSPlatform.Windows) ? ';' : ':';
        var paths = pathVar.Split(pathSeparator, StringSplitOptions.RemoveEmptyEntries);

        foreach (var path in paths)
        {
            try
            {
                var fullPath = Path.Combine(path.Trim(), fileName);
                if (File.Exists(fullPath))
                {
                    return fullPath;
                }
            }
            catch
            {
                // Ignore invalid paths
                continue;
            }
        }

        return null;
    }

    /// <summary>
    /// Uses the 'which' command to locate an executable on Unix-like systems
    /// </summary>
    /// <param name="executableName">Name of the executable to find</param>
    /// <returns>Full path to executable, or null if not found</returns>
    private static string? TryWhichCommand(string executableName)
    {
        try
        {
            var processStartInfo = new System.Diagnostics.ProcessStartInfo
            {
                FileName = "/usr/bin/which",
                Arguments = executableName,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                UseShellExecute = false,
                CreateNoWindow = true
            };

            using var process = System.Diagnostics.Process.Start(processStartInfo);
            if (process == null)
            {
                return null;
            }

            process.WaitForExit(1000); // Wait max 1 second

            if (process.ExitCode == 0)
            {
                var output = process.StandardOutput.ReadToEnd().Trim();
                if (!string.IsNullOrEmpty(output) && File.Exists(output))
                {
                    return output;
                }
            }
        }
        catch
        {
            // If 'which' command fails, return null
        }

        return null;
    }

    /// <summary>
    /// Checks if a file has executable permissions on Unix-like systems
    /// </summary>
    /// <param name="filePath">Path to the file</param>
    /// <returns>True if the file is executable, false otherwise</returns>
    private static bool IsExecutable(string filePath)
    {
        if (!File.Exists(filePath))
        {
            return false;
        }

        if (RuntimeInformation.IsOSPlatform(OSPlatform.Windows))
        {
            // On Windows, if the file exists, assume it's executable
            return true;
        }

        try
        {
            // On Unix, use UnixFileMode API (.NET 6+) to check execute permissions
            var fileInfo = new FileInfo(filePath);
            var mode = fileInfo.UnixFileMode;

            // Check if any execute bit is set (owner, group, or others)
            return (mode & (UnixFileMode.UserExecute | UnixFileMode.GroupExecute | UnixFileMode.OtherExecute)) != 0;
        }
        catch
        {
            // If we can't determine, assume it's executable if it exists
            return true;
        }
    }

    /// <summary>
    /// Verifies that the 7-Zip executable is working
    /// </summary>
    /// <param name="executablePath">Path to 7z executable</param>
    /// <returns>True if executable is working, false otherwise</returns>
    public static bool VerifyExecutable(string executablePath)
    {
        if (string.IsNullOrEmpty(executablePath) || !File.Exists(executablePath))
        {
            return false;
        }

        try
        {
            var processStartInfo = new System.Diagnostics.ProcessStartInfo
            {
                FileName = executablePath,
                Arguments = "i", // Info command - shows capabilities
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                UseShellExecute = false,
                CreateNoWindow = true
            };

            using var process = System.Diagnostics.Process.Start(processStartInfo);
            if (process == null)
            {
                return false;
            }

            process.WaitForExit(2000); // Wait max 2 seconds

            return process.ExitCode == 0;
        }
        catch
        {
            return false;
        }
    }
}
