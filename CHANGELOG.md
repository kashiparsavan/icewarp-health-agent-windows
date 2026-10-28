# Changelog - IceWarp Health Agent for Windows

All notable changes to the Windows implementation are documented here.
The Linux agent keeps its own repository and changelog.

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

- Complete health evaluation engine in `windows/lib/Health.ps1`: watchdog,
  System Monitor, OS update age, directory cache, session timeout, IMAP/POP3,
  database platform, mail-flow DNS/STARTTLS, TLS expiry, access, threat,
  resource and monitoring roll-ups, and the nine-pillar summary.
- `windows/collectors/Icewarp/Monitor.ps1`, emitting all eight `monitor.*`
  schema keys with `tool.exe`-first values, configuration defaults, and the
  primary domain's `D_AdminEmail` fallback.
- Health evaluation wiring in `windows/agent.ps1` after collectors and before
  `Write-AgentJson`, including a summary log line.
- Pester coverage for OS update, database, mail flow, IMAP/POP3, session
  timeout, roll-ups, summary, the Monitor collector, and the full-run health
  block.

### Changed

- Schema fixture and API mapping updated from the stale 411-key sample to the
  432-key Linux schema; all 84 `health.*` keys and 8 `monitor.*` keys are now
  marked implemented.
- README collector/key counts updated to ten collectors and 340 of 432 keys.

### Notes

- Health output contains every health key the available collector data can
  support (78-84 keys depending on discovered disk mounts); the schema fixture
  and evaluator cover all 84.
- No live Windows IceWarp server was available. Validation used Pester mocks,
  PowerShell 5.1 parsing, and schema type checks.

## [0.1.1] - 2026-10-28

### Added

- Three IceWarp collectors ported from the Linux reference set:
  Icewarp/ServiceStatus.ps1 (service ports and startup mode),
  Icewarp/License.ps1 (license status, type, trial expiration), and
  Icewarp/DomainsUsers.ps1 (auto-discovered domain limits).
- Timeout-bounded tool.exe list and domain-setting helpers in
  windows/lib/IceWarpTool.ps1: Invoke-IceWarpToolList,
  Get-IceWarpDomainList, and Get-IceWarpDomainSetting.
- Collector table and tool-wrapper section in windows/README.md.

### Notes

- Collectors build their own ordered dictionaries and never return
  Context.Data, so the agent can enumerate them safely.
- Domain listing filters out IceWarp's internal ##...## service domain.
- Per-user settings (U_*) are intentionally not collected yet: listing
  domains returns domain names only, and user-level reads require a
  username.

## [0.1.0] - 2026-10-26

### Added

- Independent PowerShell 5.1 entry point at windows\agent.ps1.
- PSD1 configuration with a tracked windows\config\agent.example.psd1 and
  ignored windows\config\agent.local.psd1.
- Shared modules for configuration, logging, collector execution, IceWarp
  tool.exe calls with timeouts, and flat JSON output.
- Sample General/Version collector for the IceWarp version and basic Windows
  host details.
- Flat JSON output preserves booleans and numbers and converts empty string
  values to null, matching the Linux JSON contract.
- Pester smoke tests compatible with Pester 3.4 and later, plus a
  version-aware test runner.
- Windows setup, deployment, and troubleshooting documentation.

### Notes

- This is a scaffold, not feature parity with the Linux agent. The full
  checklist, health rules, PDF reports, DNS collectors, and automatic
  updates are not implemented yet.
- This tree does not call agent.sh or source anything from the Linux lib/
  directory.
- Windows versions and tags are independent of Linux (VERSION, windows-v*
  tags).
