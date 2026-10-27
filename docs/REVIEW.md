# Review: Windows IceWarp Health Agent

**Repository:** `C:\Projects\icewarp-health-agent-windows`  
**Reviewed at:** `14a2fdf` ("Add Windows collectors for SMTP, security, backup, OS/storage, DNS")  
**Schema of record:** `C:\Users\mrkashi\Desktop\iceauto\health.json` (411 keys)  
**Reference:** Linux agent at `C:\Users\mrkashi\Documents\Default Project\icewarp-health-agent` (read-only)  
**Review date:** 2026-10-27

---

## Executive summary

The Windows agent is a credible, genuinely independent port. The collector
isolation model is sound, the `tool.exe` wrapper has real timeouts and exit-code
checks, and there is no Linux code execution. The heavy collectors referenced
as remaining are already committed in `14a2fdf`: `SmtpSettings.ps1`,
`Security.ps1`, `BackupArchive.ps1`, `OsStorage.ps1`, and `DnsMailFlow.ps1`.
If the count was four, the fifth (`DnsMailFlow.ps1`) is also already there.

The agent is **not yet 1:1 with the 411-key schema**:

| Measure | Current |
|---|---|
| Schema keys | 411 |
| Keys implemented | **246** |
| Keys remaining | **165** |
| Windows collectors | 9 |
| Pester tests | 10 |
| CI | none |
| Exact type parity | not yet |
| Exact key parity | not yet (non-schema context keys) |

The blockers are concentrated and fixable:

1. **Types:** `Write-AgentJson` only converts empty strings to `null`. It does
   not apply the Linux writer's numeric/boolean coercion, so most raw
   `tool.exe` values land in JSON as strings (`"1"`, `"true"`, `"0"`).
2. **Extra keys:** the framework injects four non-schema keys
   (`agent.platform`, `checklist.version`, `agent.config.path`,
   `agent.config.example_used`), and `License.ps1` / `Security.ps1` add
   conditional non-schema keys.
3. **Wrong math:** `os.memory.available_kb` is divided by 1024 although
   `FreePhysicalMemory` is already KB; `storage.*_gb` is **1,048,576x too
   large**; `os.cpu.count` counts sockets, not logical CPUs.
4. **Wrong DNS records:** DKIM queries `<selector>._<domain>` instead of
   `<selector>._domainkey.<domain>`, DMARC queries `_<domain>` instead of
   `_dmarc.<domain>`, PTR reads `Name` instead of `NameHost`, and SPF/DMARC
   only inspect the first TXT record.
5. **Wrong STARTTLS test:** the code performs implicit TLS on port 25 instead
   of issuing `STARTTLS`, and the TLS handshake has no timeout.
6. **Wrong RBL/firewall checks:** RBL queries the bare zone instead of
   `<reversed-ip>.<zone>`; the port-9001 check reads a non-existent
   `Get-NetFirewallRule.LocalPort` property.
7. **License gaps:** two schema keys (`seats_info_available`,
   `used_seats_note`) are missing; the registry path is unverified and returns
   `file_present=false` on the lab server.
8. **Tests lock in the wrong contract:** the DomainsUsers test asserts
   `domain.checked = 'true'`, `domain.count = '1'`, and
   `domain.list = 'mtitc.ir'` without the required trailing semicolon.

The mapping document `docs/api-key-mapping.md` is now the permanent source of
truth: all 411 schema keys are listed, 246 implemented rows carry exact
`tool.exe` settings or OS/computed sources, and the 165 remaining rows carry the
Linux reference and status.

**Verdict:** keep the architecture; fix the contract and the high-severity
collector bugs before adding the remaining collectors. The 165 remaining keys
are mostly straightforward `tool.exe` reads plus a 72-key health evaluation
layer; the evaluation layer should be a separate engine, not 72 collectors.

---

## 1. Scope and method

Reviewed:

- `windows/agent.ps1`
- `windows/lib/Common.ps1`, `Config.ps1`, `Logging.ps1`,
  `IceWarpTool.ps1`, `Json.ps1`
- all 9 collectors under `windows/collectors`
- `windows/tests/Agent.Smoke.Tests.ps1` and `Run-Tests.ps1`
- `windows/config/agent.example.psd1`
- `windows/README.md`, deployment docs, `.gitignore`
- `tool.v14.3.0.13.windows.help` (authoritative setting list)
- Linux collectors and `lib/json.sh` for expected semantics

Constraints and limits:

- No live `tool.exe` exists in the development environment. Runtime behavior
  was checked against the source and the live lab output previously provided by
  the user (IceWarp 14.3.0.13, domain `mtitc.ir`). Items marked
  **needs live verification** cannot be closed from this machine.
- The Linux repository was read only. No Linux file was modified, and the
  Windows agent does not call `tool.sh`, `bash`, or any Linux path.
- The referenced `1. ALL smtp. KEYS.txt` mapping file does not exist on disk.
  `docs/api-key-mapping.md` was reconstructed from the 411-key schema, the
  Windows collector source, and the Linux reference collectors.

---

## 2. Architecture and independence

### 2.1 Layout and pipeline

```
windows/
  agent.ps1                    entry point, argument parsing, run loop
  lib/
    Common.ps1                 context, collector discovery, merge, filters, report
    Config.ps1                 PSD1 load, defaults, path resolution, validation
    Logging.ps1                UTF-8 log, startup rotation
    IceWarpTool.ps1            tool.exe process wrapper, parsers, domain helpers
    Json.ps1                   flat JSON writer
  collectors/
    General/Version.ps1
    Icewarp/ServiceStatus.ps1
    Icewarp/DomainsUsers.ps1
    Icewarp/License.ps1
    Icewarp/SmtpSettings.ps1
    Icewarp/Security.ps1
    Icewarp/BackupArchive.ps1
    Icewarp/DnsMailFlow.ps1
    Icewarp/OsStorage.ps1
  config/agent.example.psd1
  tests/Agent.Smoke.Tests.ps1
  tests/Run-Tests.ps1
```

The run pipeline is:

1. parse `-Config`, `-Collectors`, `-Report`, `-List`
2. load and validate the PSD1 configuration
3. initialize logging
4. build the context (`Config`, `Data`, `Root`, `Version`)
5. discover every `*.ps1` under `collectors`
6. apply the case-insensitive collector filter
7. invoke each collector with `-Context`, merge the returned dictionary
8. write the flat JSON
9. optionally print the console report
10. exit 0 even if individual collectors failed

The collector contract is documented and mostly followed:

- a collector accepts `[hashtable]$Context`
- it builds and returns its own `[ordered]@{}`
- it never writes into `$Context.Data`
- it wraps every `tool.exe`/OS read in `try/catch`
- missing values become `''` or `null`, never a crash

### 2.2 Independence assessment

**Pass.**

- All IceWarp reads go through `windows/lib/IceWarpTool.ps1` and `tool.exe`.
- DNS uses `Resolve-DnsName`, OS data uses `Get-CimInstance`/`Get-PSDrive`/
  `Get-Volume`-class APIs, and firewall data uses `Get-NetFirewallRule`/`netsh`.
- No `bash`, `sh`, WSL, `tool.sh`, `/opt/...`, or Linux path is executed.
- References to Linux in comments are explanatory and acceptable.
- The Linux repo is untouched.

**One output-level Linux remnant:** `Security.ps1` defaults
`security.port_9001_egress.method` to the literal string
`firewalld (port not in list - GOOD)`. That is a Linux firewall name in a
Windows report. It should be `Windows Firewall (port not in list - GOOD)` or
`Windows Firewall rule for :9001 present`.

### 2.3 Architecture strengths

- **Collector isolation:** a throwing collector is caught, logged, and does not
  abort the run (`Common.ps1:167-235`).
- **Process robustness:** `Invoke-IceWarpTool` reads stdout and stderr
  asynchronously, waits with a timeout, kills on timeout, and checks the exit
  code (`IceWarpTool.ps1:50-113`).
