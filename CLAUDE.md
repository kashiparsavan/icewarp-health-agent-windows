# CLAUDE.md — IceWarp Health Agent (Windows)

## 1. Project Overview

**IceWarp Health Agent for Windows** is an independent PowerShell-based health-check and reporting tool for IceWarp mail servers running on Windows. It runs directly on the mail server, collects data from `tool.exe`, Windows WMI/CIM commands, and DNS queries, evaluates results against the IceWarp Checklist (v1.14), and produces structured JSON output for monitoring systems.

### Key Characteristics
- **Platform:** Windows Server 2012 R2 or later, Windows 10/11
- **Version:** 0.1.5 (Windows-specific, independent of Linux)
- **Runtime:** Windows PowerShell 5.1 — no Bash, no Linux dependencies
- **Schema:** 432-key flat dotted namespace in `output/health.json` (parity with Linux)
- **Outputs:**
  - `output/health.json` — type-aware JSON for monitoring systems
  - PDF reports — technical and executive (native PDF generation via ReportTechnical.ps1, ReportManagement.ps1)

### Collector Coverage
- **27 collector scripts** across 2 categories (`General/`, `Icewarp/`)
- Collectors run alphabetically by path; order matters for dependencies
- All values stored in `$Context.Data` hashtable with flat dotted keys

### Collector List
| Collector | Purpose |
|---|---|
| `General/Version.ps1` | IceWarp version, OS details |
| `Icewarp/AdminAccess.ps1` | WebAdmin URL, port, changed_from_default flags |
| `Icewarp/Antispam.ps1` | Antispam rule update date, version, size |
| `Icewarp/Antivirus.ps1` | Sophos update date, version, size, source |
| `Icewarp/BackupArchive.ps1` | System/database backups, last-run timestamp |
| `Icewarp/Certificate.ps1` | TLS cert path, live SslStream expiry check |
| `Icewarp/CloudFeatures.ps1` | Cloud API auto-configure flag |
| `Icewarp/DatabaseType.ps1` | Accounts ODBS connection string, DB type, scope, host |
| `Icewarp/DirectoryCache.ps1` | Directory cache connection string, schedule |
| `Icewarp/DnsMailFlow.ps1` | SPF, DKIM, DMARC, PTR, DNS, STARTTLS live probe |
| `Icewarp/DomainsUsers.ps1` | Auto-discovered domain limits |
| `Icewarp/Environment.ps1` | IceWarp home, config, default paths |
| `Icewarp/Fulltext.ps1` | Full-text enabled flag, scanner queues |
| `Icewarp/Http.ps1` | Web server port, max connections |
| `Icewarp/License.ps1` | License status, type, trial expiration, seat counts |
| `Icewarp/Logging.ps1` | SQL log type, auth/maintenance/mailqueue log levels |
| `Icewarp/Migration.ps1` | Migration active/server/errors/started flags |
| `Icewarp/Monitor.ps1` | System Monitor enable flag, thresholds, report address |
| `Icewarp/MySQL.ps1` | MySQL service, version, listening port |
| `Icewarp/OsStorage.ps1` | OS update date, memory/CPU load, storage usage |
| `Icewarp/Queue.ps1` | Incoming queue enable/size, no-retry flag |
| `Icewarp/Security.ps1` | Password policy, login blocking, TLS, DIGEST-MD5, RBL |
| `Icewarp/ServiceStatus.ps1` | Service ports and startup mode |
| `Icewarp/SessionTimeout.ps1` | Session timeout minutes |
| `Icewarp/SmtpSettings.ps1` | SMTP ports, limits, TLS, message-size settings |
| `Icewarp/StoragePaths.ps1` | Mail/temp/logs/archive paths and source flag |
| `Icewarp/Watchdog.ps1` | Service watchdog flags, remote-server watchdog |

---

## 2. Architecture Flow

