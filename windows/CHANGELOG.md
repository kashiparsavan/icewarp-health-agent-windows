# Changelog - IceWarp Health Agent for Windows

All notable changes to the Windows implementation are documented here.
The Linux agent keeps its own changelog in the repository root.
## [0.1.12] - 2026-11-01

New feature: IceWarp Configurator.

### Added
- **`lib/Configurator.ps1`.** Compares the live IceWarp configuration
  against `config/recommended.psd1` and either reports differences
  (`-Configurator`, dry-run) or applies them (`-Apply`, runs
  `tool.exe set system <key> <value>`).
- **`config/recommended.psd1`.** 62 recommended settings covering
  Intrusion Prevention thresholds (50/360), Admin Email, IMAP/POP3
  disabled, DNSBL, rejection rules, archive, protocol hardening,
  SMTP delivery, backup/watchdog/monitoring, and logging.
- **`agent.ps1 -Configurator` / `-Apply`.** New flags wired into the
  agent entry point. `-Configurator` prints `[OK]` for correct
  values and `[CHG]` for incorrect/unset values, with a summary
  ("Already correct: X, Will change: Y"). `-Apply` executes
  `tool.exe set system` for every `[CHG]` row.

## [0.1.11] - 2026-11-01

Bug fixes for four critical issues found during lab-server testing.

### Fixed
- **Duplicate key `icewarp.path.source`.** Both `StoragePaths.ps1` and
  `Environment.ps1` set the same key. Removed the line from `Environment.ps1`;
  `StoragePaths.ps1` is authoritative.
- **STARTTLS live test returned `False`.** The hostname resolution chain now
  follows `MailHostname` → `MailDomain` → primary domain from
  `Get-IceWarpDomainList`, matching `DnsMailFlow`. `COMPUTERNAME` is no longer
  used as a fallback (it would test the wrong host).
- **TLS certificate collection broken.** `${hostname}` in the failure message
  was literal (single-quoted string). Fixed to `$($hostname)`. The live check
  against port 443 now uses the same hostname chain as STARTTLS.
- **`general.os.version` emitted as JSON number.** The Windows major.minor pair
  (`10.0`) was coerced to a number by the JSON writer. Now emits the three-part
  version (`10.0.20348`) so it stays a string, matching the schema rules.
- **Pester mock test failures.** `Get-PdfTextRuns` was wrapping its return
  value in an extra array (`return , $pages`), so `$mgmtPages[1]` was null.
  Fixed the wrapper and updated assertions to match the actual PDF text.

## [0.1.9] - 2026-11-01

PDF rendering fixes. The health engine (`lib/Health.ps1`) and the JSON output
are unchanged.

### Fixed
- **PDFs ignored the health engine (Rule 3.2).** The executive report showed
  "Status: PASS" for DNS & Mail Flow while `health.mail_flow.result` was `fail`.
  - The executive overall verdict now comes from `health.summary.overall`.
  - Each control-area status is the worse of its checklist rows and its
    health pillars (`$script:MR_SECTION_PILLARS`). The pillar's health message
    is printed on the section page.
  - The Executive Overview page lists the nine health pillars with their status
    and message.
  - 31 technical checklist rows take their badge and note from
    `health.<name>.result` / `.message` (`$script:PDF_HEALTH_ROW_MAP`). This
    covers CPU, RAM, disk, OS update, backups, watchdogs, admin email,
    DIGEST-MD5, intrusion 50/360, session timeout, IMAP/POP3, database type and
    directory cache. It removes the renderer-only thresholds (for example
    "CPU load is 187.5% CRITICAL").
- **Boolean values rendered as N/A.** Native `$true`/`$false` were compared
  against strings such as `'false'`, which never matches in PowerShell.
  STARTTLS, Migration Has Errors and the RBL check showed N/A, and DIGEST-MD5
  showed "No / PASS" while it was enabled. Values are now normalized to strings
  before comparison.
- **Overlapping text in the executive report.**
  - Executive Overview: KPI labels sat on top of their values and stepped down
    the page, and "Info" and "N/A" were drawn off the right edge. The tiles now
    use fixed columns.
  - Recommended Actions: the heading collided with the first row, and the
    number boxes were drawn with an invalid colour (`4 rg`). They are now
    FAIL/WARN badges.
  - Cover-page paragraphs no longer touch, and long values are truncated.
