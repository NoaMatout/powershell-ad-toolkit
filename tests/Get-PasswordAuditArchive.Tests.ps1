BeforeAll {
    $moduleRoot = Split-Path -Parent $PSScriptRoot
    Import-Module (Join-Path $moduleRoot 'ADToolkit.psd1') -Force

    $script:Fixtures = Join-Path $PSScriptRoot 'fixtures'

    # Archives are built at run time rather than committed. A zipped audit report is exactly
    # the kind of artefact that must never live in a repository, so the tests make their own.
    function Compress-TestReport {
        param($Directory, $Name, $SourceReport, $EntryName = 'reportpassword.txt')

        $staging = Join-Path ([System.IO.Path]::GetTempPath()) ([guid]::NewGuid())
        New-Item -ItemType Directory -Path $staging -Force | Out-Null
        try {
            $entry = Join-Path $staging $EntryName
            Copy-Item -LiteralPath $SourceReport -Destination $entry
            Compress-Archive -LiteralPath $entry -DestinationPath (Join-Path $Directory $Name) -Force
        }
        finally {
            Remove-Item $staging -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe 'Get-PasswordAuditArchive' {

    BeforeEach {
        $script:ArchiveDir = Join-Path $TestDrive ([guid]::NewGuid())
        New-Item -ItemType Directory -Path $script:ArchiveDir -Force | Out-Null

        Compress-TestReport -Directory $script:ArchiveDir -Name 'Password_Audit-08_07_2026.zip' -SourceReport (Join-Path $script:Fixtures 'audit-baseline.txt')
        Compress-TestReport -Directory $script:ArchiveDir -Name 'Password_Audit-15_07_2026.zip' -SourceReport (Join-Path $script:Fixtures 'audit-current.txt')
    }

    Context 'Resolution and ordering' {

        It 'parses every archive in the directory' {
            $reports = @(Get-PasswordAuditArchive -Path $script:ArchiveDir)
            $reports.Count | Should -Be 2
        }

        It 'returns reports oldest first' {
            $reports = @(Get-PasswordAuditArchive -Path $script:ArchiveDir)
            $reports[0].Timestamp | Should -BeLessThan $reports[1].Timestamp
        }

        It 'takes the date from the file name, not the write time' {
            # Both archives were written seconds ago; only the name says which week they are.
            $reports = @(Get-PasswordAuditArchive -Path $script:ArchiveDir)
            $reports[0].Timestamp | Should -Be ([datetime]'2026-07-08')
            $reports[1].Timestamp | Should -Be ([datetime]'2026-07-15')
        }

        It 'keeps the most recent N when asked' {
            $reports = @(Get-PasswordAuditArchive -Path $script:ArchiveDir -Latest 1)
            $reports.Count | Should -Be 1
            $reports[0].Timestamp | Should -Be ([datetime]'2026-07-15')
        }

        It 'records which archive each report came from' {
            $reports = @(Get-PasswordAuditArchive -Path $script:ArchiveDir)
            $reports[0].Path | Should -BeLike '*Password_Audit-08_07_2026.zip'
        }
    }

    Context 'Content' {

        It 'parses the report inside the archive' {
            $reports = @(Get-PasswordAuditArchive -Path $script:ArchiveDir)
            $reports[0].Findings.Identity | Should -Contain 'EXAMPLE\alice'
        }

        It 'leaves nothing behind on disk' {
            $before = @(Get-ChildItem ([System.IO.Path]::GetTempPath()) -Filter '*reportpassword*' -Recurse -ErrorAction SilentlyContinue).Count
            $null = Get-PasswordAuditArchive -Path $script:ArchiveDir
            $after = @(Get-ChildItem ([System.IO.Path]::GetTempPath()) -Filter '*reportpassword*' -Recurse -ErrorAction SilentlyContinue).Count
            $after | Should -Be $before
        }

        It 'feeds Compare-PasswordAudit directly' {
            $r = @(Get-PasswordAuditArchive -Path $script:ArchiveDir -Latest 2)
            $changes = Compare-PasswordAudit -ReferenceReport $r[0] -DifferenceReport $r[-1] -WarningAction SilentlyContinue
            ($changes | Where-Object { $_.Identity -eq 'EXAMPLE\carol' }).Status | Should -Be 'New'
        }
    }

    Context 'Plain text archives' {

        It 'reads an unzipped report when pointed at one' {
            Copy-Item (Join-Path $script:Fixtures 'audit-current.txt') (Join-Path $script:ArchiveDir 'Password_Audit-22_07_2026.txt')
            $reports = @(Get-PasswordAuditArchive -Path $script:ArchiveDir -Filter '*.txt')
            $reports.Count | Should -Be 1
            $reports[0].Timestamp | Should -Be ([datetime]'2026-07-22')
        }
    }

    Context 'Failure handling' {

        It 'warns and falls back to the write time when the name does not match' {
            Compress-TestReport -Directory $script:ArchiveDir -Name 'unexpected-name.zip' -SourceReport (Join-Path $script:Fixtures 'audit-current.txt')

            $warnings = @()
            $reports = @(Get-PasswordAuditArchive -Path $script:ArchiveDir -WarningVariable warnings -WarningAction SilentlyContinue)

            ($warnings.Message -join "`n") | Should -BeLike '*unexpected-name.zip*'
            $reports.Count | Should -Be 3
        }

        It 'warns when the date portion does not match the declared format' {
            Compress-TestReport -Directory $script:ArchiveDir -Name 'Password_Audit-99_99_2026.zip' -SourceReport (Join-Path $script:Fixtures 'audit-current.txt')

            $warnings = @()
            $null = Get-PasswordAuditArchive -Path $script:ArchiveDir -WarningVariable warnings -WarningAction SilentlyContinue
            ($warnings.Message -join "`n") | Should -BeLike "*does not match the format*"
        }

        It 'errors when the archive has no entry of the expected name' {
            $dir = Join-Path $TestDrive ([guid]::NewGuid())
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
            Compress-TestReport -Directory $dir -Name 'Password_Audit-01_07_2026.zip' -SourceReport (Join-Path $script:Fixtures 'audit-current.txt') -EntryName 'somethingelse.txt'

            $errors = @()
            $null = Get-PasswordAuditArchive -Path $dir -ErrorVariable errors -ErrorAction SilentlyContinue
            $errors.Count | Should -BeGreaterThan 0
            ($errors.Exception.Message -join "`n") | Should -BeLike '*somethingelse.txt*'
        }

        It 'errors on a directory that does not exist' {
            $errors = @()
            $null = Get-PasswordAuditArchive -Path (Join-Path $TestDrive 'nope') -ErrorVariable errors -ErrorAction SilentlyContinue
            $errors.Count | Should -Be 1
        }

        It 'warns when the directory holds no matching file' {
            $empty = Join-Path $TestDrive ([guid]::NewGuid())
            New-Item -ItemType Directory -Path $empty -Force | Out-Null

            $warnings = @()
            $null = Get-PasswordAuditArchive -Path $empty -WarningVariable warnings -WarningAction SilentlyContinue
            ($warnings.Message -join "`n") | Should -BeLike '*No files matching*'
        }
    }
}
