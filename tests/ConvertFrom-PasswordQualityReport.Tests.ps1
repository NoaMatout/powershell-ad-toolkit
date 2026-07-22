BeforeAll {
    $moduleRoot = Split-Path -Parent $PSScriptRoot
    Import-Module (Join-Path $moduleRoot 'ADToolkit.psd1') -Force

    $script:FixtureDir = Join-Path $PSScriptRoot 'fixtures'
    $script:Baseline = ConvertFrom-PasswordQualityReport -LiteralPath (Join-Path $script:FixtureDir 'audit-baseline.txt')
    $script:Current = ConvertFrom-PasswordQualityReport -LiteralPath (Join-Path $script:FixtureDir 'audit-current.txt')
}

Describe 'ConvertFrom-PasswordQualityReport' {

    Context 'Report structure' {

        It 'emits a typed report object' {
            $script:Baseline.PSObject.TypeNames | Should -Contain 'ADToolkit.PasswordQualityReport'
        }

        It 'ignores the preamble above the first heading' {
            # The two preamble lines must not be mistaken for findings.
            $script:Baseline.Findings.Identity | Should -Not -Contain 'EXAMPLE'
            $script:Baseline.Findings.Identity | Should -Not -Contain 'DSInternals Password Auditing Report'
        }

        It 'records a heading that has no entries under it' {
            # "checked, found nothing" must be distinguishable from "not checked at all".
            $script:Baseline.Sections.Contains('LMHash') | Should -BeTrue
            $script:Baseline.Sections['LMHash'] | Should -Be 0
        }

        It 'counts entries per section' {
            $script:Baseline.Sections['InDictionary'] | Should -Be 2
            $script:Baseline.Sections['DuplicatePasswords'] | Should -Be 5
        }

        It 'reports the total number of findings' {
            $script:Baseline.FindingCount | Should -Be $script:Baseline.Findings.Count
        }
    }

    Context 'Finding fields' {

        It 'maps a heading to its stable section key' {
            $finding = $script:Baseline.Findings | Where-Object Identity -eq 'EXAMPLE\svc_legacy'
            $finding.Section | Should -Be 'NoPasswordSet'
        }

        It 'assigns the severity configured for the section' {
            $finding = $script:Baseline.Findings | Where-Object Identity -eq 'EXAMPLE\svc_sql'
            $finding.Severity | Should -Be 'High'
        }

        It 'splits the identity into domain and account name' {
            $finding = $script:Baseline.Findings | Where-Object Identity -eq 'EXAMPLE\alice'
            $finding.Domain | Should -Be 'EXAMPLE'
            $finding.SamAccountName | Should -Be 'alice'
        }

        It 'recognises a computer account by its trailing dollar sign' {
            $computer = $script:Baseline.Findings | Where-Object Identity -eq 'EXAMPLE\WS-001$' | Select-Object -First 1
            $computer.IsComputerAccount | Should -BeTrue

            $user = $script:Baseline.Findings | Where-Object Identity -eq 'EXAMPLE\alice'
            $user.IsComputerAccount | Should -BeFalse
        }

        It 'carries the report timestamp onto every finding' {
            $stamp = Get-Date '2026-07-15T09:00:00'
            $report = ConvertFrom-PasswordQualityReport -LiteralPath (Join-Path $script:FixtureDir 'audit-baseline.txt') -Timestamp $stamp
            $report.Findings.Timestamp | Should -Not -Contain $null
            ($report.Findings.Timestamp | Select-Object -Unique) | Should -Be $stamp
        }
    }

    Context 'Duplicate-password groups' {

        It 'attaches a group id only within the grouped section' {
            $grouped = $script:Baseline.Findings | Where-Object Section -eq 'DuplicatePasswords'
            $grouped.GroupId | Should -Not -Contain $null

            $flat = $script:Baseline.Findings | Where-Object Section -eq 'InDictionary'
            @($flat.GroupId | Where-Object { $null -ne $_ }).Count | Should -Be 0
        }

        It 'keeps members of the same group together' {
            $backup = $script:Baseline.Findings | Where-Object Identity -eq 'EXAMPLE\svc_backup' | Where-Object Section -eq 'DuplicatePasswords'
            $monitor = $script:Baseline.Findings | Where-Object Identity -eq 'EXAMPLE\svc_monitor'
            $backup.GroupId | Should -Be $monitor.GroupId
        }

        It 'gives the same signature to an unchanged group that was renumbered' {
            # svc_backup/svc_monitor are Group 1 in the baseline and Group 2 in the current
            # report. Same password holders, different label - the signature must not move.
            $before = $script:Baseline.Findings | Where-Object { $_.Identity -eq 'EXAMPLE\svc_backup' -and $_.Section -eq 'DuplicatePasswords' }
            $after = $script:Current.Findings | Where-Object { $_.Identity -eq 'EXAMPLE\svc_backup' -and $_.Section -eq 'DuplicatePasswords' }

            $before.GroupId | Should -Not -Be $after.GroupId
            $before.GroupSignature | Should -Be $after.GroupSignature
        }

        It 'changes the signature when membership changes' {
            $before = $script:Baseline.Findings | Where-Object { $_.Identity -eq 'EXAMPLE\WS-001$' -and $_.Section -eq 'DuplicatePasswords' }
            $after = $script:Current.Findings | Where-Object { $_.Identity -eq 'EXAMPLE\WS-001$' -and $_.Section -eq 'DuplicatePasswords' }

            $before.GroupSignature | Should -Not -Be $after.GroupSignature
        }
    }

    Context 'Unknown headings' {

        BeforeAll {
            $script:UnknownReport = @(
                'Passwords of these accounts have been found in the dictionary:'
                '  EXAMPLE\alice'
                ''
                'Some heading a future release invented:'
                '  EXAMPLE\mallory'
                ''
                'These accounts are susceptible to the Kerberoasting attack:'
                '  EXAMPLE\svc_sql'
            )
        }

        It 'warns rather than failing silently' {
            $warnings = @()
            $null = ConvertFrom-PasswordQualityReport -Content $script:UnknownReport -WarningVariable warnings -WarningAction SilentlyContinue
            $warnings.Count | Should -Be 1
            $warnings[0].Message | Should -BeLike '*Some heading a future release invented*'
        }

        It 'drops the unknown section rather than misfiling it under the previous heading' {
            $report = ConvertFrom-PasswordQualityReport -Content $script:UnknownReport -WarningAction SilentlyContinue
            $report.Findings.Identity | Should -Not -Contain 'EXAMPLE\mallory'
            $report.Sections['InDictionary'] | Should -Be 1
        }

        It 'resumes parsing at the next recognised heading' {
            $report = ConvertFrom-PasswordQualityReport -Content $script:UnknownReport -WarningAction SilentlyContinue
            $report.Findings.Identity | Should -Contain 'EXAMPLE\svc_sql'
        }
    }

    Context 'Input handling' {

        It 'accepts files from the pipeline' {
            $reports = @(Get-ChildItem (Join-Path $script:FixtureDir 'audit-*.txt') | ConvertFrom-PasswordQualityReport)
            $reports.Count | Should -Be 2
        }

        It 'defaults the timestamp to the file write time' {
            $path = Join-Path $script:FixtureDir 'audit-baseline.txt'
            $report = ConvertFrom-PasswordQualityReport -LiteralPath $path
            $report.Timestamp | Should -Be (Get-Item $path).LastWriteTime
        }

        It 'writes an error for a missing file instead of throwing' {
            $errors = @()
            $null = ConvertFrom-PasswordQualityReport -LiteralPath 'TestDrive:\nope.txt' -ErrorVariable errors -ErrorAction SilentlyContinue
            $errors.Count | Should -Be 1
        }

        It 'returns an empty report for empty content' {
            $report = ConvertFrom-PasswordQualityReport -Content @()
            $report.FindingCount | Should -Be 0
        }
    }
}
