# Changelog - IceWarp Health Agent for Windows

All notable changes to the Windows implementation are documented here.
The Linux agent keeps its own changelog in the repository root.

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
