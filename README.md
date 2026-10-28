# IceWarp Health Agent for Windows

This repository contains the independent Windows implementation of the
IceWarp Health Agent. It is written for Windows PowerShell 5.1 and does not
use Bash, agent.sh, or any file from the Linux project.

The Linux agent lives in a separate repository:
https://github.com/kashiparsavan/icewarp-health-agent. The two projects are
independent. This tree does not call the Linux entry point and does not
source the Linux lib/ directory.

| Item | Value |
|---|---|
| Platform | Windows |
| Entry point | windows\agent.ps1 |
| Version | 0.1.0 |
| Status | Nine collectors; 248 of 411 schema keys implemented |

Configuration, logging, the IceWarp tool.exe wrapper, schema-compatible flat
JSON output, DNS/SMTP/security/storage/license/backup collectors, and Pester
contract tests are in place. 248 of the 411 Linux health.json keys are
implemented; the remaining 163 are tracked in docs/api-key-mapping.md. PDF
reports, health rules, the full 113-item checklist and automatic updates are
not ported yet.

## Requirements

- Windows Server 2012 R2 or later, or Windows 10/11.
- Windows PowerShell 5.1 (the default on supported Windows versions).
- An IceWarp installation with tool.exe for live data collection.
- Pester 3.4 or later for the test suite. Pester 3.4 is bundled with many
  Windows Server installations; Pester 5 is also supported by the test runner.

PowerShell 7 can run the scaffold, but the supported target is Windows
PowerShell 5.1. Avoid PowerShell 7-only syntax in this directory.

## Quick Start

Run these commands from the repository root in a PowerShell console:

```powershell
Copy-Item .\windows\config\agent.example.psd1 .\windows\config\agent.local.psd1
notepad .\windows\config\agent.local.psd1

powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\windows\agent.ps1 -Report
```

If IceWarp is not installed, the sample collector reports
collector.general.version = tool_unavailable, but the agent still writes
valid JSON. Set ToolPath and IceWarpHome in
windows\config\agent.local.psd1 for the real server.

## Command Line

| Option | Description |
|---|---|
| -Report | Run collectors and print a console summary |
| -List | List available collectors and exit |
| -Only <filter> | Run only collectors whose relative path contains the filter (comma-separated, case-insensitive) |
| -Company <name> | Override CompanyName from the configuration |
| -Technician <name> | Override Technician from the configuration |
| -ConfigPath <path> | Use an alternate PSD1 configuration file |
| -Help | Show usage |

Examples:

```powershell
.\windows\agent.ps1
.\windows\agent.ps1 -Report
.\windows\agent.ps1 -List
.\windows\agent.ps1 -Only General -Report
.\windows\agent.ps1 -Report -Company "Contoso" -Technician "Alex"
```

## Configuration

The agent loads windows\config\agent.local.psd1 when it exists. Otherwise it
falls back to the tracked windows\config\agent.example.psd1 and logs a
warning. Create the local file for each server:

```powershell
Copy-Item .\windows\config\agent.example.psd1 .\windows\config\agent.local.psd1
```

agent.local.psd1 is ignored by Git. The file is read with
Import-PowerShellDataFile, so it is data-only and cannot execute code.
Relative paths are resolved against the windows/ directory.

| Key | Default | Purpose |
|---|---|---|
| IceWarpHome | C:\Program Files\IceWarp | IceWarp installation directory |
| ToolPath | C:\Program Files\IceWarp\tool.exe | IceWarp command-line tool |
| ToolTimeoutSeconds | 10 | Per-call timeout for tool.exe |
| OutputJson | output\health.json | Flat JSON output path |
| LogDirectory | logs | Runtime log directory |
| CompanyName | empty | Company name for reports |
| Technician | Parsavan | Technician name for reports |
| ChecklistVersion | 1.14 | Report metadata label |
| MailHostname | empty | Reserved for future DNS collectors |
| MailDomain | empty | Reserved for future DNS/DMARC collectors |

## Output

The current scaffold writes one output file and one runtime log:

| Path | Description |
|---|---|
| windows\output\health.json | Flat, dotted-key JSON; scalar types are preserved |
| windows\logs\agent.log | Timestamped INFO/WARN/ERROR/DEBUG log, rotated to agent.log.1 at 5 MB |

Example JSON:

