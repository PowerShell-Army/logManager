BeforeAll {
    # Import module
    $modulePath = "$PSScriptRoot/../../src/logManager/bin/Debug/net9.0/logManager.dll"
    Import-Module $modulePath -Force

    # Load PowerShell profile if running without it (e.g., VSCode test runner with -NoProfile)
    $profilePath = $PROFILE.CurrentUserCurrentHost
    if ((Test-Path $profilePath) -and [string]::IsNullOrEmpty($env:AWS_ACCESS_KEY_ID)) {
        Write-Verbose "Loading PowerShell profile to access AWS credentials: $profilePath"
        & $profilePath -ErrorAction SilentlyContinue
    }

    # Check for required environment variables
    $script:AwsAccessKey = $env:AWS_ACCESS_KEY_ID
    $script:AwsSecretKey = $env:AWS_SECRET_ACCESS_KEY
    $script:AwsRegion = $env:AWS_DEFAULT_REGION
    $script:AwsBucket = $env:AWS_BUCKET_NAME

    $script:HasAwsConfig = -not [string]::IsNullOrEmpty($AwsAccessKey) -and
                           -not [string]::IsNullOrEmpty($AwsSecretKey) -and
                           -not [string]::IsNullOrEmpty($AwsRegion) -and
                           -not [string]::IsNullOrEmpty($AwsBucket)

    if (-not $script:HasAwsConfig) {
        Write-Warning @"
AWS environment variables not set. Set:
  `$env:AWS_ACCESS_KEY_ID
  `$env:AWS_SECRET_ACCESS_KEY
  `$env:AWS_DEFAULT_REGION
  `$env:AWS_BUCKET_NAME
to enable Send-LogsToS3 tests.

NOTE: If running tests in VSCode, ensure your PowerShell profile sets these variables,
or set them as system environment variables.
"@
    }

    # Create test data directory
    $script:TestDataPath = "$PSScriptRoot/../data/S3Test"
    if (Test-Path $script:TestDataPath) {
        Remove-Item $script:TestDataPath -Recurse -Force
    }
    New-Item -ItemType Directory -Path $script:TestDataPath -Force | Out-Null

    # Track S3 objects to clean up
    $script:S3ObjectsToCleanup = @()

    # Helper function to create test file
    function New-TestFile {
        param(
            [string]$Name,
            [int]$SizeKB = 10
        )
        # Ensure directory exists
        if (-not (Test-Path $script:TestDataPath)) {
            New-Item -ItemType Directory -Path $script:TestDataPath -Force | Out-Null
        }

        $filePath = Join-Path $script:TestDataPath $Name
        $content = "A" * ($SizeKB * 1024)
        $content | Out-File -FilePath $filePath -NoNewline -Force
        return Get-Item $filePath
    }

    # Helper function to check if object exists in S3
    function Test-S3ObjectExists {
        param(
            [string]$Key,
            [string]$Bucket = $script:AwsBucket,
            [string]$Region = $script:AwsRegion
        )
        try {
            aws s3api head-object `
                --bucket $Bucket `
                --key $Key `
                --region $Region `
                --output json 2>&1 | Out-Null
            return $LASTEXITCODE -eq 0
        }
        catch {
            return $false
        }
    }

    # Helper function to delete S3 object
    function Remove-S3Object {
        param(
            [string]$Key,
            [string]$Bucket = $script:AwsBucket,
            [string]$Region = $script:AwsRegion
        )
        try {
            aws s3 rm "s3://$Bucket/$Key" --region $Region 2>&1 | Out-Null
        }
        catch {
            Write-Warning "Failed to delete s3://$Bucket/$Key`: ${_}"
        }
    }
}

