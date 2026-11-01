# 05 - Roadmap and Next Steps

The order follows four rules. Unblock the target runtime first. Fix wrong health data before
adding features. Lock fixes in with tests. Clean up documentation last, in the same commit as
the change it describes (Change Ledger, `CLAUDE.md` section 12).

Bug IDs refer to `03-CODE-AUDIT.md`. Effort: **S** < 2 h, **M** ≈ ½–1 day, **L** > 1 day.

---

## Phase P0 - Make 0.1.x work on its own target runtime (release 0.1.8)

| # | Task | Bugs | Effort | Acceptance criteria |
|---|---|---|---|---|
| P0-1 | Replace the PS7-only `Join-Path` in `ReportTechnical.ps1` and delete the dead `lib/Report.ps1` | B-01, B-37 | S | `powershell.exe -File agent.ps1 -Report` exits 0 and writes both PDFs |
| P0-2 | Rename `$host` → `$dbHost` in DatabaseType and MySQL | B-03 | S | A Pester test with a `Server=db1;...` DSN yields `database.type=mysql`, `scope=remote` |
| P0-3 | Empty DSN → `database.type=unknown` (not sqlite) | B-04 | S | Test: tool unavailable → `unknown` → health `warn "could not be determined"` |
| P0-4 | Fix Watchdog CIM properties (`Size`, `TotalVisibleMemorySize`), `$()` interpolation, and uppercase status vocabulary | B-05…B-08 | S | Live run shows real disk and memory percentages |
| P0-5 | Treat `Get-DaysAgo` = 999 as `skip` in backup and threat checks | B-09 | S | Unit tests for both paths |
| P0-6 | Fix the version test to read `windows/VERSION`; align root `VERSION`, `CLAUDE.md` and READMEs | B-40, B-41 | S | 28/28 pass; one version string in the repository |
| P0-7 | Add CHANGELOG entries for 0.1.5–0.1.8 (root and `windows/`) | B-41 | S | Both changelogs list every `windows-v*` tag |

**Outcome:** the PDFs work on PS 5.1, the worst false-data bugs are gone, and the test suite is
green. Estimated total: about 1 day.

## Phase P1 - Health correctness and Rule 3.2 renderer sync (release 0.2.0)

| # | Task | Bugs | Effort | Acceptance criteria |
|---|---|---|---|---|
| P1-1 | **Single source of truth for statuses:** the technical checklist rows that map to a health rule read `health.<x>.result` instead of re-implementing thresholds. Add a `checklist label → health key` map (CPU, disk, RAM, OS update, admin email, watchdog, backup, intrusion, DirCache). | B-14…B-18 | M | No numeric threshold remains in either renderer; Rule 3.2 holds by construction |
| P1-2 | The executive report's overall, score and pillar cards come from `health.summary.*` and the nine pillars | B-21 | M | The executive overall always equals `health.summary.overall` |
| P1-3 | Fix the management PDF operators (`Mr-Rect` call; delete or fix the RoundRect/Circle/Ring/Arc helpers); add footer and page numbers; truncate values | B-20, B-22 | S | `qpdf --check` (or similar) reports no content-stream errors |
| P1-4 | Disk roll-up: no data → `warn`/`skip` (not pass); escalate a missing floor; stop emitting `health.disk.archive.message` | B-10, B-12 | S | Output has exactly 432 schema keys on a single-drive host |
| P1-5 | Missing watchdog interval → `critical`/`warn` (not pass) in Health and the PDF | B-11 | S | Unit test |
| P1-6 | Complete the license fallback per Rule 3.5: read `$IceWarpHome\config\license.xml`, use all 7 tags, compute expiry from days remaining, normalize to ISO; the PDF never says "perpetual" when the value is unknown | B-19 | M | Fixtures for each tag variant |
| P1-7 | Locale hardening: `InvariantCulture` on every `ToString` and `Parse`; route the PDF date math through `Get-DaysAgo` | B-16, B-29, B-23 | M | The test suite passes under `fa-IR` and `de-DE` thread cultures |
| P1-8 | Remove placeholders: no `http.port = 443` fallback; `os.repository_access` treated as not applicable on Windows; fix the AdminAccess default comparison | B-24, B-25, B-46 | S | Unreadable settings emit `null` |

## Phase P2 - Architecture fixes