```
┌─────────────────────────────────────────────────────────────────────────────┐
│ agent.ps1 (Entry Point)                                                     │
│  ├─ 1. Load libraries: Common.ps1, Logging.ps1, Config.ps1,                 │
│  │                 IceWarpTool.ps1, Json.ps1, Health.ps1,                   │
│  │                 ReportTechnical.ps1, ReportManagement.ps1                │
│  ├─ 2. Load config: config\agent.local.psd1 (or agent.example.psd1)         │
│  ├─ 3. Initialize context: $Context.Data (ordered hashtable)                │
│  ├─ 4. Discover collectors\**\*.ps1 (alphabetical) → Invoke-AgentCollector  │
│  │     └─ Collectors return [ordered]@{} → merged into $Context.Data        │
│  ├─ 5. Invoke-HealthEvaluation -Data $Context.Data → health.* keys          │
│  ├─ 6. Write-AgentJson -Path $config.OutputJson -Data $Context.Data         │
│  └─ 7. Build-TechnicalReportPdf / Build-ManagementReportPdf (if -Report)    │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Data Flow
1. **Collection Phase:** 27 collectors gather data into `$Context.Data` (flat dotted keys: `os.cpu.load1`, `icewarp.backup.auto_enabled`, `storage.*`, etc.)
2. **Health Evaluation:** `lib/Health.ps1` reads `$Context.Data`, applies rules, writes `health.*` keys
3. **JSON Export:** `lib/Json.ps1` type-coerces and sorts all keys → `output/health.json`
4. **PDF Generation:** Native PDF writers (no external tools) produce technical and management reports

### Key Design Principles
- **Collector isolation:** Failures recorded but don't abort the run; each collector runs in isolated runspace
- **Health independence:** `Health.ps1` reads `$Context.Data` only; never calls `tool.exe`
- **Type-aware JSON:** Empty → `null`, numeric → unquoted, `true`/`false` → unquoted booleans
- **PowerShell 5.1 compatibility:** Avoid PowerShell 7-only syntax
- **CRLF line endings:** All `.ps1`, `.psm1`, `.psd1` files use CRLF (enforced by `.gitattributes`)

---

## 3. Strict Rules (ABSOLUTE — NEVER BREAK)

### 3.1 Line Endings
- **ALL `.ps1`, `.psm1`, `.psd1` files MUST have CRLF (Windows) line endings.** Git enforces this via `.gitattributes`.

### 3.2 PDF Renderer Sync
- If you change a threshold or logic in `lib/Health.ps1`, you **MUST** apply the exact same change in:
  - `lib/ReportTechnical.ps1` (technical report)
  - `lib/ReportManagement.ps1` (executive report)
- Never leave hardcoded values in PDF renderers that differ from health engine.

### 3.3 Health Status Discipline
- **NO arbitrary INFO statuses:** Missing/invalid settings → `WARN` or `CRITICAL`, never `INFO`
- **NO placeholders:** Never add fake values (e.g., `admin@example.com`) to silence health checks
- If a setting requires human input (Admin Email), health **MUST** remain `CRITICAL` until explicitly set

### 3.4 Strict Threshold Rules (Hardcoded in Health.ps1)

|Check|Condition|Result|Message|
|---|---|---|---|
|**Intrusion Prevention**|`security.intrusion.block_connections_per_minute.value` ≠ 50|`warn`|Expected 50|
|**Intrusion Prevention**|`security.intrusion.block_duration_minutes` ≠ 360|`warn`|Expected 360 minutes|
|**Intrusion Prevention**|Missing connections setting|`critical`|Setting not found|
|**Intrusion Prevention**|Missing duration setting|`critical`|Setting not found|
|**Admin Email**|`monitor.alert_email` empty/null/N/A|`critical`|Admin email is not set|
|**Admin Email**|Invalid email format|`warn`|Invalid format|
|**DIGEST-MD5**|`security.digest_md5.enabled` = `true`|`critical`|DIGEST-MD5 is ENABLED (weak, legacy)|
|**DIGEST-MD5**|`security.digest_md5.enabled` = `false`|`pass`|DIGEST-MD5 is disabled|
|**DIGEST-MD5**|Missing value|`critical`|Cannot verify status|
|**IMAP Service**|`service.imap.active` = `1` or `true`|`pass`|IMAP is running|
|**IMAP Service**|Disabled|`warn`|IMAP is disabled|
|**POP3 Service**|`service.pop3.active` = `1` or `true`|`pass`|POP3 is running|
|**POP3 Service**|Disabled|`warn`|POP3 is disabled|
|**Database Type**|`database.type` = `mysql`|`pass`|MySQL is active|
|**Database Type**|`database.type` = `sqlite`|`warn`|SQLite in use; MySQL recommended|
|**Database Type**|Unknown/empty|`warn`|Type could not be determined|

### 3.5 License Fallback (Evaluation Licenses)
If `C_License_TrialExpire` is empty:
1. **ALWAYS** fallback to parsing `license.xml`
2. Try multiple XML tags in order:
   - `TrialExpire`, `TrialExpiration`, `Expire`, `ExpirationDate`, `LicenseExpiration`
   - `TrialDaysRemaining`, `DaysRemaining` (calculate expiration from days remaining)
3. **NEVER** assume missing value means 'perpetual'

### 3.6 JSON Coercion Rules (lib/Json.ps1)
- **Empty string** → `null`
- **Numeric pattern** (`^-?[0-9]+(\.[0-9]+)?$`) → unquoted number
- **Boolean** (`true` or `false`, case-sensitive) → unquoted boolean
- **Everything else** → escaped string
- Keys sorted alphabetically (ordinal, case-sensitive) in output

### 3.7 DSN Redaction
- **NEVER** put a DSN password into `$Context.Data`. Wrap every DSN value in `Redact-DatabaseDsn` at collection time.
- `lib/Json.ps1` re-applies redaction to `*dsn*|*connection_string*` keys as a safety net.

### 3.8 Nine Executive Pillars (SUMMARY_KEYS)
The health summary roll-up uses exactly these 9 keys:
```powershell
backup, mail_flow, tls, access, threat, resources, os_update, monitoring, database
```
- `health.summary.total_checks` — count of non-skip pillars
- `health.summary.failed` — fail/critical count
- `health.summary.warnings` — warn count
- `health.summary.overall` — `pass`/`warn`/`fail`

### 3.9 Date Handling
- **Never pass an IceWarp date string to `[datetime]::Parse` without normalization.** Use `Normalize-ToIsoDate` from `lib/Common.ps1`
- Date keys in `$Context.Data` are ISO `YYYY-MM-DD`; keep the original string in a sibling `*_raw` key.
- `Get-DaysAgo` returns `999` for unparseable dates; callers must treat this as `skip`, never as `0` or `999` days old.

### 3.10 Windows-Specific Paths
- **IceWarp Home:** `C:\Program Files\IceWarp` (default, configurable in `agent.local.psd1`)
- **tool.exe:** `C:\Program Files\IceWarp\tool.exe`
- **Config directory:** `$IceWarpHome\config\` (for `license.xml`, etc.)
- Collectors **MUST** use configured paths from `$Context.Config.IceWarpHome`

---

## 4. Repository Structure

```
icewarp-health-agent-windows/
├── VERSION                     # Windows agent version (0.1.5)
├── CLAUDE.md                   # This file
├── README.md                   # User documentation
├── CHANGELOG.md                # Windows version history
├── .gitignore                  # Git ignore rules
├── .gitattributes              # Line ending enforcement (CRLF for .ps1)
├── tool.v14.3.0.13.windows.help # Windows API reference (APIConst.pas)
├── docs/
│   ├── deployment.md           # Task Scheduler, permissions, troubleshooting
│   ├── api-key-mapping.md      # API key mapping and corrections
│   ├── REVIEW.md               # Code review findings
│   └── api-windows-vs-linux-v14.3.0.13.md  # API comparison
├── windows/
│   ├── VERSION                 # Duplicate version (for deployment)
│   ├── agent.ps1               # Entry point (PowerShell 5.1)
│   ├── CHANGELOG.md            # Duplicate changelog
│   ├── README.md               # Duplicate README
│   ├── output/                 # Runtime artifacts (gitignored)
│   │   ├── health.json
│   │   ├── report.pdf
│   │   └── management_report.pdf
│   ├── logs/                   # Runtime logs (gitignored)
│   │   └── agent.log
│   ├── lib/
│   │   ├── Common.ps1          # Shared helpers, context, collector execution
│   │   ├── Config.ps1          # PSD1 configuration loader
│   │   ├── Logging.ps1         # Timestamped logging with rotation
│   │   ├── IceWarpTool.ps1     # tool.exe wrapper with timeouts
│   │   ├── Json.ps1            # Type-aware JSON builder
│   │   ├── Health.ps1          # Health evaluation engine (1197 lines)
│   │   ├── ReportTechnical.ps1 # Technical PDF report (native)
│   │   ├── ReportManagement.ps1# Executive PDF report (native)
│   │   └── Report.ps1          # Shared PDF helpers
│   ├── config/
│   │   ├── agent.example.psd1  # Tracked example configuration
│   │   ├── agent.local.psd1    # Site-specific (gitignored)
│   │   └── checklist.conf.pdf  # Checklist source of truth
│   ├── collectors/
│   │   ├── General/
│   │   │   └── Version.ps1
│   │   └── Icewarp/
│   │       ├── AdminAccess.ps1
│   │       ├── Antispam.ps1
│   │       ├── Antivirus.ps1
│   │       ├── BackupArchive.ps1
│   │       ├── Certificate.ps1
│   │       ├── CloudFeatures.ps1
│   │       ├── DatabaseType.ps1
│   │       ├── DirectoryCache.ps1
│   │       ├── DnsMailFlow.ps1
│   │       ├── DomainsUsers.ps1
│   │       ├── Environment.ps1
│   │       ├── Fulltext.ps1
│   │       ├── Http.ps1
│   │       ├── License.ps1
│   │       ├── Logging.ps1
│   │       ├── Migration.ps1
│   │       ├── Monitor.ps1
│   │       ├── MySQL.ps1
│   │       ├── OsStorage.ps1
│   │       ├── Queue.ps1
│   │       ├── Security.ps1
│   │       ├── ServiceStatus.ps1
│   │       ├── SessionTimeout.ps1
│   │       ├── SmtpSettings.ps1
│   │       ├── StoragePaths.ps1
│   │       └── Watchdog.ps1
│   └── tests/
│       ├── Agent.Smoke.Tests.ps1   # Pester contract tests
│       ├── Run-Tests.ps1           # Version-aware test runner
│       └── fixtures/               # Test fixtures
└── agents_bridge.md                # Multi-agent communication protocol
```

---

## 5. Commands Reference

### Normal Operation
```powershell
# Run full agent
.\windows\agent.ps1