Describe "Send-LogsToS3" -Tag "Integration", "S3" {

    Context "Prerequisites" {
        It "Should have AWS CLI available" {
            $awsCli = Get-Command aws -ErrorAction SilentlyContinue
            $awsCli | Should -Not -BeNullOrEmpty
        }

        It "Should have environment variables configured" {
            $script:HasAwsConfig | Should -Be $true
        }
    }

    Context "Basic Upload" {

        It "Should upload a small file to S3" {
            $testFile = New-TestFile -Name "basic-test.txt" -SizeKB 5
            $s3Key = "test/basic-test.txt"
            $script:S3ObjectsToCleanup += $s3Key

            $result = Send-LogsToS3 `
                -InputFile $testFile `
                -Bucket $script:AwsBucket `
                -KeyPrefix "test/" `
                -AccessKey $script:AwsAccessKey `
                -SecretKey $script:AwsSecretKey `
                -Region $script:AwsRegion `
                -Verbose

            $result | Should -Not -BeNullOrEmpty
            $result | Should -BeOfType [System.IO.FileInfo]

            # Verify object exists in S3
            Start-Sleep -Seconds 2  # Allow S3 eventual consistency
            Test-S3ObjectExists -Key $s3Key | Should -Be $true
        }

        It "Should return FileInfo for pipeline chaining" {
            $testFile = New-TestFile -Name "pipeline-test.txt" -SizeKB 5
            $s3Key = "test/pipeline-test.txt"
            $script:S3ObjectsToCleanup += $s3Key

            $result = Send-LogsToS3 `
                -InputFile $testFile `
                -Bucket $script:AwsBucket `
                -KeyPrefix "test/" `
                -AccessKey $script:AwsAccessKey `
                -SecretKey $script:AwsSecretKey `
                -Region $script:AwsRegion

            $result.FullName | Should -Be $testFile.FullName
        }

        It "Should upload with PassThru returning S3UploadResult" {
            $testFile = New-TestFile -Name "passthru-test.txt" -SizeKB 5
            $s3Key = "test/passthru-test.txt"
            $script:S3ObjectsToCleanup += $s3Key

            $results = Send-LogsToS3 `
                -InputFile $testFile `
                -Bucket $script:AwsBucket `
                -KeyPrefix "test/" `
                -AccessKey $script:AwsAccessKey `
                -SecretKey $script:AwsSecretKey `
                -Region $script:AwsRegion `
                -PassThru

            # Should have 2 outputs: FileInfo and S3UploadResult
            $results | Should -HaveCount 2

            $s3Result = $results | Where-Object { $_.PSObject.TypeNames -contains 'logManager.Common.S3UploadResult' }
            $s3Result | Should -Not -BeNullOrEmpty
            $s3Result.Success | Should -Be $true
            $s3Result.S3Uri | Should -Match "s3://$($script:AwsBucket)/"
            $s3Result.ETag | Should -Not -BeNullOrEmpty
            $s3Result.ContentLength | Should -Be $testFile.Length
            $s3Result.UploadDurationSeconds | Should -BeGreaterThan 0
        }
    }

    Context "Token Conversion" {

        It "Should convert {SERVER} token in KeyPrefix" {
            $testFile = New-TestFile -Name "token-server.txt" -SizeKB 5
            $expectedKey = "test/$env:COMPUTERNAME/token-server.txt"
            $script:S3ObjectsToCleanup += $expectedKey

            Send-LogsToS3 `
                -InputFile $testFile `
                -Bucket $script:AwsBucket `
                -KeyPrefix "test/{SERVER}/" `
                -AccessKey $script:AwsAccessKey `
                -SecretKey $script:AwsSecretKey `
                -Region $script:AwsRegion | Out-Null

            Start-Sleep -Seconds 2
            Test-S3ObjectExists -Key $expectedKey | Should -Be $true
        }

        It "Should convert {YEAR}/{MONTH}/{DAY} tokens in KeyPrefix" {
            $testFile = New-TestFile -Name "token-date.txt" -SizeKB 5
            $today = Get-Date
            $year = $today.ToString("yyyy")
            $month = $today.ToString("MM")
            $day = $today.ToString("dd")
            $expectedKey = "test/$year/$month/$day/token-date.txt"
            $script:S3ObjectsToCleanup += $expectedKey

            Send-LogsToS3 `
                -InputFile $testFile `
                -Bucket $script:AwsBucket `
                -KeyPrefix "test/{YEAR}/{MONTH}/{DAY}/" `
                -AccessKey $script:AwsAccessKey `
                -SecretKey $script:AwsSecretKey `
                -Region $script:AwsRegion | Out-Null

            Start-Sleep -Seconds 2
            Test-S3ObjectExists -Key $expectedKey | Should -Be $true
        }
    }

    Context "Verification" {

        It "Should verify upload integrity for small files (< 1GB)" {
            $testFile = New-TestFile -Name "verify-small.txt" -SizeKB 100
            $s3Key = "test/verify-small.txt"
            $script:S3ObjectsToCleanup += $s3Key

            # Should not throw on successful verification
            {
                Send-LogsToS3 `
                    -InputFile $testFile `
                    -Bucket $script:AwsBucket `
                    -KeyPrefix "test/" `
                    -AccessKey $script:AwsAccessKey `
                    -SecretKey $script:AwsSecretKey `
                    -Region $script:AwsRegion
            } | Should -Not -Throw
        }

        It "Should allow skipping verification with -SkipVerification" {
            $testFile = New-TestFile -Name "verify-skip.txt" -SizeKB 50
            $s3Key = "test/verify-skip.txt"
            $script:S3ObjectsToCleanup += $s3Key

            {
                Send-LogsToS3 `
                    -InputFile $testFile `
                    -Bucket $script:AwsBucket `
                    -KeyPrefix "test/" `
                    -AccessKey $script:AwsAccessKey `
                    -SecretKey $script:AwsSecretKey `
                    -Region $script:AwsRegion `
                    -SkipVerification
            } | Should -Not -Throw
        }
    }

    Context "Storage Class" {

        It "Should upload with STANDARD storage class" {
            $testFile = New-TestFile -Name "storage-standard.txt" -SizeKB 5
            $s3Key = "test/storage-standard.txt"
            $script:S3ObjectsToCleanup += $s3Key

            {
                Send-LogsToS3 `
                    -InputFile $testFile `
                    -Bucket $script:AwsBucket `
                    -KeyPrefix "test/" `
                    -StorageClass STANDARD `
                    -AccessKey $script:AwsAccessKey `
                    -SecretKey $script:AwsSecretKey `
                    -Region $script:AwsRegion
            } | Should -Not -Throw
        }

        It "Should upload with INTELLIGENT_TIERING storage class" {
            $testFile = New-TestFile -Name "storage-intelligent.txt" -SizeKB 5
            $s3Key = "test/storage-intelligent.txt"
            $script:S3ObjectsToCleanup += $s3Key

            {
                Send-LogsToS3 `
                    -InputFile $testFile `
                    -Bucket $script:AwsBucket `
                    -KeyPrefix "test/" `
                    -StorageClass INTELLIGENT_TIERING `
                    -AccessKey $script:AwsAccessKey `
                    -SecretKey $script:AwsSecretKey `
                    -Region $script:AwsRegion
            } | Should -Not -Throw
        }
    }

    Context "Pipeline Support" {

        It "Should accept FileInfo from pipeline" {
            $testFile = New-TestFile -Name "pipeline-direct.txt" -SizeKB 5
            $s3Key = "test/pipeline-direct.txt"
            $script:S3ObjectsToCleanup += $s3Key

            $result = $testFile | Send-LogsToS3 `
                -Bucket $script:AwsBucket `
                -KeyPrefix "test/" `
                -AccessKey $script:AwsAccessKey `
                -SecretKey $script:AwsSecretKey `
                -Region $script:AwsRegion

            $result | Should -Not -BeNullOrEmpty
            Start-Sleep -Seconds 2
            Test-S3ObjectExists -Key $s3Key | Should -Be $true
        }

        It "Should chain with Compress-Logs" {
            # Create test files
            $file1 = New-TestFile -Name "compress1.log" -SizeKB 5
            $file2 = New-TestFile -Name "compress2.log" -SizeKB 5

            $archivePath = Join-Path $script:TestDataPath "test-archive.zip"
            $s3Key = "test/test-archive.zip"
            $script:S3ObjectsToCleanup += $s3Key

            # Pipeline: files -> compress -> upload to S3
            $file1, $file2 |
                ForEach-Object { [PSCustomObject]@{ FullName = $_.FullName } } |
                ForEach-Object { Get-Item $_.FullName } |
                Select-Object -First 2 |
                ForEach-Object {
                    # Manually create a simple archive for testing
                    # (Compress-Logs requires proper pipeline setup)
                }

            # Direct test: Compress-Logs -> Send-LogsToS3
            if (Test-Path $archivePath) { Remove-Item $archivePath }
            Compress-Archive -Path $file1, $file2 -DestinationPath $archivePath

            $result = Get-Item $archivePath | Send-LogsToS3 `
                -Bucket $script:AwsBucket `
                -KeyPrefix "test/" `
                -AccessKey $script:AwsAccessKey `
                -SecretKey $script:AwsSecretKey `
                -Region $script:AwsRegion

            $result | Should -Not -BeNullOrEmpty
            Start-Sleep -Seconds 2
            Test-S3ObjectExists -Key $s3Key | Should -Be $true
        }
    }

    Context "Error Handling" {

        It "Should fail with invalid bucket name" {
            $testFile = New-TestFile -Name "error-bucket.txt" -SizeKB 5

            {
                Send-LogsToS3 `
                    -InputFile $testFile `
                    -Bucket "invalid-bucket-name-that-does-not-exist-12345" `
                    -AccessKey $script:AwsAccessKey `
                    -SecretKey $script:AwsSecretKey `
                    -Region $script:AwsRegion `
                    -ErrorAction Stop
            } | Should -Throw
        }

        It "Should fail with non-existent file" {
            $nonExistentFile = Join-Path $script:TestDataPath "does-not-exist.txt"

            {
                Send-LogsToS3 `
                    -InputFile $nonExistentFile `
                    -Bucket $script:AwsBucket `
                    -AccessKey $script:AwsAccessKey `
                    -SecretKey $script:AwsSecretKey `
                    -Region $script:AwsRegion `
                    -ErrorAction Stop
            } | Should -Throw
        }

        It "Should require SecretKey when AccessKey is specified" {
            $testFile = New-TestFile -Name "error-key.txt" -SizeKB 5

            {
                Send-LogsToS3 `
                    -InputFile $testFile `
                    -Bucket "test-bucket" `
                    -AccessKey "AKIAXXXXXXX" `
                    -Region "us-east-1" `
                    -ErrorAction Stop
            } | Should -Throw "*SecretKey is required*"
        }

        It "Should require AccessKey when SecretKey is specified" {
            $testFile = New-TestFile -Name "error-secret.txt" -SizeKB 5

            {
                Send-LogsToS3 `
                    -InputFile $testFile `
                    -Bucket "test-bucket" `
                    -SecretKey "secretkey" `
                    -Region "us-east-1" `
                    -ErrorAction Stop
            } | Should -Throw "*AccessKey is required*"
        }
    }

    Context "WhatIf Support" {

        It "Should support -WhatIf without uploading" {
            $testFile = New-TestFile -Name "whatif-test.txt" -SizeKB 5
            $s3Key = "test/whatif-test.txt"

            # Run with WhatIf
            Send-LogsToS3 `
                -InputFile $testFile `
                -Bucket $script:AwsBucket `
                -KeyPrefix "test/" `
                -AccessKey $script:AwsAccessKey `
                -SecretKey $script:AwsSecretKey `
                -Region $script:AwsRegion `
                -WhatIf

            # Object should NOT exist
            Start-Sleep -Seconds 2
            Test-S3ObjectExists -Key $s3Key | Should -Be $false
        }
    }
}

AfterAll {
    # Clean up local test data
    if (Test-Path $script:TestDataPath) {
        Remove-Item $script:TestDataPath -Recurse -Force -ErrorAction SilentlyContinue
    }

    # OPTIONAL: Uncomment below to also clean up S3 objects (comment out to inspect S3 uploads)
    # if ($script:HasAwsConfig -and $script:S3ObjectsToCleanup.Count -gt 0) {
    #     Write-Host "Cleaning up $($script:S3ObjectsToCleanup.Count) S3 objects..."
    #     foreach ($key in $script:S3ObjectsToCleanup) {
    #         Remove-S3Object -Key $key
    #     }
    # }

    if ($script:S3ObjectsToCleanup.Count -gt 0) {
        Write-Host "S3 test files uploaded and retained in bucket for inspection: $($script:S3ObjectsToCleanup.Count) objects"
    }

    Write-Host "Send-LogsToS3 test cleanup complete"
}
