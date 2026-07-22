BeforeAll {
    $moduleRoot = Split-Path -Parent $PSScriptRoot
    Import-Module (Join-Path $moduleRoot 'ADToolkit.psd1') -Force

    $fixtures = Join-Path $PSScriptRoot 'fixtures'
    $script:BaselinePath = Join-Path $fixtures 'audit-baseline.txt'
    $script:CurrentPath = Join-Path $fixtures 'audit-current.txt'

    $script:Changes = Compare-PasswordAudit -ReferencePath $script:BaselinePath -DifferencePath $script:CurrentPath -WarningAction SilentlyContinue

    function Get-Change {
        param($Section, $Identity)
        $script:Changes | Where-Object { $_.Section -eq $Section -and $_.Identity -eq $Identity }
    }
}

Describe 'Compare-PasswordAudit' {

    Context 'Classification' {

        It 'reports an account that dropped out of a section as Resolved' {
            (Get-Change -Section 'InDictionary' -Identity 'EXAMPLE\alice').Status | Should -Be 'Resolved'
        }

        It 'reports an account newly appearing in a section as New' {
            (Get-Change -Section 'InDictionary' -Identity 'EXAMPLE\carol').Status | Should -Be 'New'
        }

        It 'reports an account present in both as Persisting' {
            (Get-Change -Section 'InDictionary' -Identity 'EXAMPLE\bob').Status | Should -Be 'Persisting'
        }

        It 'treats a section that emptied out as resolutions, not as a missing section' {
            (Get-Change -Section 'NoPasswordSet' -Identity 'EXAMPLE\svc_legacy').Status | Should -Be 'Resolved'
        }

        It 'classifies each section independently for the same account' {
            # svc_backup is Persisting on two separate weaknesses.
            $rows = $script:Changes | Where-Object Identity -eq 'EXAMPLE\svc_backup'
            $rows.Section | Should -Contain 'DuplicatePasswords'
            $rows.Section | Should -Contain 'PasswordNeverExpires'
        }
    }

    Context 'Duplicate-password group movement' {

        It 'does not flag a group that was merely renumbered' {
            $change = Get-Change -Section 'DuplicatePasswords' -Identity 'EXAMPLE\svc_backup'
            $change.Status | Should -Be 'Persisting'
            $change.GroupChanged | Should -BeFalse
        }

        It 'flags a persisting account whose group membership changed' {
            $change = Get-Change -Section 'DuplicatePasswords' -Identity 'EXAMPLE\WS-001$'
            $change.Status | Should -Be 'Persisting'
            $change.GroupChanged | Should -BeTrue
        }

        It 'reports the account that left the group as Resolved' {
            (Get-Change -Section 'DuplicatePasswords' -Identity 'EXAMPLE\WS-003$').Status | Should -Be 'Resolved'
        }

        It 'leaves GroupChanged empty outside the grouped section' {
            (Get-Change -Section 'InDictionary' -Identity 'EXAMPLE\bob').GroupChanged | Should -BeNullOrEmpty
        }
    }

    Context 'Sections present in only one report' {

        It 'warns instead of reporting every entry as new' {
            $warnings = @()
            $null = Compare-PasswordAudit -ReferencePath $script:BaselinePath -DifferencePath $script:CurrentPath -WarningVariable warnings -WarningAction SilentlyContinue
            ($warnings.Message -join "`n") | Should -BeLike '*DefaultComputerPassword*'
        }

        It 'excludes the uncomparable section from the results' {
            $script:Changes.Section | Should -Not -Contain 'DefaultComputerPassword'
        }
    }

    Context 'Filtering' {

        It 'emits only the requested statuses' {
            $new = Compare-PasswordAudit -ReferencePath $script:BaselinePath -DifferencePath $script:CurrentPath -Status New -WarningAction SilentlyContinue
            ($new.Status | Select-Object -Unique) | Should -Be 'New'
            $new.Identity | Should -Contain 'EXAMPLE\carol'
        }

        It 'restricts the comparison to the requested sections' {
            $only = Compare-PasswordAudit -ReferencePath $script:BaselinePath -DifferencePath $script:CurrentPath -Section 'InDictionary' -WarningAction SilentlyContinue
            ($only.Section | Select-Object -Unique) | Should -Be 'InDictionary'
        }

        It 'warns when asked for a section that cannot be compared' {
            $warnings = @()
            $null = Compare-PasswordAudit -ReferencePath $script:BaselinePath -DifferencePath $script:CurrentPath -Section 'DefaultComputerPassword' -WarningVariable warnings -WarningAction SilentlyContinue
            ($warnings.Message -join "`n") | Should -BeLike '*requested but is not comparable*'
        }
    }

    Context 'Output shape' {

        It 'emits typed objects' {
            $script:Changes[0].PSObject.TypeNames | Should -Contain 'ADToolkit.PasswordAuditChange'
        }

        It 'orders the worst findings first' {
            $severities = $script:Changes.Severity | Select-Object -Unique
            $severities[0] | Should -Be 'Critical'
        }

        It 'carries both report dates on every row' {
            $script:Changes.ReferenceDate | Should -Not -Contain $null
            $script:Changes.DifferenceDate | Should -Not -Contain $null
        }

        It 'does not leak the internal sort rank into the output' {
            $script:Changes[0].PSObject.Properties.Name | Should -Not -Contain 'SeverityRank'
        }
    }

    Context 'Report objects as input' {

        It 'accepts already-parsed reports' {
            $ref = ConvertFrom-PasswordQualityReport -LiteralPath $script:BaselinePath
            $diff = ConvertFrom-PasswordQualityReport -LiteralPath $script:CurrentPath
            $changes = Compare-PasswordAudit -ReferenceReport $ref -DifferenceReport $diff -WarningAction SilentlyContinue
            $changes.Count | Should -Be $script:Changes.Count
        }

        It 'warns when the reports are supplied in the wrong chronological order' {
            $ref = ConvertFrom-PasswordQualityReport -LiteralPath $script:BaselinePath -Timestamp (Get-Date '2026-07-15')
            $diff = ConvertFrom-PasswordQualityReport -LiteralPath $script:CurrentPath -Timestamp (Get-Date '2026-07-08')

            $warnings = @()
            $null = Compare-PasswordAudit -ReferenceReport $ref -DifferenceReport $diff -WarningVariable warnings -WarningAction SilentlyContinue
            ($warnings.Message -join "`n") | Should -BeLike '*read backwards*'
        }
    }
}
