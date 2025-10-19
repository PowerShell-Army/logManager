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
        Write-Warning "AWS environment variables not set. Test-S3Backup tests will be skipped."
        return
    }

    # Create test data directory and upload test file to S3
    $script:TestDataPath = "$PSScriptRoot/../data/S3BackupTest"
    if (Test-Path $script:TestDataPath) {
        Remove-Item $script:TestDataPath -Recurse -Force -ErrorAction SilentlyContinue
    }
    New-Item -ItemType Directory -Path $script:TestDataPath -Force | Out-Null

    # Create a test file
    $testFilePath = "$script:TestDataPath/backup-test.txt"
    "Test backup file for Test-S3Backup cmdlet" | Set-Content -Path $testFilePath

    # Upload test file to S3 using AWS CLI for Test-S3Backup tests
    $testKey = "test/backup-test.txt"
    Write-Verbose "Uploading test file to S3: s3://$($script:AwsBucket)/$testKey"

    # Set environment variables for AWS CLI
    $env:AWS_ACCESS_KEY_ID = $script:AwsAccessKey
    $env:AWS_SECRET_ACCESS_KEY = $script:AwsSecretKey
    $env:AWS_DEFAULT_REGION = $script:AwsRegion

    $uploadResult = & aws s3 cp $testFilePath "s3://$($script:AwsBucket)/$testKey" --region $script:AwsRegion 2>&1

    if ($LASTEXITCODE -eq 0) {
        Write-Host "Test file uploaded to S3: s3://$($script:AwsBucket)/$testKey"
    } else {
        Write-Warning "Failed to upload test file: $uploadResult"
    }

    $script:TestS3Key = $testKey
}

Describe "Test-S3Backup" -Tag "Integration", "S3" {

    Context "Backup Detection" {
        It "Should find an existing backup and return metadata" {
            $result = Test-S3Backup -Bucket $script:AwsBucket `
                                    -Key $script:TestS3Key `
                                    -AccessKey $script:AwsAccessKey `
                                    -SecretKey $script:AwsSecretKey `
                                    -Region $script:AwsRegion

            $result | Should -Not -BeNullOrEmpty
            $result.Exists | Should -Be $true
            $result.S3Uri | Should -Match "s3://$($script:AwsBucket)/$($script:TestS3Key)"
            $result.ContentLength | Should -BeGreaterThan 0
            $result.ETag | Should -Not -BeNullOrEmpty
            $result.LastModified | Should -BeOfType [DateTime]
        }

        It "Should return null for non-existent backup" {
            $result = Test-S3Backup -Bucket $script:AwsBucket `
                                    -Key "nonexistent/file-12345.zip" `
                                    -AccessKey $script:AwsAccessKey `
                                    -SecretKey $script:AwsSecretKey `
                                    -Region $script:AwsRegion

            $result | Should -BeNullOrEmpty
        }
    }

    Context "Token Conversion" {
        It "Should convert {SERVER} token in key" {
            # Create a test object with the converted key name (from previous tests)
            $result = Test-S3Backup -Bucket $script:AwsBucket `
                                    -Key "test/{SERVER}/backup-test.txt" `
                                    -AccessKey $script:AwsAccessKey `
                                    -SecretKey $script:AwsSecretKey `
                                    -Region $script:AwsRegion

            if ($result) {
                $result.S3Uri | Should -Match "\{SERVER\}" -Not
                $result.Exists | Should -Be $true
            }
        }

        It "Should convert {YEAR}/{MONTH}/{DAY} tokens in key" {
            $today = Get-Date
            $year = $today.ToString("yyyy")
            $month = $today.ToString("MM")
            $day = $today.ToString("dd")

            # Test that tokens are converted
            $result = Test-S3Backup -Bucket $script:AwsBucket `
                                    -Key "test/{YEAR}/{MONTH}/{DAY}/backup-test.txt" `
                                    -AccessKey $script:AwsAccessKey `
                                    -SecretKey $script:AwsSecretKey `
                                    -Region $script:AwsRegion

            if ($result) {
                $result.S3Uri | Should -Match $year
                $result.S3Uri | Should -Match $month
                $result.S3Uri | Should -Match $day
            }
        }
    }

    Context "Authentication" {
        It "Should require SecretKey when AccessKey is specified" {
            {
                Test-S3Backup -Bucket "test-bucket" `
                              -Key "test/file.txt" `
                              -AccessKey "AKIAXXXXXXX" `
                              -Region "us-east-1" `
                              -ErrorAction Stop
            } | Should -Throw "*SecretKey is required*"
        }

        It "Should require AccessKey when SecretKey is specified" {
            {
                Test-S3Backup -Bucket "test-bucket" `
                              -Key "test/file.txt" `
                              -SecretKey "secretkey" `
                              -Region "us-east-1" `
                              -ErrorAction Stop
            } | Should -Throw "*AccessKey is required*"
        }
    }

    Context "Output Format" {
        It "Should return S3BackupInfo object" {
            $result = Test-S3Backup -Bucket $script:AwsBucket `
                                    -Key $script:TestS3Key `
                                    -AccessKey $script:AwsAccessKey `
                                    -SecretKey $script:AwsSecretKey `
                                    -Region $script:AwsRegion

            if ($result) {
                $result.PSObject.TypeNames[0] | Should -Be "logManager.Common.S3BackupInfo"
            }
        }

        It "Should include S3Uri in correct format" {
            $result = Test-S3Backup -Bucket $script:AwsBucket `
                                    -Key $script:TestS3Key `
                                    -AccessKey $script:AwsAccessKey `
                                    -SecretKey $script:AwsSecretKey `
                                    -Region $script:AwsRegion

            if ($result) {
                $result.S3Uri | Should -Match "^s3://$($script:AwsBucket)/"
            }
        }

        It "Should provide correct ContentLength" {
            $result = Test-S3Backup -Bucket $script:AwsBucket `
                                    -Key $script:TestS3Key `
                                    -AccessKey $script:AwsAccessKey `
                                    -SecretKey $script:AwsSecretKey `
                                    -Region $script:AwsRegion

            if ($result) {
                $result.ContentLength | Should -BeGreaterThan 0
            }
        }
    }

    Context "Error Handling" {
        It "Should fail with invalid bucket" {
            {
                Test-S3Backup -Bucket "invalid-bucket-name-that-does-not-exist-12345" `
                              -Key "test/file.txt" `
                              -AccessKey $script:AwsAccessKey `
                              -SecretKey $script:AwsSecretKey `
                              -Region $script:AwsRegion `
                              -ErrorAction Stop
            } | Should -Throw
        }
    }
}

AfterAll {
    # Clean up test data
    if ($script:TestDataPath -and (Test-Path $script:TestDataPath)) {
        Remove-Item $script:TestDataPath -Recurse -Force -ErrorAction SilentlyContinue
    }

    # Clean up test file from S3 if config exists
    if ($script:HasAwsConfig -and $script:TestS3Key) {
        Write-Verbose "Removing test file from S3: s3://$($script:AwsBucket)/$($script:TestS3Key)"
        & aws s3 rm "s3://$($script:AwsBucket)/$($script:TestS3Key)" `
            --region $script:AwsRegion `
            --access-key-id $script:AwsAccessKey `
            --secret-access-key $script:AwsSecretKey `
            2>&1 | Out-Null
    }

    Write-Host "Test-S3Backup tests complete"
}
