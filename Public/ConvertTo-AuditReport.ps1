function ConvertTo-AuditReport {
    <#
    .SYNOPSIS
        Renders password-audit changes as an HTML or Markdown report.

    .DESCRIPTION
        Takes the output of Compare-PasswordAudit and produces a document: a summary of how
        many findings were fixed, appeared and persisted, then one table per category ordered
        worst-first.

        This function renders. It does not send. Mail transport belongs to the caller, who
        knows the relay, the credentials and the recipients -- none of which have any business
        being baked into a reporting module. Pipe the result to Out-File, or into whichever
        mail cmdlet you use.

        The HTML carries its styling inline on each element rather than in a <style> block,
        because several mail clients (Outlook on the web and Gmail among them) strip or ignore
        document-level stylesheets and would render the report as unstyled text.

    .PARAMETER Change
        Changes emitted by Compare-PasswordAudit.

    .PARAMETER Format
        Html (default) or Markdown.

    .PARAMETER Title
        Heading placed at the top of the report.

    .PARAMETER Empty
        Text shown when there is nothing to report. Defaults to a plain statement that no
        change was detected -- worth keeping, since a silent empty report reads like a
        broken job.

    .EXAMPLE
        Compare-PasswordAudit -ReferencePath $last -DifferencePath $now |
            ConvertTo-AuditReport |
            Out-File .\report.html -Encoding utf8

        Renders the full comparison to a file.

    .EXAMPLE
        $r = Get-PasswordAuditArchive -Path D:\audits -Latest 2
        $body = Compare-PasswordAudit -ReferenceReport $r[0] -DifferenceReport $r[-1] -Status New |
            ConvertTo-AuditReport -Title 'Regressions this week'

        Builds a mail body containing only what got worse.

    .OUTPUTS
        System.String

    .LINK
        https://github.com/NoaMatout/powershell-ad-toolkit
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [AllowEmptyCollection()]
        [PSTypeName('ADToolkit.PasswordAuditChange')]
        $Change,

        [Parameter()]
        [ValidateSet('Html', 'Markdown')]
        [string] $Format = 'Html',

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string] $Title = 'Active Directory password audit',

        [Parameter()]
        [ValidateNotNull()]
        [string] $Empty = 'No change was detected between the two audits.'
    )

    begin {
        $collected = New-Object System.Collections.Generic.List[psobject]
        $severityRank = @{ Critical = 0; High = 1; Medium = 2; Low = 3 }
        $statusColour = @{ New = '#c62828'; Resolved = '#2e7d32'; Persisting = '#ef6c00' }
    }

    process {
        foreach ($item in $Change) {
            $collected.Add($item)
        }
    }

    end {
        $changes = $collected.ToArray()

        $counts = [ordered] @{
            New        = @($changes | Where-Object Status -eq 'New').Count
            Resolved   = @($changes | Where-Object Status -eq 'Resolved').Count
            Persisting = @($changes | Where-Object Status -eq 'Persisting').Count
        }

        $period = ''
        if ($changes.Count -gt 0) {
            $period = '{0:yyyy-MM-dd} to {1:yyyy-MM-dd}' -f $changes[0].ReferenceDate, $changes[0].DifferenceDate
        }

        $sections = $changes |
            Group-Object Section |
            Sort-Object @{ Expression = { $severityRank[$_.Group[0].Severity] } }, Name

        if ($Format -eq 'Markdown') {
            $sb = New-Object System.Text.StringBuilder

            $null = $sb.AppendLine("# $Title").AppendLine()
            # Braced deliberately: "_$period_" would parse as the variable $period_.
            if ($period) { $null = $sb.AppendLine("_$($period)_").AppendLine() }

            $null = $sb.AppendLine('| Fixed | New | Persisting |')
            $null = $sb.AppendLine('| ---: | ---: | ---: |')
            $null = $sb.AppendLine("| $($counts.Resolved) | $($counts.New) | $($counts.Persisting) |").AppendLine()

            if ($changes.Count -eq 0) {
                $null = $sb.AppendLine($Empty)
                return $sb.ToString()
            }

            foreach ($section in $sections) {
                $null = $sb.AppendLine("## $($section.Name) _($($section.Group[0].Severity))_").AppendLine()
                $null = $sb.AppendLine('| Status | Account | Note |')
                $null = $sb.AppendLine('| --- | --- | --- |')

                foreach ($row in $section.Group) {
                    $note = if ($row.GroupChanged -eq $true) { 'group membership changed' } else { '' }
                    $null = $sb.AppendLine("| $($row.Status) | ``$($row.Identity)`` | $note |")
                }
                $null = $sb.AppendLine()
            }

            return $sb.ToString()
        }

        $html = New-Object System.Text.StringBuilder
        $enc = { param($t) [System.Net.WebUtility]::HtmlEncode([string] $t) }

        $null = $html.Append("<div style=""font-family:Segoe UI,Arial,sans-serif;color:#222;max-width:900px"">")
        $null = $html.Append("<h1 style=""font-size:20px;border-bottom:2px solid #1565c0;padding-bottom:8px"">$(& $enc $Title)</h1>")

        if ($period) {
            $null = $html.Append("<p style=""color:#666;margin:0 0 16px"">$(& $enc $period)</p>")
        }

        $null = $html.Append("<table role=""presentation"" style=""border-collapse:collapse;margin-bottom:24px""><tr>")
        foreach ($key in $counts.Keys) {
            $label = switch ($key) { 'Resolved' { 'Fixed' } default { $key } }
            $null = $html.Append("<td style=""padding:12px 24px;text-align:center;border:1px solid #ddd"">")
            $null = $html.Append("<div style=""font-size:28px;font-weight:bold;color:$($statusColour[$key])"">$($counts[$key])</div>")
            $null = $html.Append("<div style=""font-size:12px;color:#666"">$(& $enc $label)</div></td>")
        }
        $null = $html.Append('</tr></table>')

        if ($changes.Count -eq 0) {
            $null = $html.Append("<p style=""color:#666;font-style:italic"">$(& $enc $Empty)</p></div>")
            return $html.ToString()
        }

        foreach ($section in $sections) {
            $severity = $section.Group[0].Severity
            $null = $html.Append("<h2 style=""font-size:15px;margin:24px 0 8px"">$(& $enc $section.Name) ")
            $null = $html.Append("<span style=""font-size:12px;font-weight:normal;color:#666"">($(& $enc $severity))</span></h2>")

            $null = $html.Append("<table style=""border-collapse:collapse;width:100%;font-size:13px"">")
            $null = $html.Append("<tr><th style=""text-align:left;padding:6px 10px;background:#f5f5f5;border:1px solid #ddd"">Status</th>")
            $null = $html.Append("<th style=""text-align:left;padding:6px 10px;background:#f5f5f5;border:1px solid #ddd"">Account</th>")
            $null = $html.Append("<th style=""text-align:left;padding:6px 10px;background:#f5f5f5;border:1px solid #ddd"">Note</th></tr>")

            foreach ($row in $section.Group) {
                $note = if ($row.GroupChanged -eq $true) { 'group membership changed' } else { '' }
                $null = $html.Append("<tr><td style=""padding:6px 10px;border:1px solid #ddd;color:$($statusColour[$row.Status]);font-weight:bold"">$(& $enc $row.Status)</td>")
                $null = $html.Append("<td style=""padding:6px 10px;border:1px solid #ddd;font-family:Consolas,monospace"">$(& $enc $row.Identity)</td>")
                $null = $html.Append("<td style=""padding:6px 10px;border:1px solid #ddd;color:#666"">$(& $enc $note)</td></tr>")
            }

            $null = $html.Append('</table>')
        }

        $null = $html.Append('</div>')
        $html.ToString()
    }
}
