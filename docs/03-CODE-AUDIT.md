# 03 - Code Audit (Bugs and Technical Debt)

**Method.** I read every file under `windows/` line by line and checked it against the strict
rules in `CLAUDE.md`, the 432-key fixture, `docs/api-key-mapping.md`, and
`windows/config/checklist.conf.pdf`. Findings marked **[verified]** were reproduced on this
machine with Windows PowerShell 5.1.20348 and Pester 3.4.0:

- `Run-Tests.ps1` result: 27/28 passed.
- Full `agent.ps1 -Report` run with a temporary config: JSON written, then **exit 1**.
- Small reproductions in `powershell.exe`.

**Severity scale**
- **Critical**: a core feature does not work on the target runtime.
- **High**: wrong health data, or a strict rule is violated.
- **Medium**: wrong data in edge cases, or a misleading report.
- **Low**: hygiene or maintainability issues.

---

## 1. Summary

| Severity | Count |
|---|---|
| Critical | 1 |
| High | 15 |
| Medium | 17 |
| Low | 14 |
| **Total** | **47** |

Strict-rule violations (`CLAUDE.md` section 3): **3.1** (B-37), **3.2** (B-14…B-19, B-21),
**3.3** (B-18, B-24, B-46), **3.5** (B-19), **3.7** (B-47 note), **3.9** (B-09, B-16, B-23,
B-29).

---

## 2. Critical

### B-01 - Technical PDF crashes on PowerShell 5.1 [verified]
- **Where:** `windows/lib/ReportTechnical.ps1:235` (the same code is in dead `Report.ps1:223`)
- **Code:** `Join-Path $PSScriptRoot ".." "config" "checklist.conf.pdf"`
- **Problem:** `Join-Path` only accepts more than one child path in PowerShell 6+. On 5.1 it
  throws *"A positional parameter cannot be found that accepts argument 'config'"*.
- **Impact:** `agent.ps1 -Report` exits with code 1 after writing `health.json`. Neither
  `report.pdf` nor `management_report.pdf` is produced on the platform the project targets.
  Every successful PDF in `windows/logs/agent.log` came from **PowerShell 7.4.6**.
- **Fix:** `Join-Path (Join-Path (Split-Path $PSScriptRoot -Parent) 'config') 'checklist.conf.pdf'`.
  Also add a PS 5.1 PDF smoke test.

---

## 3. High

### B-02 - MySQL collector can never run (isolation) [code-verified]
- **Where:** `collectors/Icewarp/MySQL.ps1:27,36,40`; `lib/Common.ps1:736`
- **Problem:** The collector reads `$Context.Data['database.type'|'database.scope'|'database.host']`.
  The isolated runspace builds a fresh context whose `Data` holds only the `agent.*` and
  `general.technician/company` keys. As a result `database.type` is always `''`.
- **Impact:** `mysql.applicable` is always `false`. MySQL service, version and port checks
  never execute. The checklist "Database > MySQL*" rows always render "not applicable".
- **Fix:** Merge MySQL detection into `DatabaseType.ps1`, or pass a read-only snapshot of the
  keys collected so far into the runspace, or add a declared-dependency phase.

### B-03 - `$host` assignment throws [verified]
- **Where:** `collectors/Icewarp/DatabaseType.ps1:54,56`; `collectors/Icewarp/MySQL.ps1:40`;
  also dead `Report.ps1:149`
- **Problem:** `$Host` is a constant automatic variable, and PowerShell variable names are
  case-insensitive. The assignment fails with *"Cannot overwrite variable Host because it is
  read-only or constant."*
- **Impact:** Any key=value MySQL/MariaDB DSN causes the DatabaseType collector to fail. All
  `database.*` keys are then missing and `health.database` becomes "could not be determined".
  The MySQL collector would also throw once B-02 is fixed. Tests do not catch this because
  mocks return an empty DSN.
- **Fix:** Rename the variable to `$dbHost`. Add a test with a MySQL DSN.

### B-04 - Missing DSN is reported as SQLite [verified]
- **Where:** `collectors/Icewarp/DatabaseType.ps1:31-36`
- **Problem:** An empty connection string returns `database.type = sqlite`,
  `database.scope = local`. An empty string also occurs when `tool.exe` is missing or the read
  fails.
- **Impact:** False data. The dev run without `tool.exe` reported SQLite, and health then warned
  "SQLite in use" rather than "could not be determined".
