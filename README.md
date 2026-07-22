# powershell-ad-toolkit

An orchestration layer for **recurring** Active Directory security audits.

Running an AD assessment once is easy. Running it every week and being able to answer
*"is anyone actually fixing this?"* is the part that gets skipped, because the tools that
do the assessing emit human-readable text rather than data.

This module sits on top of those tools: it drives them, turns their output into objects,
and reports what changed since last time.

```powershell
Compare-PasswordAudit -ReferencePath .\2026-07-08.txt -DifferencePath .\2026-07-15.txt -Status New |
    Where-Object Severity -in 'Critical', 'High' |
    Format-Table Status, Severity, Section, Identity
```

```
Status Severity Section                  Identity
------ -------- -------                  --------
New    Critical SamAccountNameAsPassword  EXAMPLE\dave
New    Critical InDictionary              EXAMPLE\carol
```

That is the whole point: a short list of what got worse this week, rather than a 400-line
text file identical to the last one except in ways nobody has time to spot.

## Status

Version 0.2.0. The password-audit workflow is complete end to end; the collection side and
the other assessment tools are still on the [roadmap](#roadmap). Nothing here is a stub —
what ships, works.

| Function | Purpose |
| --- | --- |
| `Get-PasswordAuditArchive` | Resolves dated archives in a directory and parses them, reading zips in memory |
| `ConvertFrom-PasswordQualityReport` | Parses an archived DSInternals `Test-PasswordQuality` report into finding objects |
| `Compare-PasswordAudit` | Classifies findings across two reports as New, Resolved or Persisting |
| `ConvertTo-AuditReport` | Renders a comparison as HTML or Markdown |

The whole weekly job, from a folder of archives to a mail body:

```powershell
$reports = Get-PasswordAuditArchive -Path D:\audits -Latest 2

Compare-PasswordAudit -ReferenceReport $reports[0] -DifferenceReport $reports[-1] |
    ConvertTo-AuditReport -Title 'Weekly AD password review' |
    Out-File .\report.html -Encoding utf8
```

## Install

```powershell
git clone https://github.com/NoaMatout/powershell-ad-toolkit.git
Import-Module .\powershell-ad-toolkit\ADToolkit.psd1
```

Requires PowerShell 5.1 or later. The module itself has no dependencies — it parses text
that other tools produce. Producing that text requires
[DSInternals](https://github.com/MichaelGrafnetter/DSInternals) and Domain Admin
(or equivalent replication) rights:

```powershell
Get-ADReplAccount -All -Server $DC -NamingContext 'DC=example,DC=local' |
    Test-PasswordQuality -WeakPasswordsFile .\pwnedpasswords.txt |
    Out-File ".\archive\audit-$(Get-Date -Format 'yyyy-MM-dd').txt"
```

Keep those archives somewhere appropriate. They name every account in the domain whose
password is weak, shared, or absent — the report is as sensitive as the weaknesses it
describes.

## What it does

### Findings become objects

Each entry in the report becomes an object carrying its section, a severity, the account
identity split into domain and SAM name, and whether it is a computer account.

```powershell
$report = ConvertFrom-PasswordQualityReport -Path .\archive\audit-2026-07-15.txt

$report.Findings | Group-Object Section | Sort-Object Count -Descending
$report.Findings | Where-Object { $_.Severity -eq 'Critical' -and -not $_.IsComputerAccount }
```

Section headings in the source report are full English sentences that have changed wording
between DSInternals releases, so they are mapped to stable keys
(`InDictionary`, `DuplicatePasswords`, `Kerberoastable`, …) in one place —
[`Private/Get-PasswordQualitySectionMap.ps1`](Private/Get-PasswordQualitySectionMap.ps1).
A heading the module does not recognise produces a warning and its entries are skipped,
rather than being silently misfiled under the previous heading.

### An empty section is not a missing section

A heading with nothing under it means the check ran and found nothing. A heading absent
entirely means the check did not run. Those are different facts, and conflating them makes
a comparison lie — every account in a section that stopped being reported would show up as
`Resolved`. Sections are recorded even when empty, and a section present in only one of two
reports is reported as a warning instead of being compared.

### Duplicate-password groups are matched on membership

The report groups accounts that share a password as `Group 1`, `Group 2`, and so on. That
numbering is assigned per run and carries no meaning across runs — the same two service
accounts can be `Group 1` one week and `Group 17` the next.

Groups are therefore identified by their sorted membership rather than by their label. A
persisting account whose group membership changed is flagged with `GroupChanged`: it still
shares its password, but with a different set of accounts, which usually means someone
rotated part of the group and stopped there.

## Design notes

**No third-party binaries are vendored.** PingCastle, ADRecon and DSInternals are excellent
and are not mine to redistribute. This module expects them to be installed and invokes them.

**No environment-specific values in the source.** Domains, controllers and paths are
parameters, never defaults. The test fixtures are synthetic.

**Text in, objects out.** The archived text report is usually the only artefact that still
exists weeks later, so it is treated as the input format rather than something to be
replaced.

### The archive is never written to disk

A zipped report is read as a stream. Expanding it to a temporary directory — the obvious
implementation, and the one I wrote first in production — leaves a plaintext list of every
weak and shared password in the domain in the profile of whoever ran the job, and leaves it
there permanently if the script fails before its cleanup step. That is a worse outcome than
any convenience it buys.

The date is taken from the file name rather than the file's write time, too: a copied or
restored archive keeps its contents but not its timestamp, and an audit dated wrongly
compares wrongly.

### Rendering is separate from sending

`ConvertTo-AuditReport` returns a string. It does not know your mail relay, and it should
not — that belongs to the caller. The HTML carries its styling inline rather than in a
`<style>` block, because Outlook on the web and Gmail both strip document-level stylesheets
and would otherwise render the report as unstyled text.

## Roadmap

Ordered by how much I want them, not by when they will land:

- `Invoke-PasswordAudit` — wrap the DSInternals collection so the archive is produced with a
  consistent name and layout
- `Invoke-ADHealthCheck` — drive PingCastle and expose its XML as objects
- `Invoke-ShareAudit` — drive PowerHunt for SMB share exposure

## Development

```powershell
Install-Module Pester -MinimumVersion 5.5 -Scope CurrentUser
Install-Module PSScriptAnalyzer -Scope CurrentUser

Invoke-Pester .\tests
Invoke-ScriptAnalyzer -Path . -Recurse -Severity Error,Warning
```

Both run in CI on every push against PowerShell 5.1 and 7.

## License

MIT — see [LICENSE](LICENSE).