- **Recommended actions out of order.** Issues were sorted as plain strings, so
  item 10 came before item 2. They are now ordered by severity (FAIL, then
  WARN), then failing health pillars, then checklist section and item order.
- The technical report's `H` rows now treat `critical` as a failure, and
  `ok` maps to PASS in the summary.

### Removed
- Unused executive-report helpers that emitted invalid PDF operators
  (`Mr-RoundRect`, `Mr-Circle`, `Mr-Ring`, `Mr-Arc`, `Mr-Card`, `Mr-DarkCard`)
  and the dead `Mr-RenderChecklist`, `Mr-GridItem` and `Mr-Priority`.

### Tests
- New test "PDF reports follow the health engine, never overlap text, and order
  actions by severity". It parses both generated PDFs and checks five things:
  - a `$false` STARTTLS renders as Missing / CRITICAL;
  - the CPU badge equals `health.cpu.result`;
  - the Mail Flow section and the overall verdict follow `health.*`;
  - no text overlaps and nothing is drawn off the page;
  - actions are numbered 1..N with every FAIL before any WARN.
- Pester on Windows PowerShell 5.1 / Pester 3.4.0: 32/32 passed.
  `agent.ps1 -Report` exits 0 and writes both PDFs.

### Known issues
- A reported "infinite year loop" (2022- 2023- ... 2789-) on page 5 of
  `report.pdf` could not be reproduced. No renderer loop generates years, and
  the supplied PDF does not contain that text.
- The technical report still prints "N/A (perpetual license)" when the license
  expiry is unknown (Rule 3.5).
## [0.1.8] - 2026-11-01

Bug-fix release from the project audit (`docs/03-CODE-AUDIT.md`).

### Fixed
- **PDF reports on Windows PowerShell 5.1 (B-01, critical).**
  `ReportTechnical.ps1` used `Join-Path` with several child paths. That form
  only exists in PowerShell 6+, so on 5.1 `agent.ps1 -Report` exited 1 and
  produced no PDFs. The calls are now nested, and both `report.pdf` and
  `management_report.pdf` are generated on 5.1.
- **`$host` assignments (B-03).** `DatabaseType.ps1` and `MySQL.ps1`
  assigned to the read-only automatic variable `$host`, so the database
  collector threw on any MySQL/MariaDB `Server=` DSN. The variable is now
  `$dbHost`. A `mysql.os_note` message that formatted `$host` (the PowerShell
  host object) now uses the database host.
- **DSN password leak (Rule 3.7).** `Redact-DatabaseDsn` treated any
  key=value DSN with three or more fields as a positional DSN. It masked the
  wrong field and left `Pwd=...` in `health.json`. Positional detection now
  requires fields without `=`.
- **Watchdog WMI properties (B-05, B-06).** The disk summary read
  `Win32_LogicalDisk.TotalSize` (the property is `Size`). The memory summary
  read `Win32_OperatingSystem.TotalPhysicalMemory` (the property is
  `TotalVisibleMemorySize`, in KB). Both summaries reported "not available"
  on every host; they now report real percentages.
- **Watchdog disk message (B-07).** `"$disk.Percent%"` rendered as
  `System.Collections.Hashtable.Percent%`; it now uses `$($disk.Percent)`.

### Removed
- `windows/lib/Report.ps1`: a dead, never-loaded duplicate of both PDF
  renderers that carried the same `Join-Path` and `$host` bugs and had LF
  line endings (B-37).

### Tests
- The version test reads the expected value from `windows/VERSION` rather
  than a hard-coded string (B-40).
- New tests: DSN redaction (positional and key=value), DatabaseType with a
  remote MySQL key=value DSN, and building both PDFs on the running
  PowerShell version.

### Documentation
- Added the project audit: `docs/01-PROJECT-OVERVIEW.md` to
  `docs/05-ROADMAP-NEXT-STEPS.md`.
- Aligned the version to 0.1.8 in `VERSION`, `windows/VERSION`, `CLAUDE.md`
  and both READMEs. Backfilled the changelog entries for 0.1.5 to 0.1.7.

### Verification
- Pester (Windows PowerShell 5.1.20348, Pester 3.4.0): 31/31 passed.
- `powershell.exe -File windows\agent.ps1 -Report` exits 0 and writes
  `health.json`, `report.pdf` (18 pages, checklist rendered) and
  `management_report.pdf`.