- **Fix:** Emit `unknown` when the DSN is empty, unless SQLite is positively detected.

### B-05 - Watchdog disk summary always "not available" [verified]
- **Where:** `collectors/Icewarp/Watchdog.ps1:74-77`
- **Problem:** `Win32_LogicalDisk` has a `Size` property, not `TotalSize`. Under
  `Set-StrictMode 2.0` the property access throws, the `catch` swallows the error, and `Ok`
  stays `false`.
- **Evidence:** Dev run output `watchdog.disk.message = Disk usage data not available`.

### B-06 - Watchdog memory summary always "not available" [verified]
- **Where:** `collectors/Icewarp/Watchdog.ps1:95-97`
- **Problem:** `Win32_OperatingSystem.TotalPhysicalMemory` does not exist. The correct property
  is `TotalVisibleMemorySize`, which is in KB.
- **Evidence:** `watchdog.memory.message = Memory data not available`.

### B-09 - Unparseable dates treated as 999 days old (Rule 3.9) [code-verified]
- **Where:** `lib/Health.ps1:519-527` (`backup.last_time`), `1052-1084` (threat:
  antispam/antivirus)
- **Problem:** `Get-DaysAgo` returns 999 when it cannot parse a date. Rule 3.9 says callers
  must treat that as **skip**. Only `Invoke-HealthOsUpdateCheck` does so.
- **Impact:** A non-ISO or foreign date string gives `backup.last_time = critical` with the
  message "999 days ago", and makes the threat pillar `fail`.
- **Fix:** Add an `if ($days -eq 999) { skip }` branch in both places, plus tests.

### B-14 - PDF CPU row uses different logic from Health (Rule 3.2)
- **Where:** `lib/ReportTechnical.ps1:365-377` compared with `lib/Health.ps1:435-464`
- **Problem:** The PDF calculates `load15 / cores * 100` with fixed 50/95 thresholds. Health
  compares `load1`, which is already a percentage on Windows, against
  `monitor.cpu.threshold_percent`. On an 8-core host at 40% load, the PDF shows 5% while
  Health shows 40%.

### B-15 - PDF disk row uses different logic from Health (Rule 3.2)
- **Where:** `ReportTechnical.ps1:353-364`
- **Problem:** The PDF uses `storage.root_fs.used_percent` with 80/95 thresholds. Health uses the
  free-MB floor (`monitor.disk.alert_below_mb`) plus the collector's 90% WARNING status.

### B-16 - PDF OS-update age differs from Health (Rules 3.2 and 3.9) [verified partly]
- **Where:** `ReportTechnical.ps1:38-42` (`Pdf-DaysAgo`), `392-404`
- **Problem:** `Pdf-DaysAgo` calls `[datetime]::Parse` with the current culture and without
  normalization, compares against `UtcNow`, and turns an unparseable value (999) into
  **CRITICAL**. Health turns the same value into **skip**. Under the `fa-IR` culture,
  `[datetime]::Parse('2026-10-19')` returns **2648-01-09** [verified]. The age becomes negative,
  so the row shows PASS.

### B-17 - PDF "H" rows ignore `critical` results
- **Where:** `ReportTechnical.ps1:482-499`
- **Problem:** The worst-result calculation only checks `fail` and `warn`. A `critical` health
  result, such as `backup.auto`, is shown as **PASS**.

### B-18 - PDF statuses contradict health statuses (Rules 3.2 and 3.3)
- **Admin email:** The checklist rows `Set Admin Email` and `Set customers-stat@parsavan.com`
  are kind `V`, so they render **INFO**. Health says `critical` when the address is empty.
- **Directory-cache DB backup:** Kind `B` renders **CRITICAL**. Health marks it optional (`warn`).
- **Intrusion:** `Pdf-IntrusionValidate` (`ReportTechnical.ps1:132-147`) enforces expected
  values 5/5/5/9.00/5 for five more settings that Health does not check at all.
- **Generic INFO:** Missing values for kinds F, R, L and D render **INFO** (`:443,452,457,480`).
  Rule 3.3 forbids arbitrary INFO for missing settings.

