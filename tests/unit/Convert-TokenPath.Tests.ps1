BeforeAll {
    $modulePath = "$PSScriptRoot\..\..\src\logManager\bin\Debug\net9.0\logManager.dll"
    Import-Module $modulePath -Force
}

Describe "Convert-TokenPath" {
    Context "Token Conversion" {
        It "Should convert {SERVER} token" {
            $result = Convert-TokenPath -Path "/{SERVER}/logs"
            $result | Should -Match "^/[A-Za-z0-9-]+/logs$"
        }

        It "Should convert {YEAR} token" {
            $result = Convert-TokenPath -Path "logs/{YEAR}"
            $currentYear = (Get-Date).Year.ToString()
            $result | Should -Be "logs/$currentYear"
        }

        It "Should convert {MONTH} token" {
            $result = Convert-TokenPath -Path "logs/{MONTH}"
            $currentMonth = (Get-Date).Month.ToString("D2")
            $result | Should -Be "logs/$currentMonth"
        }

        It "Should convert {DAY} token" {
            $result = Convert-TokenPath -Path "logs/{DAY}"
            $currentDay = (Get-Date).Day.ToString("D2")
            $result | Should -Be "logs/$currentDay"
        }

        It "Should convert all tokens together" {
            $result = Convert-TokenPath -Path "/{SERVER}/logs/{YEAR}/{MONTH}/{DAY}"
            $currentYear = (Get-Date).Year.ToString()
            $currentMonth = (Get-Date).Month.ToString("D2")
            $currentDay = (Get-Date).Day.ToString("D2")
            $result | Should -Match "^/[A-Za-z0-9-]+/logs/$currentYear/$currentMonth/$currentDay$"
        }

        It "Should be case-insensitive for tokens" {
            $result = Convert-TokenPath -Path "/{server}/logs/{year}"
            $result | Should -Match "^/[A-Za-z0-9-]+/logs/\d{4}$"
        }

        It "Should handle tokens with whitespace" {
            $result = Convert-TokenPath -Path "{ SERVER }/logs"
            $result | Should -Match "[A-Za-z0-9-]+/logs"
        }
    }

    Context "Date Parameter" {
        It "Should use provided date when specified" {
            $result = Convert-TokenPath -Path "{YEAR}/{MONTH}/{DAY}" -Date "20250315"
            $result | Should -Be "2025/03/15"
        }

        It "Should use today's date when no date provided" {
            $result = Convert-TokenPath -Path "{YEAR}/{MONTH}/{DAY}"
            $today = Get-Date
            $expected = "{0:D4}/{1:D2}/{2:D2}" -f $today.Year, $today.Month, $today.Day
            $result | Should -Be $expected
        }

        It "Should handle different dates" {
            $result = Convert-TokenPath -Path "{YEAR}-{MONTH}-{DAY}" -Date "20200101"
            $result | Should -Be "2020-01-01"
        }

        It "Should handle leap year date" {
            $result = Convert-TokenPath -Path "{YEAR}-{MONTH}-{DAY}" -Date "20200229"
            $result | Should -Be "2020-02-29"
        }
    }

    Context "Path Handling" {
        It "Should handle paths with multiple tokens" {
            $result = Convert-TokenPath -Path "{SERVER}/archive/{YEAR}/{SERVER}/logs"
            $serverName = [System.Environment]::MachineName
            $result | Should -BeLike "*$serverName*"
        }

        It "Should pass through paths without tokens" {
            $result = Convert-TokenPath -Path "C:\Logs\Archive"
            $result | Should -Be "C:\Logs\Archive"
        }

        It "Should handle forward and backward slashes" {
            $result = Convert-TokenPath -Path "/{SERVER}\logs\{YEAR}"
            $result | Should -Match "^/[A-Za-z0-9-]+\\logs\\\d{4}$"
        }

        It "Should handle UNC paths" {
            $result = Convert-TokenPath -Path "\\{SERVER}\logs\{YEAR}"
            $result | Should -Match "^\\\\[A-Za-z0-9-]+\\logs\\\d{4}$"
        }
    }

    Context "Error Handling" {
        It "Should reject invalid date format" {
            { Convert-TokenPath -Path "logs" -Date "2025-03-15" -ErrorAction Stop } | Should -Throw
        }

        It "Should reject invalid day" {
            { Convert-TokenPath -Path "logs" -Date "20250230" -ErrorAction Stop } | Should -Throw
        }

        It "Should reject date too short" {
            { Convert-TokenPath -Path "logs" -Date "202503" -ErrorAction Stop } | Should -Throw
        }

        It "Should reject non-numeric date" {
            { Convert-TokenPath -Path "logs" -Date "202a0315" -ErrorAction Stop } | Should -Throw
        }
    }

    Context "Pipeline Support" {
        It "Should accept path via pipeline" {
            $result = "/{SERVER}/logs/{YEAR}" | Convert-TokenPath
            $result | Should -Match "^/[A-Za-z0-9-]+/logs/\d{4}$"
        }

        It "Should process multiple piped paths" {
            $results = @("/{SERVER}/logs", "/{SERVER}/archive") | Convert-TokenPath
            $results | Should -HaveCount 2
            $results[0] | Should -Match "^/[A-Za-z0-9-]+/logs$"
            $results[1] | Should -Match "^/[A-Za-z0-9-]+/archive$"
        }
    }
}
