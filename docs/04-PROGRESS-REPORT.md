# 04 - Progress Report

**Snapshot:** commit `2e6694b`, `windows/VERSION` 0.1.7, audit date 2026-11-01.

Each percentage below comes from a fixed rubric. Every rubric criterion is backed by evidence
gathered during this audit (see `03-CODE-AUDIT.md`), so the numbers can be recomputed after
each fix.

---

## 1. Overall result

| Module | Weight | Completion | Weighted |
|---|---|---|---|
| Collectors | 30% | **72%** | 21.6 |
| Health engine | 25% | **74%** | 18.5 |
| PDF renderers | 20% | **37%** | 7.4 |
| Tests | 15% | **39%** | 5.9 |
| Documentation | 10% | **65%** | 6.5 |
| **Project total** | 100% | | **≈ 60%** |

```
Collectors     ██████████████░░░░░░  72%
Health engine  ███████████████░░░░░  74%
PDF renderers  ███████░░░░░░░░░░░░░  37%
Tests          ████████░░░░░░░░░░░░  39%
Docs           █████████████░░░░░░░  65%
TOTAL          ████████████░░░░░░░░  60%
```

**How to read this.** The JSON data contract is essentially complete: 432/432 keys with the
correct types. The remaining 40% is quality work: correctness bugs, renderer sync, PS 5.1
compatibility of the PDFs, test depth, and documentation hygiene.

---

## 2. Collectors - 72%

| Criterion | Weight | Score | Evidence |
|---|---|---|---|
| Schema key coverage | 40% | 100% | All 432 fixture keys emitted in the dev run. One extra non-schema key comes from Health (B-12). |
| Value correctness (collectors with no known defect) | 35% | 67% (18/27) | Defective: DatabaseType (B-03, B-04), MySQL (B-02), Watchdog (B-05…B-08), Certificate (B-23), License (B-19), Http (B-24), AdminAccess (B-25), Environment (B-26), Queue (B-28) |
| Dedicated unit tests | 15% | 24% (6.5/27) | Tested: DomainsUsers, OsStorage, DnsMailFlow, Security, License, Monitor; SmtpSettings STARTTLS helper only. The rest are covered only by the mocked full-run key/type test. |
| Live validation on a real Windows IceWarp server | 10% | 50% | TASK-006 fixed 6 lab-server bugs. No recorded run since v0.1.7, and the dev box has no `tool.exe`. |
| **Total** | | **72%** | 40 + 23.3 + 3.6 + 5 |

**Per-collector status**

| Collector | Status |
|---|---|
| General/Version | ✅ OK (date locale B-29) |
| AdminAccess | ⚠️ port-changed logic wrong (B-25) |
| Antispam | ✅ OK (label nit B-27) |
| Antivirus | ✅ OK (label nit B-27) |
| BackupArchive | ✅ OK (date locale B-29) |
| Certificate | ⚠️ literal `${hostname}`, timeouts, non-ISO date (B-23) |
| CloudFeatures | ✅ OK |
| DatabaseType | ❌ throws on MySQL DSN; empty DSN shown as sqlite (B-03, B-04) |
| DirectoryCache | ✅ OK |
| DnsMailFlow | ✅ OK (public-IP fragility B-30) |
| DomainsUsers | ✅ OK (schema design issue B-38) |
| Environment | ⚠️ duplicate key (B-26) |
| Fulltext | ✅ OK |
| Http | ⚠️ placeholder port 443 (B-24) |
| License | ❌ Rule 3.5 fallback incomplete (B-19) |
| Logging | ✅ OK |
| Migration | ✅ OK |
| Monitor | ✅ OK |
| MySQL | ❌ never applicable because of isolation; `$host` (B-02, B-03) |
| OsStorage | ✅ OK (w32tm locale B-31, repo access B-46) |
| Queue | ⚠️ duplicate reads, no normalization (B-28) |
| Security | ✅ OK (port 9001 heuristic B-32) |
| ServiceStatus | ✅ OK |
| SessionTimeout | ✅ OK |
| SmtpSettings | ✅ OK |
| StoragePaths | ✅ OK |
| Watchdog | ❌ disk and memory always unavailable; broken message (B-05…B-08) |

Result: 18 ✅ (counted as no known defect, including those with nits or minor risks), 5 ⚠️, 4 ❌.

### Linux parity note
`CLAUDE.md` section 11 compares "27 Windows collectors vs 81 Linux collectors". Counting files
is misleading. The Linux collectors are finer-grained scripts, and **by schema key the Windows
agent is at 100% parity**. The real parity gap is behavioural (value equality on the same
server). That cannot be measured without paired Linux/Windows runs or shared fixtures, and none
exist yet.

---

## 3. Health engine - 74%