| # | Task | Bugs | Effort | Notes |
|---|---|---|---|---|
| P2-1 | Add a **dependency mechanism** for collectors. Options: (a) pass a read-only snapshot of keys collected so far into each runspace; (b) a "derivers" phase in the parent scope that runs after collection (MySQL applicability, Watchdog summaries). Option (b) is recommended because it keeps isolation. | B-02, B-08 | M | Also fixes the dependency-order statement in `CLAUDE.md` |
| P2-2 | Public IP: resolve once per run in the parent, pass it via config/context, force TLS 1.2, and make it configurable (`PublicIp`, `DisableExternalLookups`) | B-30 | S | Halves outbound calls; works air-gapped |
| P2-3 | Separate `-Pdf` from the `-Report` console dump; a PDF failure logs an error but does not fail the JSON run; exit codes: 0 = pass, 2 = warn, 3 = fail (opt-in flag) | B-33, B-35 | S | Task Scheduler can alert on the exit code |
| P2-4 | Move the lock file under `windows\` (or `$env:ProgramData`) | B-34 | S | |
| P2-5 | Implement the `Json.ps1` DSN-redaction safety net promised in Rule 3.7 | B-47 | S | Unit test with a raw password |
| P2-6 | Collector runspace: record non-terminating errors as warnings, not total failure | B-45 | S | |
| P2-7 | Rename `checklist.conf.pdf` → `checklist.conf` and move vendor/customer literals (`parsavan.com`, `customers-stat@…`, `designhost.ir`) to config | B-38, B-39, B-43 | S | Requires OMP approval (data contract) |

## Phase P3 - Test hardening and CI

| # | Task | Effort |
|---|---|---|
| P3-1 | Unit tests for every strict rule in `CLAUDE.md` 3.4 (intrusion 50/360 and missing values, admin email empty/invalid, DIGEST true/false/missing, DB type) | S |
| P3-2 | Unit tests for Memory, Disk, CPU, Backup, Password/Login/TLS, Watchdog, Monitor, DirectoryCache checks | M |
| P3-3 | Tests for `Redact-DatabaseDsn` (positional, key=value, sqlite) and `Normalize-ToIsoDate` | S |
| P3-4 | Collector tests for DatabaseType, MySQL, Watchdog, Certificate, BackupArchive, Antivirus fallback, AdminAccess, Http | M |
| P3-5 | PDF smoke tests: both builders run on PS 5.1; output begins with `%PDF-1.4` and ends with `%%EOF`; xref offsets are valid; selected checklist badges equal the matching `health.*.result` (a guard for Rule 3.2) | M |
| P3-6 | End-to-end test: `agent.ps1 -Report` with a mocked `tool.exe` (stub `.cmd`/`.exe`) and a schema check of exactly 432 keys | M |
| P3-7 | GitHub Actions `windows-latest` job: `powershell.exe` 5.1 plus Pester, CRLF check, PSParser syntax check, PSScriptAnalyzer | S |
| P3-8 | Golden-file parity: run the Linux and Windows agents against the same lab server and diff `health.json` values | L (needs lab access) |

## Phase P4 - Documentation and production readiness

| # | Task | Effort |
|---|---|---|
| P4-1 | Update `CLAUDE.md`: version, real paths (`windows/docs/deployment.md`), isolation semantics, ServiceStatus description, test count, the 432-key claim | S |
| P4-2 | Rewrite `docs/api-key-mapping.md` sections 3/5/7/8 so they agree (all keys are Implemented); mark this audit as the source for open issues | S |
| P4-3 | Update the READMEs and `windows/docs/deployment.md` to the current version; create `docs/update-log.md` or remove it from the ledger | S |
| P4-4 | Repair the mojibake in `agents_bridge.md` (encoding pass, history preserved) | S |
| P4-5 | Decide the Rule 3.9 `*_raw` sibling-key policy, which conflicts with the 432-key schema (B-27) | S (decision) |
| P4-6 | Production features: Task Scheduler installer script, signed release ZIP, optional auto-update (`CLAUDE.md` section 11), Unicode-capable PDF font (B-44) | L |

---

## Recommended immediate sequence

1. **P0-1 → P0-7** as one 0.1.8 bug-fix release. Small, low risk, and it unblocks PDFs on PS 5.1.
2. **P3-1, P3-3, P3-5**: lock in the strict rules and the PDF runtime before refactoring the
   renderers.
3. **P1-1 + P1-2**: the renderer sync refactor (largest quality gain; ends Rule 3.2 drift).
4. **P2-1**: the derivers phase (fixes MySQL and Watchdog properly).
5. **P1-6, P1-7**: license and locale (needs fixtures from a real Iranian-locale server if
   possible).
6. **P3-7**: CI, so PS 5.1 regressions cannot reach a tag again.
7. **P4-x**: documentation sweep, then tag 0.2.0.

## Expected completion after each step

| After | Collectors | Health | PDF | Tests | Docs | **Total** |
|---|---|---|---|---|---|---|
| Today | 72 | 74 | 37 | 39 | 65 | **60** |
| P0 | 82 | 80 | 60 | 45 | 75 | **71** |
| + P3-1/3/5 | 82 | 82 | 65 | 62 | 75 | **75** |
| + P1 | 88 | 92 | 85 | 66 | 78 | **84** |
| + P2 + rest of P3 | 95 | 95 | 88 | 88 | 80 | **91** |
| + P4 | 95 | 95 | 90 | 90 | 95 | **93** |

The remaining ~7% requires live validation on production-like Windows IceWarp servers and
Linux/Windows golden-file parity (P3-8).
