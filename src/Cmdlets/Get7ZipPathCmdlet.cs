using System.Management.Automation;
using LogManager.Helpers;

namespace LogManager.Cmdlets;

/// <summary>
/// Get-7ZipPath cmdlet for locating 7-Zip executable
/// </summary>
[Cmdlet(VerbsCommon.Get, "7ZipPath")]
[OutputType(typeof(string))]
public class Get7ZipPathCmdlet : PSCmdlet
{
    /// <summary>
    /// Verify that the executable works
    /// </summary>
    [Parameter(
        Mandatory = false,
        HelpMessage = "Verify that the 7-Zip executable is working")]
    public SwitchParameter Verify { get; set; }

    /// <summary>
    /// Throw an error if not found instead of returning null
    /// </summary>
    [Parameter(
        Mandatory = false,
        HelpMessage = "Throw an error if 7-Zip is not found")]
    public SwitchParameter Required { get; set; }

    protected override void ProcessRecord()
    {
        WriteVerbose("Searching for 7-Zip executable...");

        var executablePath = SevenZipHelper.Find7ZipExecutable();

        if (executablePath == null)
        {
            WriteVerbose("7-Zip executable not found on this system");

            if (Required)
            {
                ThrowTerminatingError(new ErrorRecord(
                    new FileNotFoundException("7-Zip executable not found. Please install 7-Zip."),
                    "7ZipNotFound",
                    ErrorCategory.ObjectNotFound,
                    null));
            }

            WriteObject(null);
            return;
        }

        WriteVerbose($"Found 7-Zip at: {executablePath}");

        // Verify if requested
        if (Verify)
        {
            WriteVerbose("Verifying 7-Zip executable...");
            bool isWorking = SevenZipHelper.VerifyExecutable(executablePath);

            if (!isWorking)
            {
                WriteWarning($"7-Zip executable found at '{executablePath}' but verification failed");

                if (Required)
                {
                    ThrowTerminatingError(new ErrorRecord(
                        new InvalidOperationException($"7-Zip executable at '{executablePath}' is not working properly"),
                        "7ZipVerificationFailed",
                        ErrorCategory.InvalidOperation,
                        executablePath));
                }

                WriteObject(null);
                return;
            }

            WriteVerbose("7-Zip executable verified successfully");
        }

        // Return just the path (IncludeVersion parameter removed as GetVersion was unused)
        WriteObject(executablePath);
    }
}
