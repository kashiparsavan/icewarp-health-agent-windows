# 02 - Architecture and Flow

This document describes how the agent **actually** runs at commit `2e6694b`. Where the code
differs from `CLAUDE.md`, the difference is called out.

---

## 1. End-to-end runtime flow

```
agent.ps1
 │
 ├─ 1. Dot-source libraries (agent.ps1:48-56)
 │      Common, Logging, Config, IceWarpTool, Json, Health,
 │      ReportTechnical, ReportManagement          (Report.ps1 is NOT loaded - dead file)
 │
 ├─ 2. Get-AgentConfig (Config.ps1)
 │      -ConfigPath  >  config\agent.local.psd1  >  config\agent.example.psd1
 │      Merge with built-in defaults, reject unknown keys (warn), validate timeouts,
 │      resolve paths relative to windows\, normalize MailHostname/MailDomain
 │
 ├─ 3. Initialize-AgentLogging (Logging.ps1)  -> logs\agent.log, rotate at 5 MB (.1)
 │
 ├─ 4. Discover collectors: collectors\**\*.ps1 sorted by FullName; -Only filter
 │      -List prints names and exits
 │
 ├─ 5. Enter-AgentLock  ->  <ProjectRoot>\.agent.lock  (PID + timestamp; stale-lock recovery)
 │
 ├─ 6. Initialize-AgentContext -> $context.Data = agent.version/hostname/time,
 │                                general.technician/company
 │
 ├─ 7. foreach collector: Invoke-AgentCollector  (Common.ps1:776)
 │      └─ Invoke-AgentCollectorIsolated (Common.ps1:708)
 │            new [PowerShell] runspace
 │            re-dot-source Common, Logging, Config, IceWarpTool, Json
 │            NEW context (Initialize-AgentContext)  <-- Data has only agent.* keys
 │            & collector.ps1 -Context $collectorContext
 │            wait CollectorTimeoutSeconds (default 120 s) -> timeout / error / empty / ok
 │      └─ merge returned IDictionary into the parent $context.Data
 │         (duplicate keys -> WARN log, last writer wins)
 │
 ├─ 8. Invoke-HealthEvaluation -Data $context.Data   (Health.ps1:1178)
 │      core checks -> watchdog -> monitor -> os_update -> directory cache ->
 │      session timeout -> IMAP/POP3 -> database -> mail flow -> roll-ups + summary
 │
 ├─ 9. Write-AgentJson (Json.ps1) -> output\health.json  (temp file + atomic replace)
 │
 ├─ 10. if -Report:
 │       Write-AgentReport (console dump of every key)
 │       Build-TechnicalReportPdf   -> output\report.pdf
 │       Build-ManagementReportPdf  -> output\management_report.pdf
 │
 └─ 11. Exit-AgentLock; exit 0 (any exception -> log ERROR, exit 1)
```

### Exit-code semantics
- `0`: the run finished. Collector failures and `health.summary.overall = fail` do **not**
  change the exit code.
- `1`: any terminating exception, including a PDF rendering failure that happens **after**
  `health.json` was written.

## 2. Collector execution model

### 2.1 Isolation
`CollectorTimeoutSeconds` is validated as a positive integer (`Config.ps1:66-72`), so
**every collector always runs in isolated mode**. The non-isolated branch in
`Invoke-AgentCollector` (`& $Path -Context $Context`) is only reached from tests.

Consequences:

| Effect | Detail |
|---|---|
| Fault containment | Good: a hang or crash in one collector cannot take down the run. |
| No shared state | Each runspace builds a **fresh** context. Collectors cannot read keys that other collectors produced. |
| Contradiction with `CLAUDE.md` | `CLAUDE.md` section 1 says *"Collectors run alphabetically ... order matters for dependencies"*. With isolation, order has no effect except for which duplicate key wins the merge. |
| Real breakage | `MySQL.ps1` reads `$Context.Data['database.type']` and `database.scope`. Both are always empty, so `mysql.applicable` is always `false`. |
| Workaround in use | `Watchdog.ps1` re-queries CIM itself rather than reading `os.*` / `storage.*` keys, which duplicates `OsStorage.ps1`. |
| Strict error handling | Any record in the runspace `Streams.Error` turns the whole collector into `error` (`Common.ps1:752-755`), even if it returned valid data. |

### 2.2 Collector contract
```powershell
param([Parameter(Mandatory=$true)][hashtable]$Context)
$data = [ordered]@{}
$data['namespace.key'] = (Get-IceWarpSetting -Name 'C_Setting' -Context $Context)
return $data
```
- `$Context` provides `Config`, `Data` (empty in isolation), `Root`, `ProjectRoot`, `Version`.
- Settings are read with `Get-IceWarpSetting` (`display system <name>`) or
  `Get-IceWarpDomainSetting` (`display domain <d> <name>`). `Invoke-IceWarpTool` enforces
  `ToolTimeoutSeconds`. When `tool.exe` is missing, these functions return `''` rather than
  throwing.
- Bool settings that the schema types as numbers are normalized with
  `ConvertTo-AgentNumericFlag` (`true`→`1`, `false`→`0`).