### Known issues (planned for 0.2.0, see `docs/05-ROADMAP-NEXT-STEPS.md`)
- The PDF renderers still use thresholds that differ from `Health.ps1`
  (Rule 3.2).
- MySQL applicability is never detected because collectors run isolated
  (B-02).
- An empty DSN is still reported as SQLite (B-04). Unparseable backup and
  definition dates are still treated as 999 days old (B-09).

## [0.1.7] - 2026-10-31

### Fixed
- **DSN redaction:** added `Redact-DatabaseDsn` and applied it to
  `database.connection_string_raw`, `directory_cache.connection_string` and
  all four `backup.db.*.target_dsn` keys.
- **Date normalization:** added `Normalize-ToIsoDate` and applied it to
  `os.last_update_date`, `icewarp.antispam.last_update` and
  `icewarp.antivirus.last_update`, so US-format dates serialize as
  `YYYY-MM-DD`.
- **CPU check:** `os.cpu.load1` is already a 0-100 percentage on Windows and
  is now compared directly against `monitor.cpu.threshold_percent`.
- **`general.os.version`** is emitted as a JSON number (`10.0`).
- **DNS primary domain:** `DnsMailFlow.ps1` no longer falls back to the
  server hostname for SPF/DKIM/DMARC/PTR, and the DKIM domain lookup is
  guarded against an empty hostname.
- **TLS:** a missing certificate expiry downgrades a passing `tls` pillar to
  `warn`.
- **Disk roll-up:** a collector `WARNING` status on any disk forces
  `health.disk.overall` to `warn`.
- **INFO statuses:** `health.backup.db.cache` uses `ok`/`warn`, and the
  watchdog summaries use `warn` instead of `INFO`.

## [0.1.6] - 2026-10-31

### Added
- `lib/ReportTechnical.ps1`: technical PDF (`report.pdf`) with cover,
  nine-pillar health summary, 113-row checklist and data appendix.
- `lib/ReportManagement.ps1`: executive PDF (`management_report.pdf`) with
  cover letter, KPI overview, per-section control areas and recommended
  actions. It reuses the technical checklist capture.
- Both reports use a built-in PDF writer and are generated by
  `agent.ps1 -Report`.

### Fixed
- Bash-isms left over from the port (`sprintf`, arithmetic expansion,
  `-f` operands). Removed the stray `windows/check_backticks.ps1`.

### Known issue
- The reports only rendered on PowerShell 7. Fixed in 0.1.8.

## [0.1.5] - 2026-10-28

### Fixed
- `Watchdog.ps1`: the CPU/disk/RAM/OS-update summaries read
  `$Context.Data`, which is empty in the isolated collector runspace. They
  are now computed directly from CIM.
- `Watchdog.ps1`: the CPU percentage is no longer double-counted
  (`LoadPercentage` is already 0-100).
- `Antivirus.ps1`: the Sophos `update.json` fallback probes `IceWarpHome`,
  `APPDATA`, `PROGRAMDATA` and `USERPROFILE` candidates.
- `DnsMailFlow.ps1`: SPF/DKIM/DMARC prefer `MailHostname`, then
  `MailDomain`, then the first discovered IceWarp domain.
- `Environment.ps1` / `StoragePaths.ps1`: `icewarp.path.source` reports
  `tool_exe` on Windows.
- `Health.ps1`: an unparseable OS update date yields `skip` rather than a
  999-day CRITICAL.

### Verification
- Pester: 28/28 passed. Full run: exit 0, 433 keys.
## [0.1.4] - 2026-10-28

### Changed
- `Icewarp/DomainsUsers` now emits the 3 dynamic `domain.designhost.ir.*`
  keys (as null/N/A) when no domain is discoverable on the host, so the
  schema sample is always complete.
- Bumped the agent version to 0.1.4.

### Verification
- Pester: 28/28 passed.
- Full `agent.ps1 -Report` run: exit 0, 433 keys, 85 `health.*`, 8
  `monitor.*`, 0 schema violations, 0 missing.

## [0.1.3] - 2026-10-28

### Added
- 17 new collectors covering the remaining schema keys:
  `Icewarp/Antispam`, `Icewarp/Antivirus`, `Icewarp/AdminAccess`,
  `Icewarp/Certificate`, `Icewarp/CloudFeatures`, `Icewarp/DatabaseType`,
  `Icewarp/DirectoryCache`, `Icewarp/Environment`, `Icewarp/Fulltext`,
  `Icewarp/Http`, `Icewarp/Logging`, `Icewarp/Migration`, `Icewarp/MySQL`,
  `Icewarp/Queue`, `Icewarp/SessionTimeout`, `Icewarp/StoragePaths`,
  `Icewarp/Watchdog`.