### B-19 - License expiry rules not followed (Rule 3.5)
- **Where:** `collectors/Icewarp/License.ps1:89-100`; `lib/ReportTechnical.ps1:174-177`
- **Problems:**
  1. The fallback regex covers only `TrialExpire|TrialExpiration|Expire|ExpirationDate`. It
     misses `LicenseExpiration`, `TrialDaysRemaining` and `DaysRemaining`, and the
     days-remaining-to-date calculation is not implemented.
  2. The fallback reads `C_License_XML` through `tool.exe`. It never reads the `license.xml`
     file, and the file check looks in `$IceWarpHome\license.xml` rather than
     `$IceWarpHome\config\license.xml` (Rule 3.10).
  3. `trial_expiration` is not normalized to ISO (Rule 3.9).
  4. The technical PDF prints **"N/A (perpetual license)"** whenever the expiration is empty
     and the type is not exactly `Evaluation`. Rule 3.5 says "NEVER assume missing value means
     perpetual".

### B-20 - Management PDF writes invalid content-stream operators
- **Where:** `lib/ReportManagement.ps1:355`
- **Problem:** `Mr-Rect` is called with 6 arguments. The 6th argument is dropped and `'4'` is
  bound as the colour, which emits `4 rg`. `rg` needs 3 operands, so the result is an invalid
  operator.
- **Same issue in unused helpers:** `Mr-RoundRect`, `Mr-Circle`, `Mr-Ring` and `Mr-Arc`
  (`:73-90`) emit `re` with 5 to 7 operands.
- **Impact:** The "Recommended Actions" page contains invalid PDF operators. Strict viewers may
  drop the drawing or report errors.

### B-29 - Locale and calendar sensitivity (Rule 3.9) [verified partly]
- **Where:** `Common.ps1:262` (`agent.time`), `Version.ps1` (`general.date`),
  `BackupArchive.ps1:71` (`icewarp.backup.last_time`), `Antivirus.ps1` (epoch date),
  `ReportTechnical.ps1:40`, `Certificate.ps1:63,88` (`GetExpirationString()`)
- **Problem:** `DateTime.ToString('yyyy-MM-dd…')` without `InvariantCulture`, and
  `[datetime]::Parse` with the current culture. `fa-IR` uses `PersianCalendar` by default
  [verified: `ToString('yyyy-MM-dd', fa-IR)` returns `1405-08-10`]. The deployment base appears
  to be Iranian (`.ir` domains), so a server with a Persian system locale could emit
  Persian-calendar dates. The backup check would then become critical.
- **Fix:** Pass `[CultureInfo]::InvariantCulture` to every `ToString` and `Parse` call, and add
  a test that runs under `fa-IR`.

### B-30 - Public-IP lookup is fragile on PS 5.1
- **Where:** `Common.ps1:348-372`
- **Problems:**
  - It does not enforce TLS 1.2 (`[Net.ServicePointManager]::SecurityProtocol`). On 2012 R2
    and 2016, `Invoke-WebRequest` to HTTPS endpoints may fail. When it fails, PTR, SPF IP
    coverage and RBL checks are all skipped silently.
  - The lookup is called twice per run, once each from DnsMailFlow and Security, which means
    up to 4 outbound requests.
  - It is an undeclared external dependency, which raises privacy and air-gap concerns.

---

## 4. Medium