# Run with console summary
.\windows\agent.ps1 -Report

# List all collectors
.\windows\agent.ps1 -List

# Run specific collectors (case-insensitive substring match)
.\windows\agent.ps1 -Only General,Backup

# Override identity
.\windows\agent.ps1 -Report -Company "Contoso" -Technician "Alex"

# Use alternate config
.\windows\agent.ps1 -ConfigPath "C:\path\to\custom.psd1"
```

### Development/Diagnostics
```powershell
# Run Pester tests
.\windows\tests\Run-Tests.ps1

# Syntax check all PowerShell files
Get-ChildItem -Recurse -Include *.ps1,*.psm1 | ForEach-Object {
    $null = [System.Management.Automation.PSParser]::Tokenize((Get-Content $_.FullName -Raw), [ref]$null)
}

# Check line endings (should be CRLF for .ps1)
Get-ChildItem -Recurse -Include *.ps1 | ForEach-Object {
    $bytes = [System.IO.File]::ReadAllBytes($_.FullName)
    if ($bytes -notcontains 0x0D) { Write-Warning "$($_.FullName): missing CR" }
}
```

---

## 6. Health Evaluation Summary

### Result Vocabulary
- `pass` — Check passed
- `warn` — Warning (needs attention but not critical)
- `fail` — Failure (requires immediate action)
- `critical` — Critical failure (production-impacting)
- `skip` — Check skipped (missing prerequisites)
- `info` — Informational (explicitly allowed only for optional features)
- `ok` — Collector succeeded (not a health result)

### Key Thresholds (from lib/Health.ps1)

|Area|Threshold|Result|
|---|---|---|
|**Memory**|Used > 90%|`critical`|
|**Memory**|Used > 40%|`warn`|
|**Disk**|Free MB < `MonitorDiskAlertMb` (default 5120)|`fail`|
|**CPU**|Load > threshold% (default 50%)|`warn`|
|**Password**|Policy inactive|`fail`|
|**Password**|Min length < 8|`warn`|
|**Login Blocking**|Threshold > 10|`warn`|
|**Backup**|Auto disabled|`critical`|
|**Backup**|DB (Accounts) disabled|`critical`|
|**Backup**|Last run > 7 days|`critical`|
|**Watchdog**|Master/service disabled|`critical`|
|**OS Update**|> 30 days|`critical`|
|**OS Update**|8–30 days|`warn`|
|**Directory Cache**|Schedule missing|`critical`|

---

## 7. Configuration Files

### config/agent.example.psd1
```powershell
@{
    # IceWarp installation and command-line tool.
    IceWarpHome             = 'C:\Program Files\IceWarp'
    ToolPath                = 'C:\Program Files\IceWarp\tool.exe'
    ToolTimeoutSeconds      = 10
    CollectorTimeoutSeconds = 120
    NetworkTimeoutSeconds   = 10

    # Agent output. Both are relative to windows/ by default.
    OutputJson         = 'output\health.json'
    LogDirectory       = 'logs'

    # Monitor health configuration (used by the Health Evaluation Engine).
    MonitorDiskAlertMb               = 5120
    MonitorCpuThresholdPercent       = 50
    MonitorMemoryAlertKb             = 1048576
    MonitorWebThreadpoolAlertSeconds = 300

    # Report identity. The technician can also be overridden with -Technician.
    CompanyName        = ''
    Technician         = 'Parsavan'
    ChecklistVersion   = '1.14'

    # Mail hostname used for SPF/DKIM/DMARC lookups and the live SMTP
    # STARTTLS test. MailDomain is the fallback when MailHostname is empty.
    MailHostname       = ''
    MailDomain         = ''
}
```

### config/agent.local.psd1 (gitignored)
Copy `agent.example.psd1` to `agent.local.psd1` and edit site-specific values:
```powershell
Copy-Item .\windows\config\agent.example.psd1 .\windows\config\agent.local.psd1
```

---

## 8. Collector Contract

Collectors follow this contract:

```powershell
param(
    [Parameter(Mandatory = $true)]
    [hashtable]$Context
)

