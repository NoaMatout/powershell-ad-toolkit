function Compare-PasswordAudit {
    <#
    .SYNOPSIS
        Compares two password-quality audits and reports what changed between them.

    .DESCRIPTION
        A single password audit tells you how bad things are. Two audits tell you whether
        anyone is fixing them - which is the question that actually drives remediation.

        Each finding in either report is classified as:

          New         the account was clean last time and is flagged now - a regression
          Resolved    the account was flagged last time and is clean now - a fix landed
          Persisting  the account was flagged both times - nothing happened

        Sections are compared independently, so an account can be Resolved for one weakness
        and Persisting for another. A section present in only one of the two reports cannot
        be compared and is reported as a warning rather than silently treated as all-new or
        all-resolved.

        Duplicate-password findings get one extra piece of information. The group numbering
        in the source report is assigned per run and means nothing across runs, so groups are
        matched on their membership instead. A persisting account whose group membership
        changed is flagged with GroupChanged - it still shares its password, but with a
        different set of accounts, which usually means someone rotated a subset of them.

    .PARAMETER ReferencePath
        Path to the earlier report - the baseline being compared against.

    .PARAMETER DifferencePath
        Path to the later report - the current state.

    .PARAMETER ReferenceReport
        The earlier report, already parsed by ConvertFrom-PasswordQualityReport.

    .PARAMETER DifferenceReport
        The later report, already parsed by ConvertFrom-PasswordQualityReport.

    .PARAMETER Status
        Which classifications to emit. Defaults to all three.

    .PARAMETER Section
        Restrict the comparison to specific sections, for example InDictionary or
        DuplicatePasswords. Defaults to every section present in both reports.

    .EXAMPLE
        Compare-PasswordAudit -ReferencePath .\2026-07-08.txt -DifferencePath .\2026-07-15.txt

        Compares two weekly audits and emits every change.

    .EXAMPLE
        Compare-PasswordAudit -ReferencePath $last -DifferencePath $now -Status New |
            Where-Object Severity -in 'Critical', 'High'

        Emits only regressions that matter - the shortlist worth acting on this week.

    .EXAMPLE
        $diff = Compare-PasswordAudit -ReferencePath $last -DifferencePath $now
        $diff | Group-Object Section, Status | Select-Object Name, Count

        Gives the week-over-week movement per category.

    .OUTPUTS
        ADToolkit.PasswordAuditChange

    .LINK
        https://github.com/NoaMatout/powershell-ad-toolkit
    #>
    [CmdletBinding(DefaultParameterSetName = 'Path')]
    [OutputType('ADToolkit.PasswordAuditChange')]
    param(
        [Parameter(Mandatory, Position = 0, ParameterSetName = 'Path')]
        [ValidateNotNullOrEmpty()]
        [string] $ReferencePath,

        [Parameter(Mandatory, Position = 1, ParameterSetName = 'Path')]
        [ValidateNotNullOrEmpty()]
        [string] $DifferencePath,

        [Parameter(Mandatory, ParameterSetName = 'Report')]
        [PSTypeName('ADToolkit.PasswordQualityReport')]
        $ReferenceReport,

        [Parameter(Mandatory, ParameterSetName = 'Report')]
        [PSTypeName('ADToolkit.PasswordQualityReport')]
        $DifferenceReport,

        [Parameter()]
        [ValidateSet('New', 'Resolved', 'Persisting')]
        [string[]] $Status = @('New', 'Resolved', 'Persisting'),

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string[]] $Section
    )

    if ($PSCmdlet.ParameterSetName -eq 'Path') {
        $ReferenceReport = ConvertFrom-PasswordQualityReport -LiteralPath $ReferencePath
        $DifferenceReport = ConvertFrom-PasswordQualityReport -LiteralPath $DifferencePath
    }

    if ($ReferenceReport.Timestamp -gt $DifferenceReport.Timestamp) {
        Write-Warning ("The reference report ({0:yyyy-MM-dd}) is newer than the difference report ({1:yyyy-MM-dd}). " -f $ReferenceReport.Timestamp, $DifferenceReport.Timestamp +
            'Results will read backwards: fixes will appear as New and regressions as Resolved.')
    }

    $referenceSections = @($ReferenceReport.Sections.Keys)
    $differenceSections = @($DifferenceReport.Sections.Keys)

    $comparable = @($referenceSections | Where-Object { $differenceSections -contains $_ })

    foreach ($orphan in ($referenceSections + $differenceSections | Select-Object -Unique | Where-Object { $comparable -notcontains $_ })) {
        Write-Warning "Section '$orphan' is present in only one of the two reports and was not compared."
    }

    if ($PSBoundParameters.ContainsKey('Section')) {
        $unknown = @($Section | Where-Object { $comparable -notcontains $_ })
        foreach ($u in $unknown) {
            Write-Warning "Section '$u' was requested but is not comparable across these two reports."
        }
        $comparable = @($comparable | Where-Object { $Section -contains $_ })
    }

    $severityRank = @{ Critical = 0; High = 1; Medium = 2; Low = 3 }
    $results = New-Object System.Collections.Generic.List[psobject]

    foreach ($sectionKey in $comparable) {
        $before = @($ReferenceReport.Findings | Where-Object Section -eq $sectionKey)
        $after = @($DifferenceReport.Findings | Where-Object Section -eq $sectionKey)

        $beforeIndex = @{}
        foreach ($f in $before) { $beforeIndex[$f.Identity] = $f }

        $afterIndex = @{}
        foreach ($f in $after) { $afterIndex[$f.Identity] = $f }

        $identities = @($beforeIndex.Keys) + @($afterIndex.Keys) | Select-Object -Unique

        foreach ($identity in $identities) {
            $wasFlagged = $beforeIndex.ContainsKey($identity)
            $isFlagged = $afterIndex.ContainsKey($identity)

            $state = if ($wasFlagged -and $isFlagged) { 'Persisting' }
                     elseif ($isFlagged) { 'New' }
                     else { 'Resolved' }

            if ($Status -notcontains $state) { continue }

            $source = if ($isFlagged) { $afterIndex[$identity] } else { $beforeIndex[$identity] }

            $groupChanged = $null
            if ($state -eq 'Persisting' -and $null -ne $source.GroupSignature) {
                $groupChanged = $beforeIndex[$identity].GroupSignature -ne $afterIndex[$identity].GroupSignature
            }

            $results.Add([pscustomobject] @{
                PSTypeName        = 'ADToolkit.PasswordAuditChange'
                Status            = $state
                Section           = $sectionKey
                Severity          = $source.Severity
                Identity          = $identity
                Domain            = $source.Domain
                SamAccountName    = $source.SamAccountName
                IsComputerAccount = $source.IsComputerAccount
                GroupChanged      = $groupChanged
                ReferenceDate     = $ReferenceReport.Timestamp
                DifferenceDate    = $DifferenceReport.Timestamp
            })
        }
    }

    # Sorted on severity rather than alphabetically, so the output reads worst-first.
    # Ranking via a calculated expression keeps the rank out of the emitted objects, which
    # would otherwise carry a meaningless integer column into every report and export.
    $results | Sort-Object -Property @{ Expression = { $severityRank[$_.Severity] } }, Section, Status, Identity
}