- `Icewarp/Security` extended with the `antispam.*` policy keys
  (`bypass_local_ips`, `bypass_local_domains`, `max_threads`, `mode`).
- `Icewarp/DnsMailFlow` extended with `icewarp.dkim.active_flag`.
- `Health.ps1` now copies the first disk label's note into
  `health.disk.root_fs.message` when root_fs is a dedupe of another label.

### Coverage
- Full `agent.ps1 -Report` run now emits 430 of 432 schema keys (85
  `health.*`, 8 `monitor.*`, 0 schema violations). The only remaining
  fixture keys are the 3 dynamic `domain.designhost.ir.*` keys, which are
  emitted only when that domain is discovered.

## [0.1.2] - 2026-10-28

### Added

- Complete health evaluation engine in `lib/Health.ps1`: watchdog, System
  Monitor, OS update age, directory cache, session timeout, IMAP/POP3,
  database platform, mail-flow DNS/STARTTLS, TLS expiry, access, threat,
  resource and monitoring roll-ups, and the nine-pillar summary.
- `collectors/Icewarp/Monitor.ps1`, emitting all eight `monitor.*` schema keys
  with `tool.exe`-first values, configuration defaults, and the primary
  domain's `D_AdminEmail` fallback.
- Health evaluation wiring in `agent.ps1` after collectors and before
  `Write-AgentJson`, including a summary log line.
- Pester coverage for OS update, database, mail flow, IMAP/POP3, session
  timeout, roll-ups, summary, the Monitor collector, and the full-run health
  block.

### Changed

- Schema fixture and API mapping updated to the 432-key Linux schema; all 84
  `health.*` keys and 8 `monitor.*` keys are now marked implemented.
- README collector/key counts updated to ten collectors and 340 of 432 keys.

### Notes

- Health output contains every health key the available collector data can
  support (78-84 keys depending on discovered disk mounts); the schema fixture
  and evaluator cover all 84.
- No live Windows IceWarp server was available. Validation used Pester mocks,
  PowerShell 5.1 parsing, and schema type checks.

## [0.1.1] - 2026-10-28

### Fixed

- JSON output now uses the Linux writer's type coercion (numbers, booleans,
  empty-to-null), ordinal key sorting, and atomic replacement.
- Removed non-schema context and collector keys; added the two license seat
  keys.
- Fixed `domain.list` trailing semicolon and domain-list parsing.
- Fixed CPU count, memory units and storage GB/percent math.
- Fixed PTR, DKIM, DMARC and TXT record parsing; added CIDR-aware SPF
  `ip4`/`ip6`, `+a` and `+mx` matching.
- SMTP STARTTLS now issues `EHLO`/`STARTTLS` with bounded connect and
  handshake timeouts.
- RBL queries now use the reversed public IP; the firewall check uses
  `Get-NetFirewallPortFilter` for enabled outbound block rules.
- Added per-collector timeouts, duplicate-key logging, configuration
  whitelisting and a crash-safe `.agent.lock`.

## [0.1.0] - 2026-10-26

### Added

- Independent PowerShell 5.1 entry point at `agent.ps1`.
- PSD1 configuration with a tracked `config/agent.example.psd1` and ignored
  `config/agent.local.psd1`.
- Shared modules for configuration, logging, collector execution, IceWarp
  `tool.exe` calls with timeouts, and flat JSON output.
- Sample `General/Version` collector for the IceWarp version and basic Windows
  host details.
- Flat JSON output preserves booleans and numbers and converts empty string
  values to `null`, matching the Linux JSON contract.
- Pester smoke tests compatible with Pester 3.4 and later, plus a version-aware
  test runner.
- Windows setup, deployment, and troubleshooting documentation.

### Notes

- This is a scaffold, not feature parity with the Linux agent. The full
  checklist, health rules, PDF reports, DNS collectors, and automatic updates
  are not implemented yet.
- The Windows tree does not call `agent.sh` or source anything from the Linux
  `lib/` directory.
- Windows versions and tags are independent of Linux (`windows/VERSION`,
  `windows-v*` tags).
