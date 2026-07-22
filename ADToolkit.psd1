@{
    RootModule        = 'ADToolkit.psm1'
    ModuleVersion     = '0.1.0'
    GUID              = 'b7f4c2a1-9d3e-4f68-8a52-6c1e0b4d7a93'
    Author            = 'Noa Matout'
    Copyright         = '(c) 2026 Noa Matout. Released under the MIT License.'
    Description       = 'Orchestration layer for recurring Active Directory security audits. Drives third-party assessment tools, turns their text output into objects, and reports what changed since the previous run.'

    PowerShellVersion = '5.1'

    FunctionsToExport = @(
        'ConvertFrom-PasswordQualityReport'
        'Compare-PasswordAudit'
    )
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()

    PrivateData       = @{
        PSData = @{
            Tags         = @(
                'ActiveDirectory'
                'Security'
                'Audit'
                'DSInternals'
                'PasswordQuality'
                'BlueTeam'
                'Windows'
                'PowerShell'
            )
            LicenseUri   = 'https://github.com/NoaMatout/powershell-ad-toolkit/blob/main/LICENSE'
            ProjectUri   = 'https://github.com/NoaMatout/powershell-ad-toolkit'
            ReleaseNotes = 'Initial release: password-quality report parsing and week-over-week comparison.'
        }
    }
}
