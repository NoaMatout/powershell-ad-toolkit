function ConvertFrom-PasswordQualityReport {
    <#
    .SYNOPSIS
        Parses a DSInternals Test-PasswordQuality text report into structured findings.

    .DESCRIPTION
        Test-PasswordQuality returns a result object that renders as an English text report.
        Teams routinely archive that text (it is what you get from `| Out-File`), which makes
        it the only artefact still available weeks later - but text does not diff usefully.

        This function turns the archived text back into objects, one per finding, so reports
        from different weeks can be compared, filtered and rendered.

        Content before the first recognised heading is preamble and is ignored. A heading the
        module does not know about produces a warning rather than silence, so a wording change
        in a future DSInternals release surfaces instead of quietly dropping findings.

    .PARAMETER Path
        Path to one or more archived report files. Wildcards are supported.

    .PARAMETER LiteralPath
        Path to a report file, used literally - no wildcard expansion.

    .PARAMETER Content
        The report as an array of lines, for callers that already hold it in memory
        (for example `Test-PasswordQuality ... | Out-String -Stream`).

    .PARAMETER Timestamp
        The point in time the report describes. Defaults to the file's last write time, or to
        the current time when parsing from -Content. Comparisons use this to order reports.

    .PARAMETER Encoding
        Encoding of the report file. Defaults to UTF8.

    .EXAMPLE
        ConvertFrom-PasswordQualityReport -Path .\report-2026-07-15.txt

        Parses one archived report and emits a report object.

    .EXAMPLE
        Get-ChildItem .\archive\*.txt | ConvertFrom-PasswordQualityReport |
            Select-Object -ExpandProperty Findings |
            Where-Object Severity -eq 'Critical' |
            Group-Object Section

        Counts critical findings by category across a whole archive.

    .OUTPUTS
        ADToolkit.PasswordQualityReport

    .LINK
        https://github.com/NoaMatout/powershell-ad-toolkit
    #>
    [CmdletBinding(DefaultParameterSetName = 'Path')]
    [OutputType('ADToolkit.PasswordQualityReport')]
    param(
        [Parameter(Mandatory, Position = 0, ParameterSetName = 'Path', ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('FullName')]
        [ValidateNotNullOrEmpty()]
        [string[]] $Path,

        [Parameter(Mandatory, ParameterSetName = 'LiteralPath', ValueFromPipelineByPropertyName)]
        [Alias('PSPath')]
        [ValidateNotNullOrEmpty()]
        [string[]] $LiteralPath,

        [Parameter(Mandatory, ParameterSetName = 'Content')]
        [AllowEmptyCollection()]
        [AllowEmptyString()]
        [string[]] $Content,

        [Parameter()]
        [datetime] $Timestamp,

        [Parameter()]
        [ValidateSet('UTF8', 'Unicode', 'UTF7', 'UTF32', 'ASCII', 'BigEndianUnicode', 'Default', 'OEM')]
        [string] $Encoding = 'UTF8'
    )

    begin {
        $sectionMap = Get-PasswordQualitySectionMap
    }

    process {
        $items = switch ($PSCmdlet.ParameterSetName) {
            'Path'        { Resolve-Path -Path $Path | Select-Object -ExpandProperty ProviderPath }
            'LiteralPath' { $LiteralPath }
            'Content'     { $null }
        }

        if ($PSCmdlet.ParameterSetName -eq 'Content') {
            $reportTime = if ($PSBoundParameters.ContainsKey('Timestamp')) { $Timestamp } else { Get-Date }
            ConvertTo-PasswordQualityReportObject -Lines $Content -SectionMap $sectionMap -Timestamp $reportTime -SourcePath $null
            return
        }

        foreach ($item in $items) {
            if (-not (Test-Path -LiteralPath $item -PathType Leaf)) {
                Write-Error -Message "Report file not found: $item" -Category ObjectNotFound -TargetObject $item
                continue
            }

            $lines = Get-Content -LiteralPath $item -Encoding $Encoding

            $reportTime = if ($PSBoundParameters.ContainsKey('Timestamp')) {
                $Timestamp
            }
            else {
                (Get-Item -LiteralPath $item).LastWriteTime
            }

            ConvertTo-PasswordQualityReportObject -Lines $lines -SectionMap $sectionMap -Timestamp $reportTime -SourcePath $item
        }
    }
}