### 2.3 Collector inventory (keys written per file)

| Collector | Main namespaces | External dependencies |
|---|---|---|
| General/Version | `general.*`, `icewarp.version/tool/installed` | tool.exe, CIM |
| AdminAccess | `admin.*` | tool.exe |
| Antispam | `icewarp.antispam.*` | tool.exe |
| Antivirus | `icewarp.antivirus.*` | tool.exe, Sophos `update.json` on disk |
| BackupArchive | `backup.*`, `archive.*`, `icewarp.backup.*` | tool.exe, filesystem |
| Certificate | `icewarp.ssl.*` | TCP 443 + SslStream, cert file |
| CloudFeatures | `icewarp.cloud_api.*` | tool.exe |
| DatabaseType | `database.*` | tool.exe |
| DirectoryCache | `directory_cache.*` | tool.exe |
| DnsMailFlow | `dns.*`, `icewarp.dkim.active_flag` | DNS, HTTPS (ipify/ident.me), tool.exe |
| DomainsUsers | `domain.*` (dynamic) | tool.exe |
| Environment | `icewarp.home/config/*.default`, `icewarp.path.source` | config only |
| Fulltext | `fulltext.*` | tool.exe |
| Http | `http.*` | tool.exe, `webserver.dat` |
| License | `icewarp.license.*` | tool.exe, filesystem, registry |
| Logging | `logging.*` | tool.exe |
| Migration | `icewarp.migration.*` | tool.exe |
| Monitor | `monitor.*` | tool.exe (+ domain admin email fallback) |
| MySQL | `mysql.*` | services, `mysqld --version`, Get-NetTCPConnection |
| OsStorage | `os.*`, `system.swap.*`, `storage.*` | CIM, Get-PSDrive, w32tm |
| Queue | `queue.*` | tool.exe |
| Security | `security.*`, `antispam.*` | tool.exe, firewall cmdlets, DNS, HTTPS |
| ServiceStatus | `service.imap/pop3.active` | tool.exe |
| SessionTimeout | `icewarp.session_timeout_minutes` | tool.exe |
| SmtpSettings | `smtp.*`, `c_mail_smtp_other_bouncebackmode` | tool.exe, TCP 25 STARTTLS |
| StoragePaths | `icewarp.path.*` | tool.exe |
| Watchdog | `watchdog.*` | tool.exe, CIM |

## 3. Health engine

### 3.1 Structure (`windows/lib/Health.ps1`)
- State: `$script:HealthResults` and `$script:HealthMessages`. They mirror the bash
  `HEALTH` / `HEALTH_MSG` tables and are reset on every evaluation.
- `Set-HealthResult` writes `health.<name>.result` and, when non-empty,
  `health.<name>.message` into `$Data`.
- Helpers: `Get-HealthValue`, `Test-HealthMissing` (empty/`null`/`N/A`), `Test-HealthFlag`
  (`1`/`true`), `Get-DaysAgo` (returns 999 when a date cannot be parsed), `Get-HealthWorst`
  (critical maps to fail).

### 3.2 Rule groups and roll-ups

| Check function | Health keys written | Pillar |
|---|---|---|
| Memory | `memory` | resources |
| Disk | `disk.<label>`, `disk.overall` | resources |
| CPU | `cpu` | resources |
| Backup | `backup.auto`, `backup.db`, `backup.db.{accounts,as,gw,cache}`, `backup.last_time` | backup |
| Security | `password_policy`, `login_blocking`, `tls_delivery`, `digest_md5` | access / tls |
| Intrusion | `intrusion.block_connections`, `intrusion.block_duration` | (none) |
| Admin email | `admin_email` | access |
| Watchdog | `watchdog.{control,smtp,pop3,im,gw,interval}` | monitoring (control + interval only) |
| Monitor | `monitor.enabled` | monitoring |
| OS update | `os_update` | os_update |
| Directory cache | `directory_cache` | (none) |
| Session timeout | `session_timeout` | access |
| IMAP/POP3 | `service.imap`, `service.pop3` | (none) |
| Database | `database` | database |
| Mail flow | `mail_flow` | mail_flow |
| Roll-ups | `backup`, `tls`, `access`, `threat`, `resources`, `monitoring` | - |

**Summary** (`Health.ps1:1144-1175`): exactly the nine `SUMMARY_KEYS` from `CLAUDE.md` 3.8.
`total_checks` counts pillars that are not `skip`, `failed` counts `fail`/`critical`,
`warnings` counts `warn`, and `overall` is `fail` > `warn` > `pass`.

Several checks are not part of any pillar: intrusion, directory cache, IMAP/POP3, and the
SMTP/POP3/IM/GW watchdogs. Their results appear in the JSON and the PDFs but never affect
`health.summary.overall`. This may be intended Linux parity; it is worth confirming.

## 4. JSON output contract (`windows/lib/Json.ps1`)
- Keys are sorted with `StringComparer.Ordinal`, matching Linux `sort` under the C locale.
- `''` → `null`; `^-?[0-9]+(\.[0-9]+)?$` → bare number (text preserved, so `0.40` stays
  `0.40`); exact `true`/`false` → boolean; everything else becomes an escaped string with
  `\r` removed.
