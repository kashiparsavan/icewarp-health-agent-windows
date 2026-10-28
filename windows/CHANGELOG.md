# Changelog - IceWarp Health Agent for Windows

All notable changes to the Windows implementation are documented here.
The Linux agent keeps its own changelog in the repository root.

## [Unreleased]

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
