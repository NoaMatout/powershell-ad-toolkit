BeforeAll {
    $moduleRoot = Split-Path -Parent $PSScriptRoot
    Import-Module (Join-Path $moduleRoot 'ADToolkit.psd1') -Force

    $fixtures = Join-Path $PSScriptRoot 'fixtures'
    $script:Changes = Compare-PasswordAudit `
        -ReferencePath (Join-Path $fixtures 'audit-baseline.txt') `
        -DifferencePath (Join-Path $fixtures 'audit-current.txt') `
        -WarningAction SilentlyContinue
}

Describe 'ConvertTo-AuditReport' {

    Context 'HTML' {

        BeforeAll {
            $script:Html = $script:Changes | ConvertTo-AuditReport
        }

        It 'renders a single string' {
            $script:Html | Should -BeOfType [string]
        }

        It 'includes the title' {
            $custom = $script:Changes | ConvertTo-AuditReport -Title 'Weekly AD review'
            $custom | Should -BeLike '*Weekly AD review*'
        }

        It 'reports the counts per status' {
            $resolved = @($script:Changes | Where-Object Status -eq 'Resolved').Count
            $script:Html | Should -BeLike "*>$resolved<*"
        }

        It 'lists the accounts' {
            $script:Html | Should -BeLike '*EXAMPLE\alice*'
            $script:Html | Should -BeLike '*EXAMPLE\carol*'
        }

        It 'carries styling inline rather than in a stylesheet block' {
            # Several mail clients drop <style> blocks; the report must survive that.
            $script:Html | Should -Not -BeLike '*<style*'
            $script:Html | Should -BeLike '*style="*'
        }

        It 'notes a group whose membership changed' {
            $script:Html | Should -BeLike '*group membership changed*'
        }

        It 'escapes markup coming from account names' {
            $hostile = [pscustomobject] @{
                PSTypeName        = 'ADToolkit.PasswordAuditChange'
                Status            = 'New'
                Section           = 'InDictionary'
                Severity          = 'Critical'
                Identity          = 'EXAMPLE\<script>alert(1)</script>'
                Domain            = 'EXAMPLE'
                SamAccountName    = '<script>alert(1)</script>'
                IsComputerAccount = $false
                GroupChanged      = $null
                ReferenceDate     = Get-Date
                DifferenceDate    = Get-Date
            }

            $out = $hostile | ConvertTo-AuditReport
            $out | Should -Not -BeLike '*<script>*'
            $out | Should -BeLike '*&lt;script&gt;*'
        }

        It 'states plainly when there is nothing to report' {
            # An empty report that renders as blank looks like a broken scheduled job.
            $out = @() | ConvertTo-AuditReport
            $out | Should -BeLike '*No change was detected*'
        }
    }

    Context 'Markdown' {

        BeforeAll {
            $script:Markdown = $script:Changes | ConvertTo-AuditReport -Format Markdown
        }

        It 'starts with a heading' {
            $script:Markdown | Should -BeLike '# Active Directory password audit*'
        }

        It 'renders a table per section' {
            $script:Markdown | Should -BeLike '*## InDictionary*'
            $script:Markdown | Should -BeLike '*| Status | Account | Note |*'
        }

        It 'lists the accounts' {
            $script:Markdown | Should -BeLike '*EXAMPLE\carol*'
        }

        It 'contains no HTML' {
            $script:Markdown | Should -Not -BeLike '*<table*'
        }
    }

    Context 'Ordering' {

        It 'places the most severe section first' {
            $md = $script:Changes | ConvertTo-AuditReport -Format Markdown
            $firstSection = ([regex]::Matches($md, '(?m)^## (\w+)') | Select-Object -First 1).Groups[1].Value
            $expected = ($script:Changes | Select-Object -First 1).Section
            $firstSection | Should -Be $expected
        }
    }
}