# Access configuration
$toolPath = $Context.Config.ToolPath

# Call tool.exe with timeout
$value = Get-IceWarpSetting -Name 'C_Version' -Context $Context

# Return ordered dictionary with namespaced keys
return [ordered]@{
    'icewarp.version' = $value
    'general.os.name' = 'Windows'
}
```

### Rules
- Return exactly one `IDictionary` (preferably `[ordered]@{}`)
- Do not write strings or other objects to the output pipeline
- Use namespaced dotted keys, matching the Linux data contract where possible
- Use `Get-IceWarpSetting` or `Invoke-IceWarpTool` for `tool.exe` calls; both apply configured timeout
- The agent isolates collector failures, records `error` or `empty` status, and continues
- `$Context` exposes: `Config`, `Data`, `Root`, `Version`

---

## 9. API Reference

The authoritative Windows-side API reference is `tool.v14.3.0.13.windows.help`, which is the IceWarp 14.3.0.13 `APIConst.pas` from the Windows server.

| File | Platform | SHA-256 |
|---|---|---|
| `tool.v14.3.0.13.help` | Linux | `51EE702640A3B08CC0AF77805E3D54E143709E91DCEEF190BF880DEF11287E5D` |
| `tool.v14.3.0.13.windows.help` | Windows | `5102C041514887DEC81A428B05EB9D6D930EA38B3F423B350EE790EDA31D9D36` |

### Key Differences
- All Linux keys are present on Windows (case-insensitive match)
- Windows adds 4 keys: `C_API_DomainList_DefaultLimit`, `U_MailingLists`, `U_MailingListsList`, `U_SlaveDomain`
- `U_GROUPS` / `U_GROUPSLIST` → `U_Groups` / `U_GroupsList` on Windows
- `U_MasterDomain` is `String [R]` (read-only) on Windows
- Use the Windows reference when writing Windows collectors

See `docs/api-windows-vs-linux-v14.3.0.13.md` for full comparison.

---

## 10. Testing

```powershell
# Run full Pester suite
.\windows\tests\Run-Tests.ps1

