# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```powershell
# Dependencies
Install-Module Pester -MinimumVersion 5.5 -Scope CurrentUser -SkipPublisherCheck
Install-Module PSScriptAnalyzer -Scope CurrentUser

# Full suite
Invoke-Pester .\tests

# One file
Invoke-Pester .\tests\Compare-PasswordAudit.Tests.ps1

# One test or context, by name
Invoke-Pester .\tests -FilterName '*group membership changed*'

# Static analysis -- CI fails on any Error or Warning
Invoke-ScriptAnalyzer -Path . -Recurse -Severity Error,Warning

# Reload after editing (the module dot-sources at import; edits need -Force)
Import-Module .\ADToolkit.psd1 -Force
```

CI runs the suite on both `powershell` (5.1) and `pwsh` (7), plus PSScriptAnalyzer and a
manifest check. Verify locally on 5.1 before pushing — it is the older of the two and the
one that breaks. `[datetime]::TryParseExact` with a `[ref]`, `[ordered]`, and the absence of
`?.` / ternaries are all 5.1 accommodations; do not "modernise" them.

## Constraints that shape the code

**Source files are ASCII-only.** PowerShell 5.1 reads a BOM-less UTF-8 file as ANSI and
mangles non-ASCII characters, and PSScriptAnalyzer flags the file. Use `-` and `...`, never
`—` or `…`, including in comments and doc blocks.

**The manifest lists exports explicitly.** Adding a file to `Public/` is not enough — add
the function to `FunctionsToExport` in `ADToolkit.psd1` or the `Manifest` CI job fails.

**Fixtures are synthetic and stay that way.** `tests/fixtures/audit-*.txt` use `EXAMPLE\alice`
and friends. Real audit output names every account in a domain with a weak, shared or absent
password; none of it belongs in this repository, in a fixture, in a doc example, or in a
commit message. `Get-PasswordAuditArchive` tests build their own zips at run time for the
same reason.

**Third-party tools are invoked, never vendored.** DSInternals, PingCastle, ADRecon and
PowerHunt are dependencies the user installs. `.gitignore` blocks their binaries.

## Architecture

The module is a text-to-objects pipeline over tools that only emit human-readable reports.
Four public functions form one chain:

```
Get-PasswordAuditArchive  -> report objects   (folder of dated archives)
ConvertFrom-PasswordQualityReport -> report objects   (a single report file or string[])
Compare-PasswordAudit     -> change objects   (two reports)
ConvertTo-AuditReport     -> string           (HTML or Markdown)
```

`ADToolkit.psm1` dot-sources `Private/` then `Public/` at import and exports `Public/`
basenames. Private functions are the real workers; public functions handle parameter sets,
paths and pipelines.

### Three object shapes

Types are set via `PSTypeName` on `[pscustomobject]`, and parameters bind on them with
`[PSTypeName('...')]` — that is how `Compare-PasswordAudit -ReferenceReport` rejects
arbitrary input.

- `ADToolkit.PasswordQualityReport` — `Path`, `Timestamp`, `Sections` (ordered key→count),
  `Findings`, `FindingCount`
- `ADToolkit.PasswordQualityFinding` — `Section`, `Severity`, `Identity`, `Domain`,
  `SamAccountName`, `IsComputerAccount`, `GroupId`, `GroupSignature`, `Timestamp`
- `ADToolkit.PasswordAuditChange` — `Status`, `Section`, `Severity`, identity fields,
  `GroupChanged`, `ReferenceDate`, `DifferenceDate`

### Section headings are mapped in exactly one place

`Private/Get-PasswordQualitySectionMap.ps1` maps each full English heading emitted by
DSInternals to a stable key, a severity and a layout (`Flat` or `Grouped`). Severity is this
module's editorial judgement, not something DSInternals reports. A heading not in the map
produces a warning and its entries are dropped rather than misfiled under the previous
heading — that warning is the designed early signal that a DSInternals release changed its
wording. Adding support for a new heading means adding one line here.

### Two invariants the tests exist to protect

**An empty section is not a missing section.** A heading with no entries means the check ran
and found nothing; an absent heading means it did not run. `Sections` records empty sections
deliberately, and `Compare-PasswordAudit` warns about a section present in only one report
instead of comparing it. Collapsing this distinction makes the comparison report every
account in a dropped section as `Resolved` — it fails in the reassuring direction, which is
the worst way for a security tool to fail.

**Duplicate-password group numbers are meaningless across runs.** The same accounts can be
`Group 1` one week and `Group 17` the next. `ConvertTo-PasswordQualityReportObject` computes
`GroupSignature` (sorted membership, joined) after parsing, and comparison keys off that.
`GroupChanged` on a persisting account means it still shares a password but with a different
set of accounts.

### Sensitive data never touches disk

`Private/Read-ZipEntryLine.ps1` streams a zip entry into memory. `Expand-Archive` to a temp
directory would be shorter but leaves a plaintext list of the domain's weak passwords in the
caller's profile, permanently if the script fails before cleanup. Any future archive handling
must preserve this.

Relatedly, `Get-PasswordAuditArchive` takes the report date from the file name
(`-NamePattern` capture group `date` + `-DateFormat`), falling back to `LastWriteTime` only
with a warning: a copied or restored archive keeps its contents but not its timestamp.

### Rendering does not send

`ConvertTo-AuditReport` returns a string and knows nothing about mail relays or recipients.
Its HTML carries styling inline per element because Outlook on the web and Gmail strip
`<style>` blocks. All interpolated values go through `[System.Net.WebUtility]::HtmlEncode`;
account names are untrusted input.
