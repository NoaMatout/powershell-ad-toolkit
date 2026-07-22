function Get-PasswordAuditArchive {
    <#
    .SYNOPSIS
        Resolves archived password-quality reports from a directory and parses them.

    .DESCRIPTION
        Weekly audits accumulate as dated archives in a folder. This function finds them,
        works out which point in time each one describes, and returns them as parsed report
        objects ready for Compare-PasswordAudit.

        Zipped archives are read in memory. Extracting them to a temporary directory would
        leave a plaintext list of every weak and shared password in the domain sitting in the
        profile of whoever ran the script -- and it stays there if the script fails before its
        cleanup runs. The report never touches disk here.

        The date comes from the file name rather than its last write time, because a file
        copied or restored keeps its content but not its timestamp, and an audit dated wrongly
        compares wrongly. Last write time is used only as a fallback, with a warning.

        Reports are returned oldest first, so the last element is the current state:

            $reports = Get-PasswordAuditArchive -Path .\archive -Latest 2
            Compare-PasswordAudit -ReferenceReport $reports[0] -DifferenceReport $reports[-1]

    .PARAMETER Path
        Directory holding the archives.

    .PARAMETER Filter
        Wildcard filter selecting candidate files. Defaults to '*.zip'. Plain '.txt' reports
        are read directly, so a mixed folder works.

    .PARAMETER NamePattern
        Regular expression matched against the file's base name, with a named capture group
        'date' holding the timestamp portion. Defaults to the trailing dd_MM_yyyy convention.

    .PARAMETER DateFormat
        .NET format string used to interpret the captured date. Defaults to 'dd_MM_yyyy'.

    .PARAMETER EntryName
        Name of the report file inside a zipped archive. Defaults to 'reportpassword.txt'.

    .PARAMETER Latest
        Return only the N most recent archives. Defaults to all of them.

    .EXAMPLE
        Get-PasswordAuditArchive -Path D:\audits -Latest 2

        Returns the two most recent audits, oldest first.

    .EXAMPLE
        $r = Get-PasswordAuditArchive -Path D:\audits -Latest 2
        Compare-PasswordAudit -ReferenceReport $r[0] -DifferenceReport $r[-1] -Status New

        The whole week-over-week comparison, in two lines.

    .EXAMPLE
        Get-PasswordAuditArchive -Path D:\audits |
            Select-Object Timestamp, @{ N = 'Duplicates'; E = { $_.Sections['DuplicatePasswords'] } }

        Plots one metric across the full history.

    .OUTPUTS
        ADToolkit.PasswordQualityReport

    .LINK
        https://github.com/NoaMatout/powershell-ad-toolkit
    #>
    [CmdletBinding()]
    [OutputType('ADToolkit.PasswordQualityReport')]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('FullName', 'PSPath')]
        [ValidateNotNullOrEmpty()]
        [string] $Path,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string] $Filter = '*.zip',

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string] $NamePattern = '-(?<date>\d{2}_\d{2}_\d{4})$',

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string] $DateFormat = 'dd_MM_yyyy',

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string] $EntryName = 'reportpassword.txt',

        [Parameter()]
        [ValidateRange(1, [int]::MaxValue)]
        [int] $Latest
    )

    begin {
        Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue
    }

    process {
        if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
            Write-Error -Message "Archive directory not found: $Path" -Category ObjectNotFound -TargetObject $Path
            return
        }

        $files = @(Get-ChildItem -LiteralPath $Path -Filter $Filter -File)

        if ($files.Count -eq 0) {
            Write-Warning "No files matching '$Filter' in $Path."
            return
        }

        $dated = foreach ($file in $files) {
            $stamp = $null

            if ($file.BaseName -match $NamePattern) {
                $captured = $Matches['date']
                $parsed = [datetime]::MinValue
                if ([datetime]::TryParseExact($captured, $DateFormat, [cultureinfo]::InvariantCulture, [Globalization.DateTimeStyles]::None, [ref] $parsed)) {
                    $stamp = $parsed
                }
                else {
                    Write-Warning "'$($file.Name)' has a date portion ('$captured') that does not match the format '$DateFormat'. Falling back to its last write time."
                }
            }
            else {
                Write-Warning "'$($file.Name)' does not match the expected naming pattern. Falling back to its last write time."
            }

            if ($null -eq $stamp) { $stamp = $file.LastWriteTime }

            [pscustomobject] @{ File = $file; Timestamp = $stamp }
        }

        $selected = @($dated | Sort-Object Timestamp)

        if ($PSBoundParameters.ContainsKey('Latest')) {
            $selected = @($selected | Select-Object -Last $Latest)
        }

        foreach ($item in $selected) {
            $lines = if ($item.File.Extension -eq '.zip') {
                Read-ZipEntryLine -ArchivePath $item.File.FullName -EntryName $EntryName
            }
            else {
                Get-Content -LiteralPath $item.File.FullName
            }

            if ($null -eq $lines) { continue }

            ConvertFrom-PasswordQualityReport -Content $lines -Timestamp $item.Timestamp |
                ForEach-Object {
                    # Content parsing has no source path of its own; restore the archive it
                    # came from so a finding can be traced back to a file on disk.
                    $_.Path = $item.File.FullName
                    $_
                }
        }
    }
}