# Expected output: 28/28 tests passed
# Full agent run: exit 0, 433 keys, 0 schema violations
```

### Test Coverage
- Version loading and PSD1 configuration
- Tool-output parsing and JSON type coercion
- Collector success/failure isolation
- Collector discovery and `-Only` filtering
- Health checks, roll-ups, and summary
- Monitor collector
- Full-run health block

---

## 11. Known Issues / Limitations

- **Automatic updates:** Not implemented for Windows (manual `git pull` required)
- **PDF reports:** Implemented but may need threshold sync verification with Linux
- **Collector count:** 27 Windows collectors vs. 81 Linux collectors (coverage gap)
- **Dynamic domain keys:** 3 `domain.designhost.ir.*` keys emitted as null/N/A when no domain discovered
- **No live validation:** Most testing done with Pester mocks; live Windows IceWarp server validation recommended

---

## 12. Change Ledger

For every intentional change, update:
1. `CHANGELOG.md` — Windows version history
2. `windows/CHANGELOG.md` — Duplicate for deployment
3. `README.md` — User-facing documentation
4. `docs/update-log.md` — Detailed change description (if applicable)
5. This `CLAUDE.md` — if rules, thresholds, or architecture changed

### Version History
| Version | Date | Notes |
|---|---|---|
| 0.1.5 | 2026-10-28 | Fixed Watchdog summaries, CPU double-count, Antivirus fallback, DNS mail flow domain, path source |
| 0.1.4 | 2026-10-28 | Dynamic domain keys, 433 keys total |
| 0.1.3 | 2026-10-28 | 17 new collectors, 430 of 432 keys |
| 0.1.2 | 2026-10-28 | Complete health engine, Monitor collector |
| 0.1.1 | 2026-10-28 | JSON coercion fix, non-schema keys removed |
| 0.1.0 | 2026-10-26 | Initial scaffold |

---

## 13. Multi-Agent Communication Protocol

### Roles
- **OMP (Supervisor):** Task assignment, scope definition, approval gates, final verification
- **OpenCode (Worker):** Implementation, testing, documentation updates

### Workflow
1. **Task Receipt:** OMP provides clear scope with acceptance criteria
2. **Research Phase:** OpenCode reads relevant files, identifies affected code paths
3. **Implementation:** OpenCode makes changes following repository conventions
4. **Verification:** OpenCode runs smoke tests, validates outputs
5. **Documentation:** OpenCode updates CLAUDE.md, CHANGELOG.md, docs/ as needed
6. **Completion:** OpenCode reports evidence of success or blockers

### Communication Protocol
- Use `agents_bridge.md` patterns for multi-agent coordination
- Cross-file changes: update all callers, tests, docs in single commit
- Breaking changes (key renames): require explicit OMP approval

### Task Lifecycle (from agents_bridge.md)
1. **Task Assignment (OMP):** Unique ID (e.g., `TASK-001`), status `[STATUS: ASSIGNED]`
2. **Worker Acknowledgement (OpenCode):** Update to `[STATUS: IN_PROGRESS]`
3. **Real-time Logging (OpenCode):** Append progress updates under `### Execution Logs`
4. **Completion (OpenCode):** Status `[STATUS: DONE]`, final report under `### Final Result`
5. **Review (OMP):** Read logs and result, update to `[STATUS: VERIFIED]`
6. **Error Handling (OpenCode):** Fatal errors → `[STATUS: BLOCKED]` with exact error under `### Blocking Issue`
7. **Immutable History:** Never delete previous tasks/results; always append

---

## 14. Independence from Linux

- **No code sharing:** Windows files are additive under `windows/`; Linux paths at repository root are unchanged
- **Independent versioning:** `windows/VERSION` is independent of root Linux `VERSION`
- **Independent tags:** Use `windows-v*` tags; Linux uses `v*`
- **No cross-calls:** Windows agent does not call `agent.sh` or source Linux `lib/`
- **Separate configuration:** PSD1-only configuration; do not copy Linux `config/*.conf` files
- **API reference:** Use `tool.v14.3.0.13.windows.help` for Windows, not Linux reference

---

**Last Updated:** 2026-10-31  
**Agent Version:** 0.1.5  
**Checklist Version:** 1.14  
**Platform:** Windows PowerShell 5.1
