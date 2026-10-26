# Changelog - IceWarp Health Agent for Windows

All notable changes to the Windows implementation are documented here.
The Linux agent keeps its own repository and changelog.

## [Unreleased]

### Added

- Three IceWarp collectors ported from the Linux reference set:
  Icewarp/ServiceStatus.ps1 (service ports and startup mode),
  Icewarp/License.ps1 (license status, type, trial expiration), and
  Icewarp/DomainsUsers.ps1 (auto-discovered domain limits).
- Timeout-bounded 	ool.exe list and domain-setting helpers in
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