| ID | Location | Finding |
|---|---|---|
| B-07 | `Watchdog.ps1:125,128` | `"Disk usage is $disk.Percent%"` expands to `System.Collections.Hashtable.Percent%` [verified]. Currently hidden by B-05. Use `$($disk.Percent)`. |
| B-08 | `Watchdog.ps1:131-187` | Mixed status case: `WARN`/`PASS` vs lowercase `warn`. `summary.warnings` counts only `WARN`, so "unavailable" checks are ignored. Thresholds (disk 80%, mem 60%, OS update 3 days, drive `C:` hard-coded) differ from Health and OsStorage. |
| B-10 | `Health.ps1:377-379, 402-411` | `disk.overall` is **pass** ("adequate free space") when no `storage.*.free_gb` keys exist. A missing disk floor sets the per-disk result to `warn` but does not raise `$worst`. |
| B-11 | `Health.ps1:700,732-734`; `ReportTechnical.ps1:326` | A missing `watchdog.interval_minutes` defaults to `0`, which gives **pass** "Every minute - optimal". This is a false pass whenever tool.exe is unavailable. |
| B-12 | `Health.ps1:330-345, 414-432` | When every storage label is on the same drive, `archive` is processed first and gets a message. This emits the non-schema key `health.disk.archive.message`, which is the "433rd key" counted as success in `CLAUDE.md`/`CHANGELOG`. |
| B-13 | `ReportTechnical.ps1:369,383` | `if(Pdf-IsNum $a -and Pdf-IsNum $b …)` runs in command mode, so `-and …` become arguments to `Pdf-IsNum` and the second condition is ignored [verified]. |
| B-21 | `ReportManagement.ps1:455-493` | Executive score and overall come from checklist badges, not from `health.summary.*` or the nine pillars. The executive PDF can say HEALTHY while `health.json` says `fail`. |
| B-23 | `Certificate.ps1:48,53,59,63` | `$source` is single-quoted, so `${hostname}` stays literal [verified in output]. The 2000 ms timeouts ignore `NetworkTimeoutSeconds`. The expiry string is locale-formatted, not ISO. `$ssl`/`$stream` are unset in `finally` when `New-Object` throws (StrictMode). |
| B-24 | `Http.ps1` | `http.port` falls back to a hard-coded **443** when the setting cannot be read [verified in output]. This is a placeholder, which Rule 3.3 forbids. |
| B-25 | `AdminAccess.ps1` | `admin.port_changed_from_default` is `true` for any non-zero port. It never compares against the IceWarp default. |
| B-31 | `OsStorage.ps1:122-130` | Time sync looks for the English `Source:` in `w32tm` output, so it reads as not synced on localized Windows. |
| B-32 | `Security.ps1:144` | Any enabled outbound block rule with `RemotePort = Any` is reported as "port 9001 blocked". |
| B-38 | `DomainsUsers.ps1` | `domain.designhost.ir.*` keys are hard-coded for the zero-domain case. On a real host the key set changes to `domain.<real>.*`, so "432/432 parity" only holds on the reference host. The schema has customer data baked into it. |
| B-44 | `ReportTechnical.ps1:20-32`, `ReportManagement.ps1:39-51` | Non-ASCII characters become `?`, so Persian company or technician names are lost. Helvetica Type1 with WinAnsi cannot render them anyway; a font-embedding strategy is needed. |
| B-45 | `Common.ps1:752-755` | Any non-terminating error record in the runspace fails the whole collector and discards valid data. |
| B-46 | `OsStorage.ps1:117`; checklist "Repository Access" | `os.repository_access` is hard-coded `'0'`, so the PDF always shows CRITICAL on Windows even though the check does not apply there. |
| B-47 | `Json.ps1` vs `CLAUDE.md` 3.7 | The safety-net DSN redaction that `CLAUDE.md` promises in `Json.ps1` does not exist. Today every DSN key is wrapped at the source, so there is no current leak. |

## 5. Low

| ID | Location | Finding |
|---|---|---|
| B-22 | `ReportManagement.ps1` | `Mr-PageFooter` is never called, so there are no page numbers. Values are not truncated (`:336`) and can overflow. The cover shows no company or host. About 12 helper functions are unused. |
| B-26 | `Environment.ps1`, `StoragePaths.ps1` | Both emit `icewarp.path.source`, which logs a duplicate-key WARN on every run [verified]. |
| B-27 | `Antispam.ps1`, `Antivirus.ps1` | The source label is `tool_sh` on Windows (other collectors use `tool_exe`). Rule 3.9 asks for `*_raw` sibling keys, but the 432-key schema forbids extra keys. The two rules conflict and need a decision. |
| B-28 | `Queue.ps1` | Re-reads two SMTP settings and does not normalize the flags, so `queue.smtp.incoming.enabled` may differ in type from `smtp.use_incoming_queue`. |
| B-33 | `agent.ps1:126-145` | Re-dot-sources report libraries that are already loaded. PDFs are tied to the console dump (`-Report`). A PDF failure aborts the run with exit 1. |
| B-34 | `agent.ps1:101` | The lock file goes in the **parent** of `windows/`, which may not be writable in some deployment layouts. |
| B-35 | `agent.ps1` | The exit code ignores collector failures and `health.summary.overall`. Schedulers cannot alert on it. |
| B-36 | `Health.ps1:1-26,41-52,123,514` | Stale "Part 1/2/3" header. Mojibake (`â€”`) at line 123. `ConvertTo-HealthText` is unused. `ok` is used as a health result for `backup.db.cache`, which conflicts with the vocabulary in `CLAUDE.md` section 6. |
| B-37 | `lib/Report.ps1` | 631-line dead duplicate of both renderers. It is never loaded, uses **LF** line endings in the working tree (Rule 3.1), and contains the B-01 and B-03 bugs. |
| B-39 | `DnsMailFlow.ps1:82`; checklist row | Vendor-specific `parsavan.com` resolver test and the "Set customers-stat@parsavan.com" checklist row. |
| B-40 | `tests/Agent.Smoke.Tests.ps1:341` (`:34`) | The version test hard-codes `'0.1.6'` while `windows/VERSION` is `0.1.7`. **This is the only failing test.** [verified] |
| B-41 | repo-wide | Version drift: root `VERSION` 0.1.5, `windows/VERSION` 0.1.7, test 0.1.6, `CLAUDE.md` 0.1.5, READMEs 0.1.4/0.1.2. Root `CHANGELOG.md` ends at 0.1.4 and `windows/CHANGELOG.md` at 0.1.5, but tags exist up to `windows-v0.1.7`. `windows/CHANGELOG.md` has no title line. |
| B-42 | docs | `api-key-mapping.md` contradicts itself: section 3 says "0 remaining", section 5 lists about 90 keys as *Planned* that are now implemented, and sections 7/8 still say "92 planned / 340 templates". `agents_bridge.md` headings contain mojibake. `CLAUDE.md` path and description drift (see `02` section 8). |
| B-43 | `config/checklist.conf.pdf` | A plain-text checklist with a `.pdf` extension. It is easy to break with a PDF tool, and editors and diff tools treat it as binary. |