- Native `[bool]` and numeric types are emitted natively. NaN and Infinity fall back to a
  quoted string.
- Writes are atomic: `health.json.tmp.<PID>` followed by `File.Replace`, with `Move-Item`
  as the fallback.
- DSN redaction happens at collection time through `Redact-DatabaseDsn`. **Note:**
  `CLAUDE.md` 3.7 says `Json.ps1` re-applies redaction to `*dsn*` and `*connection_string*`
  keys as a safety net. **That safety net is not implemented in `Json.ps1`.**

## 5. PDF rendering pipeline

```
Build-TechnicalReportPdf(Data)
  Build-TechnicalReport   header, info rows, overall banner, legend, 9-pillar summary
  Render-Checklist        reads config\checklist.conf.pdf (113 "~" rows: section~label~kind~keys~note)
                          special-cases ~19 labels, then a generic switch on kind
                          (B,F,R,L,Z,M,G,P,W,D,H,T,V); captures rows into $script:CHECKLIST_CAPTURED
  Build-TechnicalAppendix every key grouped by prefix (status INFO)
  Pdf-WriteFile           hand-built PDF 1.4 (Helvetica Type1, xref, ASCII only)

Build-ManagementReportPdf(Data)
  reuses $script:CHECKLIST_CAPTURED (or re-runs Render-Checklist)
  ConvertTo-ManagementChecklist -> sections/items with pass/warn/fail/info/na
  Initialize-ManagementCounts   -> score = pass/(pass+warn+fail)
  cover letter, executive overview, one page per section, recommended actions
  Mr-WriteFile
```

Coupling to note:
- `ReportManagement.ps1` depends on functions and state defined in `ReportTechnical.ps1`
  (`Pdf-Trunc`, `Render-Checklist`, `$script:CHECKLIST_CAPTURED`).
- The executive score and overall status are derived from **checklist row badges**, not from
  `health.summary.*`. The two reports can therefore show a different overall status from
  `health.json`.
- The checklist "source of truth" is a plain-text file with a `.pdf` extension.

## 6. Configuration surface

| Key | Default | Used by |
|---|---|---|
| IceWarpHome / ToolPath | `C:\Program Files\IceWarp[\tool.exe]` | all collectors |
| ToolTimeoutSeconds | 10 | `Invoke-IceWarpTool` |
| CollectorTimeoutSeconds | 120 | runspace isolation |
| NetworkTimeoutSeconds | 10 | DNS/SMTP/HTTPS probes. **Certificate.ps1 ignores it** (hard-coded 2 s). |
| OutputJson / LogDirectory | `output\health.json` / `logs` | writer, logger |
| Monitor* | 5120 MB / 50 % / 1048576 KB / 300 s | Monitor fallbacks |
| CompanyName / Technician / ChecklistVersion | `''` / `Parsavan` / `1.14` | context, PDFs. **The PDFs hard-code `1.14`.** |
| MailHostname / MailDomain | `''` | DNS, STARTTLS, certificate |

## 7. External touch points and security posture
- **Outbound HTTPS** to `api.ipify.org` and `ident.me`, called twice per run (DnsMailFlow and
  Security). The code does not enforce TLS 1.2, which can matter on 2012 R2/2016 with PS 5.1.
- **Outbound DNS** to the system resolver for PTR, SPF, DKIM (8 selectors), DMARC, 4 RBL
  zones, and 3 resolver test hosts (one of them is the vendor-specific `parsavan.com`).
- **TCP 25** (STARTTLS) and **TCP 443** (certificate) to the mail hostname. Certificate
  validation is intentionally disabled because this is a connectivity test only.
- **Secrets**: DSN passwords are redacted at collection time. Logs never contain setting
  values.
- **Lock file** at `<ProjectRoot>\.agent.lock`, the **parent** of `windows/`. Depending on the
  deployment path, this may be a directory the service account cannot write to.

## 8. Differences between `CLAUDE.md` and the code

| `CLAUDE.md` statement | Reality |
|---|---|
| Version 0.1.5 | `windows/VERSION` = 0.1.7, tag `windows-v0.1.7` |
| "order matters for dependencies" | Isolation removes all inter-collector data flow |
| `Json.ps1` re-applies DSN redaction | Not implemented |
| `docs/deployment.md` | The file is at `windows/docs/deployment.md` |
| `docs/update-log.md` | Does not exist |
| ServiceStatus: "Service ports and startup mode" | Emits only `service.imap.active` / `service.pop3.active` |
| "Expected output: 28/28 tests passed" | 27/28 (version test hard-codes `0.1.6`) |
| "Full agent run: 433 keys, 0 schema violations" | Key 433 *is* a schema violation (`health.disk.archive.message`) |
| `Report.ps1` = "Shared PDF helpers" | Dead duplicate of both renderers, never loaded, LF line endings |
| License fallback "parses license.xml" with 7 tags (3.5) | Reads `C_License_XML` through tool.exe with 4 tags; never reads the file; no days-remaining handling |
