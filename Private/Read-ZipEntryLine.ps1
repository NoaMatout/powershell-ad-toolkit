function Read-ZipEntryLine {
    <#
    .SYNOPSIS
        Reads a single text entry out of a zip archive without writing it to disk.

    .DESCRIPTION
        Expand-Archive would be shorter, but it writes the entry to a temporary directory --
        and the entry here is a list of every account in the domain with a weak, shared or
        absent password. Leaving that in a temp folder is a worse outcome than any convenience
        it buys, especially since a failure between extraction and cleanup leaves it behind.

        The entry is streamed into memory instead. Nothing is written anywhere.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $ArchivePath,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $EntryName
    )

    $archive = $null
    $reader = $null

    try {
        $archive = [System.IO.Compression.ZipFile]::OpenRead($ArchivePath)

        $entry = $archive.Entries | Where-Object { $_.Name -eq $EntryName } | Select-Object -First 1

        if ($null -eq $entry) {
            $available = ($archive.Entries | Select-Object -ExpandProperty Name) -join ', '
            Write-Error -Message "No entry named '$EntryName' in $ArchivePath. Entries present: $available" -Category ObjectNotFound -TargetObject $ArchivePath
            return
        }

        $lines = New-Object System.Collections.Generic.List[string]
        $reader = New-Object System.IO.StreamReader($entry.Open(), [System.Text.Encoding]::UTF8, $true)

        while ($null -ne ($line = $reader.ReadLine())) {
            $lines.Add($line)
        }

        , $lines.ToArray()
    }
    catch {
        Write-Error -Message "Failed to read '$EntryName' from ${ArchivePath}: $($_.Exception.Message)" -TargetObject $ArchivePath
    }
    finally {
        if ($null -ne $reader) { $reader.Dispose() }
        if ($null -ne $archive) { $archive.Dispose() }
    }
}