---

## 6. Rule-by-rule compliance matrix (`CLAUDE.md` section 3)

| Rule | Status | Evidence |
|---|---|---|
| 3.1 CRLF for `.ps1`/`.psd1` | Partial | Every file is CRLF except `lib/Report.ps1` (LF, dead) |
| 3.2 PDF renderer sync | **Violated** | B-14, B-15, B-16, B-17, B-18, B-21 |
| 3.3 No arbitrary INFO / no placeholders | **Violated** (renderers, Http) | B-18, B-24, B-46. The health engine itself complies (it uses `skip` for CPU/OS data that is unavailable). |
| 3.4 Strict thresholds | **Compliant** in `Health.ps1` | Intrusion 50/360, admin email, DIGEST-MD5, IMAP/POP3 and DB type all match. They are **not unit-tested** individually. |
| 3.5 License fallback | **Violated** | B-19 |
| 3.6 JSON coercion | **Compliant** and tested | `Json.ps1`, test "coerces numeric, boolean…" |
| 3.7 DSN redaction | Compliant at source; promised safety net missing | B-47 |
| 3.8 Nine pillars | **Compliant** in `Health.ps1` | The executive PDF ignores them (B-21) |
| 3.9 Date handling | **Partially violated** | B-09, B-16, B-23, B-29 |
| 3.10 Windows paths | Mostly compliant | License looks in `$IceWarpHome` rather than `$IceWarpHome\config` (B-19) |

## 7. Technical debt register

| Debt | Cost if ignored | Suggested remedy |
|---|---|---|
| Two copies of PDF logic (`ReportTechnical`, plus dead `Report.ps1`), and renderer rules duplicating `Health.ps1` | Every threshold change has to be made 3 times, and Rule 3.2 keeps breaking | Have the renderers read `health.*.result` only, with a single checklist → health-key map |
| Isolation with no dependency mechanism | Collectors duplicate CIM queries (Watchdog vs OsStorage); MySQL cannot work | Either a two-phase run (raw → derived) or post-collection "derivers" in the parent scope |
| Watchdog derived summaries computed inside a collector | Thresholds drift from Health | Move them into `Health.ps1` or a deriver |
| Hand-rolled PDF writer with ASCII only and no font embedding | No Unicode, fragile layout | Keep for now. Later, consider embedding a TrueType subset or HTML→PDF if allowed. |
| The checklist is a text file named `.pdf` | Confusing, binary-looking diffs | Rename to `checklist.conf` (or `.tsv`) and update the reader |
| Customer and vendor literals (`designhost.ir`, `parsavan.com`, `customers-stat@parsavan.com`, default technician `Parsavan`) | Product is not reusable | Move them to config |
| No CI | PS 5.1 regressions such as B-01 reach tags | Add a GitHub Actions `windows-latest` job running `powershell.exe` and Pester |
| Version strings in 5 places | Constant drift (B-41) | Single source (`windows/VERSION`); tests read it; docs reference it |