```json
{
    "agent.version": "0.1.0",
    "general.technician": "Parsavan",
    "icewarp.version": "14.3.0.12",
    "icewarp.tool.available": true,
    "collector.general.version": "ok"
}
```

The JSON is UTF-8 without a BOM. Empty string values are emitted as null,
matching the Linux JSON contract; booleans and numbers remain native JSON
types. PDF generation is not implemented on Windows yet; the agent is focused
on a stable data path first.

## API Reference

The authoritative Windows-side API reference is tool.v14.3.0.13.windows.help,
which is the IceWarp 14.3.0.13 APIConst.pas from the Windows server. It is not
the same file as the Linux reference.

| File | Platform | SHA-256 |
|---|---|---|
| tool.v14.3.0.13.help | Linux | 51EE702640A3B08CC0AF77805E3D54E143709E91DCEEF190BF880DEF11287E5D |
| tool.v14.3.0.13.windows.help | Windows | 5102C041514887DEC81A428B05EB9D6D930EA38B3F423B350EE790EDA31D9D36 |

Key-level comparison:

- All Linux keys are present on Windows.
- Windows adds 4 keys: C_API_DomainList_DefaultLimit, U_MailingLists,
  U_MailingListsList, and U_SlaveDomain.
- U_GROUPS / U_GROUPSLIST are spelled U_Groups / U_GroupsList on Windows;
  the IDs and descriptions are the same.
- U_MasterDomain is String [R] on Windows and String on Linux. Read only
  on Windows.
- C_OS is 0 for Windows and 1 for Linux on both platforms.
- C_Accounts_Policies_Auth_Schemes is present; the incorrect
  C_Mail_Security_AuthScheme is absent.

Use the Windows reference when writing or reviewing Windows collectors. Keep
both files; do not treat the Linux reference as authoritative for Windows.
See docs/api-windows-vs-linux-v14.3.0.13.md for the full comparison.

Important: the API reference defines key names and IDs. It is not a
substitute for validating tool.exe output formatting, value semantics,
service names, and Windows-only behavior on the lab server. A Windows
tool.exe search/list export is still needed to confirm the property listing.

## Collector Contract

Collectors live under windows\collectors\<Area>\<Name>.ps1 and follow this
contract:

```powershell
param(
    [Parameter(Mandatory = $true)]
    [hashtable]$Context
)

$value = Get-IceWarpSetting -Name 'C_Version' -Context $Context

return [ordered]@{
    'icewarp.version' = $value
}
```

Rules:

- Return exactly one IDictionary (preferably an ordered dictionary).
- Do not write strings or other objects to the output pipeline.
- Use namespaced dotted keys, matching the Linux data contract where possible.
- Use Get-IceWarpSetting or Invoke-IceWarpTool for tool.exe calls; both
  apply the configured timeout.
- The agent isolates collector failures, records error or empty status, and
  continues with the remaining collectors.
- Context exposes Config, Data, Root, and Version.

Nine collectors ship in 0.1.0 (see `windows/README.md` collectors table):
General/Version plus Icewarp/BackupArchive, DnsMailFlow, DomainsUsers,
License, OsStorage, Security, SmtpSettings, and ServiceStatus.

## Tests

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\windows\tests\Run-Tests.ps1
```

The runner detects Pester 3.x or 5.x. The suite checks version loading, PSD1
configuration, tool-output parsing, JSON types, collector success/failure
handling, collector discovery, and collector filtering. The tests do not
require a live IceWarp server.

## Documentation

| File | Purpose |
|---|---|
| windows\README.md | Windows scaffold, configuration, collector contract, and tests |
| windows\docs\deployment.md | Windows Task Scheduler, permissions, troubleshooting, and update guidance |
| docs\api-windows-vs-linux-v14.3.0.13.md | Windows-vs-Linux API key, ID, type, description, and read-only comparison |
| docs\api-update-v14.3.0.12-to-14.3.0.13.md | Linux 14.3.0.12-to-14.3.0.13 API reference comparison |
| CHANGELOG.md | Windows version history |
| VERSION | Current Windows version |

## Updates

Automatic updates are not implemented for Windows in 0.1.0. For a Git
checkout, update manually during a maintenance window:

```powershell
git pull --ff-only origin main
```

Windows releases use independent windows-v* tags.