- **No unsafe config execution:** `Import-PowerShellDataFile` is used, not
  dot-sourcing or `Invoke-Expression`.
- **Logging:** UTF-8 without BOM, append-only, startup rotation.
- **Tests:** isolated temp directories and cleanup.
- **No credentials or secrets** are stored or logged.

### 2.4 Architecture findings

| ID | Severity | Finding | Evidence | Recommendation |
|---|---|---|---|---|
| A1 | **P0** | Context injects four non-schema keys: `agent.platform`, `checklist.version`, `agent.config.path`, `agent.config.example_used` | `Common.ps1:69-72` | Remove them from the default data set, or emit only under an explicit `-DebugKeys` switch. The 411-key contract has no such keys. |
| A2 | P1 | Duplicate collector keys are silently overwritten | `Common.ps1:203-209` | Detect a key already present in `$Context.Data`, log `WARN`, and fail a strict-mode validation. |
| A3 | P1 | No per-collector timeout. A slow/hung collector blocks the entire run | `agent.ps1:102-106`, sequential loop | Run each collector in a runspace/job with a bounded wait, or enforce timeouts on every network call. `AuthenticateAsClient` currently has none. |
| A4 | P1 | Collector discovery executes every `*.ps1` under `collectors`, recursively | `Common.ps1:108-122` | Use a manifest or a `*.collector.ps1` naming convention; keep helper files outside the discovery root. |
| A5 | P1 | `Set-AgentData` still writes into `$Context.Data` | `Common.ps1:90-106` | Delete it. It is unused and contradicts the collector contract; leaving it invites future violations. |
| A6 | P1 | Output write is not atomic and there is no run lock | `Json.ps1:37-38`; no lock in `agent.ps1` | Write to `health.json.tmp`, then `Move-Item -Force`; create a lock file with stale-lock detection. |
| A7 | P2 | The agent exits 0 even when collectors failed | `agent.ps1:115-121` | Add `-FailOnCollectorError` or return a documented exit code (e.g., 2) for monitoring integrations. |
| A8 | P2 | Config merge accepts arbitrary PSD1 keys and does not validate `ChecklistVersion`, `MailHostname`, or `MailDomain` | `Config.ps1:45-53` | Whitelist known keys, reject unknown keys, validate host/domain formats. |
| A9 | P2 | No run lock means overlapping scheduled runs can interleave writes | `agent.ps1` | Add `.agent.lock` with PID/time and stale-lock handling. |
| A10 | P2 | No CI, no schema-contract job | repository root | Add a GitHub Actions workflow for Pester and a schema-manifest check. |

---

## 3. Library review

### 3.1 `Common.ps1`

**Good:** clear context object, path-safe collector naming, case-insensitive
filter, per-collector timing, error isolation, console report.

**Issues:**

- A1 (extra context keys).
- A2 (duplicate overwrite).
- A4 (any `.ps1` is a collector).
- A5 (`Set-AgentData` contract violation).
- The merge is last-writer-wins with no provenance. Two collectors that both
  emit `general.company` (context and `Version.ps1`) silently disagree; the
  last one wins. Duplicate detection plus a single owner per key would help.
- `Get-CollectorFiles` sorts by full path, so run order is stable, but there is
  no dependency ordering (e.g., health evaluation must run after raw
  collectors). A manifest with phases would be safer once the health layer
  exists.

### 3.2 `Config.ps1`

**Good:** example fallback, explicit `ConfigUsedExample` warning, positive
integer timeout check, path resolution relative to the project root.

**Issues:**

- No whitelist of recognized keys (A8). A typo such as `OutputJSON` silently
  does nothing.
- `MailHostname` and `MailDomain` are accepted verbatim. A value such as
  `https://mail.example.com:443/` will break every DNS lookup in
  `DnsMailFlow.ps1`.
- `ToolPath` and `IceWarpHome` are assumed. There is no registry or
  `Program Files` auto-discovery. On a non-default install the user must edit
  the config.
- `ChecklistVersion` is not validated against the schema version (`1.14`).
- `Resolve-AgentPath` behavior for absolute paths is fine, but a path outside
  the project is allowed silently. That is acceptable, but document it.

### 3.3 `Logging.ps1`

**Good:** UTF-8 no BOM, append-only, timestamped, level validation, startup
rotation, no secrets.

**Issues:**

- Rotation only happens at startup and keeps one `.1` file. A long-lived run
  can grow the log without bound.
- No configurable log level; `DEBUG` messages are always written to the file.
- Log messages can contain newlines from `tool.exe` error text, which can break
  line-oriented log parsing. Normalize newlines in error messages.
- Log file write failures are swallowed (appropriate for an agent) but there is
  no fallback console warning.

### 3.4 `IceWarpTool.ps1`

**Good:** asynchronous stdout/stderr reads avoid pipe deadlocks, timeout plus
kill, exit-code check, working directory set to the tool directory, domain
listing filters `##...##` internal domains, `Get-IceWarpDomainSetting` prefers
the requested setting line over the entity-name first line.

**Issues:**

- **Duplication (P1):** `Invoke-IceWarpTool` (lines 50-113) and
  `Invoke-IceWarpToolList` (lines 115-178) duplicate ~110 lines of process
  handling. One private `Invoke-IceWarpProcess -Arguments ... -ReturnLines`
  function would remove the divergence risk (e.g., a future timeout fix applied
  to only one copy).
- **First-line parser (P1):** `ConvertFrom-IceWarpToolOutput` returns the first
  `Label: Value` line and discards everything after it. That is fine for scalar
  settings, but it silently truncates multi-line values. `License.ps1` works
  around this for `C_License_XML` by calling `Invoke-IceWarpTool` directly;
  other collectors (relay allowed IPs, auth-scheme lists) have no such
  workaround. Add `Get-IceWarpSettingMultiline` and use it where the setting is
  known to be multi-line.
- **Unquoted domain arguments (P1 security):** `Get-IceWarpDomainSetting`
  builds `display domain {0} {1}` with the raw domain. `tool.exe` needs the
  domain unquoted, but the domain should first be validated against a hostname
  regex; otherwise a crafted list output containing spaces or quotes can inject
  extra arguments. Domains do not contain spaces in practice, but the input is
  external data (`tool list domain`).
- **Fallback parser risk (P2):** `Get-IceWarpDomainSetting` falls back to "any
  `Label: Value` line" if the requested label is absent. That can return the
  wrong setting. Prefer returning `''` when the exact label is missing.
- **Domain-list tokenization (P2):** table rows are reduced to their first
  whitespace token. A row such as `1  example.com` becomes `1`. Validate the
  token as a hostname and skip lines that do not match.
- **No argument escaping:** `ProcessStartInfo.Arguments` is a single string.
  PowerShell 5.1 / .NET Framework does not expose `ArgumentList`, so the safe
  fix is strict validation of all interpolated values, not manual quoting.
- `Test-IceWarpTool` only checks `Test-Path`; it does not verify the file is a
  runnable executable. The first invocation will surface the error, so this is
  low priority.

### 3.5 `Json.ps1`

**Good:** empty string becomes `null`, matching one part of the Linux writer;
UTF-8 without BOM; creates the output directory.

**Issues:**

- **No numeric/boolean coercion (P0).** The Linux `lib/json.sh` applies:
  - empty -> `null`
  - `^-?[0-9]+(\.[0-9]+)?$` -> JSON number
  - `true` / `false` -> JSON boolean
  - everything else -> string

  The Windows writer only does empty -> `null`. Consequently `"1"`, `"0"`,
  `"1.5"`, and `"true"` remain strings. This is the single largest source of
  type mismatches.
- **No key sorting.** The schema file is alphabetical. `ConvertTo-Json`
  preserves insertion order, which is collector/run order. Parsed JSON compares
  fine, but text diffs and deterministic fixtures do not. Sort keys before
  serialization.
- **No atomic write** (A6).
- **No duplicate-key detection** here; duplicates are already collapsed in
  `Common.ps1`.
- `ConvertTo-Json -Depth 10` is sufficient for flat data; keep it.

