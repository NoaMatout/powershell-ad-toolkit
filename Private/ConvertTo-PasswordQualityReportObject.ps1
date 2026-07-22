function ConvertTo-PasswordQualityReportObject {
    <#
    .SYNOPSIS
        Turns the lines of a Test-PasswordQuality report into a report object.

    .DESCRIPTION
        The report is a flat list of headings, each followed by zero or more `DOMAIN\account`
        entries indented by two spaces. One heading - the duplicate-password one - nests a
        further level: `Group 1:`, `Group 2:` ... each with its own members indented by four.

        A heading present with no entries under it is meaningful: it says the check ran and
        found nothing, which is not the same as the check not having run. Sections are
        therefore recorded even when empty, so a comparison can tell "clean" from "unknown".
    #>
    [CmdletBinding()]
    [OutputType('ADToolkit.PasswordQualityReport')]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [AllowEmptyString()]
        [AllowNull()]
        [string[]] $Lines,

        [Parameter(Mandatory)]
        [System.Collections.Specialized.OrderedDictionary] $SectionMap,

        [Parameter(Mandatory)]
        [datetime] $Timestamp,

        [Parameter()]
        [AllowNull()]
        [string] $SourcePath
    )

    $findings = New-Object System.Collections.Generic.List[psobject]
    $sections = [ordered]@{}

    $current = $null
    $groupId = 0

    foreach ($line in $Lines) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }

        $text = $line.Trim()

        if ($SectionMap.Contains($text)) {
            $meta = $SectionMap[$text]
            $current = $meta
            $groupId = 0
            if (-not $sections.Contains($meta.Key)) {
                $sections[$meta.Key] = 0
            }
            continue
        }

        # A line ending in ':' is structural. Within a grouped section it opens a sub-group;
        # anywhere else it is a heading this module does not recognise, and everything under
        # it is dropped rather than misfiled under the previous heading.
        if ($text.EndsWith(':')) {
            if ($null -ne $current -and $current.Layout -eq 'Grouped' -and $text -match '^Group\s+(\d+):$') {
                $groupId = [int] $Matches[1]
                continue
            }

            Write-Warning "Unrecognised section heading, its entries were skipped: '$text'"
            $current = $null
            continue
        }

        if ($null -eq $current) { continue }

        $identity = $text
        $domain = $null
        $sam = $identity

        $separator = $identity.IndexOf('\')
        if ($separator -ge 0) {
            $domain = $identity.Substring(0, $separator)
            $sam = $identity.Substring($separator + 1)
        }

        $finding = [pscustomobject] @{
            PSTypeName        = 'ADToolkit.PasswordQualityFinding'
            Section           = $current.Key
            Severity          = $current.Severity
            Identity          = $identity
            Domain            = $domain
            SamAccountName    = $sam
            IsComputerAccount = $sam.EndsWith('$')
            GroupId           = if ($current.Layout -eq 'Grouped') { $groupId } else { $null }
            GroupSignature    = $null
            Timestamp         = $Timestamp
        }

        $findings.Add($finding)
        $sections[$current.Key] = $sections[$current.Key] + 1
    }

    # Group numbering is assigned per run and carries no meaning across runs: the same set of
    # accounts sharing a password can be "Group 3" one week and "Group 17" the next. The
    # signature - the sorted membership - is what actually identifies a group over time.
    $grouped = $findings | Where-Object { $null -ne $_.GroupId }
    foreach ($g in ($grouped | Group-Object GroupId)) {
        $signature = ($g.Group.Identity | Sort-Object) -join ';'
        foreach ($member in $g.Group) {
            $member.GroupSignature = $signature
        }
    }

    [pscustomobject] @{
        PSTypeName   = 'ADToolkit.PasswordQualityReport'
        Path         = $SourcePath
        Timestamp    = $Timestamp
        Sections     = $sections
        Findings     = $findings.ToArray()
        FindingCount = $findings.Count
    }
}