| Criterion | Weight | Score | Evidence |
|---|---|---|---|
| Rule and key coverage | 40% | 100% | All 85 `health.*` schema keys; every rule in the `CLAUDE.md` 3.4 table; nine-pillar summary |
| Correctness (check functions with no known defect) | 35% | 75% (12/16) | Defective: Disk (B-10, B-12), Backup (B-09), Watchdog interval (B-11), Threat roll-up (B-09) |
| Direct unit tests | 15% | 37.5% (6/16) | Tested: OsUpdate, Database, MailFlow, ImapPop3, SessionTimeout, Roll-ups. **Untested:** Memory, Disk, CPU, Backup, Security (password/login/TLS/DIGEST), Intrusion, Admin email, Watchdog, Monitor, DirectoryCache |
| Verified Linux parity | 10% | 25% | Ported from `health.sh` by reading the code; no shared golden fixtures |
| **Total** | | **74%** | 40 + 26.25 + 5.6 + 2.5 |

Notable: the **strict rules in `CLAUDE.md` 3.4** (intrusion 50/360, admin email, DIGEST-MD5)
are correctly implemented but have **no dedicated tests**, so a regression would go unnoticed.

---

## 4. PDF renderers - 37%

| Criterion | Weight | Score | Evidence |
|---|---|---|---|
| Feature presence | 25% | 90% | Technical: header, info block, banner, nine-pillar summary, 113-row checklist, appendix. Executive: cover, overview, per-section pages, actions. Missing: footer and page numbers, company and host on the cover. |
| Runs on the target runtime (PS 5.1) | 25% | **0%** | B-01: `-Report` exits 1 [verified] |
| Sync with Health (Rule 3.2) | 25% | 27% (3/11) | In sync: memory, watchdog flags, intrusion connections/duration. Out of sync: CPU, disk, OS update, admin email, H rows, license, DirCache backup, executive overall (B-14…B-19, B-21) |
| PDF validity and quality | 15% | 50% | Technical PDF is structurally valid. Executive PDF writes invalid operators (B-20) and can overflow text. Non-ASCII is lost (B-44). |
| Tests | 10% | 0% | No renderer tests |
| **Total** | | **37%** | 22.5 + 0 + 6.8 + 7.5 + 0 |

| Renderer | Estimate |
|---|---|
| `ReportTechnical.ps1` | ≈ 45% |
| `ReportManagement.ps1` | ≈ 30% |

---

## 5. Tests - 39%

| Criterion | Weight | Score | Evidence |
|---|---|---|---|
| Pass rate on PS 5.1 / Pester 3.4 | 20% | 96% (27/28) | Only failure: hard-coded version `0.1.6` (B-40) |
| Breadth across modules | 50% | 29% | Core libs ≈ 85%, collectors 24%, health 37.5%, PDF 0%, end-to-end agent run 0% (average of the five) |
| CI on PS 5.1 | 15% | 0% | No pipeline; tests are run by hand |
| Strict-rule tests (`CLAUDE.md` 3.4–3.10) | 15% | 36% (2.5/7) | Tested: 3.6 JSON coercion, 3.8 pillars, 3.9 partially (OS update 999). Untested: 3.4, 3.5, 3.7 (`Redact-DatabaseDsn`), 3.10. `Normalize-ToIsoDate` has no tests. |
| **Total** | | **39%** | 19.3 + 14.6 + 0 + 5.4 |

---

## 6. Documentation - 65%

| Criterion | Weight | Score | Evidence |
|---|---|---|---|
| Required documents exist | 30% | 90% | CLAUDE, two READMEs, two CHANGELOGs, deployment, API mapping, API comparison, review. `docs/update-log.md` is missing. |
| Accuracy and currency | 50% | 52% | CLAUDE ≈ 70% accurate (version, paths, isolation and test-count drift); READMEs show 0.1.4/0.1.2; changelogs are missing 0.1.5–0.1.7 (root) and 0.1.6–0.1.7 (`windows/`); API mapping contradicts itself; deployment guide says 0.1.2 |
| Hygiene (encoding, structure) | 20% | 60% | `agents_bridge.md` mojibake; `windows/CHANGELOG.md` has no title; the checklist has a misleading extension |
| **Total** | | **65%** | 27 + 26 + 12 |

---

## 7. Milestone view

| Milestone | Status |
|---|---|
| M1 - Scaffold, config, logging, tool wrapper | ✅ Done (0.1.0–0.1.1) |
| M2 - Schema-exact JSON writer | ✅ Done |
| M3 - Collectors for all 432 keys | ✅ Done (0.1.3–0.1.4); quality fixes pending |
| M4 - Health engine and nine pillars | ✅ Done (0.1.2); 4 defects |
| M5 - Lab-server bug pass | ✅ Done (TASK-006, 0.1.5–0.1.7) |
| M6 - PDF reports | 🟡 Present but broken on PS 5.1 and out of sync |
| M7 - Test hardening and CI | 🔴 Not started |
| M8 - Production readiness (scheduler, exit codes, packaging, auto-update) | 🔴 Not started (`CLAUDE.md` section 11) |

## 8. How to re-measure
1. `powershell.exe -File windows\tests\Run-Tests.ps1`: pass rate.
2. `powershell.exe -File windows\agent.ps1 -Report -ConfigPath <tmp.psd1>`: exit code and PDFs.
3. Diff the output keys against `windows/tests/fixtures/schema-keys.json`: coverage and extras.
4. Re-score each rubric row above as `03-CODE-AUDIT.md` items are closed.