---

## 4. Collector review

Counts below are schema keys actually emitted by the current collector,
including dynamic keys for the schema sample. The full key-by-key mapping is in
`docs/api-key-mapping.md`.

### 4.1 `General/Version.ps1` (10 keys, plus 4 context keys)

**Works:** `C_Version` for both version keys, tool path/existence, home-dir
installation flag, company, date, OS caption/version.

**Findings:**

| Severity | Finding | Evidence |
|---|---|---|
| P1 | `general.os.version` is a dotted Windows string (`10.0.20348`), but the schema value is numeric (`9.8`). The JSON coercion cannot convert a two-dot string; this key will always differ in type. Decide whether to emit the major version/build number (number) or document a deliberate string deviation. | `Version.ps1:45-58`; schema `general.os.version = 9.8` |
| P2 | `general.os.pretty` is identical to `general.os.name` (`Win32_OperatingSystem.Caption`). The Linux pretty value includes the edition/version. Compose a richer string. | `Version.ps1` |
| P2 | `general.company` is written by both `Common.ps1` and `Version.ps1`; last writer wins. Pick one owner. | `Common.ps1:77-79`, `Version.ps1:40` |
| P2 | `icewarp.installed` is `Test-Path IceWarpHome`; a stale empty directory reports installed. Check for `tool.exe` or a version value as well. | `Version.ps1:37` |
| P2 | `icewarp.tool` reports the configured path, not a discovered/working tool. If the path is wrong but a tool exists elsewhere, the report is misleading. | `Version.ps1:22-33` |

### 4.2 `Icewarp/ServiceStatus.ps1` (2 keys)

**Works:** emits exactly `service.imap.active` and `service.pop3.active`, reads
`C_Mail_IMAP_Active` and `C_Mail_POP_Active`, normalizes `1/true` to `1` and
`0/false` to `0`.

**Findings:**

- No schema key for SMTP service status. The user's example
  `service.smtp.startup_mode` is **not in the 411-key schema** and must not be
  added to the report. The schema has only the two keys above.
- Values are strings (`'1'`/`'0'`) until the JSON writer is fixed. After the
  writer fix they become numbers, matching the schema (`service.imap.active = 1`).

### 4.3 `Icewarp/DomainsUsers.ps1` (8 keys)

**Works:** strips the `##...##` internal domain, filters obvious table headers,
emits `domain.checked`, `domain.count`, `domain.list`, `domain.primary.*`, and
three per-domain keys. Domain-key sanitization strips spaces and tabs only,
matching Linux.

**Findings:**

| Severity | Finding | Evidence |
|---|---|---|
| **P0** | `domain.list` has no trailing semicolon. The schema value is `designhost.ir;`; the test expects `mtitc.ir` without it. | `DomainsUsers.ps1:63-67`; test line 209 |
| **P0** | `domain.checked`, `domain.count`, and the numeric domain limits are strings. The writer fix converts digit-only strings to numbers and `true`/`false` to booleans, but the test currently asserts the string forms. | test lines 202-208 |
| P1 | The collector assumes `tool list domain` output is either one domain per line or a whitespace table. A summary line such as `Total: 5` becomes a bogus domain (`Total:`), and a numbered row such as `1  example.com` becomes `1`. Validate the token as a hostname and ignore non-domain lines. | `IceWarpTool.ps1:201-229` |
| P1 | Domain names are passed to `tool.exe` unquoted without a hostname validation. The behavior is intentional for normal domains, but validate `^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?$` before constructing the argument. | `IceWarpTool.ps1:257-264` |
| P2 | If `tool list domain` fails, the collector emits only `domain.checked=false` and `domain.count=0`; it omits `domain.list` and the primary keys, so the output is not key-complete on a failure path. The schema has no failure sample, but a strict manifest should still emit the keys (with empty values). | `DomainsUsers.ps1:38-42` |
| P2 | `Get-IceWarpDomainSetting` falls back to any `Label: Value` line if the requested label is missing; this can silently attach the wrong value. | `IceWarpTool.ps1:290-298` |

### 4.4 `Icewarp/License.ps1` (5 of 7 keys)

**Works:** reads `C_LicenseStatus`, `C_License_Type`, `C_License_TrialExpire`;
uses the raw multi-line `C_License_XML` output as a fallback when the flat
trial-expiration value is empty; synthesizes `status`.

**Findings:**

| Severity | Finding | Evidence |
|---|---|---|
| **P0** | Missing schema keys: `icewarp.license.seats_info_available` and `icewarp.license.used_seats_note`. | schema; `License.ps1` |
| **P0** | Emits non-schema keys `icewarp.license.file_path` and `icewarp.license.trial_expiration_source`. | `License.ps1:29-31, 67` |
| **P1** | The registry hive paths are unverified. On the lab server `file_present` is `false` even though a license likely exists. The code checks `HKLM:\SOFTWARE\IceWarp Networks\IceWarp Server` and the WOW6432Node twin, but IceWarp's actual Windows license storage may be under a different key or registry value. Enumerate `HKLM:\SOFTWARE\IceWarp*` on the lab server and verify. | `License.ps1:33-50`; live output `file_present=false` |
| P2 | `status` values are `ok` / `installed` / `not_found`. The Linux sample is `ok`; `installed` and `not_found` are new vocabulary. Either map them to `ok`/`missing` or document them for the health rules. | `License.ps1:74-82` |
| P2 | `C_License_TrialExpire` fallback source is conditionally emitted; remove the extra key and keep only the schema key. | `License.ps1:67` |
| P2 | `icewarp.license.file_present` is based on `license.xml` or a registry `License` value; the schema key means "a license is present", not necessarily a file. Prefer `C_LicenseStatus`/`C_License_XML` non-empty as the primary signal. | `License.ps1:27-50` |

### 4.5 `Icewarp/SmtpSettings.ps1` (37 keys)

**Works:** all 31 scalar pairs are valid setting names; the DSN inversion is
correct (`c_mail_smtp_other_disable_dsn=1` -> `delivery_reports_enabled=0`);
message-size bytes/enabled/MB are computed; the max-per-domain pairs are
covered.

**Findings:**

| Severity | Finding | Evidence |
|---|---|---|
| **P0** | `smtp.starttls_live_test` performs an **implicit TLS handshake on port 25** (`SslStream.AuthenticateAsClient` immediately after TCP connect). SMTP STARTTLS requires reading the `220` banner, sending `EHLO`, checking for `STARTTLS`, sending `STARTTLS`, reading `220`, and then starting TLS. The current test will usually return `false` against a correctly configured MX. | `SmtpSettings.ps1:97-111` |
| **P0** | The TLS handshake has **no timeout**. `TcpClient.ConnectAsync(...).Wait(3000)` bounds only the connect. `AuthenticateAsClient` can hang indefinitely, and there is no per-collector timeout either. | `SmtpSettings.ps1:101-104` |
| P1 | The test accepts any certificate (`{ $true }` validation callback). That matches a connectivity-only test, but it means "TLS works" even with an invalid/expired certificate. If the key is meant to validate TLS health, capture the certificate subject/expiry or at least report the validation result. | `SmtpSettings.ps1:102-103` |
| P2 | `smtp.max_message_size.mb` formats as `20.0` (one decimal), while the schema sample is the integer `20`. After coercion the JSON number is `20.0`, numerically equal but textually different. Use `0.#` or emit an integer when the value is integral. | `SmtpSettings.ps1:89-92` |
| P2 | `smtp.relay.allowed_ips` uses the first-line scalar reader. If the setting is a multi-line list, only the first line survives. Verify the live output and use a multi-line reader if needed. | `Get-IceWarpSetting`; setting `C_Mail_SMTP_General_RelayAllowedIPs` |
| P2 | `Add-IfPresent` is defined but unused. Remove it or use it consistently. | `SmtpSettings.ps1` top |
| P2 | No SMTP service startup/status key is emitted. That is correct for the 411-key schema; do not add `service.smtp.startup_mode`. | schema |

