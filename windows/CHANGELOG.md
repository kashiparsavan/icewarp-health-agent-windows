
## [0.1.5] - 2026-10-28

### Fixed

- Watchdog.ps1: the watchdog CPU/Disk/RAM/OS-update summaries were
  computed from $Context.Data, but every collector runs in an isolated
  PowerShell runspace, so those keys were never present and the summaries
  always reported "data not available". The summaries are now computed
  directly from the local system
  (Win32_Processor, Win32_LogicalDisk, Win32_OperatingSystem,
  Win32_QuickFixEngineering).
- Watchdog.ps1: the CPU percentage was double-counted
  (LoadPercentage / cores * 100). Win32_Processor.LoadPercentage is
  already a 0-100 percentage, so it is now used directly.
- Antivirus.ps1: last_update was null on Windows because the Sophos
  fallback only probed the IceWarp home directory. The Sophos directory is
  now searched in several candidate locations
  (IceWarpHome/sophos, APPDATA/IceWarp/sophos,
  PROGRAMDATA/IceWarp/sophos, USERPROFILE/IceWarp/sophos).
- DnsMailFlow.ps1: SPF/DKIM/DMARC now prefer the configured primary
  IceWarp domain (MailHostname / MailDomain / discovered first domain)
  instead of falling back to the server hostname, which made the checks
  run against the wrong name.
- Environment.ps1 / StoragePaths.ps1: icewarp.path.source now
  reports 	ool_exe on Windows (it previously reported 	ool_sh, which
  is the Linux value).
- Health.ps1: os_update can no longer be marked CRITICAL when the last
  update date cannot be parsed. An unparseable date now yields skip
  instead of the 999-day fallback that would have produced a CRITICAL
  result.

### Verification

- Pester: 28/28 passed.
- Full run: gent.ps1 -Report exits 0 with 433 keys, 0 schema violations.
- All 36 .ps1 files are CRLF and parse cleanly under PowerShell 5.1.# Changelog - IceWarp Health Agent for Windows

All notable changes to the Windows implementation are documented here.
The Linux agent keeps its own changelog in the repository root.

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