### 4.6 `Icewarp/Security.ps1` (62 keys)

**Works:** all 62 schema keys are present on the success path, including the
4 RBL zone keys; login/password/intrusion settings are valid; the spam-score
value uses raw/1024; the `refuse_blocked_ip_source` string matches Linux;
Cyren folder checks are reasonable.

**Findings:**

| Severity | Finding | Evidence |
|---|---|---|
| **P0** | `security.auth_schemes.raw` reads `C_Mail_Security_AuthScheme`, which does not exist in either the Linux or Windows help file. The Windows help has `C_Accounts_Policies_Auth_Schemes`. | `Security.ps1:96-99`; help-file scan |
| **P0** | RBL self-check queries the **bare zone** (`Resolve-DnsName zen.spamhaus.org`), not `<reversed-ip>.<zone>`. This can report a false "clean" or a false "LISTED" depending on whether the zone apex has an A record. | `Security.ps1:161-181` |
| **P0** | Port-9001 check uses `Get-NetFirewallRule | Where-Object { $_.LocalPort -eq 9001 }`. Firewall rule objects do not expose `LocalPort`; the filter must join `Get-NetFirewallPortFilter`. The current code always sees zero rules and reports "not blocked" with the Linux `firewalld` method string. | `Security.ps1:125-139` |
| P1 | The port-9001 check counts any matching rule regardless of direction and action. A rule that allows outbound 9001 is not "blocked". Filter `Direction -eq 'Outbound'` and `Action -eq 'Block'` (or the intended semantics). | `Security.ps1:128-129` |
| P1 | The `netsh` fallback matches `:9001` in localized output. On non-English Windows the output text differs; parse the firewall rule fields or use the cmdlet only. | `Security.ps1:131-136` |
| P1 | `security.port_9001_egress.method` defaults to the Linux string `firewalld (port not in list - GOOD)` even when the check fails. Replace with `Windows Firewall` wording. | `Security.ps1:126` |
| **P0** | `security.rbl_self_check.reason` is emitted on public-IP failure but is **not in the 411-key schema**. Remove it or gate it behind a debug switch. | `Security.ps1:155` |
| P1 | Public-IP lookup accepts any 200 response body as an IP. Validate with `IPAddress.TryParse` and trim. The same code is duplicated in `DnsMailFlow.ps1`; centralize it. | `Security.ps1:143-150` |
| P2 | `security.cyren_folder.checked` is set to `'true'` before the `Test-Path`; if the path is inaccessible the key still says checked. Minor. | `Security.ps1:107` |
| P2 | `security.digest_md5.enabled` emits `'false'` when the auth-scheme string is non-empty but lacks `DIGEST-MD5`; the schema sample is `null`. After the writer fix it becomes boolean `false`, which is semantically fine but not value-identical. | `Security.ps1:100-104` |

### 4.7 `Icewarp/BackupArchive.ps1` (26 keys)

**Works:** the 8 database backup pairs, email backup flag, auto-backup
enabled/target/delete-after, archive settings, `icewarp.archive.default`, and
the last-file/last-time scan.

**Findings:**

| Severity | Finding | Evidence |
|---|---|---|
| P1 | The last-backup scan hardcodes `<IceWarpHome>\backup` and `*.zip`. It ignores the configured `icewarp.backup.auto_target` (`c_system_tools_autobackup_backupto`), which may point to another directory. If the configured target differs, `last_file`/`last_time` are wrong or empty. | `BackupArchive.ps1:38-55` |
| P1 | The filename pattern is assumed to be `.zip`. The Linux sample is `.zip`, so this matches the requirement, but the configured auto-backup target may use a different extension/pattern. Document the assumption. | `BackupArchive.ps1:43` |
| P2 | `icewarp.backup.default` is the literal `<IceWarpHome>\backup`, not a value read from `tool.exe`. If IceWarp's default is elsewhere, the key is wrong. | `BackupArchive.ps1:36` |
| P2 | `last_time` uses `LastWriteTime` formatted `yyyy-MM-dd HH:mm:ss`; the Linux sample is `2026-10-19 02:00:13`. The format matches; verify timezone (local time vs UTC). | `BackupArchive.ps1:47-50` |
| P2 | `backup.db.*` and `archive.*` values are raw first-line strings; if any target DSN or path is multi-line, it is truncated. | `Get-IceWarpSetting` |

### 4.8 `Icewarp/DnsMailFlow.ps1` (33 keys)

This is the most correctness-compromised collector. Key-level coverage is
complete (33/33), but several values will be wrong on a normal domain.

**Findings:**

| Severity | Finding | Evidence |
|---|---|---|
| **P0** | PTR lookup uses `Select-Object -ExpandProperty Name`. For `Resolve-DnsName -Type PTR`, `Name` is the queried IP; the PTR hostname is `NameHost`. The collector therefore reports the IP as the PTR result, sets `exists=true`, and compares the IP to the hostname. | `DnsMailFlow.ps1:55-61` |
| **P0** | DKIM queries `"$sel._$hostname"` (e.g., `default._example.com`) instead of `<selector>._domainkey.<domain>` (e.g., `default._domainkey.example.com`). | `DnsMailFlow.ps1:154-157` |
| **P0** | DMARC queries `"_$hostname"` (e.g., `_example.com`) instead of `_dmarc.<domain>`. | `DnsMailFlow.ps1:189-190` |
| **P0** | TXT values are selected with `Select-Object -ExpandProperty Strings -First 1` and cast with `[string]$txt`. A TXT record split into multiple 255-byte strings is joined with a **space**, which corrupts DKIM public keys and can corrupt long SPF/DMARC records. Use `-join ''`. | `DnsMailFlow.ps1:115-117, 156-157, 189-190` |
| **P0** | SPF and DMARC inspect only the **first TXT record** (`Select-Object -First 1`) and then test it for `v=spf1`/`v=DMARC1`. If another TXT record (verification, site token, DKIM) sorts first, the collector reports "not found". Filter all TXT records for the SPF/DMARC prefix. | `DnsMailFlow.ps1:115-125, 189-193` |
| P1 | SPF `+a` / `+mx` is treated as covered merely because the token appears; the A/MX records are not resolved and compared to the public IP. Linux explicitly resolves both. This can report `includes_server_ip=true` when the IP is not actually authorized. | `DnsMailFlow.ps1:132-135`; Linux `collectors/dns/spf.sh:53-75` |
| P1 | `ip4:$publicIp` / `ip6:$publicIp` is an unanchored regex. `ip4:1.2.3.4` matches `ip4:1.2.3.45`; a CIDR (`ip4:1.2.3.0/24`) is not evaluated at all. Parse mechanisms and compare addresses/CIDRs. | `DnsMailFlow.ps1:129` |
| P1 | `MailHostname` is used verbatim. A value with a scheme, port, or trailing slash makes every DNS query fail. Normalize to a bare hostname (strip `https://`, path, port, trailing dot) and validate. | `DnsMailFlow.ps1:20-28` |
| P1 | Public IP from `api.ipify.org` / `ident.me` is not validated as an IP. A captive portal or HTML error page can produce a body that is then used in DNS queries. | `DnsMailFlow.ps1:34-41` |
| P1 | `dns.configured_server` is reported but not used. All queries use the OS resolver. If the IceWarp-configured DNS server differs from the OS resolver, the report describes the OS resolver's view, not IceWarp's. | `DnsMailFlow.ps1:31`; `Resolve-DnsName` calls |
| P1 | No query timeout or overall budget. The collector can issue ~15 sequential DNS queries plus two 5-second HTTP attempts. `Resolve-DnsName` has no explicit timeout, and there is no per-collector timeout in the framework. | whole collector |
| P2 | `dns.ptr.matches_hostname` compares the PTR to `$hostname` with `-ieq` but does not normalize a trailing dot on the expected hostname. | `DnsMailFlow.ps1:61` |
| P2 | `dns.dkim.selectors_tried` is a hardcoded list. Confirm it matches the Linux selector list and the schema sample. | `DnsMailFlow.ps1:142` |
| P2 | `dns.spf.ip_coverage_via` is emitted as `''` when not covered; the schema sample contains a string. That is acceptable for key completeness, but the value differs. | `DnsMailFlow.ps1:138` |

### 4.9 `Icewarp/OsStorage.ps1` (59 keys)

**Works:** all 59 keys are emitted; CIM/PSDrive reads are wrapped in
`try/catch`; pagefile summary keys are computed; storage labels match the
schema's five labels.

**Findings:**

| Severity | Finding | Evidence |
|---|---|---|
| **P0** | `os.cpu.count` uses `(Get-CimInstance Win32_Processor).Count`, which counts physical processor instances (sockets), not logical CPUs. On a single-socket 8-core server it reports `1` instead of `8`. Sum `NumberOfLogicalProcessors`. | `OsStorage.ps1:32-38` |
| **P0** | `os.memory.available_kb` divides `FreePhysicalMemory` by 1024, but `FreePhysicalMemory` is already in **KB**. The value is 1024x too small. (`os.memory.total_kb` uses `TotalPhysicalMemory`, which is bytes, so its `/1024` is correct.) | `OsStorage.ps1:51-59` |
| **P0** | `storage.*_gb` is **1,048,576x too large**. `Get-PSDrive.Used/Free` are bytes; the code multiplies by 1024 and then divides by 1024 twice, netting bytes/1024. Correct is bytes / 1073741824 (or `/1GB`). `used_percent` happens to be correct because both sides are scaled equally. | `OsStorage.ps1:148-153` |
| **P0** | Drive matching compares `$drive.Root` (`C:\`) to `Split-Path -Qualifier` (`C:`) with `-eq`; it always fails, so every storage label falls back to the first filesystem drive. On a multi-drive server all five labels report the same drive. | `OsStorage.ps1:141-145` |
| P1 | If no drive is found, `$drive` is null and the code emits empty device/mount with zeroed sizes and `status=OK`. A missing/unmounted path should be `UNKNOWN`/`WARNING`, not healthy. | `OsStorage.ps1:143-159` |
| P1 | `storage.mail` is hardcoded to `<IceWarpHome>\mail` and `storage.archive` to `<IceWarpHome>\archive`. IceWarp's mail/archive roots are configurable; `icewarp.archive.default` already reads `C_System_Tools_AutoArchive_Path`. Use the configured paths where available. | `OsStorage.ps1:174-178` |
| P1 | `os.package_manager` is always `'unknown'` and `os.repository_access` is always `'0'`. The schema sample is `dnf` / `1`. On Windows the correct analogue is Windows Update/WSUS; returning "unknown"/0 is at least honest, but it is a known deviation. Decide whether to report `windows-update` and probe WSUS/Windows Update reachability. | `OsStorage.ps1:76-88` |
| P1 | `os.time_sync.synced` is set to `1` whenever the text `Last Successful Sync Time` appears. That line can appear even when the source is the local CMOS clock. Check `Source`/`Last Successful Sync Time` age, or use `w32tm /query /status` fields explicitly. | `OsStorage.ps1:90-97` |
| P2 | `os.cpu.load1/5/15` are all the same instantaneous `LoadPercentage` value. The schema uses real 1/5/15-minute load averages. Document the approximation or sample performance counters over time. | `OsStorage.ps1:40-49` |
| P2 | `os.last_update_date` uses the newest `Win32_QuickFixEngineering.InstalledOn` date, not the last Windows Update scan/install. Semantics differ from the Linux `dnf` history. | `OsStorage.ps1:74-86` |
| P2 | `storage.device` and `storage.mount` are both `C:\`. Linux distinguishes `/dev/sda1` from `/`. Use the volume label/disk for `device` and the root path for `mount`. | `OsStorage.ps1:146-147` |
| P2 | `system.swap.status` is `CRITICAL` when pagefile use is **>3%**, not `>0`. The mapping document should say >3%. | `OsStorage.ps1:115-122` |
| P2 | `os.memory.total_kb` is correct only because it uses `TotalPhysicalMemory` (bytes); a future switch to `TotalVisibleMemorySize` (KB) would introduce the same /1024 bug. Add a unit comment. | `OsStorage.ps1:55-59` |

---

## 5. Schema accuracy and type parity

### 5.1 Coverage matrix

| Area | Schema keys | Implemented | Remaining |
|---|---:|---:|---:|
| Agent, general, service, domain | 20 | 20 | 0 |
| SMTP | 37 | 37 | 0 |
| Security | 62 | 62 | 0 |
| DNS & mail flow | 33 | 33 | 0 |
| Backup & archive (including `icewarp.backup/archive`) | 26 | 26 | 0 |
| IceWarp environment/version/license | 11 | 9 | 2 |
| Other IceWarp (SSL, migration, paths, antispam/AV, cloud, session, config, DKIM, home/logs/mail/temp) | 33 | 0 | 33 |
| OS, system, storage | 59 | 59 | 0 |
| Admin, HTTP, queue, logging, monitor, watchdog | 43 | 0 | 43 |
| Data stores & indexing (database, directory cache, fulltext, MySQL, antispam) | 15 | 0 | 15 |
| Health evaluation | 72 | 0 | 72 |
| **Total** | **411** | **246** | **165** |

Remaining keys by top-level prefix:

| Prefix | Count |
|---|---:|
| `health.*` | 72 |
| `icewarp.*` | 35 |
| `watchdog.*` | 22 |
| `monitor.*` | 8 |
| `admin.*` | 4 |
| `antispam.*` | 4 |
| `database.*` | 4 |
| `directory_cache.*` | 4 |
| `logging.*` | 4 |
| `fulltext.*` | 2 |
| `http.*` | 2 |
| `mysql.*` | 1 |
| `queue.*` | 3 |

### 5.2 Implemented key counts per collector

| Collector | Schema keys implemented |
|---|---:|
| `Common.ps1` context | 4 (`agent.*` x3 + `general.technician`) |
| `General/Version.ps1` | 10 |
| `Icewarp/ServiceStatus.ps1` | 2 |
| `Icewarp/DomainsUsers.ps1` | 8 |
| `Icewarp/License.ps1` | 5 |
| `Icewarp/SmtpSettings.ps1` | 37 |
| `Icewarp/Security.ps1` | 62 |
| `Icewarp/BackupArchive.ps1` | 26 |
| `Icewarp/DnsMailFlow.ps1` | 33 |
| `Icewarp/OsStorage.ps1` | 59 |
| **Total** | **246** |

### 5.3 Non-schema keys currently emitted

| Key | Source | Status |
|---|---|---|
| `agent.platform` | `Common.ps1:69` | Remove/gate |
| `checklist.version` | `Common.ps1:70` | Remove/gate |
| `agent.config.path` | `Common.ps1:71` | Remove/gate |
| `agent.config.example_used` | `Common.ps1:72` | Remove/gate |
| `icewarp.license.file_path` | `License.ps1:30, 44` | Remove/gate |
| `icewarp.license.trial_expiration_source` | `License.ps1:67` | Remove/gate |
| `security.rbl_self_check.reason` | `Security.ps1:155` | Remove/gate |

The Linux collectors also emit conditional `reason`/`note` keys on failure
paths (for example `dns.spf.reason`, `dns.dkim.reason`,
`security.rbl_self_check.reason`). The 411-key schema was sampled on a success
path and does not include them. For strict 1:1 output, the Windows agent must
not emit any of them.

### 5.4 Type parity

The Linux writer (`lib/json.sh`) applies these rules centrally:

```
empty              -> null
^-?[0-9]+(\.[0-9]+)?$ -> number
true / false       -> boolean
otherwise          -> string
```

`Write-AgentJson` only implements the first rule. Examples of current
mismatches:

| Schema key | Schema type/value | Current Windows emission | After writer fix |
|---|---|---|---|
| `domain.checked` | boolean `true` | string `"true"` | boolean `true` |
| `domain.count` | number `1` | string `"1"` | number `1` |
| `domain.*.daily_send_messages_limit` | number `0` | string `"0"` | number `0` |
| `service.imap.active` | number `1` | string `"1"` | number `1` |
| `backup.db.accounts.enabled` | number `1` | string `"1"` | number `1` |
| `security.login.policy_enabled` | number `1` | string `"1"` | number `1` |
| `security.password_policy.active` | number `1` | string `"1"` | number `1` |
| `dns.dkim.checked` | boolean `true` | string `"true"` | boolean `true` |
| `dns.spf.includes_server_ip` | boolean `true` | string `"true"` | boolean `true` |
| `smtp.starttls_live_test` | boolean `true` | boolean `true` (already) | boolean `true` |
| `icewarp.license.status_code` | number `0` | string `"0"` | number `0` |
| `os.memory.available_kb` | number | string (and 1024x too small) | number (after math fix) |
| `storage.*.total_gb` | number | string (and 1,048,576x too large) | number (after math fix) |
| `general.os.version` | number `9.8` | string `"10.0.20348"` | still string; **needs a decision** |
| `smtp.max_message_size.mb` | number `20` | string `"20.0"` | number `20.0` (numerically equal) |

Important nuance: the writer's `"1"` rule produces a **number**, not a boolean.
Most `.enabled` keys in this schema are numbers (for example
`security.intrusion.block_connections_per_minute.enabled = 1`), so that is
correct. The keys that are genuinely boolean use `true`/`false` strings in the
collectors and will coerce correctly. Do not add a global `"1" -> true` rule;
it would break the numeric `.enabled` keys. A per-key manifest test is the
safest way to enforce this.

### 5.5 Value parity issues

| Key | Expected (schema sample) | Current Windows behavior |
|---|---|---|
| `domain.list` | `designhost.ir;` (trailing semicolon) | `mtitc.ir` (no semicolon) |
| `os.memory.available_kb` | KB | KB / 1024 (MB) |
| `storage.*.total_gb` | GB | bytes / 1024 (1,048,576x too large) |
| `storage.*.used_gb` / `free_gb` | GB | same 1,048,576x error |
| `os.cpu.count` | logical CPUs | socket count |
| `general.os.version` | numeric OS version | dotted Windows version string |
| `dns.ptr.result` | PTR hostname | IP address (uses `Name`) |
| `dns.dkim.record` | DKIM TXT at `_domainkey` | query at wrong name |
| `dns.dmarc.record` | DMARC TXT at `_dmarc` | query at wrong name |
| `smtp.starttls_live_test` | STARTTLS result | implicit TLS result |
| `security.port_9001_egress.blocked` | outbound firewall status | false negative due to `LocalPort` |
| `security.rbl_self_check.*` | reversed-IP RBL lookup | bare-zone lookup |
| `icewarp.license.file_present` | true on licensed host | false on lab (registry path unverified) |
| `icewarp.license.seats_info_available` / `used_seats_note` | present | missing |
| `agent.version` | `0.6.0` (Linux sample) | `0.1.0` (Windows agent) |
| `security.port_9001_egress.method` | Windows wording | `firewalld ...` |

### 5.6 Dynamic keys

Four families are dynamic. The schema sample uses concrete values:

| Family | Template | Sanitization |
|---|---|---|
| Domains | `domain.<domain>.<field>` | Strip spaces and tabs only (Linux behavior). Fields: `daily_send_messages_limit`, `disk_quota_kb`, `user_send_data_limit_mb_per_day`. |
| Storage | `storage.<label>.<field>` | Fixed labels: `root_fs`, `root_home`, `install`, `mail`, `archive`. Fields: `device`, `mount`, `path`, `status`, `total_gb`, `used_gb`, `free_gb`, `used_percent`. |
| RBL zones | `security.rbl_self_check.zones.<zone>` | Dots to underscores (`zen.spamhaus.org` -> `zen_spamhaus_org`). |
| Resolver hosts | `dns.resolver.external_test_ok_<host>` | Dots to underscores (`google.com` -> `google_com`). |

A strict validator must compare dynamic keys by template, not by the sample
domain/host. The mapping document lists the concrete sample keys for
completeness.

### 5.7 Strict validation recipe

Add a test (or a small script) that:

1. loads the 411 schema keys and their JSON types;
2. loads the generated `health.json`;
3. asserts every schema key is present exactly once, except dynamic templates;
4. asserts no key outside the schema is present;
5. asserts the JSON type of every scalar matches the schema type (with the
   documented `general.os.version` exception);
6. asserts dynamic keys are present for each discovered domain, storage label,
   RBL zone, and resolver host.

Until that test is green, "1:1 with health.json" is a goal, not a fact.

---

## 6. Pester coverage

### 6.1 What exists

| Test | Coverage |
|---|---|
| `reads the Windows agent version from VERSION` | VERSION file |
| `loads the example PSD1 configuration` | defaults, example fallback, paths |
| `parses key/value and plain tool output` | scalar parser |
| `writes valid JSON without changing scalar types` | already-typed values, empty -> null |
| `invokes a collector and merges its dictionary into agent data` | happy-path merge |
| `records a collector error without stopping the run` | throw isolation |
| `finds the bundled Version collector` | discovery |
| `filters collector names case-insensitively` | filter |
| `DomainsUsers produces exactly the Linux key set and parses values correctly` | one mocked domain, exact key set |
| `new collectors return an IDictionary without throwing when tool.exe is absent` | contract smoke for the 5 heavy collectors |

### 6.2 Gaps

**Contract tests**

- No test that the generated output has exactly the 411 key templates and no
  extras. The only exact-key test is DomainsUsers.
- No per-collector key manifest. A collector can silently drop or add a key and
  the suite stays green.
- No duplicate-key test. Two collectors can write the same key and the last one
  wins silently.
- No test for the non-schema context/license/security keys.

**Type tests**

- `writes valid JSON without changing scalar types` only tests values that are
  already `int`/`bool`/`null`/`''`. It does not test raw `"1"`, `"0"`,
  `"true"`, `"false"`, `"1.5"`, or `"10.0.20348"`.
- The DomainsUsers test **asserts the wrong contract**: `'true'` for
  `domain.checked`, `'1'` for `domain.count`, and `'mtitc.ir'` for
  `domain.list`. It invokes the collector directly and bypasses
  `Write-AgentJson`, so it will keep passing after the writer is fixed and
  will not catch the type mismatch. Rewrite it to assert the final JSON types
  (or run the returned dictionary through the writer's coercion) and expect
  `mtitc.ir;` for `domain.list`.

**Parser/robustness tests**

- No test for `tool.exe` timeout, non-zero exit code, or stderr capture.
- No test for multi-line values, values with colons (URLs/IPv6), CRLF, or
  localized output.
- No test for `Get-IceWarpDomainList` header/`##...##`/summary-line handling;
  the DomainsUsers test mocks the helper away.
- No test for config errors: missing file, empty path, non-integer timeout,
  unknown key, invalid `MailHostname`.
- No test for the run lock or atomic output write.

**Collector logic tests**

- Security RBL/firewall/auth-scheme logic has no mocked tests.
- DNS PTR/SPF/DKIM/DMARC logic has no mocked tests; `Resolve-DnsName` is called
  live.
- OS/storage math has no fixture tests. The unit errors above would have been
  caught by a single mocked `Get-PSDrive`/CIM test.
- License registry/XML fallback has no mocked test.

**Environment/CI**

- The `new collectors` test invokes all five heavy collectors with no
  `tool.exe`, but they still perform live DNS/HTTP/TLS. It can take ~10 seconds
  and fail on an isolated runner. Mock the network or skip it in unit runs.
- Pester 3.x is supported through `Run-Tests.ps1`'s `-Script`/`-Path` shim,
  but there is no CI matrix proving both 3.x and 5.x.
- No GitHub Actions (or other) workflow at all.

### 6.3 Recommended test layers

1. **Unit:** pure functions (`ConvertFrom-IceWarpToolOutput`, writer coercion,
   storage math, DNS record parsing) with table-driven fixtures. No network.
2. **Collector contract:** invoke each collector with a mocked `Get-IceWarpSetting`
   / `Get-IceWarpDomainSetting` / `Resolve-DnsName` / `Get-CimInstance`, assert
   exact key set + types.
3. **Integration (lab):** run `agent.ps1 -Report` against a real `tool.exe`,
   compare to the schema, and record a fixture.
4. **CI:** unit + contract layers on every push; integration manually or on a
   self-hosted Windows lab runner.

---

## 7. Technical debt and risk register

| Severity | Item | Impact | Fix | Effort |
|---|---|---|---|---|
| **P0** | JSON writer lacks numeric/boolean coercion | Almost every raw setting is the wrong JSON type | Port the Linux writer rules into `Json.ps1`; add unit tests | S |
| **P0** | Non-schema context/license/security keys | Cannot pass a strict 411-key diff | Remove or gate behind `-DebugKeys` | S |
| **P0** | `domain.list` missing trailing `;` | Value mismatch; test enshrines it | Append `;`; update test | S |
| **P0** | `os.memory.available_kb` /1024 | Memory report 1024x too small | Remove the division for `FreePhysicalMemory` | S |
| **P0** | `storage.*_gb` 1,048,576x too large | Storage report unusable | Use bytes / 1GB; fix drive match | S |
| **P0** | `os.cpu.count` counts sockets | CPU count wrong on single-socket multi-core hosts | Sum `NumberOfLogicalProcessors` | S |
| **P0** | DNS DKIM/DMARC names, PTR `Name`, TXT join, first-record selection | DNS/SPF/DKIM/DMARC report wrong | Correct names; `NameHost`; `-join ''`; filter records | M |
| **P0** | STARTTLS test does implicit TLS; no handshake timeout | False negatives; possible hang | Implement SMTP STARTTLS with timeouts | M |
| **P0** | RBL bare-zone query; firewall `LocalPort` | False RBL/firewall results | Build reversed-IP query; join port filter; check action/direction | M |
| **P0** | Wrong auth-scheme setting | Auth schemes always empty | Use `C_Accounts_Policies_Auth_Schemes` | S |
| **P0** | License seats keys missing; registry path unverified | 2 keys missing; file_present false | Add keys; discover registry path on lab | M |
| P1 | No per-collector timeout | A hung collector blocks the run | Runspace/job timeout or per-call timeouts | M |
| P1 | Duplicate keys silently overwritten | Divergent collectors mask each other | Detect/log/fail duplicates | S |
| P1 | Tool wrapper duplication (~110 lines) | Fixes diverge | Extract one process runner | S |
| P1 | Domain args unvalidated/unquoted | Argument injection / wrong lookups | Hostname regex before invoking | S |
| P1 | First-line scalar parser truncates multi-line settings | Relay/auth/XML values wrong | Add multi-line reader; use where needed | S |
| P1 | Backup scan ignores configured target | last_file/last_time wrong | Use `auto_target` + pattern | S |
| P1 | SPF `+a`/`+mx` not resolved; ip4 prefix match | SPF false positives/negatives | Resolve A/MX; parse CIDRs | M |
| P1 | Config accepts arbitrary keys; no host sanitization | Typos and malformed hosts silently fail | Whitelist + validate | S |
| P1 | Output not atomic; no lock | Corrupt/overlapping output | Temp+move; lock file | S |
| P1 | Test contract asserts wrong types/values | Fixing the writer breaks tests; bugs hidden | Update tests; add schema/type tests | M |
| P2 | `os.package_manager='unknown'`, `repository_access='0'` | Known deviation; health rules may misread | Use Windows Update/WSUS analogue or document | S |
| P2 | CPU load 1/5/15 identical | Misleading load trend | Sample counters or document approximation | M |
| P2 | Time-sync check only greps `Last Successful Sync Time` | False "synced" when source is local CMOS | Parse source/age | S |
| P2 | `storage.mail`/`archive` hardcoded subfolders | Wrong paths on custom installs | Use configured paths | S |
| P2 | `security.port_9001_egress.method` says `firewalld` | Linux remnant in Windows output | Windows wording | S |
| P2 | README says "0.1.0 scaffold, one sample collector" | Misleading onboarding | Update status, collector list, config table | S |
| P2 | No CI | Regressions land unnoticed | GitHub Actions + Pester + schema check | M |
| P2 | No auto-update / PDF / management report | Operational parity gap vs Linux | Decide scope; not part of 411-key JSON | L |
| P2 | Pester 3/5 compatibility shim only | No proof it works on both | CI matrix or drop 3.x | S |

---

## 8. Prioritized plan

### P0 — Contract and correctness (do before adding any collector)

1. **Central JSON coercion.** Port the Linux rules into `Write-AgentJson`:
   empty -> null, numeric regex -> number, `true`/`false` -> boolean, sort keys.
   Add a table-driven test with `"1"`, `"0"`, `"1.5"`, `"-2"`, `"true"`,
   `"false"`, `"10.0.20348"`, and `""`.
2. **Remove non-schema keys.** Delete the four context keys, the two license
   keys, and `security.rbl_self_check.reason`; or hide them behind an explicit
   debug switch that is off by default.
3. **Fix value math.** `os.cpu.count` (sum logical processors),
   `os.memory.available_kb` (no /1024), storage GB (bytes / 1GB), drive match
   (`C:\` vs `C:`), and null-drive status.
4. **Fix DNS.** DKIM `_domainkey`, DMARC `_dmarc`, PTR `NameHost`, TXT
   `-join ''`, select the matching TXT record rather than the first one.
5. **Fix STARTTLS.** Read the banner, `EHLO`, check `STARTTLS`, issue it, then
   TLS with an explicit handshake timeout. Use a 5-second budget.
6. **Fix RBL/firewall/auth.** Reversed-IP RBL query; firewall port filter +
   outbound/action; `C_Accounts_Policies_Auth_Schemes`; Windows method string.
7. **License.** Add `seats_info_available` and `used_seats_note`; verify the
   registry hive on the lab server; make `file_present` reflect a real license.
8. **Domain list.** Append the trailing `;`; rewrite the DomainsUsers test to
   assert the final JSON types (post-writer) and `mtitc.ir;`, rather than the
   raw collector strings.

**Acceptance for P0:**

- generated JSON has exactly the 411 schema key templates, no extras;
- every scalar type matches the schema (except documented
  `general.os.version`);
- the DomainsUsers test asserts the corrected contract;
- no live network call can hang the run (per-collector or per-call timeout);
- lab `health.json` shows plausible CPU/memory/storage/DNS values.

### P1 — Robustness and fidelity

1. Per-collector timeout in `Invoke-AgentCollector` (runspace/job with a
   bounded wait), plus explicit timeouts for DNS/TLS/HTTP.
2. Duplicate-key detection with `WARN` and a strict-mode failure.
3. Refactor `Invoke-IceWarpTool`/`Invoke-IceWarpToolList` into one runner;
   add `Get-IceWarpSettingMultiline`; validate domain names before invoking.
4. Config whitelist and host/domain validation; optional registry auto-discovery
   for `ToolPath`/`IceWarpHome`.
5. Atomic JSON write and a run lock with stale-lock handling.
6. Backup last-file scan using the configured `auto_target` and pattern.
7. SPF `+a`/`+mx` resolution and CIDR-aware `ip4`/`ip6` matching.
8. Time-sync source/age check; decide the Windows semantics for
   `package_manager`/`repository_access`.
9. Update README (remove "0.1.0 scaffold"/"one sample collector", document the
   9 collectors, config keys, and status).
10. Test layers: unit fixtures, collector manifests, config errors, parser
    edge cases, mocked DNS/firewall/CIM/storage, and a schema-contract test.

**Acceptance for P1:**

- every collector has an exact-key manifest test;
- a strict schema validator passes in CI;
- no collector performs an unbounded network call;
- a failed collector does not corrupt/overwrite other keys;
- README matches the code.

### P2 — Remaining collectors and evaluation

Build in this order, because each group unlocks more health rules:

1. **IceWarp environment/updates/SSL/migration/paths (33 keys).**
   `env.sh`, `certificate.sh`, `antivirus.sh`, `antispam.sh`, `migration.sh`,
   `storage_paths.sh`, `session_timeout.sh`, `cloud_features.sh`,
   `domain_limits.sh`, `dkim.sh`, `company.sh`. Most are scalar `tool.exe`
   reads; SSL needs a certificate-expiry check (`Get-ChildItem Cert:\` or
   `X509Certificate2`).
2. **Watchdog, monitor, admin, HTTP, queue, logging (43 keys).**
   Watchdog is mostly settings plus the 22-key percentage/status layer;
   `watchdog_percentage.sh` shows the status/message/summary logic. Admin/HTTP
   are simple settings; logging is settings; queue may need `tool.exe list
   queue` or a file/queue count.
3. **Data stores (15 keys).** Database type/connection string, directory cache
   schedule/next run, fulltext scanner queues, MySQL applicability, antispam
   mode/bypass lists. Most are scalar reads; `fulltext.scanner.queues` and
   `directory_cache.next_run` may be computed.
4. **Health evaluation (72 keys).** Do **not** write 72 collectors. Port the
   Linux `lib/health.sh` evaluation rules into one evaluator that runs after
   the raw collectors, reads the merged dictionary, applies thresholds, and
   emits `health.<check>.result/message` plus `health.summary.*`. The 72 keys
   are a rules engine, not data collection.
5. **CI and release hygiene.** GitHub Actions on `windows-latest` with Pester
   5.x and Windows PowerShell 5.1, the schema-contract test, and a lab smoke
   job. Tag a meaningful Windows version (not `0.1.0` forever).

**Acceptance for P2:**

- 411/411 key templates present, types match, no extras;
- health rules match the Linux thresholds and messages;
- CI green on a clean Windows runner;
- lab integration report reviewed by the user.

---

## 9. Clarifications and next actions

### 9.1 The heavy collectors are already done

The heavy collectors referenced as remaining are committed in `14a2fdf`:

- `Icewarp/SmtpSettings.ps1` (37 keys)
- `Icewarp/Security.ps1` (62 keys)
- `Icewarp/BackupArchive.ps1` (26 keys)
- `Icewarp/OsStorage.ps1` (59 keys)
- `Icewarp/DnsMailFlow.ps1` (33 keys)

Do not rebuild them. The next work is the P0 fixes above, then the 33
IceWarp environment keys, 43 operations keys, 15 data-store keys, and the
72-key health evaluator.

### 9.2 `service.smtp.startup_mode` is not in the schema

The 411-key schema has only `service.imap.active` and `service.pop3.active`.
There is no SMTP service status/startup key. Do not add
`service.smtp.startup_mode` to the output; it would be an immediate strict-diff
failure. If the user wants SMTP service status for operations, put it in a
separate operational report, not `health.json`.

### 9.3 The mapping file

`1. ALL smtp. KEYS.txt` was not found anywhere under the project, Desktop,
Documents, Downloads, or temp paths. `docs/api-key-mapping.md` is the
reconstructed source of truth: 411 schema keys, 246 implemented rows with exact
settings/sources, 165 planned/derived rows with Linux references, dynamic-key
templates, status legend, and known deviations. Commit it with this review.

### 9.4 Live validation requested

After pulling `14a2fdf` and applying the P0 fixes, run:

```powershell
cd C:\Projects\icewarp-health-agent-windows\windows
.\agent.ps1 -Report
```

Please share `output\health.json` and the log. The highest-value live checks:

1. `tool.exe display system C_Mail_Security_AuthScheme` vs
   `C_Accounts_Policies_Auth_Schemes` - which one returns the auth scheme list?
2. The actual registry location of the Windows license
   (`HKLM:\SOFTWARE\IceWarp*`) and whether `C_LicenseStatus` is non-zero.
3. `tool.exe list domain` raw output shape (header? one per line? numbered?).
4. `tool.exe display domain <domain> D_NumberLimit` raw output (entity name
   first line? `D_NumberLimit: 0`?).
5. Whether `c_system_tools_autobackup_backupto` is empty or points outside
   `<IceWarpHome>\backup`.
6. `Get-NetFirewallRule | Get-NetFirewallPortFilter` behavior for TCP 9001 and
   the direction/action of any rule.
7. The actual IceWarp mail/archive roots, to replace the hardcoded
   `<IceWarpHome>\mail` and `<IceWarpHome>\archive` storage paths.
8. `Resolve-DnsName` output for a PTR and for a multi-string DKIM TXT record,
   to confirm the `NameHost` and `-join ''` fixes.

### 9.5 Commit plan

1. Add `docs/api-key-mapping.md` and `docs/REVIEW.md` in one commit, e.g.
   `docs: add 411-key mapping and Windows agent review`.
2. Push to `origin/main`.
3. Open a P0 issue/PR for the type coercion + non-schema keys + math/DNS/
   STARTTLS/RBL/license fixes.
4. Do not start the remaining collectors until the P0 acceptance criteria are
   met; otherwise the new collectors inherit the same contract bugs.

---

## Appendix A - Implemented key counts per collector

| Collector | Keys |
|---|---:|
| `Common.ps1` context | 4 |
| `General/Version.ps1` | 10 |
| `Icewarp/ServiceStatus.ps1` | 2 |
| `Icewarp/DomainsUsers.ps1` | 8 |
| `Icewarp/License.ps1` | 5 |
| `Icewarp/SmtpSettings.ps1` | 37 |
| `Icewarp/Security.ps1` | 62 |
| `Icewarp/BackupArchive.ps1` | 26 |
| `Icewarp/DnsMailFlow.ps1` | 33 |
| `Icewarp/OsStorage.ps1` | 59 |
| **Total** | **246** |

## Appendix B - Remaining keys by area

| Area | Keys | Linux references |
|---|---:|---|
| Health evaluation | 72 | `lib/health.sh`, `collectors/watchdog/watchdog_percentage.sh` |
| IceWarp environment/SSL/migration/paths/antispam/AV (other) | 33 | `collectors/icewarp/{env,certificate,migration,storage_paths,session_timeout,cloud_features,domain_limits,dkim,company,antivirus,antispam}.sh` |
| Watchdog | 22 | `collectors/watchdog/*.sh` |
| Monitor | 8 | `collectors/icewarp/system_monitor.sh`, `monitor.sh` |
| Admin | 4 | `collectors/icewarp/admin_access.sh` |
| Antispam | 4 | `collectors/icewarp/antispam_policy.sh` |
| Database | 4 | `collectors/icewarp/database_type.sh`, `database_backup.sh` |
| Directory cache | 4 | `collectors/icewarp/directory_cache.sh` |
| Logging | 4 | `collectors/logging/*.sh` |
| HTTP | 2 | `collectors/http/*.sh` |
| Queue | 3 | `collectors/queue/*.sh` |
| Fulltext | 2 | `collectors/fulltext/*.sh` |
| MySQL | 1 | `collectors/icewarp/mysql_server.sh` |

The exact key-by-key Linux file and setting hint is in
`docs/api-key-mapping.md`, section 5.

## Appendix C - Commands

```powershell
# Run the Windows Pester suite
cd C:\Projects\icewarp-health-agent-windows\windows
.\tests\Run-Tests.ps1

# Run the agent and print the console report
.\agent.ps1 -Report

# List collectors without running them
.\agent.ps1 -List

# Run only selected collectors
.\agent.ps1 -Collectors 'smtp,security,dns' -Report
```

```powershell
# Validate the schema key count
$j = Get-Content -Raw C:\Users\mrkashi\Desktop\iceauto\health.json | ConvertFrom-Json
$j.PSObject.Properties.Count   # 411
```

---

*This review is based on static source inspection plus the live lab output
available at review time. Items marked "needs live verification" require the
Windows lab server; they are called out in section 9.4.*
